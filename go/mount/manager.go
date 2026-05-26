// Mount manager coordinates one macOS desktop bucket mount at a time for now.
package mount

import (
	"fmt"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"sync"

	storageconfig "remote-storage/go/config"
)

type manager struct {
	mu      sync.Mutex
	session *mountSession
}

var globalManager = &manager{}

// MountBucket starts the local WebDAV server and mounts the bucket to Desktop.
func MountBucket(
	cfg storageconfig.RemoteStorageConfig,
	bucket string,
) (BucketMountStatus, error) {
	return globalManager.mountBucket(cfg, bucket)
}

// UnmountBucket unmounts the current mount when it matches the provided bucket.
func UnmountBucket(bucket string) (BucketMountStatus, error) {
	return globalManager.unmountBucket(bucket)
}

// GetBucketMountStatus returns the current status for the requested bucket.
func GetBucketMountStatus(bucket string) (BucketMountStatus, error) {
	return globalManager.getBucketMountStatus(bucket)
}

// OpenBucketMount opens the mounted directory in Finder.
func OpenBucketMount(bucket string) (BucketMountStatus, error) {
	return globalManager.openBucketMount(bucket)
}

// CleanupMounts unmounts any active desktop mount during app shutdown.
func CleanupMounts() error {
	return globalManager.cleanupMounts()
}

func (m *manager) mountBucket(
	cfg storageconfig.RemoteStorageConfig,
	bucket string,
) (BucketMountStatus, error) {
	m.mu.Lock()
	defer m.mu.Unlock()

	if runtime.GOOS != "darwin" {
		return BucketMountStatus{}, fmt.Errorf("bucket mount currently only supports macOS")
	}

	trimmedBucket := normalizeBucketName(bucket)
	if trimmedBucket == "" {
		trimmedBucket = normalizeBucketName(cfg.Bucket)
	}
	if trimmedBucket == "" {
		return BucketMountStatus{}, fmt.Errorf("missing bucket name")
	}

	if err := m.syncSessionLocked(); err != nil {
		return BucketMountStatus{}, err
	}
	if m.session != nil && m.session.bucket == trimmedBucket && m.session.server != nil {
		return m.session.status(), nil
	}
	if m.session != nil && m.session.server != nil {
		if err := m.unmountCurrentLocked(); err != nil {
			return BucketMountStatus{}, err
		}
	}

	session, err := newMountSession(cfg.Normalized(), trimmedBucket)
	if err != nil {
		return BucketMountStatus{}, err
	}
	if err := session.start(); err != nil {
		_ = session.stop()
		return BucketMountStatus{}, err
	}

	m.session = session
	return session.status(), nil
}

func (m *manager) unmountBucket(bucket string) (BucketMountStatus, error) {
	m.mu.Lock()
	defer m.mu.Unlock()

	if err := m.syncSessionLocked(); err != nil {
		return BucketMountStatus{Bucket: normalizeBucketName(bucket)}, err
	}
	if m.session == nil {
		return BucketMountStatus{Bucket: normalizeBucketName(bucket)}, nil
	}
	if trimmed := normalizeBucketName(bucket); trimmed != "" && trimmed != m.session.bucket {
		return BucketMountStatus{Bucket: trimmed}, nil
	}

	status := m.session.status()
	if err := m.unmountCurrentLocked(); err != nil {
		return status, err
	}
	status.Mounted = false
	return status, nil
}

func (m *manager) getBucketMountStatus(bucket string) (BucketMountStatus, error) {
	m.mu.Lock()
	defer m.mu.Unlock()

	if err := m.syncSessionLocked(); err != nil {
		return BucketMountStatus{Bucket: normalizeBucketName(bucket)}, err
	}
	if m.session == nil {
		return BucketMountStatus{Bucket: normalizeBucketName(bucket)}, nil
	}
	if trimmed := normalizeBucketName(bucket); trimmed != "" && trimmed != m.session.bucket {
		return BucketMountStatus{Bucket: trimmed}, nil
	}
	return m.session.status(), nil
}

func (m *manager) openBucketMount(bucket string) (BucketMountStatus, error) {
	m.mu.Lock()
	if err := m.syncSessionLocked(); err != nil {
		m.mu.Unlock()
		return BucketMountStatus{Bucket: normalizeBucketName(bucket)}, err
	}
	session := m.session
	m.mu.Unlock()

	if session == nil {
		return BucketMountStatus{Bucket: normalizeBucketName(bucket)}, fmt.Errorf("bucket is not mounted")
	}
	if trimmed := normalizeBucketName(bucket); trimmed != "" && trimmed != session.bucket {
		return BucketMountStatus{Bucket: trimmed}, fmt.Errorf("bucket %q is not mounted", trimmed)
	}
	if err := openMountPath(session.mountPath); err != nil {
		return session.status(), err
	}
	return session.status(), nil
}

func (m *manager) syncSessionLocked() error {
	if m.session == nil {
		return nil
	}
	active, err := isWebDAVMountActive(m.session.mountTarget)
	if err != nil {
		m.session.lastError = err.Error()
		return err
	}
	if active {
		m.session.mounted = true
		return nil
	}
	_ = m.session.stop()
	m.session = nil
	return nil
}

func (m *manager) unmountCurrentLocked() error {
	if m.session == nil {
		return nil
	}
	err := m.session.stop()
	m.session = nil
	return err
}

func (m *manager) cleanupMounts() error {
	m.mu.Lock()
	defer m.mu.Unlock()
	return m.unmountCurrentLocked()
}

func newMountSession(
	cfg storageconfig.RemoteStorageConfig,
	bucket string,
) (*mountSession, error) {
	homeDir, err := os.UserHomeDir()
	if err != nil {
		return nil, fmt.Errorf("resolve user home: %w", err)
	}
	mountName := "云卷-" + bucket
	mountPath := filepath.Join(homeDir, "Desktop", mountName)
	access, err := newBucketAccess(cfg, bucket)
	if err != nil {
		return nil, err
	}
	return &mountSession{
		config:      cfg,
		bucket:      bucket,
		rootPrefix:  normalizeRootPrefix(cfg.RootPrefix),
		mountName:   mountName,
		mountPath:   mountPath,
		mountTarget: mountPath,
		access:      access,
	}, nil
}

func normalizeBucketName(value string) string {
	return strings.TrimSpace(value)
}
