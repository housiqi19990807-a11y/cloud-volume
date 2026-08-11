package jwanfs

import (
	"context"
	"net"
	"testing"
	"time"

	storageconfig "remote-storage/go/config"
)

// configForEndpoint builds a minimal S3 RemoteStorageConfig for tests.
func configForEndpoint(endpoint string) storageconfig.RemoteStorageConfig {
	return storageconfig.RemoteStorageConfig{
		Endpoint:        endpoint,
		StorageType:     storageconfig.StorageTypeS3,
		AccessKeyID:     "ak",
		SecretAccessKey: "sk",
	}
}

func TestConfigForEndpoint(t *testing.T) {
	cfg := configForEndpoint("http://example")
	if cfg.Endpoint != "http://example" || cfg.AccessKeyID != "ak" {
		t.Fatalf("unexpected cfg: %+v", cfg)
	}
}

// freeEndpoint listens on an ephemeral port, captures the address, then closes
// the listener so the address actively refuses connections. This simulates an
// unreachable upstream that fails fast rather than silently dropping packets.
func freeEndpoint(t *testing.T) string {
	t.Helper()
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatalf("listen: %v", err)
	}
	addr := "http://" + ln.Addr().String()
	if err := ln.Close(); err != nil {
		t.Fatalf("close listener: %v", err)
	}
	return addr
}

// TestIsJWanFSGatewayDoesNotHangOnUnreachableEndpoint pins the construction-
// phase timeout fix. Before the bound, an unreachable endpoint stalled on the
// OS-level TCP timeout (~1-2 minutes), which neither the S3 ListBuckets
// context nor the bridge list_buckets timeout could interrupt (detection runs
// during client construction, before those contexts exist). It must now return
// promptly — well under the gatewayRefreshTimeout — and report not-JWanFS.
func TestIsJWanFSGatewayDoesNotHangOnUnreachableEndpoint(t *testing.T) {
	endpoint := freeEndpoint(t)
	cfg := configForEndpoint(endpoint)

	// Clear any cached detection so the probe actually runs.
	InvalidateDetectionCache(cfg)

	deadline := time.Now().Add(gatewayRefreshTimeout + 2*time.Second)
	ctx, cancel := context.WithTimeout(context.Background(), gatewayRefreshTimeout)
	defer cancel()

	done := make(chan bool, 1)
	go func() {
		done <- IsJWanFSGateway(ctx, cfg, DetectionAuto)
	}()

	select {
	case isJWanFS := <-done:
		if isJWanFS {
			t.Fatal("unreachable endpoint must not be detected as JWanFS")
		}
		if time.Now().After(deadline) {
			t.Fatalf("detection ran past the construction-phase bound")
		}
	case <-time.After(gatewayRefreshTimeout + 2*time.Second):
		t.Fatal("IsJWanFSGateway hung on unreachable endpoint; construction-phase timeout missing")
	}
}

// TestNewClientFallsBackOnUnreachableGateway verifies NewClient does not hang
// when balancer discovery cannot reach the gateway: discovery failure must
// fall back to direct connect within the construction-phase bound, returning a
// usable client (or an explicit error) rather than blocking.
func TestNewClientFallsBackOnUnreachableGateway(t *testing.T) {
	endpoint := freeEndpoint(t)

	deadline := gatewayRefreshTimeout + 2*time.Second
	done := make(chan struct{})
	go func() {
		defer close(done)
		_, _ = NewClient(&ClientOption{
			Ak:      "ak",
			Sk:      "sk",
			Servers: []string{endpoint},
		})
	}()

	select {
	case <-done:
		// NewClient returned (success via fallback or explicit error) — the
		// important property is that it did not block past the bound.
	case <-time.After(deadline):
		t.Fatal("NewClient hung on unreachable gateway; balancer refresh bound missing")
	}
}

