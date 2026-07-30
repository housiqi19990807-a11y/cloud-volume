// Bucket quota cache tests pin account isolation and expiry behavior.
package storage

import (
	"testing"
	"time"

	storageconfig "remote-storage/go/config"
)

func TestBucketQuotaCacheReusesMatchingAccountAndBucket(t *testing.T) {
	cfg := storageconfig.RemoteStorageConfig{
		StorageType: storageconfig.StorageTypeSFTP,
		Endpoint:    "sftp://cache-test",
		FTPUsername: "user-a",
		FTPPassword: "secret-a",
	}
	want := BucketInfo{Name: "bucket-a", QuotaBytes: 1000, UsedBytes: 250, QuotaKnown: true}
	cacheBucketQuota(cfg, "bucket-a", want)

	got, ok := CachedBucketQuota(cfg, "bucket-a")
	if !ok || got != want {
		t.Fatalf("cached quota = %+v, %t; want %+v, true", got, ok, want)
	}
	if _, ok := CachedBucketQuota(cfg, "bucket-b"); ok {
		t.Fatal("quota cache leaked across buckets")
	}
	changed := cfg
	changed.FTPPassword = "secret-b"
	if _, ok := CachedBucketQuota(changed, "bucket-a"); ok {
		t.Fatal("quota cache leaked across credentials")
	}
}

func TestBucketQuotaCacheExpiresEntries(t *testing.T) {
	cfg := storageconfig.RemoteStorageConfig{
		StorageType: storageconfig.StorageTypeSFTP,
		Endpoint:    "sftp://expired-cache-test",
	}
	cacheBucketQuota(cfg, "bucket-a", BucketInfo{Name: "bucket-a", QuotaKnown: true})
	key := bucketQuotaCacheKey(cfg, "bucket-a")
	sharedBucketQuotaCache.Lock()
	entry := sharedBucketQuotaCache.entries[key]
	entry.expiresAt = time.Now().Add(-time.Second)
	sharedBucketQuotaCache.entries[key] = entry
	sharedBucketQuotaCache.Unlock()

	if _, ok := CachedBucketQuota(cfg, "bucket-a"); ok {
		t.Fatal("expired quota cache entry remained visible")
	}
}
