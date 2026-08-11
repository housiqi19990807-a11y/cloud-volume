// Package storage routes account operations to concrete S3 or WebDAV backends.
package storage

import (
	"context"
	"io"
	"net/http"
	"os"

	storageconfig "remote-storage/go/config"
	s3ops "remote-storage/go/s3"
)

type BucketInfo = s3ops.BucketInfo
type ObjectInfo = s3ops.ObjectInfo
type ObjectPage = s3ops.ObjectPage
type TrashItem = s3ops.TrashItem
type TrashPage = s3ops.TrashPage

type DirectoryAccess struct {
	Writable bool   `json:"writable"`
	Known    bool   `json:"known"`
	Reason   string `json:"reason,omitempty"`
}

type Backend interface {
	ListBuckets(context.Context) ([]BucketInfo, error)
	ListObjectsPage(context.Context, string, string, string, int32) (ObjectPage, error)
	// ListObjectsRecursive returns every file object under prefix (sync reconcile).
	ListObjectsRecursive(context.Context, string, string) ([]ObjectInfo, error)
	HeadObject(context.Context, string, string) (ObjectInfo, error)
	ReadObjectRange(context.Context, string, string, int64, int64) ([]byte, error)
	DirectoryAccess(context.Context, string, string) (DirectoryAccess, error)
	CreateDirectory(context.Context, string, string, string) error
	DeleteObject(context.Context, string, string, bool, string) error
	DeleteObjectHard(context.Context, string, string, bool, string) error
	ListTrashPage(context.Context, string, string, int32) (TrashPage, error)
	RestoreTrashItem(context.Context, string, string) error
	DeleteTrashItem(context.Context, string, string) error
	ClearTrash(context.Context, string) error
	RenameObject(context.Context, string, string, bool, string) error
	CopyObject(context.Context, string, string, string, bool, string) error
	MoveObject(context.Context, string, string, string, bool, string) error
	UploadFile(context.Context, string, string, string, string) error
	UploadReader(context.Context, string, string, io.Reader, int64, string, string) error
	DownloadFile(context.Context, string, string, string, string) error
	StreamObjectToHTTP(context.Context, string, string, bool, http.ResponseWriter) error
}

// BucketQuotaProvider exposes optional remote capacity without delaying bucket discovery.
type BucketQuotaProvider interface {
	BucketQuota(context.Context, string) (BucketInfo, error)
}

// MountPrefetchPolicy lets slower backends opt out of directory preview prefetch.
type MountPrefetchPolicy interface {
	SupportsMountPrefetch() bool
}

// MountRemotePollingPolicy lets connection-sensitive backends disable P0
// refreshes that desktop background crawlers could otherwise amplify.
type MountRemotePollingPolicy interface {
	SupportsMountRemotePolling() bool
}

// PartialFileUploader exposes optional prefix upload support for append-heavy mount writes.
type PartialFileUploader interface {
	UploadFilePrefix(context.Context, string, string, string, os.FileInfo, int64, int) error
}

// SupportsMountPrefetch defaults to true so existing backends keep current behavior.
func SupportsMountPrefetch(backend Backend) bool {
	policy, ok := backend.(MountPrefetchPolicy)
	if !ok {
		return true
	}
	return policy.SupportsMountPrefetch()
}

// SupportsMountRemotePolling defaults to true for existing providers.
func SupportsMountRemotePolling(backend Backend) bool {
	policy, ok := backend.(MountRemotePollingPolicy)
	if !ok {
		return true
	}
	return policy.SupportsMountRemotePolling()
}

// IsScoped reports whether backend is a scopedBackend wrapper. Mount layer
// uses this to assert it cleared RootPrefix before ForConfig (otherwise the
// mount's own prefix translation would double-prefix provider keys).
func IsScoped(backend Backend) bool {
	_, ok := backend.(interface{ Root() string })
	return ok
}

// GetBucketQuota resolves optional provider capacity for a previously listed bucket.
func GetBucketQuota(
	ctx context.Context,
	cfg storageconfig.RemoteStorageConfig,
	bucket string,
) (BucketInfo, error) {
	if cached, ok := CachedBucketQuota(cfg, bucket); ok {
		return cached, nil
	}
	backend := ForConfig(cfg)
	provider, ok := backend.(BucketQuotaProvider)
	if !ok {
		return BucketInfo{Name: bucket}, nil
	}
	quota, err := provider.BucketQuota(ctx, bucket)
	if err == nil {
		cacheBucketQuota(cfg, bucket, quota)
	}
	return quota, err
}

func ForConfig(cfg storageconfig.RemoteStorageConfig) Backend {
	globalProxy, err := storageconfig.LoadGlobalProxy()
	if err == nil {
		cfg = storageconfig.ResolveProxyConfig(cfg, globalProxy)
	}
	normalized := cfg.Normalized()
	var backend Backend
	switch normalized.StorageType {
	case storageconfig.StorageTypeWebDAV:
		backend = NewWebDAVBackend(normalized)
	case storageconfig.StorageTypeBaiduPan:
		backend = newBaiduPanBackend(normalized)
	case storageconfig.StorageTypeFTP:
		backend = newFTPBackend(normalized)
	case storageconfig.StorageTypeSFTP:
		backend = newSFTPBackend(normalized)
	default:
		backend = s3Backend{cfg: normalized}
	}
	if normalized.RootPrefix != "" {
		return scopedBackend{Backend: backend, root: normalized.RootPrefix}
	}
	return backend
}
