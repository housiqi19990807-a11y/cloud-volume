// Discovery tests keep the mDNS registration values compatible with hashicorp/mdns.
package p2p

import (
	"errors"
	"net"
	"syscall"
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

func TestMulticastRouteUnavailableUsesInterfaceBackoff(t *testing.T) {
	iface := net.Interface{Name: "test-mdns-no-route"}
	clearMulticastInterfaceBlock(iface)
	if multicastInterfaceBlocked(iface) {
		t.Fatal("interface unexpectedly blocked before error")
	}
	blockMulticastInterface(iface)
	if !multicastInterfaceBlocked(iface) {
		t.Fatal("interface was not blocked after no-route error")
	}
	clearMulticastInterfaceBlock(iface)
	if multicastInterfaceBlocked(iface) {
		t.Fatal("interface block was not cleared")
	}
}

func TestMulticastRouteErrorClassification(t *testing.T) {
	if !isMulticastRouteUnavailable(&net.OpError{Err: syscall.EHOSTUNREACH}) {
		t.Fatal("host-unreachable error was not classified")
	}
	if !isMulticastRouteUnavailable(&net.OpError{Err: syscall.ENETUNREACH}) {
		t.Fatal("network-unreachable error was not classified")
	}
	if isMulticastRouteUnavailable(errors.New("permission denied")) {
		t.Fatal("permission error was misclassified as a route error")
	}
}
