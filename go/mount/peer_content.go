// Peer content helpers expose safe complete-cache files to the bridge P2P layer.
package mount

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"sync"

	storageconfig "remote-storage/go/config"
	s3ops "remote-storage/go/s3"
)

type peerSource struct {
	cfg  storageconfig.RemoteStorageConfig
	path string
	info s3ops.ObjectInfo
}

var peerSources = struct {
	sync.RWMutex
	items map[string]peerSource
}{items: make(map[string]peerSource)}

// RememberPeerContent records a bridge-upload source only after the remote
// backend confirmed its object metadata. This avoids exposing queued writes.
func RememberPeerContent(cfg storageconfig.RemoteStorageConfig, bucket, virtualPath, localPath string, info s3ops.ObjectInfo) {
	if info.IsDir || localPath == "" {
		return
	}
	peerSources.Lock()
	peerSources.items[peerSourceKey(cfg, bucket, virtualPath)] = peerSource{cfg: cfg.Normalized(), path: localPath, info: info}
	peerSources.Unlock()
}

// ForgetPeerContent stops serving a bridge-upload source after a delete/rename.
func ForgetPeerContent(cfg storageconfig.RemoteStorageConfig, bucket, virtualPath string) {
	peerSources.Lock()
	delete(peerSources.items, peerSourceKey(cfg, bucket, virtualPath))
	peerSources.Unlock()
}

// LocalPeerContentPath finds a complete cache entry in a matching active mount.
// It never exposes staged writeback data, which is not yet remote-confirmed.
func LocalPeerContentPath(
	cfg storageconfig.RemoteStorageConfig,
	bucket, virtualPath, versionHint string,
) (string, int64, bool) {
	if source, ok := lookupPeerSource(cfg, bucket, virtualPath, versionHint); ok {
		return source.path, source.info.Size, true
	}
	globalManager.mu.Lock()
	defer globalManager.mu.Unlock()
	trimmedBucket := normalizeBucketName(bucket)
	session, ok := globalManager.sessions[trimmedBucket]
	if !ok || session.access == nil || !mountSessionMatches(session, cfg, trimmedBucket, MountOptions{}) {
		return "", 0, false
	}
	access := session.access
	info, ok := access.cache.cachedObject(virtualPath)
	if ok && !info.IsDir && peerContentVersionHint(info) == versionHint {
		if path, ok := access.localReadablePath(virtualPath, info); ok {
			return path, info.Size, true
		}
	}
	// Cache metadata can have a zero TTL, while a completed disk cache remains
	// valid for peer service through its persistent remote-version stamp.
	path := access.cachePathFor(cleanVirtualPath(virtualPath))
	stamp, ok := loadDownloadStamp(path)
	if !ok || peerContentVersionHint(s3ops.ObjectInfo{
		Size: stamp.Size, LastModified: stamp.LastModified, ETag: stamp.ETag,
	}) != versionHint || !isUsableLocalFile(path, stamp.Size) {
		return "", 0, false
	}
	return path, stamp.Size, true
}

func lookupPeerSource(cfg storageconfig.RemoteStorageConfig, bucket, path, versionHint string) (peerSource, bool) {
	peerSources.RLock()
	source, ok := peerSources.items[peerSourceKey(cfg, bucket, path)]
	peerSources.RUnlock()
	if !ok || peerContentVersionHint(source.info) != versionHint || !isUsableLocalFile(source.path, source.info.Size) {
		return peerSource{}, false
	}
	return source, true
}

func peerSourceKey(cfg storageconfig.RemoteStorageConfig, bucket, path string) string {
	normalized := cfg.Normalized()
	return normalized.StorageType + "\x00" + normalized.Endpoint + "\x00" + normalized.AccessKeyID + "\x00" + normalized.WebDAVUsername + "\x00" + normalized.FTPUsername + "\x00" + normalizeBucketName(bucket) + "\x00" + cleanVirtualPath(path)
}

// peerContentVersionHint prefers a provider's strong ETag. Backends without
// one use their normal cache version tuple, retaining D2 acceleration for
// SFTP/FTP/WebDAV while accepting their same-second overwrite limitation.
func peerContentVersionHint(info s3ops.ObjectInfo) string {
	if etag := strings.TrimSpace(info.ETag); etag != "" {
		return "etag:" + etag
	}
	modified := strings.TrimSpace(info.LastModified)
	if modified == "" || info.Size < 0 {
		return ""
	}
	return fmt.Sprintf("mtime-size:%s:%d", modified, info.Size)
}

// downloadFromPeerToCache preserves the normal cache stamp/rename semantics
// after the P2P transport has populated the temporary file.
func (a *bucketAccess) downloadFromPeerToCache(
	ctx context.Context,
	virtualPath string,
	info s3ops.ObjectInfo,
	localPath string,
) (string, bool) {
	fetcher := peerContentFetchHook()
	if fetcher == nil || !a.config.P2PEnabled {
		return "", false
	}
	versionHint := peerContentVersionHint(info)
	if versionHint == "" {
		return "", false
	}
	tempPath := partialDownloadPath(localPath)
	clearDownloadArtifacts(localPath)
	if err := writeDownloadStamp(tempPath, info); err != nil {
		return "", false
	}
	timeoutCtx, cancel := a.withTransferTimeout(ctx)
	err := fetcher(timeoutCtx, ContentFetchPayload{Config: a.config, Bucket: a.bucket, VirtualPath: virtualPath,
		VersionHint: versionHint, Size: info.Size, DestinationPath: tempPath})
	cancel()
	if err != nil || !isPartialDownloadUsable(localPath, info) {
		clearDownloadArtifacts(localPath)
		return "", false
	}
	// Remote metadata remains authoritative if the object changed mid-transfer.
	current, err := a.fetchStat(ctx, virtualPath)
	if err != nil || current.Size != info.Size || peerContentVersionHint(current) != versionHint {
		clearDownloadArtifacts(localPath)
		return "", false
	}
	if err := os.MkdirAll(filepath.Dir(localPath), 0o755); err != nil {
		clearDownloadArtifacts(localPath)
		return "", false
	}
	if err := os.Rename(tempPath, localPath); err != nil {
		clearDownloadArtifacts(localPath)
		return "", false
	}
	if err := renameDownloadStamp(stampPath(tempPath), stampPath(localPath)); err != nil {
		clearDownloadArtifacts(localPath)
		return "", false
	}
	a.cache.storeObject(virtualPath, info)
	return localPath, true
}
