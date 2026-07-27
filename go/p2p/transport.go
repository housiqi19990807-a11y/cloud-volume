// QUIC transport carries authenticated peer events and content chunks.
package p2p

import (
	"context"
	"crypto/tls"
	"encoding/binary"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net"
	"os"
	"sync"
	"time"

	"github.com/quic-go/quic-go"
)

const (
	maxControlMessageSize = 64 * 1024
	streamReadTimeout     = 60 * time.Second
	quicMaxIdleTimeout    = 120 * time.Second
)

// ContentResolver returns a complete local file matching a remote version.
// Its path is only used inside the provider device and never sent to peers.
type ContentResolver func(
	ctx context.Context,
	bucket, virtualPath, versionHint string,
) (localPath string, size int64, ok bool)

// PeerStream provides framed control messages plus raw bytes on one QUIC stream.
type PeerStream struct {
	stream *quic.Stream
}

func (ps *PeerStream) SendMessage(data []byte) error {
	if len(data) > maxControlMessageSize {
		return fmt.Errorf("control message too large: %d", len(data))
	}
	header := make([]byte, 4)
	binary.BigEndian.PutUint32(header, uint32(len(data)))
	if _, err := ps.stream.Write(header); err != nil {
		return err
	}
	_, err := ps.stream.Write(data)
	return err
}

func (ps *PeerStream) RecvMessage() ([]byte, error) {
	_ = ps.stream.SetReadDeadline(time.Now().Add(streamReadTimeout))
	header := make([]byte, 4)
	if _, err := io.ReadFull(ps.stream, header); err != nil {
		return nil, err
	}
	length := binary.BigEndian.Uint32(header)
	if length > maxControlMessageSize {
		return nil, fmt.Errorf("control message too large: %d", length)
	}
	data := make([]byte, length)
	if _, err := io.ReadFull(ps.stream, data); err != nil {
		return nil, err
	}
	return data, nil
}

func (ps *PeerStream) Close() error { return ps.stream.Close() }

// Transport owns one encrypted QUIC listener and dispatches peer streams.
type Transport struct {
	tlsConfig  *tls.Config
	quicConfig *quic.Config
	listener   *quic.Listener
	accountKey []byte

	mu              sync.RWMutex
	onEventReceived func(SignedEvent)
	contentResolver ContentResolver
}

func NewTransport(identity *DeviceIdentity, accountKey []byte) *Transport {
	cert, err := generateECDSACertificate()
	if err != nil {
		panic(fmt.Sprintf("generate P2P TLS certificate: %v", err))
	}
	return &Transport{
		accountKey: append([]byte(nil), accountKey...),
		tlsConfig: &tls.Config{
			Certificates:       []tls.Certificate{cert},
			NextProtos:         []string{"cloud-volume-p2p"},
			MinVersion:         tls.VersionTLS13,
			InsecureSkipVerify: true, // account HMAC authenticates each request
		},
		quicConfig: &quic.Config{
			MaxIdleTimeout:  quicMaxIdleTimeout,
			KeepAlivePeriod: 30 * time.Second,
		},
	}
}

func (t *Transport) SetEventHandler(handler func(SignedEvent)) {
	t.mu.Lock()
	t.onEventReceived = handler
	t.mu.Unlock()
}

func (t *Transport) SetContentResolver(resolver ContentResolver) {
	t.mu.Lock()
	t.contentResolver = resolver
	t.mu.Unlock()
}

func (t *Transport) Listen(addr string) (int, error) {
	listener, err := quic.ListenAddr(addr, t.serverTLSConfig(), t.quicConfig)
	if err != nil {
		return 0, fmt.Errorf("quic listen: %w", err)
	}
	t.listener = listener
	go t.acceptLoop()
	port := listener.Addr().(*net.UDPAddr).Port
	log.Printf("[p2p/transport] listening port=%d", port)
	return port, nil
}

func (t *Transport) serverTLSConfig() *tls.Config {
	config := t.tlsConfig.Clone()
	config.ClientAuth = tls.RequireAnyClientCert
	return config
}

func (t *Transport) acceptLoop() {
	for {
		conn, err := t.listener.Accept(context.Background())
		if err != nil {
			return
		}
		go t.handleConn(conn)
	}
}

func (t *Transport) handleConn(conn *quic.Conn) {
	for {
		stream, err := conn.AcceptStream(context.Background())
		if err != nil {
			return
		}
		go t.handleStream(&PeerStream{stream: stream})
	}
}

func (t *Transport) handleStream(ps *PeerStream) {
	defer ps.Close()
	message, err := ps.RecvMessage()
	if err != nil || len(message) == 0 {
		return
	}
	switch message[0] {
	case MsgEvent:
		var event SignedEvent
		if json.Unmarshal(message[1:], &event) == nil {
			t.mu.RLock()
			handler := t.onEventReceived
			t.mu.RUnlock()
			if handler != nil {
				handler(event)
			}
		}
	case MsgContentQuery:
		t.handleContentQuery(ps, message[1:])
	case MsgContentFetch:
		t.handleContentFetch(ps, message[1:])
	}
}

func (t *Transport) handleContentQuery(ps *PeerStream, payload []byte) {
	var query ContentQuery
	if err := json.Unmarshal(payload, &query); err != nil || !query.Verify(t.accountKey) {
		return
	}
	t.mu.RLock()
	resolver := t.contentResolver
	t.mu.RUnlock()
	response := ContentResponse{}
	if resolver != nil {
		_, size, ok := resolver(context.Background(), query.Bucket, query.Path, query.VersionHint)
		response = ContentResponse{Has: ok, Size: size}
	}
	if response.Sign(t.accountKey) != nil {
		return
	}
	encoded, err := json.Marshal(response)
	if err == nil {
		_ = ps.SendMessage(append([]byte{MsgContentReply}, encoded...))
	}
}

func (t *Transport) handleContentFetch(ps *PeerStream, payload []byte) {
	var request ChunkRequest
	if err := json.Unmarshal(payload, &request); err != nil || !request.Verify(t.accountKey) {
		return
	}
	t.mu.RLock()
	resolver := t.contentResolver
	t.mu.RUnlock()
	if resolver == nil || request.Offset < 0 || request.Length <= 0 {
		return
	}
	path, size, ok := resolver(context.Background(), request.Bucket, request.Path, request.VersionHint)
	if !ok || request.Offset >= size {
		return
	}
	length := request.Length
	if remaining := size - request.Offset; length > remaining {
		length = remaining
	}
	file, err := os.Open(path)
	if err != nil {
		return
	}
	defer file.Close()
	response := ChunkResponse{Offset: request.Offset, Length: length}
	if response.Sign(t.accountKey) != nil {
		return
	}
	metadata, err := json.Marshal(response)
	if err != nil || ps.SendMessage(append([]byte{MsgContentChunk}, metadata...)) != nil {
		return
	}
	mac := NewChunkAuthenticator(t.accountKey, request.Bucket, request.Path, request.VersionHint, request.Offset, length)
	if _, err := io.CopyN(io.MultiWriter(ps.stream, mac), io.NewSectionReader(file, request.Offset, length), length); err != nil {
		return
	}
	proof, err := json.Marshal(ContentProof{AuthTag: mac.Sum(nil)})
	if err == nil {
		_ = ps.SendMessage(append([]byte{MsgContentProof}, proof...))
	}
}

func (t *Transport) Connect(ctx context.Context, addr string) (*quic.Conn, error) {
	conn, err := quic.DialAddr(ctx, addr, t.tlsConfig, t.quicConfig)
	if err != nil {
		return nil, fmt.Errorf("quic dial %s: %w", addr, err)
	}
	return conn, nil
}

func (t *Transport) SendEvent(ctx context.Context, conn *quic.Conn, event SignedEvent) error {
	stream, err := conn.OpenStreamSync(ctx)
	if err != nil {
		return err
	}
	ps := &PeerStream{stream: stream}
	defer ps.Close()
	payload, err := json.Marshal(event)
	if err != nil {
		return err
	}
	return ps.SendMessage(append([]byte{MsgEvent}, payload...))
}

func (t *Transport) Close() error {
	if t.listener == nil {
		return nil
	}
	return t.listener.Close()
}
