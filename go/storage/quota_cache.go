// Bucket quota cache shares recently resolved capacity across bridge and mount calls.
package storage

import (
	"crypto/sha256"
	"encoding/json"
	"sync"
	"time"

	storageconfig "remote-storage/go/config"
)

const bucketQuotaCacheTTL = 5 * time.Minute

type bucketQuotaCacheEntry struct {
	quota     BucketInfo
	expiresAt time.Time
}

var sharedBucketQuotaCache = struct {
	sync.RWMutex
	entries map[[sha256.Size]byte]bucketQuotaCacheEntry
}{entries: make(map[[sha256.Size]byte]bucketQuotaCacheEntry)}

// CachedBucketQuota returns capacity already fetched by the bucket list flow.
// Mount startup uses this read-only path and never waits for the provider.
func CachedBucketQuota(
	cfg storageconfig.RemoteStorageConfig,
	bucket string,
) (BucketInfo, bool) {
	key := bucketQuotaCacheKey(cfg, bucket)
	sharedBucketQuotaCache.RLock()
	entry, ok := sharedBucketQuotaCache.entries[key]
	sharedBucketQuotaCache.RUnlock()
	if !ok || time.Now().After(entry.expiresAt) {
		if ok {
			sharedBucketQuotaCache.Lock()
			delete(sharedBucketQuotaCache.entries, key)
			sharedBucketQuotaCache.Unlock()
		}
		return BucketInfo{}, false
	}
	return entry.quota, true
}

func cacheBucketQuota(
	cfg storageconfig.RemoteStorageConfig,
	bucket string,
	quota BucketInfo,
) {
	key := bucketQuotaCacheKey(cfg, bucket)
	sharedBucketQuotaCache.Lock()
	defer sharedBucketQuotaCache.Unlock()
	sharedBucketQuotaCache.entries[key] = bucketQuotaCacheEntry{
		quota:     quota,
		expiresAt: time.Now().Add(bucketQuotaCacheTTL),
	}
}

func bucketQuotaCacheKey(
	cfg storageconfig.RemoteStorageConfig,
	bucket string,
) [sha256.Size]byte {
	// Hash the normalized config so credential changes cannot reuse stale quota,
	// while the cache itself never retains a plaintext credential-bearing key.
	payload, _ := json.Marshal(struct {
		Config storageconfig.RemoteStorageConfig `json:"config"`
		Bucket string                            `json:"bucket"`
	}{Config: cfg.Normalized(), Bucket: bucket})
	return sha256.Sum256(payload)
}
