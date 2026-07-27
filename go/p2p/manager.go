// PeerManager coordinates LAN discovery, authenticated events, and content reads.
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

// EventReceiver receives an already authenticated remote mutation.
type EventReceiver interface {
	OnPeerEvent(accountFP, bucket, parentPath, operation string)
}

// PeerStatus is the JSON-serializable state returned to the settings UI.
type PeerStatus struct {
	Enabled   bool       `json:"enabled"`
	DeviceID  string     `json:"deviceId"`
	Peers     []PeerInfo `json:"peers"`
	StartedAt time.Time  `json:"startedAt"`
}

// PeerInfo describes one mDNS-discovered compatible device.
type PeerInfo struct {
	DeviceID string `json:"deviceId"`
	Addr     string `json:"addr"`
	LastSeen string `json:"lastSeen"`
}

// PeerManager keeps P2P isolated from mount/storage packages.
type PeerManager struct {
	mu          sync.RWMutex
	enabled     bool
	running     bool
	starting    bool
	generation  uint64
	identity    *DeviceIdentity
	accountFP   string
	accountKey  []byte
	chunkSizeMB int
	startedAt   time.Time
	discovery   *Discovery
	transport   *Transport
	receiver    EventReceiver
	resolver    ContentResolver
	seqCounter  uint64
}

// NewPeerManager constructs a stopped manager for one configured account.
func NewPeerManager(runtimeDir, accountFP string, accountKey []byte, chunkSizeMB int) (*PeerManager, error) {
	if accountFP == "" || len(accountKey) == 0 {
		return nil, fmt.Errorf("missing P2P account identity")
	}
	identity, err := LoadOrCreateIdentity(runtimeDir)
	if err != nil {
		return nil, err
	}
	return &PeerManager{identity: identity, enabled: true, accountFP: accountFP,
		accountKey: append([]byte(nil), accountKey...), chunkSizeMB: normalizeChunkSizeMB(chunkSizeMB)}, nil
}

// SetReceiver registers the mount-side invalidation callback.
func (pm *PeerManager) SetReceiver(receiver EventReceiver) {
	pm.mu.Lock()
	pm.receiver = receiver
	pm.mu.Unlock()
}

// SetContentResolver registers a provider for fully cached local objects.
func (pm *PeerManager) SetContentResolver(resolver ContentResolver) {
	pm.mu.Lock()
	pm.resolver = resolver
	pm.mu.Unlock()
}

// Start starts listening once. It may be called repeatedly by config bootstrap.
func (pm *PeerManager) Start() error {
	pm.mu.Lock()
	if !pm.enabled || pm.running || pm.starting {
		pm.mu.Unlock()
		return nil
	}
	pm.starting = true
	generation := pm.generation
	transport := NewTransport(pm.identity, pm.accountKey)
	transport.SetEventHandler(pm.handleIncomingEvent)
	transport.SetContentResolver(func(ctx context.Context, bucket, path, hint string) (string, int64, bool) {
		pm.mu.RLock()
		resolver := pm.resolver
		pm.mu.RUnlock()
		if resolver == nil {
			return "", 0, false
		}
		return resolver(ctx, bucket, path, hint)
	})
	pm.mu.Unlock()
	port, err := transport.Listen("0.0.0.0:0")
	if err != nil {
		pm.mu.Lock()
		if pm.generation == generation {
			pm.starting = false
		}
		pm.mu.Unlock()
		return err
	}
	discovery := NewDiscovery(pm.identity, pm.accountFP, port)
	discovery.SetCallbacks(pm.onPeerJoined, pm.onPeerLeft)
	if err := discovery.Start(); err != nil {
		_ = transport.Close()
		pm.mu.Lock()
		if pm.generation == generation {
			pm.starting = false
		}
		pm.mu.Unlock()
		return err
	}
	pm.mu.Lock()
	if !pm.enabled || pm.generation != generation {
		pm.starting = false
		pm.mu.Unlock()
		discovery.Stop()
		_ = transport.Close()
		return nil
	}
	pm.transport, pm.discovery, pm.running, pm.starting, pm.startedAt = transport, discovery, true, false, time.Now()
	pm.mu.Unlock()
	log.Printf("[p2p/manager] started device=%s", pm.identity.DeviceID)
	return nil
}

// Stop releases network resources without holding the manager lock.
func (pm *PeerManager) Stop() {
	pm.mu.Lock()
	discovery, transport := pm.discovery, pm.transport
	pm.discovery, pm.transport, pm.running, pm.starting = nil, nil, false, false
	pm.generation++
	pm.mu.Unlock()
	if discovery != nil {
		discovery.Stop()
	}
	if transport != nil {
		_ = transport.Close()
	}
}

// IsEnabled reports the user setting, while IsRunning reports active network state.
func (pm *PeerManager) IsEnabled() bool { pm.mu.RLock(); defer pm.mu.RUnlock(); return pm.enabled }
func (pm *PeerManager) IsRunning() bool { pm.mu.RLock(); defer pm.mu.RUnlock(); return pm.running }

// BroadcastMutation tells peers to refresh a specific directory immediately.
func (pm *PeerManager) BroadcastMutation(bucket, path, parentPath, versionHint, operation string) {
	pm.mu.RLock()
	transport, discovery, enabled := pm.transport, pm.discovery, pm.enabled
	pm.mu.RUnlock()
	if !enabled || transport == nil || discovery == nil {
		return
	}
	event := PeerEvent{DeviceID: pm.identity.DeviceID, Sequence: atomic.AddUint64(&pm.seqCounter, 1), AccountFP: pm.accountFP,
		BucketFP: BucketFingerprint(pm.accountFP, bucket), PathHash: PathHash(pm.accountFP, path), ParentHash: PathHash(pm.accountFP, parentPath),
		Bucket: bucket, Path: path, ParentPath: parentPath, VersionHint: versionHint, Operation: operation, Timestamp: time.Now().UnixMilli(), Nonce: randomHex(8)}
	signed, err := event.Sign(pm.identity, pm.accountKey)
	if err != nil {
		log.Printf("[p2p/broadcast] sign: %v", err)
		return
	}
	for _, peer := range discovery.Peers() {
		go pm.sendToPeer(transport, peer, signed)
	}
}

func (pm *PeerManager) sendToPeer(transport *Transport, peer DiscoveredPeer, event SignedEvent) {
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	conn, err := transport.Connect(ctx, peer.Addr)
	if err == nil {
		err = transport.SendEvent(ctx, conn, event)
		_ = conn.CloseWithError(0, "done")
	}
	if err != nil {
		log.Printf("[p2p/broadcast] peer=%s error=%v", peer.DeviceID, err)
	}
}

func (pm *PeerManager) handleIncomingEvent(event SignedEvent) {
	pm.mu.RLock()
	receiver, accountFP, key := pm.receiver, pm.accountFP, append([]byte(nil), pm.accountKey...)
	pm.mu.RUnlock()
	if !event.Verify(key) || event.Event.AccountFP != accountFP || event.Event.Bucket == "" {
		return
	}
	if age := time.Since(time.UnixMilli(event.Event.Timestamp)); age > 5*time.Minute || age < -time.Minute {
		return
	}
	if receiver != nil {
		receiver.OnPeerEvent(accountFP, event.Event.Bucket, event.Event.ParentPath, event.Event.Operation)
	}
}

func (pm *PeerManager) onPeerJoined(peer DiscoveredPeer) {
	log.Printf("[p2p/manager] peer-online device=%s addr=%s", peer.DeviceID, peer.Addr)
}
func (pm *PeerManager) onPeerLeft(deviceID string) {
	log.Printf("[p2p/manager] peer-offline device=%s", deviceID)
}

// Status produces a stable UI snapshot.
func (pm *PeerManager) Status() PeerStatus {
	pm.mu.RLock()
	enabled, device, discovery, started := pm.enabled, pm.identity.DeviceID, pm.discovery, pm.startedAt
	pm.mu.RUnlock()
	status := PeerStatus{Enabled: enabled, DeviceID: device, Peers: []PeerInfo{}, StartedAt: started}
	if discovery != nil {
		for _, peer := range discovery.Peers() {
			status.Peers = append(status.Peers, PeerInfo{DeviceID: peer.DeviceID, Addr: peer.Addr, LastSeen: peer.LastSeen.Format(time.RFC3339)})
		}
	}
	return status
}
func (pm *PeerManager) StatusJSON() ([]byte, error) { return json.Marshal(pm.Status()) }
func (pm *PeerManager) SetEnabled(enabled bool) error {
	pm.mu.Lock()
	pm.enabled = enabled
	pm.mu.Unlock()
	if enabled {
		return pm.Start()
	}
	pm.Stop()
	return nil
}
func (pm *PeerManager) DeviceID() string  { return pm.identity.DeviceID }
func (pm *PeerManager) AccountFP() string { return pm.accountFP }
func (pm *PeerManager) chunkSize() int64 {
	pm.mu.RLock()
	defer pm.mu.RUnlock()
	return int64(pm.chunkSizeMB) * 1024 * 1024
}
func (pm *PeerManager) peerSnapshot() (*Transport, []DiscoveredPeer) {
	pm.mu.RLock()
	defer pm.mu.RUnlock()
	if !pm.running || pm.transport == nil || pm.discovery == nil {
		return nil, nil
	}
	return pm.transport, pm.discovery.Peers()
}
func normalizeChunkSizeMB(value int) int {
	if value < 1 || value > 64 {
		return 4
	}
	return value
}
