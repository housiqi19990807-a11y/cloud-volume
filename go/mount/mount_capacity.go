// Mount capacity helpers resolve per-bucket quota before backend fallbacks.
package mount

import storageconfig "remote-storage/go/config"

const mountBytesPerGiB uint64 = 1024 * 1024 * 1024

func resolvedMountCapacityBytes(
	cfg storageconfig.RemoteStorageConfig,
	bucket string,
	fallbackBytes uint64,
) uint64 {
	quota := cfg.BucketSettingsFor(bucket).CustomQuotaBytes
	if quota > 0 {
		return uint64(quota)
	}
	return fallbackBytes
}

func mountCapacityBlocks(capacityBytes, blockBytes uint64) uint64 {
	if capacityBytes == 0 || blockBytes == 0 {
		return 0
	}
	return capacityBytes / blockBytes
}
