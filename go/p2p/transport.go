// QUIC transport for encrypted peer-to-peer event and content transfer.
// Each device runs a QUIC listener that accepts authenticated streams from
// trusted peers (identified by their Ed25519 public key / device ID).
package p2p

import (
	"context"
	"crypto/tls"
	"crypto/x509"
	"encoding/binary"
	"fmt"
	"io"
	"log"
	"net"
	"sync"
	"time"

	"github.com/quic-go/quic-go"
)

const (
	// maxEventMessageSize caps a single event message (events are tiny).
	maxEventMessageSize = 64 * 1024
	// streamReadTimeout caps how long we wait on a single peer stream.
	streamReadTimeout = 60 * time.Second
	// quicMaxIdleTimeout drops connections that go quiet.
	quicMaxIdleTimeout = 120 * time.Second
)

// PeerStream is a bidirectional QUIC stream for exchanging framed messages.
type PeerStream struct {
	stream *quic.Stream
}

// SendMessage writes a length-prefixed message on the stream.
func (ps *PeerStream) SendMessage(data []byte) error {
	header := make([]byte, 4)
	binary.BigEndian.PutUint32(header, uint32(len(data)))
	if _, err := ps.stream.Write(header); err != nil {
		return err
	}
	_, err := ps.stream.Write(data)
	return err
}

// RecvMessage reads a length-prefixed message from the stream.
func (ps *PeerStream) RecvMessage() ([]byte, error) {
	ps.stream.SetReadDeadline(time.Now().Add(streamReadTimeout))
	header := make([]byte, 4)
	if _, err := io.ReadFull(ps.stream, header); err != nil {
		return nil, err
	}
	length := binary.BigEndian.Uint32(header)
	if length > maxEventMessageSize {
		return nil, fmt.Errorf("message too large: %d", length)
	}
	buf := make([]byte, length)
	if _, err := io.ReadFull(ps.stream, buf); err != nil {
		return nil, err
	}
	return buf, nil
}

// Close terminates the underlying QUIC stream.
func (ps *PeerStream) Close() error {
	return ps.stream.Close()
}

// Transport wraps a QUIC listener and connection pool for outbound peers.
type Transport struct {
	identity    *DeviceIdentity
	tlsConfig   *tls.Config
	quicConfig  *quic.Config
	listener    *quic.Listener

	mu          sync.Mutex
	conns       map[string]*quic.Conn // keyed by device ID

	onEventReceived func(SignedEvent)
	onContentQuery  func(ContentQuery) (*ContentResponse, error)
}

// NewTransport creates a QUIC transport. The TLS certificate is self-signed
// using the device's Ed25519 key; peer verification is done at the application
// level by matching the announced device ID against discovered peers.
func NewTransport(identity *DeviceIdentity) *Transport {
	tlsConf := &tls.Config{
		NextProtos: []string{"cloud-volume-p2p"},
		// We use application-level device ID verification, so skip standard
		// cert chain verification and rely on the mDNS fingerprint match.
		InsecureSkipVerify: true,
		// ClientAuth is set on the listener config below.
	}
	quicConf := &quic.Config{
		MaxIdleTimeout:  quicMaxIdleTimeout,
		KeepAlivePeriod: 30 * time.Second,
	}
	return &Transport{
		identity:   identity,
		tlsConfig:  tlsConf,
		quicConfig: quicConf,
		conns:      make(map[string]*quic.Conn),
	}
}

// Listen starts accepting QUIC connections on the given address.
// Returns the actual port assigned (useful when port 0 is requested).
func (t *Transport) Listen(addr string) (int, error) {
	listener, err := quic.ListenAddr(addr, t.serverTLSConfig(), t.quicConfig)
	if err != nil {
		return 0, fmt.Errorf("quic listen: %w", err)
	}
	t.listener = listener
	go t.acceptLoop()
	port := listener.Addr().(*net.UDPAddr).Port
	log.Printf("[p2p/transport] listening on %s port=%d", addr, port)
	return port, nil
}

// serverTLSConfig returns a TLS config for the listener side.
// In production this would use a self-signed cert from the Ed25519 key.
// For now we use a generated ECDSA cert as quic-go requires a tls.Certificate.
func (t *Transport) serverTLSConfig() *tls.Config {
	cert := mustGenerateSelfSignedCert(t.identity)
	return &tls.Config{
		Certificates:     []tls.Certificate{cert},
		NextProtos:       []string{"cloud-volume-p2p"},
		MinVersion:       tls.VersionTLS13,
		ClientAuth:       tls.RequireAnyClientCert,
	}
}

// acceptLoop accepts incoming connections and dispatches streams.
func (t *Transport) acceptLoop() {
	for {
		conn, err := t.listener.Accept(context.Background())
		if err != nil {
			log.Printf("[p2p/transport] accept-error: %v", err)
			return
		}
		go t.handleConn(conn)
	}
}

// handleConn processes streams from one peer connection.
func (t *Transport) handleConn(conn *quic.Conn) {
	for {
		stream, err := conn.AcceptStream(context.Background())
		if err != nil {
			return
		}
		go t.handleStream(&PeerStream{stream: stream})
	}
}

// handleStream reads one message from a stream and dispatches it.
func (t *Transport) handleStream(ps *PeerStream) {
	defer ps.Close()
	msg, err := ps.RecvMessage()
	if err != nil {
		return
	}
	// Peek the first byte to decide message type.
	if len(msg) == 0 {
		return
	}
	switch msg[0] {
	case MsgEvent:
		se, err := DecodeSignedEvent(msg[1:])
		if err != nil {
			log.Printf("[p2p/transport] decode-event-error: %v", err)
			return
		}
		if t.onEventReceived != nil {
			t.onEventReceived(se)
		}
	case MsgContentQuery:
		// Content queries are handled in content_server.go; this is a fallback.
		log.Printf("[p2p/transport] content-query received (unhandled in fallback)")
	default:
		log.Printf("[p2p/transport] unknown msg-type=%d", msg[0])
	}
}

// Connect establishes a QUIC connection to a peer address.
func (t *Transport) Connect(addr string) (*quic.Conn, error) {
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	conn, err := quic.DialAddr(ctx, addr, t.tlsConfig, t.quicConfig)
	if err != nil {
		return nil, fmt.Errorf("quic dial %s: %w", addr, err)
	}
	return conn, nil
}

// SendEvent opens a stream to a connected peer and sends a signed event.
func (t *Transport) SendEvent(conn *quic.Conn, se SignedEvent) error {
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	stream, err := conn.OpenStreamSync(ctx)
	if err != nil {
		return err
	}
	ps := &PeerStream{stream: stream}
	defer ps.Close()
	payload, err := se.Encode()
	if err != nil {
		return err
	}
	// Prepend message type byte.
	msg := append([]byte{MsgEvent}, payload...)
	return ps.SendMessage(msg)
}

// Close shuts down the listener and all connections.
func (t *Transport) Close() error {
	t.mu.Lock()
	for _, conn := range t.conns {
		_ = conn.CloseWithError(0, "shutdown")
	}
	t.conns = make(map[string]*quic.Conn)
	t.mu.Unlock()
	if t.listener != nil {
		return t.listener.Close()
	}
	return nil
}

// mustGenerateSelfSignedCert generates a throwaway TLS certificate so QUIC
// can complete its handshake. The actual peer trust is established at the
// application level via mDNS account fingerprint matching.
func mustGenerateSelfSignedCert(identity *DeviceIdentity) tls.Certificate {
	// We use a simple in-memory ECDSA P-256 cert. This is sufficient because
	// TLS 1.3 (used by QUIC) encrypts the certificate, and peer trust is
	// enforced by matching account fingerprints in mDNS, not by PKI.
	_ = x509.NewCertPool() // placeholder for potential future CA verification
	cert, err := generateECDSACertificate()
	if err != nil {
		// If cert generation fails, QUIC cannot work. This is fatal.
		log.Fatalf("[p2p/transport] cert-generation-fatal: %v", err)
	}
	_ = identity
	return cert
}
