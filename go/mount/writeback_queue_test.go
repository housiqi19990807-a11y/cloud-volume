// Writeback queue tests verify canceling mount uploads clears local staged state.
package mount

import (
	"os"
	"path/filepath"
	"testing"
)

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
