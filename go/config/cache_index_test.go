// Cache index tests cover bbolt persistence for preview/open cache metadata.
package config

import "testing"

func TestCacheIndexUpsertFindRemove(t *testing.T) {
	home := t.TempDir()
	setTestHome(t, home)

	record := CacheIndexRecord{
		Bucket:       "bucket-a",
		ObjectKey:    "dir/file.txt",
		LocalPath:    "/cache/files/bucket-a/dir/file.txt",
		FileSize:     42,
		LastModified: "2026-07-07T10:00:00Z",
	}
	if err := UpsertCacheIndexRecord(record); err != nil {
		t.Fatalf("UpsertCacheIndexRecord returned error: %v", err)
	}

	found, err := FindCacheIndexRecord("bucket-a", "dir/file.txt")
	if err != nil {
		t.Fatalf("FindCacheIndexRecord returned error: %v", err)
	}
	if found == nil {
		t.Fatal("expected cache index record, got nil")
	}
	if found.LocalPath != record.LocalPath || found.FileSize != record.FileSize {
		t.Fatalf("unexpected record: %#v", found)
	}
	if found.UpdatedAtEpochMs == 0 {
		t.Fatal("expected UpdatedAtEpochMs to be set")
	}

	if err := RemoveCacheIndexRecord("bucket-a", "dir/file.txt"); err != nil {
		t.Fatalf("RemoveCacheIndexRecord returned error: %v", err)
	}
	found, err = FindCacheIndexRecord("bucket-a", "dir/file.txt")
	if err != nil {
		t.Fatalf("FindCacheIndexRecord after remove returned error: %v", err)
	}
	if found != nil {
		t.Fatalf("expected removed record to be nil, got %#v", found)
	}
}

func TestCacheIndexRemovePrefixReturnsRemovedRecords(t *testing.T) {
	home := t.TempDir()
	setTestHome(t, home)

	records := []CacheIndexRecord{
		{Bucket: "bucket-a", ObjectKey: "dir/a.txt", LocalPath: "/cache/a", FileSize: 1},
		{Bucket: "bucket-a", ObjectKey: "dir/nested/b.txt", LocalPath: "/cache/b", FileSize: 2},
		{Bucket: "bucket-a", ObjectKey: "other.txt", LocalPath: "/cache/other", FileSize: 3},
		{Bucket: "bucket-b", ObjectKey: "dir/a.txt", LocalPath: "/cache/foreign", FileSize: 4},
	}
	for _, record := range records {
		if err := UpsertCacheIndexRecord(record); err != nil {
			t.Fatalf("UpsertCacheIndexRecord(%s): %v", record.ObjectKey, err)
		}
	}

	removed, err := RemoveCacheIndexPrefix("bucket-a", "dir/")
	if err != nil {
		t.Fatalf("RemoveCacheIndexPrefix returned error: %v", err)
	}
	if len(removed) != 2 {
		t.Fatalf("expected 2 removed records, got %d: %#v", len(removed), removed)
	}
	if found, _ := FindCacheIndexRecord("bucket-a", "dir/a.txt"); found != nil {
		t.Fatalf("expected dir/a.txt to be removed, got %#v", found)
	}
	if found, _ := FindCacheIndexRecord("bucket-a", "other.txt"); found == nil {
		t.Fatal("expected other.txt to remain")
	}
	if found, _ := FindCacheIndexRecord("bucket-b", "dir/a.txt"); found == nil {
		t.Fatal("expected other bucket record to remain")
	}
}
