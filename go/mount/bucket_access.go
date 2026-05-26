// Bucket access wires high-level mount operations to remote S3 state.
package mount

import (
	"context"
	"fmt"
	"io"
	"log"
	"os"
	"path/filepath"
	"strings"
	"sync"
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

	cache          *bucketCache
	overlay        *localMountOverlay
	uploadMu       sync.Mutex
	pendingUploads map[string]context.CancelFunc
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
		overlay:        overlay,
		pendingUploads: map[string]context.CancelFunc{},
	}, nil
}

func (a *bucketAccess) listDirectory(
	ctx context.Context,
	virtualPrefix string,
) ([]s3ops.ObjectInfo, error) {
	if err := a.hiddenTrashError(virtualPrefix); err != nil {
		return nil, err
	}
	if a.overlay.handles(virtualPrefix) {
		return a.overlay.listDirectory(virtualPrefix)
	}
	if items, ok := a.cache.cachedList(cleanVirtualPath(virtualPrefix)); ok {
		merged := a.filterTrashItems(
			a.mergeOverlayItems(virtualPrefix, a.cache.mergeLocalFiles(virtualPrefix, items)),
		)
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
		return a.filterTrashItems(
			a.mergeOverlayItems(virtualPrefix, a.cache.mergeLocalFiles(virtualPrefix, items)),
		), nil
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
	if err := a.hiddenTrashError(clean); err != nil {
		return s3ops.ObjectInfo{}, err
	}
	if clean == "" {
		return s3ops.ObjectInfo{Key: "", IsDir: true}, nil
	}
	if a.overlay.handles(clean) {
		info, err := a.overlay.statObject(clean)
		if err != nil {
			return s3ops.ObjectInfo{}, err
		}
		return info, nil
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
		if !a.registerPendingUpload(clean, localPath, cancel) {
			cancel()
			return
		}
		defer a.finishPendingUpload(clean, cancel)
		if !a.shouldUploadLocalFile(clean, localPath) {
			return
		}
		taskID := "mount-upload-" + uuid.NewString()
		if err := s3ops.UploadFileContext(
			ctx,
			a.config,
			a.bucket,
			a.remoteKey(clean),
			localPath,
			taskID,
		); err == nil {
			if !a.shouldUploadLocalFile(clean, localPath) {
				return
			}
			a.cache.invalidatePath(clean)
			a.cache.clearLocalFileMarker(clean)
			a.cache.storeObject(clean, s3ops.ObjectInfo{
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
	if err := a.hiddenTrashError(clean); err != nil {
		return err
	}
	if a.overlay.handles(clean) {
		return a.overlay.mkdir(clean, 0o755)
	}
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
		log.Printf(
			"[mount/mkdir] bucket=%q path=%q parent=%q name=%q remotePrefix=%q error=%v",
			a.bucket,
			clean,
			parent,
			name,
			a.remotePrefix(parent),
			err,
		)
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
	if err := a.hiddenTrashError(virtualPath); err != nil {
		return err
	}
	if a.overlay.handles(virtualPath) {
		return a.overlay.removeAll(virtualPath)
	}
	timeoutCtx, cancel := a.withTimeout(ctx)
	defer cancel()
	if !isDir {
		hadPendingUpload := a.cancelPendingUpload(cleanVirtualPath(virtualPath))
		if hadPendingUpload && !a.remoteFileExists(timeoutCtx, virtualPath) {
			a.cache.removeLocalFile(virtualPath, false)
			a.cache.invalidatePath(virtualPath)
			return nil
		}
	} else {
		a.cancelPendingUploadsAtOrBelow(virtualPath, true)
	}
	deleteFunc := s3ops.DeleteObjectContext
	if isLocalMetadataPath(virtualPath) {
		deleteFunc = s3ops.DeleteObjectHardContext
	}
	if err := a.runDelete(
		timeoutCtx,
		deleteFunc,
		virtualPath,
		isDir,
		isLocalMetadataPath(virtualPath),
	); err != nil {
		log.Printf(
			"[mount/delete] bucket=%q path=%q isDir=%t remoteKey=%q hard=%t error=%v",
			a.bucket,
			virtualPath,
			isDir,
			a.remoteKeyForMutation(virtualPath, isDir),
			isLocalMetadataPath(virtualPath),
			err,
		)
		return err
	}
	a.cache.removeLocalFile(virtualPath, isDir)
	a.cache.invalidatePath(virtualPath)
	return nil
}

func (a *bucketAccess) runDelete(
	ctx context.Context,
	deleteFunc func(context.Context, storageconfig.RemoteStorageConfig, string, string, bool) error,
	virtualPath string,
	isDir bool,
	hardDelete bool,
) error {
	err := deleteFunc(
		ctx,
		a.config,
		a.bucket,
		a.remoteKeyForMutation(virtualPath, isDir),
		isDir,
	)
	if err == nil || isDir || hardDelete || !isRetryableCopySourceError(err) {
		return err
	}
	for attempt := 0; attempt < 4; attempt++ {
		select {
		case <-ctx.Done():
			return err
		case <-time.After(750 * time.Millisecond):
		}
		retryErr := deleteFunc(
			ctx,
			a.config,
			a.bucket,
			a.remoteKeyForMutation(virtualPath, isDir),
			isDir,
		)
		if retryErr == nil {
			return nil
		}
		err = retryErr
		if !isRetryableCopySourceError(err) {
			return err
		}
	}
	return err
}

func (a *bucketAccess) renamePath(
	ctx context.Context,
	oldVirtualPath,
	newVirtualPath string,
	isDir bool,
) error {
	oldClean := cleanVirtualPath(oldVirtualPath)
	newClean := cleanVirtualPath(newVirtualPath)
	if a.overlay.isTrashPath(newClean) {
		return a.deletePath(ctx, oldClean, isDir)
	}
	a.cancelPendingUploadsAtOrBelow(oldClean, isDir)
	if err := a.hiddenTrashError(oldClean); err != nil {
		return err
	}
	if err := a.hiddenTrashError(newClean); err != nil {
		return err
	}
	if oldClean == "" || newClean == "" {
		return fmt.Errorf("source and target paths are required")
	}
	oldOverlay := a.overlay.handles(oldClean)
	newOverlay := a.overlay.handles(newClean)
	if oldOverlay || newOverlay {
		if oldOverlay && newOverlay {
			return a.overlay.rename(oldClean, newClean)
		}
		return a.renameAcrossBoundary(ctx, oldClean, newClean, isDir)
	}
	timeoutCtx, cancel := a.withTimeout(ctx)
	defer cancel()
	taskID := "mount-move-" + uuid.NewString()
	if err := s3ops.MoveObjectContextWithTask(
		timeoutCtx,
		a.config,
		a.bucket,
		a.remoteKeyForMutation(oldClean, isDir),
		a.remoteKeyForMutation(newClean, isDir),
		isDir,
		taskID,
	); err != nil {
		return err
	}
	a.cache.renameLocalFile(oldClean, newClean, isDir, a.cacheRoot)
	a.cache.invalidatePath(oldClean)
	a.cache.invalidatePath(newClean)
	return nil
}

func (a *bucketAccess) registerPendingUpload(
	virtualPath,
	localPath string,
	cancel context.CancelFunc,
) bool {
	a.uploadMu.Lock()
	defer a.uploadMu.Unlock()

	if !a.shouldUploadLocalFileLocked(virtualPath, localPath) {
		return false
	}
	if existing, ok := a.pendingUploads[virtualPath]; ok {
		existing()
	}
	a.pendingUploads[virtualPath] = cancel
	return true
}

func (a *bucketAccess) finishPendingUpload(virtualPath string, cancel context.CancelFunc) {
	a.uploadMu.Lock()
	defer a.uploadMu.Unlock()

	current, ok := a.pendingUploads[virtualPath]
	if ok && sameCancelFunc(current, cancel) {
		delete(a.pendingUploads, virtualPath)
	}
	cancel()
}

func (a *bucketAccess) shouldUploadLocalFile(virtualPath, localPath string) bool {
	a.uploadMu.Lock()
	defer a.uploadMu.Unlock()
	return a.shouldUploadLocalFileLocked(virtualPath, localPath)
}

func (a *bucketAccess) shouldUploadLocalFileLocked(virtualPath, localPath string) bool {
	item, ok := a.cache.localFile(virtualPath)
	if !ok {
		return false
	}
	return item.localPath == localPath
}

func (a *bucketAccess) cancelPendingUploadsAtOrBelow(virtualPath string, isDir bool) {
	a.uploadMu.Lock()
	defer a.uploadMu.Unlock()

	clean := cleanVirtualPath(virtualPath)
	if !isDir {
		if cancel, ok := a.pendingUploads[clean]; ok {
			cancel()
			delete(a.pendingUploads, clean)
		}
		return
	}
	prefix := ensureDirSuffix(clean)
	for key, cancel := range a.pendingUploads {
		if strings.HasPrefix(key, prefix) {
			cancel()
			delete(a.pendingUploads, key)
		}
	}
}

func (a *bucketAccess) cancelPendingUpload(virtualPath string) bool {
	a.uploadMu.Lock()
	defer a.uploadMu.Unlock()

	cancel, ok := a.pendingUploads[cleanVirtualPath(virtualPath)]
	if ok {
		cancel()
		delete(a.pendingUploads, cleanVirtualPath(virtualPath))
	}
	return ok
}

func (a *bucketAccess) remoteFileExists(ctx context.Context, virtualPath string) bool {
	_, err := s3ops.HeadObjectContext(
		ctx,
		a.config,
		a.bucket,
		a.remoteKey(virtualPath),
	)
	return err == nil
}

func sameCancelFunc(left, right context.CancelFunc) bool {
	return fmt.Sprintf("%p", left) == fmt.Sprintf("%p", right)
}

func isRetryableCopySourceError(err error) bool {
	if err == nil {
		return false
	}
	text := err.Error()
	return strings.Contains(text, "CopyObject") && strings.Contains(text, "InvalidArgument")
}

func (a *bucketAccess) stagePathFor(virtualPath string) string {
	return pathForVirtualKey(a.stageRoot, virtualPath)
}

func (a *bucketAccess) cachePathFor(virtualPath string) string {
	return pathForVirtualKey(a.cacheRoot, virtualPath)
}

func (a *bucketAccess) mergeOverlayItems(
	virtualPrefix string,
	items []s3ops.ObjectInfo,
) []s3ops.ObjectInfo {
	if cleanVirtualPath(virtualPrefix) != "" {
		return items
	}
	overlayItems, err := a.overlay.listRootEntries()
	if err != nil {
		return items
	}
	byKey := make(map[string]s3ops.ObjectInfo, len(items)+len(overlayItems))
	for _, item := range items {
		byKey[item.Key] = item
	}
	for _, item := range overlayItems {
		byKey[item.Key] = item
	}
	merged := make([]s3ops.ObjectInfo, 0, len(byKey))
	for _, item := range byKey {
		merged = append(merged, item)
	}
	return merged
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
