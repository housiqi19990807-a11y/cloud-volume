// Bucket access write helpers own create/delete/rename and local cache file utilities.
package mount

import (
	"context"
	"fmt"
	"io"
	"log"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/google/uuid"

	storageconfig "remote-storage/go/config"
	s3ops "remote-storage/go/s3"
)

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
	a.writeback.enqueue(cleanVirtualPath(virtualPath), localPath, fileSize(localPath))
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
	if clean == "" {
		return fmt.Errorf("directory name is required")
	}
	a.stageLocalDirectory(clean, time.Now())
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
		hadPendingUpload := a.writeback.cancel(cleanVirtualPath(virtualPath))
		if hadPendingUpload && !a.remoteFileExists(timeoutCtx, virtualPath) {
			a.cache.markDeleted(virtualPath, false)
			a.cache.invalidatePath(virtualPath)
			return nil
		}
	} else {
		a.writeback.cancelAtOrBelow(virtualPath, true)
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
	a.cache.markDeleted(virtualPath, isDir)
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
	hadPendingWriteback := a.writeback.rename(oldClean, newClean, isDir)
	if hadPendingWriteback {
		a.cache.renameLocalFile(oldClean, newClean, isDir, a.cacheRoot)
		a.cache.invalidatePath(oldClean)
		a.cache.invalidatePath(newClean)
		if !a.remotePathExists(ctx, oldClean, isDir) {
			return nil
		}
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

func (a *bucketAccess) remoteFileExists(ctx context.Context, virtualPath string) bool {
	_, err := s3ops.HeadObjectContext(
		ctx,
		a.config,
		a.bucket,
		a.remoteKey(virtualPath),
	)
	return err == nil
}

func (a *bucketAccess) remotePathExists(ctx context.Context, virtualPath string, isDir bool) bool {
	if !isDir {
		return a.remoteFileExists(ctx, virtualPath)
	}
	items, err := s3ops.ListObjectsContext(
		ctx,
		a.config,
		a.bucket,
		a.remotePrefix(virtualPath),
	)
	return err == nil && len(items) > 0
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
