// resolve_system_proxy reads the OS-level proxy configuration (Windows registry
// on Windows, environment variables elsewhere) so Dart HTTP clients can honor
// the "follow system" proxy mode. Dart's HttpClient.findProxyFromEnvironment
// only reads http_proxy/https_proxy and ignores the Windows settings UI.

package main

type systemProxyResult struct {
	// Available is true when a usable proxy was detected on this host.
	Available bool `json:"available"`
	// Mode is "http" or "socks5"; empty when not available.
	Type string `json:"type"`
	// Host is the proxy hostname or IP; empty when not available.
	Host string `json:"host"`
	// Port is the proxy port as a string; empty when not available.
	Port string `json:"port"`
}

func resolveSystemProxy() (any, error) {
	return readSystemProxy(), nil
}
