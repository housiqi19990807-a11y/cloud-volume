// Mount capacity helpers resolve per-bucket quota before backend fallbacks.
package mount

import storageconfig "remote-storage/go/config"

const mountBytesPerGiB uint64 = 1024 * 1024 * 1024

func resolvedMountCapacityBytes(
	cfg storageconfig.RemoteStorageConfig,
	bucket string,
	fallbackBytes uint64,
) uint64 {
	capacityBytes, _ := resolvedMountCapacity(
		cfg,
		bucket,
		0,
		0,
		fallbackBytes,
	)
	return capacityBytes
}

// resolvedMountCapacity uses the user override first, then provider quota,
// and leaves the backend fallback only for providers without quota support.
func resolvedMountCapacity(
	cfg storageconfig.RemoteStorageConfig,
	bucket string,
	providerQuotaBytes, providerUsedBytes int64,
	fallbackBytes uint64,
) (capacityBytes, usedBytes uint64) {
	customQuotaBytes := cfg.BucketSettingsFor(bucket).CustomQuotaBytes
	if customQuotaBytes > 0 {
		return uint64(customQuotaBytes), 0
	}
	if providerQuotaBytes > 0 {
		capacityBytes = uint64(providerQuotaBytes)
		if providerUsedBytes > 0 {
			usedBytes = uint64(providerUsedBytes)
		}
		return capacityBytes, usedBytes
	}
	return fallbackBytes, 0
}

func mountCapacityBlocks(capacityBytes, blockBytes uint64) uint64 {
	if capacityBytes == 0 || blockBytes == 0 {
		return 0
	}
	return capacityBytes / blockBytes
}
