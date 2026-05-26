// Bucket access holds shared mount session state used by read/write helper files.
package mount

import (
	"fmt"
	"os"
	"path/filepath"
	"sync"
	"time"

	"golang.org/x/sync/singleflight"

	storageconfig "remote-storage/go/config"
)

type bucketAccess struct {
	config         storageconfig.RemoteStorageConfig
	bucket         string
	rootPrefix     string
	cacheRoot      string
	stageRoot      string
	requestTimeout time.Duration
	listTTL        time.Duration
	prefetchTTL    time.Duration

	group singleflight.Group

	cache     *bucketCache
	overlay   *localMountOverlay
	writeback *writebackQueue
}

func newBucketAccess(
	cfg storageconfig.RemoteStorageConfig,
	bucket string,
) (*bucketAccess, error) {
	mountRoot, err := storageconfig.MountRuntimeDir()
	if err != nil {
		return nil, err
	}
	sessionRoot := filepath.Join(mountRoot, safeSegment(bucket))
	cacheRoot := filepath.Join(sessionRoot, "cache")
	stageRoot := filepath.Join(sessionRoot, "staging")
	overlayRoot := filepath.Join(sessionRoot, "overlay")
	if err := os.MkdirAll(cacheRoot, 0o755); err != nil {
		return nil, fmt.Errorf("create mount cache dir: %w", err)
	}
	if err := os.MkdirAll(stageRoot, 0o755); err != nil {
		return nil, fmt.Errorf("create mount staging dir: %w", err)
	}
	overlay, err := newLocalMountOverlay(overlayRoot)
	if err != nil {
		return nil, fmt.Errorf("create mount overlay dir: %w", err)
	}

	access := &bucketAccess{
		config:         cfg,
		bucket:         bucket,
		rootPrefix:     normalizeRootPrefix(cfg.RootPrefix),
		cacheRoot:      cacheRoot,
		stageRoot:      stageRoot,
		requestTimeout: defaultRequestTimeout * time.Second,
		listTTL:        defaultCacheTTL * time.Second,
		prefetchTTL:    defaultPrefetchTTL * time.Second,
		cache:          newBucketCache(defaultCacheTTL*time.Second, defaultPrefetchTTL*time.Second),
		overlay:        overlay,
	}
	access.writeback = newWritebackQueue(access)
	return access, nil
}

func (a *bucketAccess) close() error {
	if a == nil || a.writeback == nil {
		return nil
	}
	return a.writeback.shutdown()
}

type writebackQueue struct {
	access  *bucketAccess
	mu      sync.Mutex
	entries map[string]*pendingWriteback
	closed  bool
}

type pendingWriteback struct {
	taskID      string
	virtualPath string
	localPath   string
	size        int64
	timer       *time.Timer
}

func newWritebackQueue(access *bucketAccess) *writebackQueue {
	return &writebackQueue{
		access:  access,
		entries: map[string]*pendingWriteback{},
	}
}
