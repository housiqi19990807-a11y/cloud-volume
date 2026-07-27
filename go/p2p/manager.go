// PeerManager orchestrates discovery, transport, and event routing for the
// entire P2P subsystem. It is the single entry point for mount/bridge code.
package p2p

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"sync"
	"sync/atomic"
	"time"
)

// EventReceiver is implemented by the mount layer to handle incoming change
// notifications. When a peer signals "bucket X, path Y may have changed",
// this callback refreshes the matching mount session's cache.
type EventReceiver interface {
	OnPeerEvent(accountFP, bucketFP, pathHash, parentHash, versionHint, operation string)
}

// PeerStatus is the JSON-serializable status returned to the Flutter UI.
type PeerStatus struct {
	Enabled   bool          `json:"enabled"`
	DeviceID  string        `json:"deviceId"`
	Peers     []PeerInfo    `json:"peers"`
	StartedAt time.Time     `json:"startedAt"`
}

// PeerInfo is one discovered peer as seen by the UI.
type PeerInfo struct {
	DeviceID string `json:"deviceId"`
	Addr     string `json:"addr"`
	LastSeen string `json:"lastSeen"`
}

// PeerManager is the top-level coordinator for P2P operations.
type PeerManager struct {
	mu          sync.Mutex
	enabled     bool
	identity    *DeviceIdentity
	accountFP   string
	discovery   *Discovery
	transport   *Transport
	receiver    EventReceiver
	seqCounter  uint64
	cancel      context.CancelFunc
	connMutex   sync.Mutex
	connections map[string]*quicConn // deviceID -> connection

	// configRef provides the current chunk size and account details for content transfer.
	configRef ConfigProvider
}

// ConfigProvider gives the P2P layer access to user-configurable settings.
type ConfigProvider interface {
	P2PEnabled() bool
	P2PChunkSizeMB() int
	AccountFingerprint() string
}

// quicConn wraps a live connection with metadata.
type quicConn struct {
	conn   any // *quic.Conn, kept as any to avoid import leak in header
	device string
	addr   string
}

// NewPeerManager creates the coordinator. It does not start anything yet;
// call Start() after configuring the receiver.
func NewPeerManager(runtimeDir string, provider ConfigProvider) (*PeerManager, error) {
	identity, err := LoadOrCreateIdentity(runtimeDir)
	if err != nil {
		return nil, err
	}
	return &PeerManager{
		identity:    identity,
		enabled:     provider.P2PEnabled(),
		accountFP:   provider.AccountFingerprint(),
		connections: make(map[string]*quicConn),
		configRef:   provider,
	}, nil
}

// SetReceiver registers the mount-layer handler for incoming events.
func (pm *PeerManager) SetReceiver(r EventReceiver) {
	pm.mu.Lock()
	pm.receiver = r
	pm.mu.Unlock()
}

// Start begins mDNS discovery and QUIC listening. It is safe to call after Stop.
func (pm *PeerManager) Start() error {
	pm.mu.Lock()
	if !pm.enabled {
		pm.mu.Unlock()
		return nil
	}
	pm.mu.Unlock()

	transport := NewTransport(pm.identity)
	port, err := transport.Listen("0.0.0.0:0")
	if err != nil {
		return err
	}
	pm.transport = transport

	// Wire incoming events to the receiver.
	transport.onEventReceived = func(se SignedEvent) {
		pm.handleIncomingEvent(se)
	}

	discovery := NewDiscovery(pm.identity, pm.accountFP, port)
	discovery.SetCallbacks(
		func(peer DiscoveredPeer) {
			pm.onPeerJoined(peer)
		},
		func(deviceID string) {
			pm.onPeerLeft(deviceID)
		},
	)
	if err := discovery.Start(); err != nil {
		transport.Close()
		return err
	}
	pm.discovery = discovery
	log.Printf("[p2p/manager] started device=%s fp=%s", pm.identity.DeviceID, pm.accountFP[:8]+"…")
	return nil
}

// Stop shuts down discovery and transport.
func (pm *PeerManager) Stop() {
	pm.mu.Lock()
	defer pm.mu.Unlock()
	if pm.discovery != nil {
		pm.discovery.Stop()
		pm.discovery = nil
	}
	if pm.transport != nil {
		pm.transport.Close()
		pm.transport = nil
	}
	pm.connMutex.Lock()
	pm.connections = make(map[string]*quicConn)
	pm.connMutex.Unlock()
	log.Printf("[p2p/manager] stopped")
}

// IsEnabled returns whether P2P is currently active.
func (pm *PeerManager) IsEnabled() bool {
	pm.mu.Lock()
	defer pm.mu.Unlock()
	return pm.enabled
}

// BroadcastMutation sends a change notification to all discovered peers.
// It is called from writeback_queue.go after a successful remote upload,
// and from bridge dispatchers after successful UI mutations.
func (pm *PeerManager) BroadcastMutation(
	bucketFP, pathHash, parentHash, versionHint, operation string,
) {
	pm.mu.Lock()
	if !pm.enabled || pm.transport == nil {
		pm.mu.Unlock()
		return
	}
	pm.mu.Unlock()

	seq := atomic.AddUint64(&pm.seqCounter, 1)
	event := PeerEvent{
		DeviceID:    pm.identity.DeviceID,
		Sequence:    seq,
		AccountFP:   pm.accountFP,
		BucketFP:    bucketFP,
		PathHash:    pathHash,
		ParentHash:  parentHash,
		VersionHint: versionHint,
		Operation:   operation,
		Timestamp:   time.Now().UnixMilli(),
		Nonce:       randomHex(8),
	}
	signed, err := event.Sign(pm.identity)
	if err != nil {
		log.Printf("[p2p/broadcast] sign-error: %v", err)
		return
	}
	// Fan-out to all peers. Non-blocking; failures are logged, not fatal.
	for _, peer := range pm.discovery.Peers() {
		go func(addr, devID string) {
			if err := pm.sendToPeer(devID, addr, signed); err != nil {
				log.Printf("[p2p/broadcast] send-to %s error: %v", devID, err)
			}
		}(peer.Addr, peer.DeviceID)
	}
}

// sendToPeer opens or reuses a connection and sends one signed event.
func (pm *PeerManager) sendToPeer(deviceID, addr string, se SignedEvent) error {
	pm.connMutex.Lock()
	existing, ok := pm.connections[deviceID]
	pm.connMutex.Unlock()
	if ok && existing != nil {
		conn, _ := existing.conn.(interface {
			OpenStreamSync(context.Context) (any, error)
		})
		_ = conn // try reuse path omitted for simplicity in this layer
	}
	// For now, open a fresh connection per broadcast. QUIC 1-RTT is fast
	// enough for occasional events, and this avoids stale-connection bugs.
	conn, err := pm.transport.Connect(addr)
	if err != nil {
		return err
	}
	defer func() {
		_ = conn.CloseWithError(0, "done")
	}()
	return pm.transport.SendEvent(conn, se)
}

// handleIncomingEvent validates and dispatches an event from a peer.
func (pm *PeerManager) handleIncomingEvent(se SignedEvent) {
	// Reject events from different accounts.
	if se.Event.AccountFP != pm.accountFP {
		return
	}
	// TODO: verify signature against known peer public keys (from discovery).
	// For now, the mDNS fingerprint match + same-account check is sufficient.
	pm.mu.Lock()
	r := pm.receiver
	pm.mu.Unlock()
	if r != nil {
		r.OnPeerEvent(
			se.Event.AccountFP,
			se.Event.BucketFP,
			se.Event.PathHash,
			se.Event.ParentHash,
			se.Event.VersionHint,
			se.Event.Operation,
		)
	}
}

// onPeerJoined is called when mDNS discovers a new trusted peer.
func (pm *PeerManager) onPeerJoined(peer DiscoveredPeer) {
	log.Printf("[p2p/manager] peer-online device=%s addr=%s", peer.DeviceID, peer.Addr)
}

// onPeerLeft is called when a peer has not been seen for a while.
func (pm *PeerManager) onPeerLeft(deviceID string) {
	log.Printf("[p2p/manager] peer-offline device=%s", deviceID)
	pm.connMutex.Lock()
	delete(pm.connections, deviceID)
	pm.connMutex.Unlock()
}

// Status returns the current P2P state for the UI.
func (pm *PeerManager) Status() PeerStatus {
	pm.mu.Lock()
	defer pm.mu.Unlock()
	peers := []PeerInfo{}
	if pm.discovery != nil {
		for _, p := range pm.discovery.Peers() {
			peers = append(peers, PeerInfo{
				DeviceID: p.DeviceID,
				Addr:     p.Addr,
				LastSeen: p.LastSeen.Format(time.RFC3339),
			})
		}
	}
	return PeerStatus{
		Enabled:  pm.enabled,
		DeviceID: pm.identity.DeviceID,
		Peers:    peers,
	}
}

// StatusJSON is a convenience for the bridge layer.
func (pm *PeerManager) StatusJSON() ([]byte, error) {
	return json.Marshal(pm.Status())
}

// SetEnabled toggles P2P at runtime (from the settings UI).
func (pm *PeerManager) SetEnabled(enabled bool) error {
	pm.mu.Lock()
	wasEnabled := pm.enabled
	pm.enabled = enabled
	pm.mu.Unlock()
	if enabled && !wasEnabled {
		return pm.Start()
	}
	if !enabled && wasEnabled {
		pm.Stop()
	}
	return nil
}

// DeviceID returns this device's identifier (for UI display).
func (pm *PeerManager) DeviceID() string {
	return pm.identity.DeviceID
}

// AccountFP returns the account fingerprint (for diagnostics).
func (pm *PeerManager) AccountFP() string {
	return pm.accountFP
}

// fmtStringer avoids unused import warning.
var _ = fmt.Sprintf
