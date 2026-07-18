// Bucket settings tests cover custom quota normalization and resolution.
package config

import "testing"

func TestNormalizeBucketSettingsClampsNegativeQuota(t *testing.T) {
	t.Parallel()

	settings := normalizeBucketSettings(map[string]BucketSettings{
		" bucket-a ": {CustomQuotaBytes: -1},
		"":           {CustomQuotaBytes: 1024},
	})
	if len(settings) != 1 {
		t.Fatalf("len(settings) = %d, want 1", len(settings))
	}
	if got := settings["bucket-a"].CustomQuotaBytes; got != 0 {
		t.Fatalf("CustomQuotaBytes = %d, want 0", got)
	}
}

func TestBucketSettingsForReturnsCustomQuota(t *testing.T) {
	t.Parallel()

	const quota = int64(1536 * 1024 * 1024)
	config := RemoteStorageConfig{
		StorageType: StorageTypeS3,
		BucketSettings: map[string]BucketSettings{
			"bucket-a": {CustomQuotaBytes: quota},
		},
	}
	if got := config.BucketSettingsFor("bucket-a").CustomQuotaBytes; got != quota {
		t.Fatalf("CustomQuotaBytes = %d, want %d", got, quota)
	}
	if got := config.BucketSettingsFor("bucket-b").CustomQuotaBytes; got != 0 {
		t.Fatalf("unset CustomQuotaBytes = %d, want 0", got)
	}
}
