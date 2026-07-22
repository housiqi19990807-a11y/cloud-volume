// GatewayBalancer discovers JWanFS gateways, probes them for health/latency,
// and keeps the Client's upstream pool sorted so failover prefers the fastest
// healthy gateway. Migrated from jwanfs/pkg/sdk/s3/lb.go.
package jwanfs

import (
	"context"
	"fmt"
	"net/http"
	"sort"
	"strings"
	"sync"
	"time"

	"remote-storage/go/jwanfs/types"
)

const (
	defaultDiscoveryTimeout       = 3 * time.Second
	defaultGatewayProbeTimeout    = 2 * time.Second
	defaultGatewayRefreshInterval = time.Hour
	gatewayHealthPath             = "/status"
)

// GatewayBalancer periodically re-discovers the gateway list and re-sorts the
// client's upstream pool by measured latency.
type GatewayBalancer struct {
	client     *Client
	lbEndpoint string

	discoveryTimeout time.Duration
	probeTimeout     time.Duration
	refreshInterval  time.Duration

	startOnce sync.Once
	stopOnce  sync.Once
	stopCh    chan struct{}
}

type gatewayHealthResult struct {
	server  string
	latency time.Duration
	err     error
}

func newGatewayBalancer(client *Client, lbEndpoint string) *GatewayBalancer {
	return &GatewayBalancer{
		client:           client,
		lbEndpoint:       lbEndpoint,
		discoveryTimeout: defaultDiscoveryTimeout,
		probeTimeout:     defaultGatewayProbeTimeout,
		refreshInterval:  defaultGatewayRefreshInterval,
		stopCh:           make(chan struct{}),
	}
}

// Start launches the periodic refresh goroutine (idempotent).
func (b *GatewayBalancer) Start() {
	if b == nil || b.refreshInterval <= 0 {
		return
	}
	b.startOnce.Do(func() {
		go func() {
			ticker := time.NewTicker(b.refreshInterval)
			defer ticker.Stop()
			for {
				select {
				case <-ticker.C:
					_ = b.Refresh(context.Background())
				case <-b.stopCh:
					return
				}
			}
		}()
	})
}

// Stop terminates the refresh goroutine (idempotent).
func (b *GatewayBalancer) Stop() {
	if b == nil {
		return
	}
	b.stopOnce.Do(func() { close(b.stopCh) })
}

// Refresh discovers the gateway list, probes each gateway, and installs the
// fastest healthy gateway as the primary upstream with the rest as fallbacks.
func (b *GatewayBalancer) Refresh(ctx context.Context) error {
	if b == nil || b.client == nil {
		return fmt.Errorf("gateway balancer not initialized")
	}
	ctx = ctxOrBackground(ctx)

	servers, err := b.discoverGatewayList(ctx)
	if err != nil {
		b.client.debugf("GatewayBalancer discovery failed: %v", err)
		return err
	}

	// The discovered gateways are preferred when reachable; the configured LB
	// remains a public fallback for clients that cannot reach internal gateways.
	servers = normalizeServers(append(servers, b.lbEndpoint)...)
	primary, remaining, probeCh := b.probeFirst(ctx, servers)
	if primary == "" {
		primary = servers[0]
	}

	// Install the first healthy responder immediately. The remaining probes are
	// drained asynchronously and only healthy gateways are added as fallbacks.
	if err := b.client.replaceUpstreams([]string{primary}, primary); err != nil {
		b.client.debugf("GatewayBalancer initial upstream setup failed: %v", err)
		return err
	}
	go b.resortByLatency(probeCh, remaining, servers, primary)

	b.client.debugf("GatewayBalancer primary gateway: %s", b.client.DefaultServer())
	return nil
}

// discoverGatewayList calls the gateway-list FGW route on the LB endpoint.
func (b *GatewayBalancer) discoverGatewayList(ctx context.Context) ([]string, error) {
	timeout := b.discoveryTimeout
	if timeout <= 0 {
		timeout = defaultDiscoveryTimeout
	}
	ctx, cancel := context.WithTimeout(ctx, timeout)
	defer cancel()

	urlValue, err := NewFGWAPI(b.lbEndpoint, types.FGWS3APIGatewayList)
	if err != nil {
		return nil, err
	}

	data, status, err := b.client.httpGet(ctx, urlValue.String(), nil)
	if err != nil {
		return nil, err
	}
	if status < http.StatusOK || status >= http.StatusMultipleChoices {
		return nil, fmt.Errorf("gateway discovery status=%d body=%s", status, string(data))
	}

	var fgwResp types.FGWResp[[]string]
	if err := readJSON(data, &fgwResp); err != nil {
		return nil, err
	}
	if fgwResp.Code != http.StatusOK {
		if fgwResp.Msg == "" {
			fgwResp.Msg = "gateway discovery failed"
		}
		return nil, fmt.Errorf("%s", fgwResp.Msg)
	}
	if fgwResp.Data == nil {
		return nil, fmt.Errorf("gateway discovery data is nil")
	}
	// servers是fgw-lb返回的fgws
	servers := normalizeServers((*fgwResp.Data)...)
	if len(servers) == 0 {
		return nil, fmt.Errorf("gateway discovery data is empty")
	}
	return servers, nil
}

// probeFirst launches concurrent health probes for all servers and returns as
// soon as the first server responds successfully. It returns the primary server
// and a channel still receiving the remaining results for async re-sorting.
func (b *GatewayBalancer) probeFirst(ctx context.Context, servers []string) (primary string, remaining int, results chan gatewayHealthResult) {
	servers = normalizeServers(servers...)
	total := len(servers)
	results = make(chan gatewayHealthResult, total)

	if total == 0 {
		close(results)
		return "", 0, results
	}

	for _, server := range servers {
		go func(endpoint string) {
			latency, err := b.probeGateway(ctx, endpoint)
			results <- gatewayHealthResult{
				server:  endpoint,
				latency: latency,
				err:     err,
			}
		}(server)
	}

	// Read until we find the first healthy server (or exhaust all).
	drained := 0
	var firstHealthy *gatewayHealthResult
	for i := 0; i < total; i++ {
		r := <-results
		drained++
		if r.err == nil && firstHealthy == nil {
			fr := r
			firstHealthy = &fr
		}
		if firstHealthy != nil {
			// Stop early — remaining goroutines still write to the buffered chan.
			break
		}
	}

	if firstHealthy != nil {
		primary = firstHealthy.server
		// Push the captured result back so resortByLatency sees it.
		results <- *firstHealthy
		// remaining = total - (drained - 1 re-added) = total - drained + 1
		remaining = total - drained + 1
	}
	return primary, remaining, results
}

// resortByLatency drains the remaining probe results (launched by probeFirst),
// builds a latency-sorted server list, and updates the client's upstream pool.
// Runs asynchronously — the client is already operational; this just optimizes
// fallback priority based on measured latency.
func (b *GatewayBalancer) resortByLatency(probeCh chan gatewayHealthResult, remaining int, servers []string, currentPrimary string) {
	var healthy []gatewayHealthResult
	for i := 0; i < remaining; i++ {
		r := <-probeCh
		if r.err == nil {
			healthy = append(healthy, r)
		}
	}

	if len(healthy) == 0 {
		return
	}

	sort.SliceStable(healthy, func(i, j int) bool {
		return healthy[i].latency < healthy[j].latency
	})

	// Keep current primary first, then sorted healthy, then unreachable.
	// Only include servers that responded successfully — unreachable ones
	// are excluded from the candidate pool so fallback never routes to them.
	sorted := make([]string, 0, len(healthy)+1)
	sorted = append(sorted, currentPrimary)
	seen := map[string]bool{currentPrimary: true}
	for _, h := range healthy {
		if !seen[h.server] {
			sorted = append(sorted, h.server)
			seen[h.server] = true
		}
	}

	_ = b.client.replaceUpstreams(sorted, currentPrimary)
	b.client.debugf("GatewayBalancer latency re-sort: %v", sorted)
}

// probeGateway measures the round-trip latency of a GET /status request.
func (b *GatewayBalancer) probeGateway(ctx context.Context, server string) (time.Duration, error) {
	ctx = ctxOrBackground(ctx)

	timeout := b.probeTimeout
	if timeout <= 0 {
		timeout = defaultGatewayProbeTimeout
	}
	ctx, cancel := context.WithTimeout(ctx, timeout)
	defer cancel()

	req, err := http.NewRequestWithContext(ctx, http.MethodGet, strings.TrimRight(server, "/")+gatewayHealthPath, nil)
	if err != nil {
		return 0, err
	}

	start := time.Now()
	resp, err := b.client.HTTPClient().Do(req)
	latency := time.Since(start)
	if err != nil {
		return latency, err
	}
	defer resp.Body.Close()

	if resp.StatusCode < http.StatusOK || resp.StatusCode >= http.StatusBadRequest {
		return latency, fmt.Errorf("gateway health status=%d", resp.StatusCode)
	}
	return latency, nil
}

