// Shared HTTP client with sane defaults, replacing jtool.GetHttpClient.
package jwanfs

import (
	"crypto/tls"
	"net"
	"net/http"
	"sync"
	"time"
)

// gatewayDialTimeout bounds how long gateway discovery/probe waits on a single
// TCP dial. A powered-off or firewalled gateway drops SYN packets; without a
// dial timeout the OS retries for ~75s on macOS, blocking bucket list startup
// until the request context expires. 3s lets discovery fail fast and fall back
// to direct connect.
const gatewayDialTimeout = 3 * time.Second

var (
	defaultHTTPClientOnce sync.Once
	defaultHTTPClient     *http.Client
)

// DefaultHTTPClient returns a process-wide *http.Client configured with a
// connection pool, relaxed TLS (the legacy client skipped verification to
// support self-hosted gateways), a bounded dial timeout, and no global timeout
// (per-call contexts bound the duration).
func DefaultHTTPClient() *http.Client {
	defaultHTTPClientOnce.Do(func() {
		transport := &http.Transport{
			Proxy:                 http.ProxyFromEnvironment,
			DialContext:           (&net.Dialer{Timeout: gatewayDialTimeout}).DialContext,
			MaxIdleConns:          1024,
			MaxIdleConnsPerHost:   1024,
			IdleConnTimeout:       90 * time.Second,
			TLSHandshakeTimeout:   10 * time.Second,
			ExpectContinueTimeout: 1 * time.Second,
			TLSClientConfig:       &tls.Config{InsecureSkipVerify: true},
		}
		defaultHTTPClient = &http.Client{Transport: transport}
	})
	return defaultHTTPClient
}

