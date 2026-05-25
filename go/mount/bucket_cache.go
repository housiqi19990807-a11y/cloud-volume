// Bucket cache keeps short-lived metadata plus local staged-file overlays.
package mount

import (
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"

	s3ops "remote-storage/go/s3"
)

type bucketCache struct {
	mu            sync.RWMutex
	ttl           time.Duration
	prefetchTTL   time.Duration
	objectCache   map[string]cachedObject
	listCache     map[string]cachedList
	localFiles    map[string]localFile
	prefetchStamp map[string]time.Time
}

type cachedObject struct {
	info      s3ops.ObjectInfo
	expiresAt time.Time
}

type cachedList struct {
	items     []s3ops.ObjectInfo
	expiresAt time.Time
}

type localFile struct {
	info      s3ops.ObjectInfo
	localPath string
}

func newBucketCache(ttl, prefetchTTL time.Duration) *bucketCache {
	return &bucketCache{
		ttl:           ttl,
		prefetchTTL:   prefetchTTL,
		objectCache:   map[string]cachedObject{},
		listCache:     map[string]cachedList{},
		localFiles:    map[string]localFile{},
		prefetchStamp: map[string]time.Time{},
	}
}

func (c *bucketCache) cachedList(virtualPrefix string) ([]s3ops.ObjectInfo, bool) {
	c.mu.RLock()
	defer c.mu.RUnlock()

	item, ok := c.listCache[cleanVirtualPath(virtualPrefix)]
	if !ok || time.Now().After(item.expiresAt) {
		return nil, false
	}
	return cloneObjects(item.items), true
}

func (c *bucketCache) cachedObject(virtualPath string) (s3ops.ObjectInfo, bool) {
	c.mu.RLock()
	defer c.mu.RUnlock()

	item, ok := c.objectCache[cleanVirtualPath(virtualPath)]
	if !ok || time.Now().After(item.expiresAt) {
		return s3ops.ObjectInfo{}, false
	}
	return item.info, true
}

func (c *bucketCache) localFile(virtualPath string) (localFile, bool) {
	c.mu.RLock()
	defer c.mu.RUnlock()

	item, ok := c.localFiles[cleanVirtualPath(virtualPath)]
	return item, ok
}

func (c *bucketCache) storeList(virtualPrefix string, items []s3ops.ObjectInfo) {
	c.mu.Lock()
	defer c.mu.Unlock()

	c.listCache[cleanVirtualPath(virtualPrefix)] = cachedList{
		items:     cloneObjects(items),
		expiresAt: time.Now().Add(c.ttl),
	}
}

func (c *bucketCache) storeObject(virtualPath string, info s3ops.ObjectInfo) {
	c.mu.Lock()
	defer c.mu.Unlock()

	key := cleanVirtualPath(virtualPath)
	if info.IsDir {
		info.Key = ensureDirSuffix(key)
	} else {
		info.Key = key
	}
	c.objectCache[key] = cachedObject{
		info:      info,
		expiresAt: time.Now().Add(c.ttl),
	}
}

func (c *bucketCache) storeLocalFile(
	virtualPath,
	localPath string,
	info s3ops.ObjectInfo,
) {
	c.mu.Lock()
	defer c.mu.Unlock()

	key := cleanVirtualPath(virtualPath)
	info.Key = key
	c.localFiles[key] = localFile{
		info:      info,
		localPath: localPath,
	}
	c.objectCache[key] = cachedObject{
		info:      info,
		expiresAt: time.Now().Add(c.ttl),
	}
	delete(c.listCache, parentVirtualPrefix(key))
}

func (c *bucketCache) removeLocalFile(virtualPath string, isDir bool) {
	c.mu.Lock()
	defer c.mu.Unlock()

	clean := cleanVirtualPath(virtualPath)
	if !isDir {
		if item, ok := c.localFiles[clean]; ok {
			_ = os.Remove(item.localPath)
		}
		delete(c.localFiles, clean)
		return
	}

	prefix := ensureDirSuffix(clean)
	for key, item := range c.localFiles {
		if strings.HasPrefix(key, prefix) {
			_ = os.Remove(item.localPath)
			delete(c.localFiles, key)
		}
	}
}

func (c *bucketCache) renameLocalFile(
	oldVirtualPath,
	newVirtualPath string,
	isDir bool,
	cacheRoot string,
) {
	c.mu.Lock()
	defer c.mu.Unlock()

	oldClean := cleanVirtualPath(oldVirtualPath)
	newClean := cleanVirtualPath(newVirtualPath)
	if !isDir {
		item, ok := c.localFiles[oldClean]
		if !ok {
			return
		}
		newCachePath := pathForVirtualKey(cacheRoot, newClean)
		_ = os.MkdirAll(filepath.Dir(newCachePath), 0o755)
		_ = os.Remove(newCachePath)
		_ = os.Rename(item.localPath, newCachePath)
		item.localPath = newCachePath
		item.info.Key = newClean
		c.localFiles[newClean] = item
		delete(c.localFiles, oldClean)
		return
	}

	oldPrefix := ensureDirSuffix(oldClean)
	newPrefix := ensureDirSuffix(newClean)
	for key, item := range c.localFiles {
		if !strings.HasPrefix(key, oldPrefix) {
			continue
		}
		suffix := strings.TrimPrefix(key, oldPrefix)
		nextKey := newPrefix + suffix
		nextPath := pathForVirtualKey(cacheRoot, nextKey)
		_ = os.MkdirAll(filepath.Dir(nextPath), 0o755)
		_ = os.Remove(nextPath)
		_ = os.Rename(item.localPath, nextPath)
		item.localPath = nextPath
		item.info.Key = nextKey
		c.localFiles[nextKey] = item
		delete(c.localFiles, key)
	}
}

func (c *bucketCache) mergeLocalFiles(
	virtualPrefix string,
	items []s3ops.ObjectInfo,
) []s3ops.ObjectInfo {
	c.mu.RLock()
	defer c.mu.RUnlock()

	byKey := map[string]s3ops.ObjectInfo{}
	for _, item := range items {
		byKey[item.Key] = item
	}

	cleanPrefix := cleanVirtualPath(virtualPrefix)
	for key, item := range c.localFiles {
		if parentVirtualPrefix(key) != cleanPrefix {
			continue
		}
		byKey[key] = item.info
	}

	out := make([]s3ops.ObjectInfo, 0, len(byKey))
	for _, item := range byKey {
		out = append(out, item)
	}
	return out
}

func (c *bucketCache) shouldPrefetch(virtualPrefix string) bool {
	c.mu.Lock()
	defer c.mu.Unlock()

	now := time.Now()
	clean := cleanVirtualPath(virtualPrefix)
	if stamp, ok := c.prefetchStamp[clean]; ok && now.Sub(stamp) < c.prefetchTTL {
		return false
	}
	c.prefetchStamp[clean] = now
	return true
}

func (c *bucketCache) invalidatePath(virtualPath string) {
	c.mu.Lock()
	defer c.mu.Unlock()

	clean := cleanVirtualPath(virtualPath)
	delete(c.objectCache, clean)
	delete(c.listCache, clean)
	delete(c.listCache, parentVirtualPrefix(clean))
	for prefix := range c.listCache {
		if clean != "" && strings.HasPrefix(prefix, ensureDirSuffix(clean)) {
			delete(c.listCache, prefix)
		}
	}
}
