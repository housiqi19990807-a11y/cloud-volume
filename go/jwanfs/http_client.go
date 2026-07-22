// Shared HTTP client with sane defaults, replacing jtool.GetHttpClient.
package jwanfs

import (
	"crypto/tls"
	"net/http"
	"sync"
	"time"
)

var (
	defaultHTTPClientOnce sync.Once
	defaultHTTPClient     *http.Client
)

// DefaultHTTPClient returns a process-wide *http.Client configured with a
// connection pool, relaxed TLS (the legacy client skipped verification to
// support self-hosted gateways), and no global timeout (per-call contexts
// bound the duration).
func DefaultHTTPClient() *http.Client {
	defaultHTTPClientOnce.Do(func() {
		transport := &http.Transport{
			Proxy:                 http.ProxyFromEnvironment,
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

