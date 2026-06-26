package sync

import (
	"path/filepath"
	"testing"
)

func TestBboltIndexPutGetDelete(t *testing.T) {
	dir := t.TempDir()
	idx, err := openIndex(dir, "test-profile")
	if err != nil {
		t.Fatalf("openIndex: %v", err)
	}
	defer idx.Close()

	entry := IndexEntry{LocalSize: 100, LocalMTime: 1234, RemoteSize: 100, RemoteMTime: 1234}
	if err := idx.PutEntry("a/b.txt", entry); err != nil {
		t.Fatalf("PutEntry: %v", err)
	}

	got, ok := idx.GetEntry("a/b.txt")
	if !ok {
		t.Fatal("GetEntry: not found")
	}
	if got.LocalSize != 100 || got.RemoteMTime != 1234 {
		t.Fatalf("GetEntry returned wrong data: %+v", got)
	}

	if err := idx.DeleteEntry("a/b.txt"); err != nil {
		t.Fatalf("DeleteEntry: %v", err)
	}
	if _, ok := idx.GetEntry("a/b.txt"); ok {
		t.Fatal("GetEntry should report absent after delete")
	}
}

func TestBboltIndexEachAndCount(t *testing.T) {
	dir := t.TempDir()
	idx, err := openIndex(dir, "count-profile")
	if err != nil {
		t.Fatalf("openIndex: %v", err)
	}
	defer idx.Close()

	entries := map[string]IndexEntry{
		"x.txt":     {LocalSize: 1},
		"y/z.txt":   {LocalSize: 2},
		"a/b/c.txt": {LocalSize: 3},
	}
	for k, v := range entries {
		if err := idx.PutEntry(k, v); err != nil {
			t.Fatalf("PutEntry %s: %v", k, err)
		}
	}

	if n := idx.CountEntries(); n != 3 {
		t.Fatalf("CountEntries = %d, want 3", n)
	}

	seen := map[string]int64{}
	_ = idx.EachEntry(func(rel string, e IndexEntry) bool {
		seen[rel] = e.LocalSize
		return true
	})
	if len(seen) != 3 || seen["x.txt"] != 1 || seen["y/z.txt"] != 2 || seen["a/b/c.txt"] != 3 {
		t.Fatalf("EachEntry missed entries: %+v", seen)
	}
}

func TestBboltIndexReopensPersisted(t *testing.T) {
	dir := t.TempDir()
	idx, err := openIndex(dir, "persist-profile")
	if err != nil {
		t.Fatalf("openIndex: %v", err)
	}
	if err := idx.PutEntry("keep.txt", IndexEntry{LocalSize: 42}); err != nil {
		t.Fatalf("PutEntry: %v", err)
	}
	idx.Close()

	// Reopen and verify the entry survived.
	idx2, err := openIndex(filepath.Clean(dir), "persist-profile")
	if err != nil {
		t.Fatalf("reopen: %v", err)
	}
	defer idx2.Close()
	got, ok := idx2.GetEntry("keep.txt")
	if !ok || got.LocalSize != 42 {
		t.Fatalf("entry not persisted, got: %+v ok=%v", got, ok)
	}
}
