// Writeback queue tests verify canceling mount uploads clears local staged state.
package mount

import (
	"os"
	"path/filepath"
	"testing"
)

type syncStateCall struct {
	virtualPath string
	inSync      bool
}

type recordingSyncStateProjector struct {
	calls []syncStateCall
}

func (p *recordingSyncStateProjector) UpdateSyncState(virtualPath string, inSync bool) error {
	p.calls = append(p.calls, syncStateCall{
		virtualPath: cleanVirtualPath(virtualPath),
		inSync:      inSync,
	})
	return nil
}

func TestCancelQueuedTransferRemovesLocalCacheState(t *testing.T) {
	t.Parallel()

	access := newTestBucketAccess(t)
	virtualPath := "archive/output.zip"
	localPath := filepath.Join(access.cacheRoot, "archive", "output.zip")
	if err := os.MkdirAll(filepath.Dir(localPath), 0o755); err != nil {
		t.Fatalf("mkdir local path: %v", err)
	}
	if err := os.WriteFile(localPath, []byte("payload"), 0o644); err != nil {
		t.Fatalf("write staged file: %v", err)
	}
	access.registerLocalWrite(virtualPath, localPath, 7)
	access.writeback.enqueue(virtualPath, localPath, 7)

	var taskID string
	for _, entry := range access.writeback.entries {
		taskID = entry.taskID
	}
	if taskID == "" {
		t.Fatal("expected queued writeback task")
	}

	if ok := access.writeback.cancelTask(taskID); !ok {
		t.Fatal("expected queued task cancel to succeed")
	}
	if _, ok := access.cache.localFile(virtualPath); ok {
		t.Fatal("expected local file marker removal after cancel")
	}
	if _, err := os.Stat(localPath); !os.IsNotExist(err) {
		t.Fatalf("expected staged file removal, got %v", err)
	}
}

func TestCancelRunningTransferRemovesLocalCacheState(t *testing.T) {
	t.Parallel()

	access := newTestBucketAccess(t)
	virtualPath := "archive/output.zip"
	localPath := filepath.Join(access.cacheRoot, "archive", "output.zip")
	if err := os.MkdirAll(filepath.Dir(localPath), 0o755); err != nil {
		t.Fatalf("mkdir local path: %v", err)
	}
	if err := os.WriteFile(localPath, []byte("payload"), 0o644); err != nil {
		t.Fatalf("write staged file: %v", err)
	}
	access.registerLocalWrite(virtualPath, localPath, 7)
	access.writeback.running["task-running"] = &pendingWriteback{
		taskID:      "task-running",
		virtualPath: virtualPath,
		localPath:   localPath,
		size:        7,
	}

	if ok := access.writeback.cancelTask("task-running"); !ok {
		t.Fatal("expected running task cancel to succeed")
	}
	if _, ok := access.cache.localFile(virtualPath); ok {
		t.Fatal("expected local file marker removal after running cancel")
	}
	if _, err := os.Stat(localPath); !os.IsNotExist(err) {
		t.Fatalf("expected staged file removal, got %v", err)
	}
}

func TestEnqueueProjectsNotInSyncState(t *testing.T) {
	t.Parallel()

	access := newTestBucketAccess(t)
	projector := &recordingSyncStateProjector{}
	access.syncState = projector

	access.writeback.enqueue(
		"archive/output.zip",
		filepath.Join(access.cacheRoot, "archive", "output.zip"),
		7,
	)

	if len(projector.calls) != 1 {
		t.Fatalf("expected 1 sync-state call, got %d", len(projector.calls))
	}
	if projector.calls[0].virtualPath != "archive/output.zip" ||
		projector.calls[0].inSync {
		t.Fatalf("unexpected sync-state call: %+v", projector.calls[0])
	}
}

func TestRenameQueuedTransferProjectsNewPathNotInSync(t *testing.T) {
	t.Parallel()

	access := newTestBucketAccess(t)
	projector := &recordingSyncStateProjector{}
	access.syncState = projector

	access.writeback.enqueue(
		"archive/output.zip",
		filepath.Join(access.cacheRoot, "archive", "output.zip"),
		7,
	)
	projector.calls = nil

	if ok := access.writeback.rename("archive/output.zip", "archive/final.zip", false); !ok {
		t.Fatal("expected queued writeback rename to succeed")
	}
	if len(projector.calls) != 1 {
		t.Fatalf("expected 1 sync-state call after rename, got %d", len(projector.calls))
	}
	if projector.calls[0].virtualPath != "archive/final.zip" ||
		projector.calls[0].inSync {
		t.Fatalf("unexpected sync-state call after rename: %+v", projector.calls[0])
	}
}

func TestEnqueueSupersedesRunningTransferForSamePath(t *testing.T) {
	t.Parallel()

	access := newTestBucketAccess(t)
	localPath := filepath.Join(access.cacheRoot, "archive", "output.zip")
	access.writeback.running["task-running"] = &pendingWriteback{
		taskID:      "task-running",
		virtualPath: "archive/output.zip",
		localPath:   localPath,
		size:        7,
	}

	access.writeback.enqueue("archive/output.zip", localPath, 9)

	running := access.writeback.running["task-running"]
	if running == nil || !running.discard {
		t.Fatalf("expected running task to be marked discard, got %+v", running)
	}
	queued := access.writeback.entries["archive/output.zip"]
	if queued == nil {
		t.Fatal("expected replacement queued entry")
	}
	if queued.size != 9 {
		t.Fatalf("expected replacement size 9, got %d", queued.size)
	}
}

func TestWritebackQueueUsesConfiguredConcurrency(t *testing.T) {
	t.Parallel()

	access := newTestBucketAccess(t)
	_ = access.writeback.shutdown()
	access.config.WindowsWritebackConcurrency = 2
	access.writeback = newWritebackQueue(access)
	defer func() {
		_ = access.writeback.shutdown()
	}()

	if got := access.writeback.pool.Cap(); got != 2 {
		t.Fatalf("expected writeback pool capacity 2, got %d", got)
	}
}
