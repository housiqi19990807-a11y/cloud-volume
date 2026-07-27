// mDNS-based LAN discovery for trusted peers with matching account fingerprints.
package p2p

import (
	"context"
	"fmt"
	"log"
	"net"
	"strconv"
	"sync"
	"time"

	"github.com/hashicorp/mdns"
)

const (
	mdnsService = "_cloudvolume"
	mdnsProto   = "_tcp"
	// discoveryInterval controls how often we query for peers on the LAN.
	discoveryInterval = 30 * time.Second
	// peerExpiry is how long since last-seen before a peer is considered gone.
	peerExpiry = 90 * time.Second
)

// DiscoveredPeer represents another device on the LAN that shares our account.
type DiscoveredPeer struct {
	DeviceID  string    // from mDNS TXT record
	AccountFP string    // account fingerprint from TXT record
	Addr      string    // IP:Port for QUIC connections
	LastSeen  time.Time // last mDNS response time
}

// Discovery manages mDNS service registration and browsing.
type Discovery struct {
	identity  *DeviceIdentity
	accountFP string
	quicPort  int

	mu    sync.Mutex
	peers map[string]*DiscoveredPeer // keyed by DeviceID

	server   *mdns.Server
	cancel   context.CancelFunc
	stopOnce sync.Once
	stopCh   chan struct{}
	doneCh   chan struct{}

	onPeerJoined func(DiscoveredPeer)
	onPeerLeft   func(string)
}

// NewDiscovery creates a discovery instance. accountFP must match what the
// other device computes from the same endpoint + access key.
func NewDiscovery(identity *DeviceIdentity, accountFP string, quicPort int) *Discovery {
	return &Discovery{
		identity:  identity,
		accountFP: accountFP,
		quicPort:  quicPort,
		peers:     make(map[string]*DiscoveredPeer),
		stopCh:    make(chan struct{}),
		doneCh:    make(chan struct{}),
	}
}

// SetCallbacks registers handlers for peer join/leave events.
func (d *Discovery) SetCallbacks(joined func(DiscoveredPeer), left func(string)) {
	d.onPeerJoined = joined
	d.onPeerLeft = left
}

// Start registers the mDNS service and begins periodic browsing.
func (d *Discovery) Start() error {
	service, err := mdns.NewMDNSService(
		d.identity.DeviceID,
		mdnsService,
		mdnsProto,
		"",
		d.quicPort,
		nil,
		[]string{
			fmt.Sprintf("fp=%s", d.accountFP),
			fmt.Sprintf("dev=%s", d.identity.DeviceID),
		},
	)
	if err != nil {
		return fmt.Errorf("mdns service: %w", err)
	}
	server, err := mdns.NewServer(&mdns.Config{Zone: service})
	if err != nil {
		return fmt.Errorf("mdns server: %w", err)
	}
	d.server = server

	ctx, cancel := context.WithCancel(context.Background())
	d.cancel = cancel
	go d.browseLoop(ctx)
	log.Printf("[p2p/discovery] started device=%s port=%d", d.identity.DeviceID, d.quicPort)
	return nil
}

// browseLoop periodically queries the LAN for peers until Stop.
func (d *Discovery) browseLoop(ctx context.Context) {
	defer close(d.doneCh)
	ticker := time.NewTicker(discoveryInterval)
	defer ticker.Stop()
	d.queryPeers()
	for {
		select {
		case <-d.stopCh:
			return
		case <-ctx.Done():
			return
		case <-ticker.C:
			d.queryPeers()
			d.expirePeers()
		}
	}
}

// queryPeers sends one mDNS query and processes matching responses.
func (d *Discovery) queryPeers() {
	entriesCh := make(chan *mdns.ServiceEntry, 16)
	go func() {
		for entry := range entriesCh {
			d.processEntry(entry)
		}
	}()
	params := &mdns.QueryParam{
		Service:             mdnsService + "." + mdnsProto,
		Domain:              "local",
		Timeout:             5 * time.Second,
		Entries:             entriesCh,
		WantUnicastResponse: false,
	}
	if err := mdns.Query(params); err != nil {
		log.Printf("[p2p/discovery] query-error: %v", err)
	}
	close(entriesCh)
}

// processEntry inspects one mDNS response; adds or refreshes matching peers.
func (d *Discovery) processEntry(entry *mdns.ServiceEntry) {
	var fp, devID string
	for _, txt := range entry.InfoFields {
		if len(txt) > 3 && txt[:3] == "fp=" {
			fp = txt[3:]
		}
		if len(txt) > 4 && txt[:4] == "dev=" {
			devID = txt[4:]
		}
	}
	if fp != d.accountFP || devID == "" || devID == d.identity.DeviceID {
		return
	}
	ip := entry.AddrV4
	if ip == nil && len(entry.AddrV6) > 0 {
		ip = entry.AddrV6
	}
	if ip == nil {
		return
	}
	addr := net.JoinHostPort(ip.String(), strconv.Itoa(entry.Port))
	now := time.Now()
	d.mu.Lock()
	existing, existed := d.peers[devID]
	if existed {
		existing.LastSeen = now
		existing.Addr = addr
	} else {
		d.peers[devID] = &DiscoveredPeer{
			DeviceID:  devID,
			AccountFP: fp,
			Addr:      addr,
			LastSeen:  now,
		}
	}
	peer := *d.peers[devID]
	d.mu.Unlock()
	if !existed && d.onPeerJoined != nil {
		d.onPeerJoined(peer)
		log.Printf("[p2p/discovery] peer-joined device=%s addr=%s", devID, addr)
	}
}

// expirePeers removes peers not seen within peerExpiry.
func (d *Discovery) expirePeers() {
	now := time.Now()
	d.mu.Lock()
	var expired []string
	for id, peer := range d.peers {
		if now.Sub(peer.LastSeen) > peerExpiry {
			delete(d.peers, id)
			expired = append(expired, id)
		}
	}
	d.mu.Unlock()
	if d.onPeerLeft != nil {
		for _, id := range expired {
			d.onPeerLeft(id)
			log.Printf("[p2p/discovery] peer-left device=%s", id)
		}
	}
}

// Peers returns a snapshot of currently discovered peers.
func (d *Discovery) Peers() []DiscoveredPeer {
	d.mu.Lock()
	defer d.mu.Unlock()
	out := make([]DiscoveredPeer, 0, len(d.peers))
	for _, p := range d.peers {
		out = append(out, *p)
	}
	return out
}

// Stop shuts down the mDNS server and browsing loop.
func (d *Discovery) Stop() {
	d.stopOnce.Do(func() {
		if d.cancel != nil {
			d.cancel()
		}
		close(d.stopCh)
		<-d.doneCh
		if d.server != nil {
			_ = d.server.Shutdown()
		}
	})
}
