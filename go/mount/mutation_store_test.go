// Mutation store tests pin crash-tolerant append-only recovery and compaction rules.
package mount

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func newTestMutationRecord(oldPath, newPath string) mutationRecord {
	return mutationRecord{
		Version:           mutationRecordVersion,
		ID:                "mutation-test-1",
		TaskID:            "mount-move-test",
		Kind:              mutationKindRename,
		OldVirtualPath:    oldPath,
		NewVirtualPath:    newPath,
		IsDirectory:       true,
		UploadGeneration:  3,
		RetryCount:        1,
		NextAttemptUnixNs: time.Now().Add(time.Minute).UnixNano(),
		UpdatedAtUnixNs:   time.Now().UnixNano(),
	}
}

func writeMutationLines(t *testing.T, dir, name string, lines ...string) {
	t.Helper()
	if err := os.MkdirAll(dir, 0o755); err != nil {
		t.Fatalf("mkdir mutation dir: %v", err)
	}
	payload := ""
	for _, line := range lines {
		payload += line + "\n"
	}
	if err := os.WriteFile(filepath.Join(dir, name), []byte(payload), 0o600); err != nil {
		t.Fatalf("write mutation file: %v", err)
	}
}

func TestMutationStoreIgnoresOnlyATruncatedFinalLine(t *testing.T) {
	dir := filepath.Join(t.TempDir(), "mutations")
	store := openMutationStoreForTest(t, dir)
	record := newTestMutationRecord("New Folder", "Reports")
	complete, err := encodeMutationEvent(mutationEvent{
		Kind:   mutationEventUpsert,
		Record: record,
	})
	if err != nil {
		t.Fatalf("encode upsert: %v", err)
	}
	truncated := complete[:len(complete)-8]
	// The truncated line must be unterminated: a crash mid-append leaves no
	// trailing newline, which is the only tolerable corruption.
	if err := os.WriteFile(
		filepath.Join(dir, "queue-100.jsonl"),
		[]byte(complete+"\n"+truncated),
		0o600,
	); err != nil {
		t.Fatalf("write mutation file: %v", err)
	}

	restored, err := store.Restore()
	if err != nil {
		t.Fatalf("restore with truncated final line: %v", err)
	}
	if len(restored) != 1 || restored[record.ID].NewVirtualPath != "Reports" {
		t.Fatalf("unexpected restored records: %+v", restored)
	}
}

func TestMutationStoreRejectsMalformedInteriorLine(t *testing.T) {
	dir := filepath.Join(t.TempDir(), "mutations")
	store := openMutationStoreForTest(t, dir)
	record := newTestMutationRecord("New Folder", "Reports")
	complete, err := encodeMutationEvent(mutationEvent{
		Kind:   mutationEventUpsert,
		Record: record,
	})
	if err != nil {
		t.Fatalf("encode upsert: %v", err)
	}
	writeMutationLines(t, dir, "queue-101.jsonl", complete, "{not-json", complete)

	if _, err := store.Restore(); err == nil {
		t.Fatal("expected error for malformed interior line")
	}
}

func TestMutationStoreRejectsUnsupportedVersion(t *testing.T) {
	dir := filepath.Join(t.TempDir(), "mutations")
	store := openMutationStoreForTest(t, dir)
	future := newTestMutationRecord("a", "b")
	future.Version = mutationRecordVersion + 1
	line, err := encodeMutationEvent(mutationEvent{
		Kind:   mutationEventUpsert,
		Record: future,
	})
	if err != nil {
		t.Fatalf("encode future record: %v", err)
	}
	writeMutationLines(t, dir, "queue-102.jsonl", line)

	if _, err := store.Restore(); err == nil {
		t.Fatal("expected error for unsupported record version")
	}
}

func TestMutationStoreCompletesAndCompacts(t *testing.T) {
	dir := filepath.Join(t.TempDir(), "mutations")
	store := openMutationStoreForTest(t, dir)
	record := newTestMutationRecord("New Folder", "Reports")
	if err := store.Upsert(record); err != nil {
		t.Fatalf("upsert: %v", err)
	}
	if err := store.Complete(record.ID); err != nil {
		t.Fatalf("complete: %v", err)
	}

	restored, err := openMutationStoreForTest(t, dir).Restore()
	if err != nil {
		t.Fatalf("restore: %v", err)
	}
	if len(restored) != 0 {
		t.Fatalf("completed record survived restore: %+v", restored)
	}

	entries, err := os.ReadDir(dir)
	if err != nil {
		t.Fatalf("read mutation dir: %v", err)
	}
	if len(entries) != 1 || !strings.HasSuffix(entries[0].Name(), ".jsonl") {
		t.Fatalf("compaction must keep exactly one JSONL file, got %v", entries)
	}
	if strings.Contains(entries[0].Name(), "101") {
		t.Fatalf("stale process log survived compaction: %s", entries[0].Name())
	}
}

func TestMutationStorePersistsUpdatesDurably(t *testing.T) {
	dir := filepath.Join(t.TempDir(), "mutations")
	store := openMutationStoreForTest(t, dir)
	record := newTestMutationRecord("a", "b")
	record.ID = "mutation-retry"
	if err := store.Upsert(record); err != nil {
		t.Fatalf("upsert: %v", err)
	}
	record.RetryCount = 5
	if err := store.Upsert(record); err != nil {
		t.Fatalf("update: %v", err)
	}

	restored, err := openMutationStoreForTest(t, dir).Restore()
	if err != nil {
		t.Fatalf("restore: %v", err)
	}
	if restored["mutation-retry"].RetryCount != 5 {
		t.Fatalf("retry count = %d, want 5", restored["mutation-retry"].RetryCount)
	}
}

func openMutationStoreForTest(t *testing.T, dir string) *mutationStore {
	t.Helper()
	store, err := openMutationStore(dir)
	if err != nil {
		t.Fatalf("open mutation store: %v", err)
	}
	t.Cleanup(func() { _ = store.Close() })
	return store
}
