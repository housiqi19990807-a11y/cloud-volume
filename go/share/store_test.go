package share

import (
	"testing"

	storageconfig "remote-storage/go/config"
)

// Share store tests pin the local-record persistence contract independent of S3.
func TestSaveAndLoadRecords(t *testing.T) {
	t.Setenv("HOME", t.TempDir())

	cfg := storageconfig.RemoteStorageConfig{
		Endpoint:    "https://s3.example.com",
		AccessKeyID: "demo",
	}
	input := []Record{
		{ID: "older", UpdatedAt: "2026-05-27T10:00:00Z"},
		{ID: "newer", UpdatedAt: "2026-05-27T12:00:00Z"},
	}

	if err := saveRecords(cfg, input); err != nil {
		t.Fatalf("saveRecords returned error: %v", err)
	}

	loaded, err := loadRecords(cfg)
	if err != nil {
		t.Fatalf("loadRecords returned error: %v", err)
	}
	if len(loaded) != 2 {
		t.Fatalf("expected 2 records, got %d", len(loaded))
	}
	if loaded[0].ID != "newer" {
		t.Fatalf("expected records to be sorted by UpdatedAt descending, got %q", loaded[0].ID)
	}
}

func TestDeleteRemovesOnlyMatchingRecord(t *testing.T) {
	t.Setenv("HOME", t.TempDir())

	cfg := storageconfig.RemoteStorageConfig{
		Endpoint:    "https://s3.example.com",
		AccessKeyID: "demo",
	}
	if err := saveRecords(cfg, []Record{
		{ID: "keep", UpdatedAt: "2026-05-27T12:00:00Z"},
		{ID: "drop", UpdatedAt: "2026-05-27T10:00:00Z"},
	}); err != nil {
		t.Fatalf("seed saveRecords returned error: %v", err)
	}

	if err := Delete(cfg, "drop"); err != nil {
		t.Fatalf("Delete returned error: %v", err)
	}

	loaded, err := loadRecords(cfg)
	if err != nil {
		t.Fatalf("loadRecords returned error: %v", err)
	}
	if len(loaded) != 1 || loaded[0].ID != "keep" {
		t.Fatalf("unexpected remaining records: %+v", loaded)
	}
}
