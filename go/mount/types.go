// Package mount owns bucket-to-desktop mount lifecycle and WebDAV-facing models.
package mount

import (
	"strings"
	"time"

	storageconfig "remote-storage/go/config"
)

const (
	defaultRequestTimeout = 15
	defaultCacheTTL       = 15
	defaultPrefetchTTL    = 10
	writebackQuietPeriod  = time.Minute
)

// BucketMountStatus is returned to Flutter so the UI can render mount actions.
type BucketMountStatus struct {
	Mounted   bool   `json:"mounted"`
	Bucket    string `json:"bucket"`
	MountPath string `json:"mountPath"`
	ServerURL string `json:"serverUrl"`
	Port      int    `json:"port"`
	LastError string `json:"lastError,omitempty"`
}

type mountSession struct {
	config      storageconfig.RemoteStorageConfig
	bucket      string
	rootPrefix  string
	mountName   string
	mountPath   string
	mountTarget string
	serverURL   string
	port        int
	mounted     bool
	server      *webDAVServer
	access      *bucketAccess
	lastError   string
}

func (s *mountSession) status() BucketMountStatus {
	if s == nil {
		return BucketMountStatus{}
	}
	return BucketMountStatus{
		Mounted:   s.mounted,
		Bucket:    s.bucket,
		MountPath: s.mountPath,
		ServerURL: s.serverURL,
		Port:      s.port,
		LastError: s.lastError,
	}
}

func normalizeRootPrefix(value string) string {
	return strings.Trim(strings.TrimSpace(value), "/")
}
