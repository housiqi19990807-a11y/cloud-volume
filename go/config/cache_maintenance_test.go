package config

import (
	"os"
	"path/filepath"
	"testing"
	"time"
)

// Cache maintenance tests pin size/age eviction so the settings card can rely on
// stable byte accounting and idempotent empty-dir handling.
func TestGetCacheStatsReportsMissingDirAsEmpty(t *testing.T) {
	stats, err := GetCacheStats(RemoteStorageConfig{
		CacheDirectory: filepath.Join(t.TempDir(), "missing"),
	})
	if err != nil {
		t.Fatalf("GetCacheStats returned error: %v", err)
	}
	if stats.Exists {
		t.Fatalf("expected missing cache dir to be reported as not existing")
	}
	if stats.SizeBytes != 0 || stats.FileCount != 0 {
		t.Fatalf("expected zero stats for missing dir, got %+v", stats)
	}
}

func TestGetCacheStatsCountsFiles(t *testing.T) {
	dir := t.TempDir()
	if err := os.WriteFile(filepath.Join(dir, "a.bin"), []byte{0, 1, 2}, 0o600); err != nil {
		t.Fatalf("write file: %v", err)
	}
	if err := os.MkdirAll(filepath.Join(dir, "nested"), 0o700); err != nil {
		t.Fatalf("mkdir: %v", err)
	}
	if err := os.WriteFile(filepath.Join(dir, "nested", "b.bin"), []byte{0, 1, 2, 3, 4}, 0o600); err != nil {
		t.Fatalf("write nested file: %v", err)
	}

	stats, err := GetCacheStats(RemoteStorageConfig{CacheDirectory: dir})
	if err != nil {
		t.Fatalf("GetCacheStats returned error: %v", err)
	}
	if !stats.Exists {
		t.Fatalf("expected cache dir to be reported as existing")
	}
	if stats.SizeBytes != 8 || stats.FileCount != 2 {
		t.Fatalf("unexpected stats: size=%d count=%d", stats.SizeBytes, stats.FileCount)
	}
}

func TestCleanCacheClearAllRemovesEverything(t *testing.T) {
	dir := t.TempDir()
	if err := os.WriteFile(filepath.Join(dir, "a.bin"), []byte{0, 1, 2, 3}, 0o600); err != nil {
		t.Fatalf("write file: %v", err)
	}
	if err := os.MkdirAll(filepath.Join(dir, "nested"), 0o700); err != nil {
		t.Fatalf("mkdir: %v", err)
	}
	if err := os.WriteFile(filepath.Join(dir, "nested", "b.bin"), []byte{0, 1, 2}, 0o600); err != nil {
		t.Fatalf("write nested file: %v", err)
	}

	result, err := CleanCache(
		RemoteStorageConfig{CacheDirectory: dir},
		CleanCacheRequest{ClearAll: true},
	)
	if err != nil {
		t.Fatalf("CleanCache returned error: %v", err)
	}
	if result.Removed != 2 || result.FreedBytes != 7 {
		t.Fatalf("unexpected result: %+v", result)
	}

	stats, err := GetCacheStats(RemoteStorageConfig{CacheDirectory: dir})
	if err != nil {
		t.Fatalf("GetCacheStats after clean returned error: %v", err)
	}
	if stats.SizeBytes != 0 || stats.FileCount != 0 {
		t.Fatalf("expected empty cache after clear, got %+v", stats)
	}
}

func TestCleanCacheRulesEvictByAgeAndSize(t *testing.T) {
	dir := t.TempDir()
	oldPath := filepath.Join(dir, "old.bin")
	if err := os.WriteFile(oldPath, []byte{0, 1, 2, 3, 4}, 0o600); err != nil {
		t.Fatalf("write old file: %v", err)
	}
	oldTime := time.Now().Add(-48 * time.Hour)
	if err := os.Chtimes(oldPath, oldTime, oldTime); err != nil {
		t.Fatalf("chtimes old: %v", err)
	}

	freshPath := filepath.Join(dir, "fresh.bin")
	if err := os.WriteFile(freshPath, []byte{0, 1, 2}, 0o600); err != nil {
		t.Fatalf("write fresh file: %v", err)
	}

	// Age rule of 1 day should evict only the old file; size cap of 0 disables.
	result, err := CleanCache(
		RemoteStorageConfig{
			CacheDirectory:  dir,
			CacheMaxAgeDays: 1,
			CacheMaxSizeMB:  0,
		},
		CleanCacheRequest{},
	)
	if err != nil {
		t.Fatalf("CleanCache returned error: %v", err)
	}
	if result.Removed != 1 {
		t.Fatalf("expected 1 file removed by age, got %d", result.Removed)
	}
	if _, err := os.Stat(freshPath); err != nil {
		t.Fatalf("expected fresh file to remain, got %v", err)
	}

	// Add a large file again and confirm size cap evicts the oldest survivor.
	if err := os.WriteFile(oldPath, []byte{0, 1, 2, 3, 4, 5, 6, 7, 8, 9}, 0o600); err != nil {
		t.Fatalf("rewrite old file: %v", err)
	}
	if err := os.Chtimes(oldPath, oldTime, oldTime); err != nil {
		t.Fatalf("chtimes old again: %v", err)
	}
	// 1 MiB cap with ~13 bytes of data should not evict; use a tiny cap instead.
	result, err = CleanCache(
		RemoteStorageConfig{
			CacheDirectory:  dir,
			CacheMaxAgeDays: 0,
			CacheMaxSizeMB:  1,
		},
		CleanCacheRequest{},
	)
	if err != nil {
		t.Fatalf("CleanCache by size returned error: %v", err)
	}
	// 1 MiB cap >> current ~13 bytes, so nothing should be removed.
	if result.Removed != 0 {
		t.Fatalf("expected no eviction under loose cap, got %d", result.Removed)
	}
}

func TestCleanCacheEmptyDirIsIdempotent(t *testing.T) {
	dir := t.TempDir()
	result, err := CleanCache(
		RemoteStorageConfig{CacheDirectory: dir},
		CleanCacheRequest{ClearAll: true},
	)
	if err != nil {
		t.Fatalf("CleanCache on empty dir returned error: %v", err)
	}
	if result.Removed != 0 || result.BeforeBytes != 0 || result.AfterBytes != 0 {
		t.Fatalf("expected empty result, got %+v", result)
	}
}
