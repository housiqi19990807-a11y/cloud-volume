// Bucket remote helpers handle timeout-bound S3 fetches and key translation.
package mount

import (
	"context"
	"os"
	"path/filepath"
	"strings"

	"github.com/google/uuid"

	s3ops "remote-storage/go/s3"
)

func (a *bucketAccess) fetchDirectory(
	ctx context.Context,
	virtualPrefix string,
) ([]s3ops.ObjectInfo, error) {
	timeoutCtx, cancel := a.withTimeout(ctx)
	defer cancel()
	items, err := s3ops.ListObjectsContext(
		timeoutCtx,
		a.config,
		a.bucket,
		a.remotePrefix(virtualPrefix),
	)
	if err != nil {
		return nil, err
	}

	rewritten := make([]s3ops.ObjectInfo, 0, len(items))
	for _, item := range items {
		virtualKey, ok := a.virtualKey(item.Key, item.IsDir)
		if !ok {
			continue
		}
		item.Key = virtualKey
		rewritten = append(rewritten, item)
		a.cache.storeObject(strings.TrimSuffix(virtualKey, "/"), item)
	}
	return rewritten, nil
}

func (a *bucketAccess) fetchStat(
	ctx context.Context,
	virtualPath string,
) (s3ops.ObjectInfo, error) {
	timeoutCtx, cancel := a.withTimeout(ctx)
	defer cancel()
	fileInfo, err := s3ops.HeadObjectContext(
		timeoutCtx,
		a.config,
		a.bucket,
		a.remoteKey(virtualPath),
	)
	if err == nil {
		fileInfo.Key = cleanVirtualPath(virtualPath)
		return fileInfo, nil
	}

	items, listErr := a.listDirectory(ctx, parentVirtualPrefix(virtualPath))
	if listErr == nil {
		clean := cleanVirtualPath(virtualPath)
		for _, item := range items {
			if item.Key == clean || item.Key == ensureDirSuffix(clean) {
				return item, nil
			}
		}
	}

	return s3ops.ObjectInfo{}, err
}

func (a *bucketAccess) downloadToCache(
	ctx context.Context,
	virtualPath string,
	info s3ops.ObjectInfo,
	localPath string,
) (string, error) {
	timeoutCtx, cancel := a.withTimeout(ctx)
	defer cancel()
	tempPath := localPath + ".downloading"
	_ = os.Remove(tempPath)
	taskID := "mount-download-" + uuid.NewString()
	if err := s3ops.DownloadFileContext(
		timeoutCtx,
		a.config,
		a.bucket,
		a.remoteKey(virtualPath),
		tempPath,
		taskID,
	); err != nil {
		_ = os.Remove(tempPath)
		return "", err
	}
	if err := os.MkdirAll(filepath.Dir(localPath), 0o755); err != nil {
		return "", err
	}
	_ = os.Remove(localPath)
	if err := os.Rename(tempPath, localPath); err != nil {
		return "", err
	}
	a.cache.storeObject(virtualPath, info)
	return localPath, nil
}

func (a *bucketAccess) prefetchChildren(items []s3ops.ObjectInfo) {
	for _, item := range items {
		if !item.IsDir {
			continue
		}
		childPrefix := strings.TrimSuffix(item.Key, "/")
		if !a.cache.shouldPrefetch(childPrefix) {
			continue
		}
		go func(prefix string) {
			ctx, cancel := context.WithTimeout(context.Background(), a.requestTimeout)
			defer cancel()
			_, _ = a.listDirectory(ctx, prefix)
		}(childPrefix)
	}
}

func (a *bucketAccess) withTimeout(ctx context.Context) (context.Context, context.CancelFunc) {
	if ctx == nil {
		ctx = context.Background()
	}
	return context.WithTimeout(ctx, a.requestTimeout)
}

func (a *bucketAccess) remotePrefix(virtualPrefix string) string {
	clean := cleanVirtualPath(virtualPrefix)
	switch {
	case a.rootPrefix == "" && clean == "":
		return ""
	case a.rootPrefix == "":
		return ensureDirSuffix(clean)
	case clean == "":
		return ensureDirSuffix(a.rootPrefix)
	default:
		return ensureDirSuffix(a.rootPrefix + "/" + clean)
	}
}

func (a *bucketAccess) remoteKey(virtualPath string) string {
	clean := cleanVirtualPath(virtualPath)
	if a.rootPrefix == "" {
		return clean
	}
	if clean == "" {
		return a.rootPrefix
	}
	return a.rootPrefix + "/" + clean
}

func (a *bucketAccess) remoteKeyForMutation(virtualPath string, isDir bool) string {
	key := a.remoteKey(virtualPath)
	if isDir {
		return ensureDirSuffix(strings.TrimSuffix(key, "/"))
	}
	return key
}

func (a *bucketAccess) virtualKey(remoteKey string, isDir bool) (string, bool) {
	trimmed := strings.TrimSpace(remoteKey)
	if a.rootPrefix != "" {
		prefix := a.rootPrefix + "/"
		if trimmed == a.rootPrefix {
			trimmed = ""
		} else if strings.HasPrefix(trimmed, prefix) {
			trimmed = strings.TrimPrefix(trimmed, prefix)
		} else {
			return "", false
		}
	}
	trimmed = strings.TrimPrefix(trimmed, "/")
	if isDir {
		return ensureDirSuffix(strings.TrimSuffix(trimmed, "/")), true
	}
	return trimmed, true
}
