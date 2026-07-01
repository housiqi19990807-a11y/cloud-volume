// Package config proxy helpers build HTTP transports that respect the global
// proxy mode (system / direct / custom) configured by the user.
package config

import (
	"net/http"
	"net/url"
	"strings"
	"time"
)

func durationFromSeconds(s int) time.Duration {
	return time.Duration(s) * time.Second
}

// ProxyTransport returns an http.RoundTripper honouring the ProxyMode setting.
//   - system: reads HTTP_PROXY / HTTPS_PROXY / NO_PROXY environment variables
//     (the Go and runtime default).
//   - direct: clears all proxies regardless of environment.
//   - custom: forces the configured ProxyURL for all requests.
func ProxyTransport(mode, customURL string) http.RoundTripper {
	switch strings.TrimSpace(mode) {
	case ProxyModeDirect:
		return &http.Transport{Proxy: nil}
	case ProxyModeCustom:
		if u := strings.TrimSpace(customURL); u != "" {
			if parsed, err := url.Parse(u); err == nil && parsed.Scheme != "" {
				return &http.Transport{Proxy: http.ProxyURL(parsed)}
			}
		}
		// Invalid custom URL falls back to system.
		fallthrough
	default: // ProxyModeSystem or unknown
		return &http.Transport{Proxy: http.ProxyFromEnvironment}
	}
}

// ProxyHTTPClient is a convenience wrapper returning a client with the
// configured transport and the given timeout.
func ProxyHTTPClient(mode, customURL string, timeoutSeconds int) *http.Client {
	if timeoutSeconds <= 0 {
		timeoutSeconds = 60
	}
	return &http.Client{
		Transport: ProxyTransport(mode, customURL),
		Timeout:   durationFromSeconds(timeoutSeconds),
	}
}

// ProxyModeFromConfig extracts the proxy fields from a RemoteStorageConfig.
func ProxyModeFromConfig(cfg RemoteStorageConfig) (string, string) {
	return cfg.ProxyMode, cfg.ProxyURL
}
