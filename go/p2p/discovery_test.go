// Discovery tests keep the mDNS registration values compatible with hashicorp/mdns.
package p2p

import (
	"net"
	"testing"

	"github.com/hashicorp/mdns"
)

func TestDiscoveryMDNSRegistrationUsesServiceAndFQDN(t *testing.T) {
	service, err := mdns.NewMDNSService(
		"test-device",
		mdnsService,
		mdnsDomain,
		"test-host.local.",
		56708,
		[]net.IP{net.ParseIP("127.0.0.1")},
		nil,
	)
	if err != nil {
		t.Fatalf("create mDNS service: %v", err)
	}
	if service.Service != "_cloudvolume._tcp" || service.Domain != "local." {
		t.Fatalf("unexpected mDNS registration: service=%q domain=%q", service.Service, service.Domain)
	}
}
