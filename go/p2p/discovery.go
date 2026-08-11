// mDNS-based LAN discovery for trusted peers with matching account fingerprints.
package p2p

import (
	"context"
	"errors"
	"fmt"
	"io"
	"log"
	"net"
	"strconv"
	"sync"
	"syscall"
	"time"

	"github.com/hashicorp/mdns"
	"github.com/miekg/dns"
)

const (
	mdnsService = "_cloudvolume._tcp"
	// mdnsDomain must remain an FQDN because hashicorp/mdns validates it on registration.
	mdnsDomain = "local."
	// discoveryInterval controls how often we query for peers on the LAN.
	discoveryInterval = 30 * time.Second
	// peerExpiry is how long since last-seen before a peer is considered gone.
	peerExpiry = 90 * time.Second
	// multicastRouteBackoff avoids retrying an interface that currently has no
	// route to the mDNS multicast group on every account/ticker cycle.
	multicastRouteBackoff = 2 * time.Minute
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

	server   *sharedMDNS
	cancel   context.CancelFunc
	stopOnce sync.Once
	stopCh   chan struct{}
	doneCh   chan struct{}

	onPeerJoined func(DiscoveredPeer)
	onPeerLeft   func(string)
}

// sharedMDNS owns one UDP 5353 socket and multiplexes several account
// fingerprints on it. hashicorp/mdns binds 5353 per Server, so parallel
// managers on the same device would fight for the port and lose broadcasts.
type sharedMDNS struct {
	server *mdns.Server
	zone   *multiServiceZone
}

var (
	sharedOnce sync.Once
	sharedInst *sharedMDNS
	sharedErr  error

	multicastRouteState = struct {
		sync.Mutex
		blocked map[string]time.Time
	}{blocked: make(map[string]time.Time)}
)

func sharedMDNSServer() (*sharedMDNS, error) {
	sharedOnce.Do(func() {
		zone := &multiServiceZone{svcs: map[string]*mdns.MDNSService{}}
		server, err := mdns.NewServer(&mdns.Config{
			Zone: zone,
			// Silence the IPv6 listener warning; many LANs have no routable
			// IPv6 multicast and hashicorp/mdns logs it as INFO every query.
			Logger: log.New(io.Discard, "", 0),
		})
		if err != nil {
			sharedErr = err
			return
		}
		sharedInst = &sharedMDNS{server: server, zone: zone}
	})
	return sharedInst, sharedErr
}

// multiServiceZone implements mdns.Zone by fanning queries out to every
// registered account fingerprint. It lets one socket serve many accounts.
type multiServiceZone struct {
	mu   sync.RWMutex
	svcs map[string]*mdns.MDNSService
}

// Records answers an mDNS query by merging records from every registered
// fingerprint service that matches the question.
func (z *multiServiceZone) Records(q dns.Question) []dns.RR {
	z.mu.RLock()
	defer z.mu.RUnlock()
	var out []dns.RR
	for _, svc := range z.svcs {
		out = append(out, svc.Records(q)...)
	}
	return out
}

// add registers one account fingerprint's records under the shared socket.
func (z *multiServiceZone) add(fp string, svc *mdns.MDNSService) {
	z.mu.Lock()
	defer z.mu.Unlock()
	z.svcs[fp] = svc
}

// remove deregisters one account fingerprint; the socket stays open.
func (z *multiServiceZone) remove(fp string) {
	z.mu.Lock()
	defer z.mu.Unlock()
	delete(z.svcs, fp)
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

// Start registers the mDNS service and begins periodic browsing. Multiple
// account fingerprints share one mDNS server to avoid UDP 5353 port
// conflicts when several managers start on the same device.
func (d *Discovery) Start() error {
	shared, err := sharedMDNSServer()
	if err != nil {
		return fmt.Errorf("mdns server: %w", err)
	}
	service, err := mdns.NewMDNSService(
		d.identity.DeviceID,
		mdnsService,
		mdnsDomain,
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
	shared.zone.add(d.accountFP, service)
	d.server = shared

	ctx, cancel := context.WithCancel(context.Background())
	d.cancel = cancel
	go d.browseLoop(ctx)
	log.Printf("[p2p/discovery] started device=%s port=%d fp=%s", d.identity.DeviceID, d.quicPort, d.accountFP)
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
	// Query every multicast-capable interface that has an IPv4 address.
	// The default query only uses the primary interface, so peers reachable
	// through a secondary NIC (e.g. VMware bridge on en1) are missed.
	ifaces := multicastIPv4Interfaces()
	if len(ifaces) == 0 {
		ifaces = []net.Interface{{}} // zero value = library default
	}
	for _, iface := range ifaces {
		if multicastInterfaceBlocked(iface) {
			continue
		}
		ifaceCopy := iface
		params := &mdns.QueryParam{
			Service:             mdnsService,
			Domain:              mdnsDomain,
			Timeout:             5 * time.Second,
			Entries:             entriesCh,
			WantUnicastResponse: false,
			Interface:           &ifaceCopy,
			// Disable IPv6: many LANs (VMware bridge, Windows firewall) have no
			// routable IPv6 multicast, which makes hashicorp/mdns spam
			// "Failed to bind to udp6 port" every query. IPv4 mDNS is sufficient.
			DisableIPv6: true,
			// Discard the library's INFO/ERR logs; DisableIPv6 already prevents
			// the IPv6 listener from being created, but the client still logs a
			// one-line notice on every query.
			Logger: log.New(io.Discard, "", 0),
		}
		if err := mdns.Query(params); err != nil {
			if isMulticastRouteUnavailable(err) {
				blockMulticastInterface(iface)
				log.Printf(
					"[p2p/discovery] query-suppressed iface=%s retry_after=%s err=%v",
					iface.Name,
					multicastRouteBackoff,
					err,
				)
			} else {
				log.Printf("[p2p/discovery] query-error iface=%s: %v", iface.Name, err)
			}
		} else {
			clearMulticastInterfaceBlock(iface)
		}
	}
	close(entriesCh)
}

func multicastInterfaceKey(iface net.Interface) string {
	if iface.Name == "" {
		return "<default>"
	}
	return iface.Name
}

func multicastInterfaceBlocked(iface net.Interface) bool {
	key := multicastInterfaceKey(iface)
	multicastRouteState.Lock()
	defer multicastRouteState.Unlock()
	until, ok := multicastRouteState.blocked[key]
	if !ok {
		return false
	}
	if time.Now().After(until) {
		delete(multicastRouteState.blocked, key)
		return false
	}
	return true
}

func blockMulticastInterface(iface net.Interface) {
	key := multicastInterfaceKey(iface)
	multicastRouteState.Lock()
	multicastRouteState.blocked[key] = time.Now().Add(multicastRouteBackoff)
	multicastRouteState.Unlock()
}

func clearMulticastInterfaceBlock(iface net.Interface) {
	key := multicastInterfaceKey(iface)
	multicastRouteState.Lock()
	delete(multicastRouteState.blocked, key)
	multicastRouteState.Unlock()
}

func isMulticastRouteUnavailable(err error) bool {
	return errors.Is(err, syscall.ENETUNREACH) || errors.Is(err, syscall.EHOSTUNREACH)
}

// multicastIPv4Interfaces returns up, multicast-capable interfaces with an
// IPv4 address, so discovery queries can target each LAN segment.
func multicastIPv4Interfaces() []net.Interface {
	ifaces, err := net.Interfaces()
	if err != nil {
		return nil
	}
	var out []net.Interface
	for _, iface := range ifaces {
		if iface.Flags&net.FlagUp == 0 || iface.Flags&net.FlagMulticast == 0 ||
			iface.Flags&net.FlagLoopback != 0 {
			continue
		}
		addrs, err := iface.Addrs()
		if err != nil {
			continue
		}
		for _, addr := range addrs {
			ipNet, ok := addr.(*net.IPNet)
			if ok && ipNet.IP.To4() != nil {
				out = append(out, iface)
				break
			}
		}
	}
	return out
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
	log.Printf("[p2p/discovery] matched-fp device=%s port=%d fp=%s", devID, entry.Port, fp)
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

// Stop deregisters this fingerprint from the shared socket and stops browsing.
// The UDP socket stays open while other account managers still need it.
func (d *Discovery) Stop() {
	d.stopOnce.Do(func() {
		if d.cancel != nil {
			d.cancel()
		}
		close(d.stopCh)
		<-d.doneCh
		if d.server != nil {
			d.server.zone.remove(d.accountFP)
		}
	})
}
