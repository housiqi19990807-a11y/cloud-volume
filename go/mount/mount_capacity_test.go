// Mount capacity tests pin custom quota precedence and block conversion.
package mount

import (
	"testing"

	storageconfig "remote-storage/go/config"
)

func TestResolvedMountCapacityPrefersBucketQuota(t *testing.T) {
	t.Parallel()

	const customQuota = int64(1536 * 1024 * 1024)
	cfg := storageconfig.RemoteStorageConfig{
		BucketSettings: map[string]storageconfig.BucketSettings{
			"bucket-a": {CustomQuotaBytes: customQuota},
		},
	}
	if got := resolvedMountCapacityBytes(cfg, "bucket-a", 10*mountBytesPerGiB); got != uint64(customQuota) {
		t.Fatalf("capacity = %d, want %d", got, customQuota)
	}
	if got := resolvedMountCapacityBytes(cfg, "bucket-b", 10*mountBytesPerGiB); got != 10*mountBytesPerGiB {
		t.Fatalf("fallback capacity = %d, want %d", got, 10*mountBytesPerGiB)
	}
	capacity, used := resolvedMountCapacity(
		cfg,
		"bucket-a",
		10*int64(mountBytesPerGiB),
		3*int64(mountBytesPerGiB),
		1024*mountBytesPerGiB,
	)
	if capacity != uint64(customQuota) || used != 0 {
		t.Fatalf("custom capacity/used = %d/%d, want %d/0", capacity, used, customQuota)
	}
}

func TestResolvedMountCapacityUsesProviderQuotaBeforeFallback(t *testing.T) {
	t.Parallel()

	cfg := storageconfig.RemoteStorageConfig{}
	capacity, used := resolvedMountCapacity(
		cfg,
		"bucket-a",
		10*int64(mountBytesPerGiB),
		3*int64(mountBytesPerGiB),
		1024*mountBytesPerGiB,
	)
	if capacity != 10*mountBytesPerGiB || used != 3*mountBytesPerGiB {
		t.Fatalf("capacity/used = %d/%d, want 10 GiB/3 GiB", capacity, used)
	}

	capacity, used = resolvedMountCapacity(
		cfg,
		"bucket-a",
		0,
		0,
		1024*mountBytesPerGiB,
	)
	if capacity != 1024*mountBytesPerGiB || used != 0 {
		t.Fatalf("fallback capacity/used = %d/%d, want 1024 GiB/0", capacity, used)
	}
}

func TestMountCapacityBlocks(t *testing.T) {
	t.Parallel()

	if got := mountCapacityBlocks(10_000, 4096); got != 2 {
		t.Fatalf("blocks = %d, want 2", got)
	}
	if got := mountCapacityBlocks(10_000, 0); got != 0 {
		t.Fatalf("zero block size returned %d blocks", got)
	}
}
