// Bucket quota cache shares recently resolved capacity across bridge and mount calls.
package storage

import (
	"crypto/sha256"
	"encoding/json"
	"log"
	"strings"
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

// CachedBucketQuota returns fresh capacity already fetched by the bucket list
// flow. Ordinary callers use this TTL-bound view to decide when to refresh.
func CachedBucketQuota(
	cfg storageconfig.RemoteStorageConfig,
	bucket string,
) (BucketInfo, bool) {
	key := bucketQuotaCacheKey(cfg, bucket)
	sharedBucketQuotaCache.RLock()
	entry, ok := sharedBucketQuotaCache.entries[key]
	sharedBucketQuotaCache.RUnlock()
	if !ok || time.Now().After(entry.expiresAt) {
		log.Printf("[storage/quota-cache] miss bucket=%q key=%x", strings.TrimSpace(bucket), key[:6])
		return BucketInfo{}, false
	}
	log.Printf("[storage/quota-cache] hit bucket=%q key=%x", strings.TrimSpace(bucket), key[:6])
	return entry.quota, true
}

// CachedBucketQuotaForMount returns the last known capacity even after its
// refresh TTL expires. A mount must answer the initial WebDAV quota handshake
// immediately; it can refresh stale capacity asynchronously after doing so.
func CachedBucketQuotaForMount(
	cfg storageconfig.RemoteStorageConfig,
	bucket string,
) (quota BucketInfo, fresh bool, ok bool) {
	key := bucketQuotaCacheKey(cfg, bucket)
	sharedBucketQuotaCache.RLock()
	entry, ok := sharedBucketQuotaCache.entries[key]
	sharedBucketQuotaCache.RUnlock()
	if !ok {
		log.Printf("[storage/quota-cache] mount-miss bucket=%q key=%x", strings.TrimSpace(bucket), key[:6])
		return BucketInfo{}, false, false
	}
	fresh = !time.Now().After(entry.expiresAt)
	log.Printf(
		"[storage/quota-cache] mount-hit bucket=%q key=%x fresh=%t",
		strings.TrimSpace(bucket),
		key[:6],
		fresh,
	)
	return entry.quota, fresh, true
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
	normalized := cfg.Normalized()
	// Only connection identity participates. Mount, cache, display, and bucket
	// presentation settings do not change which upstream quota is being read.
	payload, _ := json.Marshal(struct {
		StorageType     string `json:"storageType"`
		ProviderType    string `json:"providerType"`
		Endpoint        string `json:"endpoint"`
		Region          string `json:"region"`
		AccessKeyID     string `json:"accessKeyId"`
		SecretAccessKey string `json:"secretAccessKey"`
		WebDAVUsername  string `json:"webdavUsername"`
		WebDAVPassword  string `json:"webdavPassword"`
		FTPUsername     string `json:"ftpUsername"`
		FTPPassword     string `json:"ftpPassword"`
		FTPPort         int    `json:"ftpPort"`
		FTPAnonymous    bool   `json:"ftpAnonymous"`
		UsePathStyle    bool   `json:"usePathStyle"`
		JWanMode        string `json:"jwanMode"`
		ProxyMode       string `json:"proxyMode"`
		ProxyType       string `json:"proxyType"`
		ProxyHost       string `json:"proxyHost"`
		ProxyPort       string `json:"proxyPort"`
		ProxyUsername   string `json:"proxyUsername"`
		ProxyPassword   string `json:"proxyPassword"`
		Bucket          string `json:"bucket"`
	}{
		StorageType: normalized.StorageType, ProviderType: normalized.ProviderType,
		Endpoint: normalized.Endpoint, Region: normalized.Region,
		AccessKeyID: normalized.AccessKeyID, SecretAccessKey: normalized.SecretAccessKey,
		WebDAVUsername: normalized.WebDAVUsername, WebDAVPassword: normalized.WebDAVPassword,
		FTPUsername: normalized.FTPUsername, FTPPassword: normalized.FTPPassword,
		FTPPort: normalized.FTPPort, FTPAnonymous: normalized.FTPAnonymous,
		UsePathStyle: normalized.UsePathStyle, JWanMode: normalized.JWanFSGatewayMode,
		ProxyMode: normalized.ProxyMode, ProxyType: normalized.ProxyType,
		ProxyHost: normalized.ProxyHost, ProxyPort: normalized.ProxyPort,
		ProxyUsername: normalized.ProxyUsername, ProxyPassword: normalized.ProxyPassword,
		Bucket: strings.TrimSpace(bucket),
	})
	return sha256.Sum256(payload)
}
