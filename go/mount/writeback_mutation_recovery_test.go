// Writeback mutation recovery tests pin restart persistence and remote-state convergence.
package mount

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func newMutationRecoveryAccess(t *testing.T, backend *mutationMoveTestBackend) *bucketAccess {
	t.Helper()
	access := newTestBucketAccess(t)
	access.backend = backend
	return access
}

// TestRenameMutationRestoresAfterRestart closes the first queue with a pending
// move and observes completion from a second queue over the same session root.
func TestRenameMutationRestoresAfterRestart(t *testing.T) {
	backend := newMutationMoveTestBackend()
	backend.files["old/report.txt"] = true
	access := newMutationRecoveryAccess(t, backend)

	root := filepath.Join(access.sessionRoot, "sync-root")
	oldDir := filepath.Join(root, "old")
	if err := os.MkdirAll(oldDir, 0o755); err != nil {
		t.Fatalf("mkdir old: %v", err)
	}
	backend.moveFails = 1000
	if err := access.enqueueRenamePath(
		"old",
		"new",
		oldDir,
		filepath.Join(root, "new"),
		true,
	); err != nil {
		t.Fatalf("enqueue rename: %v", err)
	}
	waitForMutationState(t, access, func(record mutationRecord) bool {
		return record.RetryCount >= 1
	})
	if err := access.close(); err != nil {
		t.Fatalf("close first access: %v", err)
	}

	backend.moveFails = 0
	restored := newMutationRecoveryAccess(t, backend)
	restored.sessionRoot = access.sessionRoot
	restored.cacheRoot = filepath.Join(access.sessionRoot, "cache")
	restored.stageRoot = filepath.Join(access.sessionRoot, "staging")
	writeback, err := newWritebackQueue(restored)
	if err != nil {
		t.Fatalf("restore writeback queue: %v", err)
	}
	restored.writeback = writeback
	t.Cleanup(func() { _ = restored.close() })

	waitForMutationCompletion(t, restored, "mutation", 10*time.Second)
	if !backend.has("new/report.txt") {
		t.Fatal("restored move did not converge to the destination")
	}
	if backend.has("old/report.txt") {
		t.Fatal("restored move left the source behind")
	}
}

// TestMoveWithBothSourceAndDestinationConverges pins the ambiguous retry
// state on the restore path: the first queue crashed after the provider copy
// succeeded but before the source delete, so both keys exist and the restored
// reconciler must converge via copy + hard delete without MoveObject.
func TestMoveWithBothSourceAndDestinationConverges(t *testing.T) {
	backend := newMutationMoveTestBackend()
	backend.files["src/a.txt"] = true
	access := newMutationRecoveryAccess(t, backend)

	root := filepath.Join(access.sessionRoot, "sync-root")
	if err := os.MkdirAll(filepath.Join(root, "src"), 0o755); err != nil {
		t.Fatalf("mkdir src: %v", err)
	}
	backend.moveFails = 1000
	if err := access.enqueueRenamePath(
		"src/a.txt",
		"dst/a.txt",
		filepath.Join(root, "src", "a.txt"),
		filepath.Join(root, "dst", "a.txt"),
		false,
	); err != nil {
		t.Fatalf("enqueue move: %v", err)
	}
	waitForMutationState(t, access, func(record mutationRecord) bool {
		return record.RetryCount >= 1
	})
	if err := access.close(); err != nil {
		t.Fatalf("close first access: %v", err)
	}

	// Simulate the crash window: the provider copy landed, the delete did not.
	backend.files["dst/a.txt"] = true
	backend.moveFails = 0
	movesBefore, copiesBefore, deletesBefore := backend.counters()

	restored := newMutationRecoveryAccess(t, backend)
	restored.sessionRoot = access.sessionRoot
	restored.cacheRoot = filepath.Join(access.sessionRoot, "cache")
	restored.stageRoot = filepath.Join(access.sessionRoot, "staging")
	writeback, err := newWritebackQueue(restored)
	if err != nil {
		t.Fatalf("restore writeback queue: %v", err)
	}
	restored.writeback = writeback
	t.Cleanup(func() { _ = restored.close() })

	waitForMutationCompletion(t, restored, "mutation", 10*time.Second)
	if !backend.has("dst/a.txt") {
		t.Fatal("destination missing after converging move")
	}
	if backend.has("src/a.txt") {
		t.Fatal("source survived a converged move")
	}
	moves, copies, deletes := backend.counters()
	if moves != movesBefore {
		t.Fatalf("ambiguous retry must not call MoveObject, got %d extra calls", moves-movesBefore)
	}
	if copies == copiesBefore || deletes <= deletesBefore {
		t.Fatalf(
			"ambiguous retry must merge by copy then hard delete: copies %d->%d deletes %d->%d",
			copiesBefore,
			copies,
			deletesBefore,
			deletes,
		)
	}
}

// TestCompletedMoveIsNotRepeatedAfterRestore verifies a persisted completion
// tombstone prevents a second provider mutation after restart.
func TestCompletedMoveIsNotRepeatedAfterRestore(t *testing.T) {
	backend := newMutationMoveTestBackend()
	backend.files["old/report.txt"] = true
	access := newMutationRecoveryAccess(t, backend)

	root := filepath.Join(access.sessionRoot, "sync-root")
	oldDir := filepath.Join(root, "old")
	if err := os.MkdirAll(oldDir, 0o755); err != nil {
		t.Fatalf("mkdir old: %v", err)
	}
	if err := access.enqueueRenamePath(
		"old",
		"new",
		oldDir,
		filepath.Join(root, "new"),
		true,
	); err != nil {
		t.Fatalf("enqueue rename: %v", err)
	}
	waitForMutationCompletion(t, access, "mutation", 10*time.Second)
	if !backend.has("new/report.txt") {
		t.Fatal("first-queue move did not finish")
	}
	if err := access.close(); err != nil {
		t.Fatalf("close first access: %v", err)
	}
	moves, _, deletes := backend.counters()

	restored := newMutationRecoveryAccess(t, backend)
	restored.sessionRoot = access.sessionRoot
	restored.cacheRoot = filepath.Join(access.sessionRoot, "cache")
	restored.stageRoot = filepath.Join(access.sessionRoot, "staging")
	writeback, err := newWritebackQueue(restored)
	if err != nil {
		t.Fatalf("restore writeback queue: %v", err)
	}
	restored.writeback = writeback
	t.Cleanup(func() { _ = restored.close() })

	time.Sleep(300 * time.Millisecond)
	afterMoves, _, afterDeletes := backend.counters()
	if afterMoves != moves || afterDeletes != deletes {
		t.Fatalf(
			"completed move repeated after restore: moves %d->%d deletes %d->%d",
			moves, afterMoves, deletes, afterDeletes,
		)
	}
	if !backend.has("new/report.txt") || backend.has("old/report.txt") {
		t.Fatal("restore disturbed converged remote state")
	}
}

// TestRenameFailureAppearsInMountStatus surfaces durable mutation errors
// through mountSession.status().
func TestRenameFailureAppearsInMountStatus(t *testing.T) {
	backend := newMutationMoveTestBackend()
	backend.files["old/report.txt"] = true
	backend.moveFails = 1000
	access := newMutationRecoveryAccess(t, backend)

	root := filepath.Join(access.sessionRoot, "sync-root")
	oldDir := filepath.Join(root, "old")
	if err := os.MkdirAll(oldDir, 0o755); err != nil {
		t.Fatalf("mkdir old: %v", err)
	}
	if err := access.enqueueRenamePath(
		"old",
		"new",
		oldDir,
		filepath.Join(root, "new"),
		true,
	); err != nil {
		t.Fatalf("enqueue rename: %v", err)
	}

	deadline := time.Now().Add(5 * time.Second)
	for time.Now().Before(deadline) {
		session := &mountSession{access: access}
		if status := session.status(); status.LastError != "" {
			if !strings.Contains(status.LastError, "injected move failure") {
				t.Fatalf("status error %q does not carry the provider failure", status.LastError)
			}
			return
		}
		time.Sleep(10 * time.Millisecond)
	}
	t.Fatal("durable mutation failure never surfaced in mount status")
}

func waitForMutationState(
	t *testing.T,
	access *bucketAccess,
	match func(mutationRecord) bool,
) {
	t.Helper()
	deadline := time.Now().Add(5 * time.Second)
	for time.Now().Before(deadline) {
		if records := access.writeback.pendingMutations(); len(records) > 0 {
			for _, record := range records {
				if match(record) {
					return
				}
			}
		}
		time.Sleep(10 * time.Millisecond)
	}
	t.Fatal("timed out waiting for persisted mutation state")
}

func waitForMutationCompletion(
	t *testing.T,
	access *bucketAccess,
	idPrefix string,
	timeout time.Duration,
) {
	t.Helper()
	deadline := time.Now().Add(timeout)
	for time.Now().Before(deadline) {
		if access.writeback.mutationLastError() == "" {
			records := access.writeback.pendingMutations()
			pending := false
			for _, record := range records {
				if strings.HasPrefix(record.ID, idPrefix) {
					pending = true
					break
				}
			}
			if !pending {
				return
			}
		}
		time.Sleep(10 * time.Millisecond)
	}
	t.Fatalf(
		"mutation %s* did not complete: pending=%+v lastError=%q",
		idPrefix,
		access.writeback.pendingMutations(),
		access.writeback.mutationLastError(),
	)
}
