// Overlay bridge moves macOS volume-private temp content back into the remote bucket tree.
package mount

import (
	"context"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"strings"

	"github.com/google/uuid"

	s3ops "remote-storage/go/s3"
)

func (a *bucketAccess) renameAcrossBoundary(
	ctx context.Context,
	oldVirtualPath,
	newVirtualPath string,
	isDir bool,
) error {
	oldOverlay := a.overlay.handles(oldVirtualPath)
	newOverlay := a.overlay.handles(newVirtualPath)
	switch {
	case oldOverlay && !newOverlay:
		return a.moveOverlayPathToRemote(ctx, oldVirtualPath, newVirtualPath)
	case !oldOverlay && newOverlay:
		return a.handleRemoteMoveIntoOverlay(ctx, oldVirtualPath, newVirtualPath, isDir)
	default:
		return fmt.Errorf("unsupported mount rename between %q and %q", oldVirtualPath, newVirtualPath)
	}
}

func (a *bucketAccess) handleRemoteMoveIntoOverlay(
	ctx context.Context,
	oldVirtualPath,
	newVirtualPath string,
	isDir bool,
) error {
	if a.overlay.isTrashPath(newVirtualPath) {
		return a.deletePath(ctx, oldVirtualPath, isDir)
	}
	return fmt.Errorf("moving remote objects into system temporary mount folders is not supported")
}

func (a *bucketAccess) moveOverlayPathToRemote(
	ctx context.Context,
	oldVirtualPath,
	newVirtualPath string,
) error {
	info, err := a.overlay.statPath(oldVirtualPath)
	if err != nil {
		return err
	}
	if info.IsDir() {
		if err := a.uploadOverlayDirectory(ctx, oldVirtualPath, newVirtualPath); err != nil {
			return err
		}
	} else {
		if err := a.uploadOverlayFile(ctx, oldVirtualPath, newVirtualPath); err != nil {
			return err
		}
	}
	if err := a.overlay.removeAll(oldVirtualPath); err != nil {
		return err
	}
	a.cache.invalidatePath(oldVirtualPath)
	a.cache.invalidatePath(newVirtualPath)
	return nil
}

func (a *bucketAccess) uploadOverlayDirectory(
	ctx context.Context,
	oldVirtualPath,
	newVirtualPath string,
) error {
	localRoot := a.overlay.localPath(oldVirtualPath)
	if err := a.createRemoteDirectory(ctx, newVirtualPath); err != nil {
		return err
	}
	return filepath.WalkDir(localRoot, func(current string, entry fs.DirEntry, walkErr error) error {
		if walkErr != nil {
			return walkErr
		}
		if current == localRoot {
			return nil
		}
		relative, err := filepath.Rel(localRoot, current)
		if err != nil {
			return err
		}
		virtualRelative := filepath.ToSlash(relative)
		targetVirtualPath := joinVirtualPath(newVirtualPath, virtualRelative)
		if entry.IsDir() {
			return a.createRemoteDirectory(ctx, targetVirtualPath)
		}
		sourceVirtualPath := joinVirtualPath(oldVirtualPath, virtualRelative)
		return a.uploadOverlayFile(ctx, sourceVirtualPath, targetVirtualPath)
	})
}

func (a *bucketAccess) uploadOverlayFile(
	ctx context.Context,
	oldVirtualPath,
	newVirtualPath string,
) error {
	timeoutCtx, cancel := a.withTimeout(ctx)
	defer cancel()
	taskID := "mount-upload-" + uuid.NewString()
	localPath := a.overlay.localPath(oldVirtualPath)
	if err := s3ops.UploadFileContext(
		timeoutCtx,
		a.config,
		a.bucket,
		a.remoteKey(newVirtualPath),
		localPath,
		taskID,
	); err != nil {
		return err
	}
	info, err := os.Stat(localPath)
	if err == nil {
		cachePath := a.cachePathFor(newVirtualPath)
		if copyErr := copyFile(cachePath, localPath); copyErr == nil {
			localPath = cachePath
		}
		a.cache.storeLocalFile(cleanVirtualPath(newVirtualPath), localPath, s3ops.ObjectInfo{
			Key:          cleanVirtualPath(newVirtualPath),
			Size:         info.Size(),
			LastModified: info.ModTime().Format("2006-01-02 15:04:05"),
			IsDir:        false,
		})
	}
	return nil
}

func (a *bucketAccess) createRemoteDirectory(
	ctx context.Context,
	virtualPath string,
) error {
	clean := cleanVirtualPath(virtualPath)
	if clean == "" {
		return nil
	}
	parent := parentVirtualPrefix(clean)
	name := baseName(clean)
	timeoutCtx, cancel := a.withTimeout(ctx)
	defer cancel()
	err := s3ops.CreateDirectoryContext(
		timeoutCtx,
		a.config,
		a.bucket,
		a.remotePrefix(parent),
		name,
	)
	if err != nil && !strings.Contains(strings.ToLower(err.Error()), "exists") {
		return err
	}
	return nil
}

func joinVirtualPath(basePath, relativePath string) string {
	base := cleanVirtualPath(basePath)
	relative := cleanVirtualPath(relativePath)
	switch {
	case base == "":
		return relative
	case relative == "":
		return base
	default:
		return base + "/" + relative
	}
}
