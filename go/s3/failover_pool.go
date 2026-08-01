// failover_pool.go builds a multi-endpoint S3 client pool with transferable-
// error failover, mirroring the JWanFS SDK lb/s3 failover model on top of the
// aws-sdk-go-v2 client used throughout this package.
//
// When the configured endpoint is a JWanFS file gateway, the pool participates
// in gateway discovery (fgw-lb gateway-list + latency probing) so the data
// plane automatically tracks the live gateway set. For generic S3 endpoints
// the pool contains the single configured endpoint (or the manually-configured
// multi-endpoint list when one is provided).
package s3

import (
	"context"
	"errors"
	"fmt"
	"net"
	"net/url"
	"strings"
	"sync"
	"time"

	"github.com/aws/aws-sdk-go-v2/service/s3"

	storageconfig "remote-storage/go/config"
	jwanfs "remote-storage/go/jwanfs"
)

// jwanfsDetectionTimeout bounds the JWanFS gateway probe performed during S3
// client construction. The probe runs before any per-request context exists,
// so without this bound an unreachable endpoint stalls the whole bucket load.
// Kept to a single dial's worth (3s, matching proxyDialTimeout): the probe
// dials the endpoint, and if that one dial cannot connect within 3s the
// endpoint is treated as non-JWanFS (and ListBuckets will fail fast against
// it). A longer window just stacks multiple failed dials (Refresh + AuthInfo).
const jwanfsDetectionTimeout = 3 * time.Second

// upstreamS3 pairs one endpoint URL with its dedicated aws-sdk-go-v2 client.
type upstreamS3 struct {
	server string
	client *s3.Client
}

// FailoverClient wraps a pool of per-endpoint *s3.Client instances and drives
// S3 data-plane calls across them with transferable-error failover.
type FailoverClient struct {
	cfg     storageconfig.RemoteStorageConfig
	options []func(*s3.Options)

	mu           sync.RWMutex
	upstreams    []*upstreamS3
	defaultIdx   int
	balancer     *jwanfs.Client // nil for generic S3
	stopBalancer bool
}

// NewFailoverClient builds the failover pool from cfg. It performs JWanFS
// gateway discovery when applicable and falls back to direct connect otherwise.
func NewFailoverClient(cfg storageconfig.RemoteStorageConfig) *FailoverClient {
	options := singleObjectClientOptions(cfg)
	fc := &FailoverClient{
		cfg:        cfg,
		options:    options,
		defaultIdx: -1,
	}

	normalized := cfg.Normalized()
	servers := failoverServers(normalized)

	// The gateway detection + balancer refresh happen during client construction,
	// before any per-request context is established. An unreachable endpoint
	// would otherwise stall here on the OS-level TCP timeout (~1-2 minutes),
	// which neither the ListBuckets request context nor the bridge timeout can
	// interrupt (the probe uses its own context.Background). Bound the whole
	// construction phase so a dead upstream surfaces as a fast failure instead
	// of locking the multi-account bucket load.
	mode := jwanfs.ParseDetectionMode(normalized.JWanFSGatewayMode)
	detectCtx, detectCancel := context.WithTimeout(context.Background(), jwanfsDetectionTimeout)
	defer detectCancel()
	if jwanfs.IsJWanFSGateway(detectCtx, normalized, mode) {
		if balancer, err := jwanfs.NewClient(&jwanfs.ClientOption{
			Ak:      normalized.AccessKeyID,
			Sk:      normalized.SecretAccessKey,
			Servers: servers,
		}); err == nil {
			fc.balancer = balancer
			if discovered := balancer.Servers(); len(discovered) > 0 {
				servers = discovered
			}
		}
	}

	fc.replaceUpstreams(servers)
	return fc
}

// Stop releases background resources (balancer goroutine). Callers using a
// FailoverClient for a one-shot operation should defer this.
func (fc *FailoverClient) Stop() {
	if fc == nil {
		return
	}
	fc.mu.Lock()
	defer fc.mu.Unlock()
	if fc.stopBalancer {
		return
	}
	fc.stopBalancer = true
	if fc.balancer != nil {
		fc.balancer.BalancerStop()
	}
}

// DefaultClient returns the currently active upstream's *s3.Client.
func (fc *FailoverClient) DefaultClient() *s3.Client {
	fc.mu.RLock()
	defer fc.mu.RUnlock()
	if fc.defaultIdx < 0 || fc.defaultIdx >= len(fc.upstreams) {
		return nil
	}
	return fc.upstreams[fc.defaultIdx].client
}

// DefaultServer returns the currently active endpoint URL.
func (fc *FailoverClient) DefaultServer() string {
	fc.mu.RLock()
	defer fc.mu.RUnlock()
	if fc.defaultIdx < 0 || fc.defaultIdx >= len(fc.upstreams) {
		return ""
	}
	return fc.upstreams[fc.defaultIdx].server
}

// Servers returns a copy of the current endpoint list.
func (fc *FailoverClient) Servers() []string {
	fc.mu.RLock()
	defer fc.mu.RUnlock()
	out := make([]string, 0, len(fc.upstreams))
	for _, u := range fc.upstreams {
		if u != nil {
			out = append(out, u.server)
		}
	}
	return out
}

// orderedUpstreams returns candidate upstreams ordered by preference: the
// current default first, then the remaining pool.
func (fc *FailoverClient) orderedUpstreams() []*upstreamS3 {
	fc.mu.RLock()
	defer fc.mu.RUnlock()
	if len(fc.upstreams) == 0 {
		return nil
	}
	order := make([]*upstreamS3, 0, len(fc.upstreams))
	seen := make(map[int]struct{}, len(fc.upstreams))
	add := func(idx int) {
		if idx < 0 || idx >= len(fc.upstreams) || fc.upstreams[idx] == nil {
			return
		}
		if _, ok := seen[idx]; ok {
			return
		}
		order = append(order, fc.upstreams[idx])
		seen[idx] = struct{}{}
	}
	add(fc.defaultIdx)
	for i := range fc.upstreams {
		add(i)
	}
	return order
}

// setDefault records the upstream that succeeded so subsequent calls prefer it.
func (fc *FailoverClient) setDefault(server string) {
	fc.mu.Lock()
	defer fc.mu.Unlock()
	for i, u := range fc.upstreams {
		if u != nil && u.server == server {
			fc.defaultIdx = i
			return
		}
	}
}

// replaceUpstreams rebuilds the per-endpoint client pool from servers.
func (fc *FailoverClient) replaceUpstreams(servers []string) {
	normalized := normalizeS3Servers(servers...)
	if len(normalized) == 0 {
		return
	}
	next := make([]*upstreamS3, 0, len(normalized))
	for _, server := range normalized {
		client := newSingleEndpointClient(fc.cfg, server)
		next = append(next, &upstreamS3{server: server, client: client})
	}
	if len(next) == 0 {
		return
	}
	fc.mu.Lock()
	defer fc.mu.Unlock()
	fc.upstreams = next
	fc.defaultIdx = 0
}

// DoWithFallback runs fn against the ordered upstream pool, switching to the
// next upstream on transferable errors (5xx/429/network). The first argument
// passed to fn is the *s3.Client for the upstream being tried.
func DoWithFallback[T any](fc *FailoverClient, fn func(client *s3.Client) (T, error)) (T, error) {
	var zero T
	order := fc.orderedUpstreams()
	if len(order) == 0 {
		return zero, errors.New("no available S3 upstreams")
	}
	var errs []error
	for _, upstream := range order {
		result, err := fn(upstream.client)
		if err == nil {
			fc.setDefault(upstream.server)
			return result, nil
		}
		errs = append(errs, err)
		if !shouldFallbackS3(err) {
			return zero, err
		}
	}
	return zero, joinS3Errors(errs...)
}

// singleObjectClientOptions returns the shared aws-sdk-go-v2 options (creds,
// region, path style, proxy) applied to every per-endpoint client.
func singleObjectClientOptions(cfg storageconfig.RemoteStorageConfig) []func(*s3.Options) {
	return nil // newSingleEndpointClient applies them directly from cfg
}

// failoverServers returns the initial endpoint list for the pool: the
// configured endpoint plus any extra endpoints the user supplied.
func failoverServers(cfg storageconfig.RemoteStorageConfig) []string {
	servers := []string{cfg.Endpoint}
	return normalizeS3Servers(servers...)
}

// shouldFallbackS3 reports whether err is a transferable failure that should
// trigger a switch to the next endpoint (5xx, 429, network/timeout errors).
func shouldFallbackS3(err error) bool {
	if err == nil {
		return false
	}
	if errors.Is(err, context.Canceled) || errors.Is(err, context.DeadlineExceeded) {
		return true
	}
	var netErr net.Error
	if errors.As(err, &netErr) {
		return true
	}
	var urlErr *url.Error
	if errors.As(err, &urlErr) {
		return true
	}
	status := s3HTTPStatus(err)
	return status == 429 || status >= 500
}

// joinS3Errors combines multiple errors into one (errors.Join equivalent).
func joinS3Errors(errs ...error) error {
	switch len(errs) {
	case 0:
		return nil
	case 1:
		return errs[0]
	}
	msgs := make([]string, 0, len(errs))
	for _, e := range errs {
		if e == nil {
			continue
		}
		msgs = append(msgs, e.Error())
	}
	return fmt.Errorf("%s", strings.Join(msgs, "; "))
}

// normalizeS3Servers trims, scheme-prefixes, and deduplicates endpoint URLs.
func normalizeS3Servers(servers ...string) []string {
	list := make([]string, 0, len(servers))
	seen := make(map[string]struct{}, len(servers))
	for _, server := range servers {
		server = strings.TrimSpace(server)
		if server == "" {
			continue
		}
		if !strings.HasPrefix(server, "http://") && !strings.HasPrefix(server, "https://") {
			server = "http://" + server
		}
		server = strings.TrimSuffix(server, "/")
		if _, ok := seen[server]; ok {
			continue
		}
		seen[server] = struct{}{}
		list = append(list, server)
	}
	return list
}

