// Package jwanfs provides a JWanFS FGW (file-gateway) SDK client that supports
// multi-gateway discovery, latency-based load balancing, and automatic failover.
//
// It is migrated from jwanfs/pkg/sdk/s3 with the jtool/consts/size dependencies
// replaced by standard library equivalents so it runs standalone inside
// remote-storage. The heavy s3iface bridge layer (which depended on a vendored
// aws-sdk-go-v1 fork) is intentionally NOT migrated; this package focuses on
// the FGW business API surface.
package jwanfs

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"
	"sync"
)

// ---- configuration ---------------------------------------------------------

// ClientOption configures a new Client.
type ClientOption struct {
	Ak      string
	Sk      string
	Servers []string
	Debug   bool
	// HTTPClient optionally overrides the shared *http.Client used for FGW
	// discovery, health probes, and FGW API calls. When nil, DefaultHTTPClient
	// is used.
	HTTPClient *http.Client
}

// ---- upstream / client state -----------------------------------------------

type upstreamClient struct {
	server string
	host   string
	secure bool
}

// Client is a JWanFS FGW SDK client with multi-gateway failover.
type Client struct {
	ak string
	sk string

	servers   []string
	upstreams []*upstreamClient

	defaultIndex int
	mu           sync.RWMutex

	balancer *GatewayBalancer

	httpClient *http.Client
	debug      bool
}

// SetDebug toggles verbose FGW request logging.
func (c *Client) SetDebug(d bool) { c.debug = d }

// BalancerStop stops the background gateway-discovery goroutine. Callers that
// create a transient client (e.g. for a one-shot quota probe) should defer
// this to avoid leaking the refresh goroutine.
func (c *Client) BalancerStop() {
	if c != nil && c.balancer != nil {
		c.balancer.Stop()
	}
}

// HTTPClient returns the *http.Client used by this client (for tests / probes).
func (c *Client) HTTPClient() *http.Client {
	if c.httpClient != nil {
		return c.httpClient
	}
	return DefaultHTTPClient()
}

// ---- constructors ----------------------------------------------------------

// New creates a Client from credentials and one-or-more server endpoints.
func New(ak, sk string, servers ...string) (*Client, error) {
	return NewClient(&ClientOption{Ak: ak, Sk: sk, Servers: servers})
}

// NewClient creates a fully-configured Client and starts the balancer refresh
// goroutine. If gateway discovery fails, it falls back to direct connect.
func NewClient(opt *ClientOption) (*Client, error) {
	lbEndpoint := firstConfiguredEndpoint(opt.Servers...)
	if lbEndpoint == "" {
		return nil, ErrNoServer
	}

	client := &Client{
		ak:           opt.Ak,
		sk:           opt.Sk,
		defaultIndex: -1,
		httpClient:   opt.HTTPClient,
		debug:        opt.Debug,
	}

	// 创建负载均衡
	client.balancer = newGatewayBalancer(client, lbEndpoint)
	// 尝试第一次discovery并更新配置。Discovery 的网络探测可能对不可达
	// endpoint 阻塞到 OS 级 TCP 超时（1-2 分钟），这里用有界 ctx 兜住；
	// 失败时下方已有的直连 fallback 仍会生效。
	refreshCtx, refreshCancel := context.WithTimeout(context.Background(), gatewayRefreshTimeout)
	if err := client.balancer.Refresh(refreshCtx); err != nil {
		refreshCancel()
		// 如果discovery失败，当成直连fgw用
		if err := client.replaceUpstreams(opt.Servers, lbEndpoint); err != nil {
			return nil, err
		}
	} else {
		refreshCancel()
	}
	if client.DefaultServer() == "" {
		return nil, ErrNoServer
	}

	client.balancer.Start()
	return client, nil
}

// ---- upstream accessors ----------------------------------------------------

// Servers returns a copy of the current gateway server list.
func (c *Client) Servers() []string {
	c.mu.RLock()
	defer c.mu.RUnlock()
	return append([]string(nil), c.servers...)
}

// DefaultServer returns the currently active gateway endpoint.
func (c *Client) DefaultServer() string {
	c.mu.RLock()
	defer c.mu.RUnlock()
	if c.defaultIndex < 0 || c.defaultIndex >= len(c.servers) {
		return ""
	}
	return c.servers[c.defaultIndex]
}

// SetDefaultServer switches the active gateway to server, if present.
func (c *Client) SetDefaultServer(server string) bool {
	c.mu.Lock()
	defer c.mu.Unlock()

	for i, current := range c.servers {
		if current != server || c.upstreams[i] == nil {
			continue
		}
		c.defaultIndex = i
		return true
	}
	return false
}

// orderedUpstreams returns the candidate upstreams ordered by preference.
func (c *Client) orderedUpstreams() []*upstreamClient {
	c.mu.RLock()
	defer c.mu.RUnlock()

	if len(c.upstreams) == 0 {
		return nil
	}

	order := make([]*upstreamClient, 0, len(c.upstreams))
	seen := make(map[int]struct{}, len(c.upstreams))

	appendIndex := func(index int) {
		if index < 0 || index >= len(c.upstreams) || c.upstreams[index] == nil {
			return
		}
		if _, ok := seen[index]; ok {
			return
		}
		order = append(order, c.upstreams[index])
		seen[index] = struct{}{}
	}

	appendIndex(c.defaultIndex)
	for i := range c.upstreams {
		appendIndex(i)
	}

	return order
}

// ---- failover generic helper ----------------------------------------------

// doWithFallback runs fn against the ordered upstream pool, switching to the
// next upstream on transferable errors (5xx/429/network). The first server
// argument passed to fn is the upstream endpoint being tried.
func doWithFallback[T any](c *Client, fn func(server string) (T, error)) (T, error) {
	var zero T

	order := c.orderedUpstreams()
	if len(order) == 0 {
		return zero, ErrNoAvailableUpstreams
	}

	var errs []error
	for _, upstream := range order {
		result, err := fn(upstream.server)
		if err == nil {
			c.SetDefaultServer(upstream.server)
			return result, nil
		}

		errs = append(errs, err)
		if !shouldFallback(err) {
			return zero, err
		}
	}

	return zero, joinErrors(errs...)
}

// ---- upstream pool management ----------------------------------------------

func (c *Client) setDefaultIndex(index int) {
	c.mu.Lock()
	defer c.mu.Unlock()

	if index < 0 || index >= len(c.upstreams) || c.upstreams[index] == nil {
		return
	}
	c.defaultIndex = index
}

func (c *Client) replaceUpstreams(servers []string, preferred string) error {
	normalized := normalizeServers(servers...)
	if len(normalized) == 0 {
		return ErrNoAvailableUpstreams
	}

	preferredServer := ""
	if preferredServers := normalizeServers(preferred); len(preferredServers) > 0 {
		preferredServer = preferredServers[0]
	}

	nextServers := make([]string, 0, len(normalized))
	nextUpstreams := make([]*upstreamClient, 0, len(normalized))
	defaultIndex := -1

	for _, server := range normalized {
		host, secure, err := parseServer(server)
		if err != nil {
			continue
		}
		upstream := &upstreamClient{server: server, host: host, secure: secure}

		candidateIndex := len(nextServers)
		nextServers = append(nextServers, server)
		nextUpstreams = append(nextUpstreams, upstream)

		// 第一个可初始化的网关作为兜底；preferred 可用时覆盖兜底。
		if defaultIndex == -1 || server == preferredServer {
			defaultIndex = candidateIndex
		}
	}

	if len(nextUpstreams) == 0 || defaultIndex < 0 {
		return ErrNoAvailableUpstreams
	}

	c.mu.Lock()
	defer c.mu.Unlock()
	c.servers = nextServers
	c.upstreams = nextUpstreams
	c.defaultIndex = defaultIndex
	return nil
}

// ---- server normalization helpers -----------------------------------------

func normalizeServers(servers ...string) []string {
	list := make([]string, 0, len(servers))
	for _, server := range servers {
		server = strings.TrimSpace(server)
		if server == "" {
			continue
		}
		if !strings.HasPrefix(server, "http://") && !strings.HasPrefix(server, "https://") {
			server = "http://" + server
		}
		server = strings.TrimSuffix(server, "/")
		list = append(list, server)
	}
	return sliceRemoveDup(list)
}

func firstConfiguredEndpoint(servers ...string) string {
	for _, server := range servers {
		normalized := normalizeServers(server)
		if len(normalized) > 0 {
			return normalized[0]
		}
	}
	return ""
}

func parseServer(server string) (host string, secure bool, err error) {
	// Imported from sign.go to avoid a circular dependency on url parsing.
	return parseServerURL(server)
}

// ---- error classification --------------------------------------------------

// shouldFallback reports whether err is transferable (5xx / 429 / network).
func shouldFallback(err error) bool {
	if err == nil {
		return false
	}
	if errorsIs(err, context.Canceled) || errorsIs(err, context.DeadlineExceeded) {
		return true
	}
	if isNetError(err) {
		return true
	}
	if status := httpErrorStatus(err); status > 0 {
		return status == 429 || status >= 500
	}
	return false
}

// ---- small stdlib-replacement helpers --------------------------------------

// sliceRemoveDup removes duplicate strings preserving order.
func sliceRemoveDup(data []string) []string {
	if len(data) <= 1 {
		return data
	}
	seen := make(map[string]struct{}, len(data))
	out := make([]string, 0, len(data))
	for _, v := range data {
		if _, ok := seen[v]; ok {
			continue
		}
		seen[v] = struct{}{}
		out = append(out, v)
	}
	return out
}

// joinErrors joins errors into a single error (compatible with errors.Join
// on Go 1.20+; wrapped to keep the call site clean).
func joinErrors(errs ...error) error {
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

// httpGet performs a GET with the client's HTTPClient and returns the body
// bytes and status code. Used by the balancer discovery and FGW raw calls.
func (c *Client) httpGet(ctx context.Context, urlValue string, headers map[string]string) ([]byte, int, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, urlValue, nil)
	if err != nil {
		return nil, 0, err
	}
	req.Header.Set("Accept", "application/json")
	for k, v := range headers {
		req.Header.Set(k, v)
	}
	return c.doRequest(req)
}

// doRequest sends req using the client's HTTPClient and returns body+status.
func (c *Client) doRequest(req *http.Request) ([]byte, int, error) {
	resp, err := c.HTTPClient().Do(req)
	if err != nil {
		return nil, 0, err
	}
	defer resp.Body.Close()

	data, readErr := io.ReadAll(resp.Body)
	if readErr != nil {
		return nil, resp.StatusCode, readErr
	}
	return data, resp.StatusCode, nil
}

// readJSON unmarshals data into target using encoding/json (the legacy jtool
// wrapper was just json.Unmarshal).
func readJSON(data []byte, target any) error {
	return json.Unmarshal(data, target)
}

// debugf logs a formatted debug line when debug mode is enabled.
func (c *Client) debugf(format string, args ...any) {
	if c.debug {
		fmt.Printf("[jwanfs] "+format+"\n", args...)
	}
}
