// Shared FTP/SFTP endpoint parsing helpers.
package storage

import (
	"net"
	"strconv"
	"strings"
)

// hostPortFromEndpoint extracts host:port from an endpoint URL or bare address.
// protocol prefix is stripped, trailing slash removed. If no port is present,
// defaultPort is appended. "0.0.0.0" is replaced by "127.0.0.1" for dialing.
func hostPortFromEndpoint(endpoint string, defaultPort int) string {
	trimmed := strings.TrimSpace(endpoint)
	for _, scheme := range []string{"ftp://", "ftps://", "sftp://", "http://", "https://"} {
		trimmed = strings.TrimPrefix(trimmed, scheme)
	}
	trimmed = strings.TrimSuffix(trimmed, "/")
	if trimmed == "" {
		return "127.0.0.1:" + strconv.Itoa(defaultPort)
	}
	// IPv6 with port: [::1]:22
	if strings.HasPrefix(trimmed, "[") {
		return trimmed
	}
	if !strings.Contains(trimmed, ":") {
		trimmed = strings.ReplaceAll(trimmed, "0.0.0.0", "127.0.0.1")
		return trimmed + ":" + strconv.Itoa(defaultPort)
	}
	// host:port — normalize 0.0.0.0
	host, port, err := net.SplitHostPort(trimmed)
	if err != nil {
		return trimmed
	}
	if host == "0.0.0.0" {
		host = "127.0.0.1"
	}
	return net.JoinHostPort(host, port)
}

// hostFromEndpoint extracts just the host part (no port) from an endpoint.
func hostFromEndpoint(endpoint string) string {
	trimmed := strings.TrimSpace(endpoint)
	for _, scheme := range []string{"ftp://", "ftps://", "sftp://", "http://", "https://"} {
		trimmed = strings.TrimPrefix(trimmed, scheme)
	}
	trimmed = strings.TrimSuffix(trimmed, "/")
	host, _, err := net.SplitHostPort(trimmed)
	if err != nil {
		return strings.ReplaceAll(trimmed, "0.0.0.0", "127.0.0.1")
	}
	if host == "0.0.0.0" {
		host = "127.0.0.1"
	}
	return host
}

