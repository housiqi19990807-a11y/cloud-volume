// Bucket access wires high-level mount operations to remote S3 state.
package mount

import (
	"context"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"time"

	"github.com/google/uuid"
	"golang.org/x/sync/singleflight"

	storageconfig "remote-storage/go/config"
	s3ops "remote-storage/go/s3"
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

	cache *bucketCache
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
	if err := os.MkdirAll(cacheRoot, 0o755); err != nil {
		return nil, fmt.Errorf("create mount cache dir: %w", err)
	}
	if err := os.MkdirAll(stageRoot, 0o755); err != nil {
		return nil, fmt.Errorf("create mount staging dir: %w", err)
	}

	return &bucketAccess{
		config:         cfg,
		bucket:         bucket,
		rootPrefix:     normalizeRootPrefix(cfg.RootPrefix),
		cacheRoot:      cacheRoot,
		stageRoot:      stageRoot,
		requestTimeout: defaultRequestTimeout * time.Second,
		listTTL:        defaultCacheTTL * time.Second,
		prefetchTTL:    defaultPrefetchTTL * time.Second,
		cache:          newBucketCache(defaultCacheTTL*time.Second, defaultPrefetchTTL*time.Second),
	}, nil
}

func (a *bucketAccess) listDirectory(
	ctx context.Context,
	virtualPrefix string,
) ([]s3ops.ObjectInfo, error) {
	if items, ok := a.cache.cachedList(cleanVirtualPath(virtualPrefix)); ok {
		merged := a.cache.mergeLocalFiles(virtualPrefix, items)
		a.prefetchChildren(merged)
		return cloneObjects(merged), nil
	}

	flightKey := "list:" + cleanVirtualPath(virtualPrefix)
	value, err, _ := a.group.Do(flightKey, func() (any, error) {
		items, err := a.fetchDirectory(ctx, virtualPrefix)
		if err != nil {
			return nil, err
		}
		a.cache.storeList(virtualPrefix, items)
		return a.cache.mergeLocalFiles(virtualPrefix, items), nil
	})
	if err != nil {
		return nil, err
	}
	items, _ := value.([]s3ops.ObjectInfo)
	a.prefetchChildren(items)
	return cloneObjects(items), nil
}

func (a *bucketAccess) statPath(
	ctx context.Context,
	virtualPath string,
) (s3ops.ObjectInfo, error) {
	clean := cleanVirtualPath(virtualPath)
	if clean == "" {
		return s3ops.ObjectInfo{Key: "", IsDir: true}, nil
	}
	if item, ok := a.cache.localFile(clean); ok {
		return item.info, nil
	}
	if item, ok := a.cache.cachedObject(clean); ok {
		return item, nil
	}

	parentPrefix := parentVirtualPrefix(clean)
	if items, ok := a.cache.cachedList(parentPrefix); ok {
		for _, item := range a.cache.mergeLocalFiles(parentPrefix, items) {
			if item.Key == clean || item.Key == ensureDirSuffix(clean) {
				a.cache.storeObject(clean, item)
				return item, nil
			}
		}
	}

	flightKey := "stat:" + clean
	value, err, _ := a.group.Do(flightKey, func() (any, error) {
		info, err := a.fetchStat(ctx, clean)
		if err != nil {
			return nil, err
		}
		a.cache.storeObject(clean, info)
		return info, nil
	})
	if err != nil {
		return s3ops.ObjectInfo{}, err
	}
	info, _ := value.(s3ops.ObjectInfo)
	return info, nil
}

func (a *bucketAccess) ensureLocalFile(
	ctx context.Context,
	virtualPath string,
) (string, s3ops.ObjectInfo, error) {
	clean := cleanVirtualPath(virtualPath)
	if item, ok := a.cache.localFile(clean); ok {
		if isUsableLocalFile(item.localPath, item.info.Size) {
			return item.localPath, item.info, nil
		}
	}

	info, err := a.statPath(ctx, clean)
	if err != nil {
		return "", s3ops.ObjectInfo{}, err
	}
	if info.IsDir {
		return "", s3ops.ObjectInfo{}, fmt.Errorf("%s is a directory", clean)
	}

	localPath := a.cachePathFor(clean)
	if isUsableLocalFile(localPath, info.Size) {
		return localPath, info, nil
	}

	flightKey := "download:" + clean
	value, err, _ := a.group.Do(flightKey, func() (any, error) {
		return a.downloadToCache(ctx, clean, info, localPath)
	})
	if err != nil {
		return "", s3ops.ObjectInfo{}, err
	}
	pathValue, _ := value.(string)
	return pathValue, info, nil
}

func (a *bucketAccess) registerLocalWrite(virtualPath, localPath string, size int64) {
	info := s3ops.ObjectInfo{
		Key:          cleanVirtualPath(virtualPath),
		Size:         size,
		LastModified: time.Now().Format("2006-01-02 15:04:05"),
		IsDir:        false,
	}
	a.cache.storeLocalFile(cleanVirtualPath(virtualPath), localPath, info)
}

func (a *bucketAccess) scheduleUpload(virtualPath, localPath string) {
	clean := cleanVirtualPath(virtualPath)
	go func() {
		ctx, cancel := context.WithTimeout(context.Background(), a.requestTimeout)
		defer cancel()
		taskID := "mount-upload-" + uuid.NewString()
		if err := s3ops.UploadFileContext(
			ctx,
			a.config,
			a.bucket,
			a.remoteKey(clean),
			localPath,
			taskID,
		); err == nil {
			a.cache.invalidatePath(clean)
			a.cache.storeLocalFile(clean, localPath, s3ops.ObjectInfo{
				Key:          clean,
				Size:         fileSize(localPath),
				LastModified: time.Now().Format("2006-01-02 15:04:05"),
				IsDir:        false,
			})
		}
	}()
}

func (a *bucketAccess) createDirectory(
	ctx context.Context,
	virtualPath string,
) error {
	clean := cleanVirtualPath(virtualPath)
	parent := parentVirtualPrefix(clean)
	name := baseName(clean)
	if name == "" {
		return fmt.Errorf("directory name is required")
	}
	timeoutCtx, cancel := a.withTimeout(ctx)
	defer cancel()
	if err := s3ops.CreateDirectoryContext(
		timeoutCtx,
		a.config,
		a.bucket,
		a.remotePrefix(parent),
		name,
	); err != nil {
		return err
	}
	a.cache.invalidatePath(clean)
	return nil
}

func (a *bucketAccess) deletePath(
	ctx context.Context,
	virtualPath string,
	isDir bool,
) error {
	timeoutCtx, cancel := a.withTimeout(ctx)
	defer cancel()
	if err := s3ops.DeleteObjectContext(
		timeoutCtx,
		a.config,
		a.bucket,
		a.remoteKeyForMutation(virtualPath, isDir),
		isDir,
	); err != nil {
		return err
	}
	a.cache.removeLocalFile(virtualPath, isDir)
	a.cache.invalidatePath(virtualPath)
	return nil
}

func (a *bucketAccess) renamePath(
	ctx context.Context,
	oldVirtualPath,
	newVirtualPath string,
	isDir bool,
) error {
	oldClean := cleanVirtualPath(oldVirtualPath)
	newClean := cleanVirtualPath(newVirtualPath)
	if oldClean == "" || newClean == "" {
		return fmt.Errorf("source and target paths are required")
	}
	timeoutCtx, cancel := a.withTimeout(ctx)
	defer cancel()
	if err := s3ops.MoveObjectContext(
		timeoutCtx,
		a.config,
		a.bucket,
		a.remoteKeyForMutation(oldClean, isDir),
		a.remoteKeyForMutation(newClean, isDir),
		isDir,
	); err != nil {
		return err
	}
	a.cache.renameLocalFile(oldClean, newClean, isDir, a.cacheRoot)
	a.cache.invalidatePath(oldClean)
	a.cache.invalidatePath(newClean)
	return nil
}

func (a *bucketAccess) stagePathFor(virtualPath string) string {
	return pathForVirtualKey(a.stageRoot, virtualPath)
}

func (a *bucketAccess) cachePathFor(virtualPath string) string {
	return pathForVirtualKey(a.cacheRoot, virtualPath)
}

func pathForVirtualKey(root, virtualPath string) string {
	segments := []string{root}
	for _, part := range splitVirtualPath(virtualPath) {
		segments = append(segments, safeSegment(part))
	}
	if len(segments) == 1 {
		segments = append(segments, "_root")
	}
	return filepath.Join(segments...)
}

func copyFile(dstPath, srcPath string) error {
	src, err := os.Open(srcPath)
	if err != nil {
		return err
	}
	defer src.Close()

	if err := os.MkdirAll(filepath.Dir(dstPath), 0o755); err != nil {
		return err
	}
	dst, err := os.Create(dstPath)
	if err != nil {
		return err
	}
	defer dst.Close()

	_, err = io.Copy(dst, src)
	return err
}

func fileSize(localPath string) int64 {
	info, err := os.Stat(localPath)
	if err != nil {
		return 0
	}
	return info.Size()
}
