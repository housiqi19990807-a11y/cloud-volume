// Mount manager keeps the public lifecycle API stable while platform backends vary.
package mount

import (
	"fmt"
	"strings"
	"sync"

	storageconfig "remote-storage/go/config"
)

type manager struct {
	mu      sync.Mutex
	session *mountSession
}

var globalManager = &manager{}

// MountBucket starts the platform mount backend for one bucket at a time.
func MountBucket(
	cfg storageconfig.RemoteStorageConfig,
	bucket string,
) (BucketMountStatus, error) {
	return globalManager.mountBucket(cfg, bucket, MountOptions{})
}

// MountBucketWithOptions lets non-desktop callers override mount details such
// as the Linux mountpoint while keeping the existing public desktop API stable.
func MountBucketWithOptions(
	cfg storageconfig.RemoteStorageConfig,
	bucket string,
	options MountOptions,
) (BucketMountStatus, error) {
	return globalManager.mountBucket(cfg, bucket, options)
}

// UnmountBucket unmounts the current mount when it matches the provided bucket.
func UnmountBucket(bucket string) (BucketMountStatus, error) {
	return globalManager.unmountBucket(bucket)
}

// GetBucketMountStatus returns the current status for the requested bucket.
func GetBucketMountStatus(bucket string) (BucketMountStatus, error) {
	return globalManager.getBucketMountStatus(bucket)
}

// OpenBucketMount opens the mounted directory in the host file manager.
func OpenBucketMount(bucket string) (BucketMountStatus, error) {
	return globalManager.openBucketMount(bucket)
}

// CleanupMounts unmounts any active bucket volume during app shutdown.
func CleanupMounts() error {
	return globalManager.cleanupMounts()
}

func (m *manager) mountBucket(
	cfg storageconfig.RemoteStorageConfig,
	bucket string,
	options MountOptions,
) (BucketMountStatus, error) {
	m.mu.Lock()
	defer m.mu.Unlock()

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
	if m.session != nil && m.session.bucket == trimmedBucket {
		if mountSessionMatches(m.session, cfg, trimmedBucket, options) {
			return m.session.status(), nil
		}
		if err := m.unmountCurrentLocked(); err != nil {
			return BucketMountStatus{}, err
		}
	}
	if m.session != nil {
		if err := m.unmountCurrentLocked(); err != nil {
			return BucketMountStatus{}, err
		}
	}

	session, err := newMountSession(cfg.Normalized(), trimmedBucket, options)
	if err != nil {
		return BucketMountStatus{}, err
	}
	if err := session.backend.CleanupStale(session); err != nil {
		return BucketMountStatus{}, err
	}
	if err := session.backend.Start(session); err != nil {
		_ = session.backend.Stop(session)
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
	active, err := m.session.backend.IsActive(m.session)
	if err != nil {
		m.session.lastError = err.Error()
		return err
	}
	if active {
		m.session.mounted = true
		return nil
	}
	_ = m.session.backend.Stop(m.session)
	m.session = nil
	return nil
}

func (m *manager) unmountCurrentLocked() error {
	if m.session == nil {
		return nil
	}
	err := m.session.backend.Stop(m.session)
	m.session = nil
	return err
}

func (m *manager) cleanupMounts() error {
	m.mu.Lock()
	defer m.mu.Unlock()
	if err := m.unmountCurrentLocked(); err != nil {
		return err
	}
	return cleanupAllManagedMounts()
}

func newMountSession(
	cfg storageconfig.RemoteStorageConfig,
	bucket string,
	options MountOptions,
) (*mountSession, error) {
	access, err := newBucketAccess(cfg, bucket)
	if err != nil {
		return nil, err
	}
	backend, err := newPlatformMountBackend(cfg)
	if err != nil {
		_ = access.close()
		return nil, err
	}
	session := &mountSession{
		config:        cfg,
		bucket:        bucket,
		rootPrefix:    normalizeRootPrefix(cfg.RootPrefix),
		requestedPath: normalizeMountPath(options.MountPath),
		mountTarget:   normalizeMountPath(options.MountPath),
		access:        access,
		backend:       backend,
	}
	if err := backend.Initialize(session); err != nil {
		_ = access.close()
		return nil, err
	}
	return session, nil
}

func normalizeBucketName(value string) string {
	return strings.TrimSpace(value)
}
