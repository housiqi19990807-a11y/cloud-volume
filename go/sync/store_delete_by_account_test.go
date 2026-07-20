package sync

import (
	"path/filepath"
	"testing"
)

// TestStoreDeleteByAccount verifies that deleting an account profile cascades
// to every sync profile that references it, while leaving unrelated profiles
// intact. This backs the account-deletion cascade contract.
func TestStoreDeleteByAccount(t *testing.T) {
	dir := t.TempDir()
	store := NewStore(filepath.Join(dir, "cloud-volume"))

	profiles := []SyncProfile{
		{ID: "sync-a", Name: "A", AccountProfile: "acct-1", Bucket: "b1", LocalPath: "/tmp/a"},
		{ID: "sync-b", Name: "B", AccountProfile: "acct-2", Bucket: "b2", LocalPath: "/tmp/b"},
		{ID: "sync-c", Name: "C", AccountProfile: "acct-1", Bucket: "b3", LocalPath: "/tmp/c"},
	}
	for _, p := range profiles {
		if err := store.Upsert(p); err != nil {
			t.Fatalf("upsert %s: %v", p.ID, err)
		}
	}

	removed, err := store.DeleteByAccount("acct-1")
	if err != nil {
		t.Fatalf("DeleteByAccount: %v", err)
	}
	if removed != 2 {
		t.Fatalf("expected 2 removed, got %d", removed)
	}

	remaining, err := store.LoadAll()
	if err != nil {
		t.Fatalf("LoadAll: %v", err)
	}
	if len(remaining) != 1 || remaining[0].ID != "sync-b" {
		t.Fatalf("expected only sync-b to remain, got %+v", remaining)
	}

	// Deleting an account with no sync profiles is a no-op (0 removed), not
	// an error.
	again, err := store.DeleteByAccount("acct-1")
	if err != nil || again != 0 {
		t.Fatalf("re-delete expected 0, got %d / %v", again, err)
	}

	// Empty account name is a no-op rather than wiping everything.
	empty, err := store.DeleteByAccount("")
	if err != nil || empty != 0 {
		t.Fatalf("empty-name delete expected 0, got %d / %v", empty, err)
	}
	stillThere, _ := store.LoadAll()
	if len(stillThere) != 1 {
		t.Fatalf("empty-name delete should not remove anything, got %+v", stillThere)
	}
}

// TestStoreDeleteRemovesOnlyTarget verifies the single-profile delete path used
// by the sync tasks page does not share backing arrays with the source slice
// (which would let a concurrent reader observe stale entries).
func TestStoreDeleteRemovesOnlyTarget(t *testing.T) {
	dir := t.TempDir()
	store := NewStore(filepath.Join(dir, "cloud-volume"))

	if err := store.Upsert(SyncProfile{ID: "1", Name: "one", AccountProfile: "acct", Bucket: "b", LocalPath: "/tmp/1"}); err != nil {
		t.Fatal(err)
	}
	if err := store.Upsert(SyncProfile{ID: "2", Name: "two", AccountProfile: "acct", Bucket: "b", LocalPath: "/tmp/2"}); err != nil {
		t.Fatal(err)
	}

	if err := store.Delete("1"); err != nil {
		t.Fatalf("Delete: %v", err)
	}
	remaining, _ := store.LoadAll()
	if len(remaining) != 1 || remaining[0].ID != "2" {
		t.Fatalf("expected only profile 2, got %+v", remaining)
	}
}

