// Package config proxy helpers build HTTP transports that respect the global
// proxy mode (system / direct / custom) configured by the user.
// Custom mode supports HTTP and SOCKS5 proxies with optional authentication.
package config

import (
	"crypto/tls"
	"fmt"
	"net/http"
	"net/url"
	"strings"
	"time"

	"golang.org/x/net/proxy"
)

func durationFromSeconds(s int) time.Duration {
	return time.Duration(s) * time.Second
}

// ProxyTransport returns an http.RoundTripper honouring the ProxyMode setting.
//
//   - system: reads HTTP_PROXY / HTTPS_PROXY / NO_PROXY environment variables.
//   - direct: clears all proxies regardless of environment.
//   - custom: forces the configured proxy (HTTP or SOCKS5) for all requests.
//     ProxyType/ProxyHost/ProxyPort select the proxy server.
//     ProxyUsername/ProxyPassword are used for authentication if non-empty.
func ProxyTransport(cfg RemoteStorageConfig) http.RoundTripper {
	mode := strings.TrimSpace(cfg.ProxyMode)
	switch mode {
	case ProxyModeDirect:
		return &http.Transport{Proxy: nil}
	case ProxyModeCustom:
		return buildCustomProxyTransport(cfg)
	default: // ProxyModeSystem or unknown
		return &http.Transport{Proxy: http.ProxyFromEnvironment}
	}
}

// buildCustomProxyTransport creates a transport for HTTP CONNECT or SOCKS5.
// Falls back to system proxy if the custom config is incomplete or invalid.
func buildCustomProxyTransport(cfg RemoteStorageConfig) http.RoundTripper {
	host := strings.TrimSpace(cfg.ProxyHost)
	if host == "" {
		return &http.Transport{Proxy: http.ProxyFromEnvironment}
	}
	port := strings.TrimSpace(cfg.ProxyPort)
	rt, err := buildCustomTransport(cfg.ProxyType, host, port, cfg.ProxyUsername, cfg.ProxyPassword)
	if err != nil || rt == nil {
		return &http.Transport{Proxy: http.ProxyFromEnvironment}
	}
	return rt
}

// ProxyHTTPClient wraps ProxyTransport with a timeout.
func ProxyHTTPClient(cfg RemoteStorageConfig, timeoutSeconds int) *http.Client {
	if timeoutSeconds <= 0 {
		timeoutSeconds = 60
	}
	return &http.Client{
		Transport: ProxyTransport(cfg),
		Timeout:   durationFromSeconds(timeoutSeconds),
	}
}

// buildCustomTransport creates a round-tripper for HTTP CONNECT or SOCKS5 proxy.
func buildCustomTransport(proxyType, host, port, username, password string) (http.RoundTripper, error) {
	addr := host + ":" + port
	switch proxyType {
	case ProxyTypeSocks5:
		var auth *proxy.Auth
		if username != "" {
			auth = &proxy.Auth{User: username, Password: password}
		}
		dialer, err := proxy.SOCKS5("tcp", addr, auth, nil)
		if err != nil {
			return nil, fmt.Errorf("socks5 dialer: %w", err)
		}
		return &http.Transport{
			Dial:            dialer.Dial,
			TLSClientConfig: &tls.Config{},
		}, nil
	default: // HTTP
		proxyURL := &url.URL{Scheme: "http", Host: addr}
		if username != "" {
			proxyURL.User = url.UserPassword(username, password)
		}
		return &http.Transport{Proxy: http.ProxyURL(proxyURL)}, nil
	}
}
