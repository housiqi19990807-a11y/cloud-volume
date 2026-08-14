// Writeback rename tests pin upload-barrier ordering and renamed local source resolution.
package mount

import (
	"context"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"
)

type orderedRenameTestBackend struct {
	mountTestBackend

	mu                 sync.Mutex
	events             []string
	firstUploadStarted chan struct{}
	releaseFirstUpload chan struct{}
	startOnce          sync.Once
	releaseOnce        sync.Once
}

func newOrderedRenameTestBackend() *orderedRenameTestBackend {
	return &orderedRenameTestBackend{
		firstUploadStarted: make(chan struct{}),
		releaseFirstUpload: make(chan struct{}),
	}
}

func (b *orderedRenameTestBackend) UploadFile(
	ctx context.Context,
	_,
	remotePath,
	localPath,
	_ string,
) error {
	b.record("upload:" + remotePath + ":" + filepath.Clean(localPath))
	if strings.HasSuffix(remotePath, "old/before.txt") {
		b.startOnce.Do(func() { close(b.firstUploadStarted) })
		select {
		case <-b.releaseFirstUpload:
		case <-ctx.Done():
			return ctx.Err()
		}
	}
	return nil
}

func (b *orderedRenameTestBackend) MoveObject(
	_ context.Context,
	_,
	oldPath,
	newPath string,
	_ bool,
	_ string,
) error {
	b.record("rename:" + oldPath + ":" + newPath)
	return nil
}

func (b *orderedRenameTestBackend) record(event string) {
	b.mu.Lock()
	b.events = append(b.events, event)
	b.mu.Unlock()
}

func (b *orderedRenameTestBackend) snapshot() []string {
	b.mu.Lock()
	defer b.mu.Unlock()
	return append([]string(nil), b.events...)
}

func (b *orderedRenameTestBackend) releaseUpload() {
	b.releaseOnce.Do(func() { close(b.releaseFirstUpload) })
}

func TestQueuedRenameOrdersUploadsAcrossDirectoryBarrier(t *testing.T) {
	access := newTestBucketAccess(t)
	backend := newOrderedRenameTestBackend()
	t.Cleanup(backend.releaseUpload)
	access.backend = backend
	access.writeback.mu.Lock()
	access.writeback.quiet = time.Hour
	access.writeback.mu.Unlock()

	root := filepath.Join(access.sessionRoot, "sync-root")
	oldDir := filepath.Join(root, "old")
	newDir := filepath.Join(root, "new")
	beforeOld := filepath.Join(oldDir, "before.txt")
	if err := os.MkdirAll(oldDir, 0o755); err != nil {
		t.Fatalf("mkdir old directory: %v", err)
	}
	if err := os.WriteFile(beforeOld, []byte("before"), 0o644); err != nil {
		t.Fatalf("write before file: %v", err)
	}
	access.writeback.enqueue("old/before.txt", beforeOld, 6)
	if err := os.Rename(oldDir, newDir); err != nil {
		t.Fatalf("rename local directory: %v", err)
	}

	if err := access.enqueueRenamePath(
		"old",
		"new",
		oldDir,
		newDir,
		true,
	); err != nil {
		t.Fatalf("enqueue directory rename: %v", err)
	}

	afterPath := filepath.Join(newDir, "after.txt")
	if err := os.WriteFile(afterPath, []byte("after"), 0o644); err != nil {
		t.Fatalf("write after file: %v", err)
	}
	access.writeback.enqueue("new/after.txt", afterPath, 5)
	access.writeback.mu.Lock()
	afterTaskID := access.writeback.entries["new/after.txt"].taskID
	access.writeback.mu.Unlock()
	if !access.writeback.triggerTask(afterTaskID) {
		t.Fatal("expected later upload task to be triggerable")
	}

	select {
	case <-backend.firstUploadStarted:
	case <-time.After(3 * time.Second):
		t.Fatal("prior upload did not start")
	}
	events := backend.snapshot()
	if len(events) != 1 || !strings.HasPrefix(events[0], "upload:old/before.txt:") {
		t.Fatalf("rename or later upload crossed the barrier: %v", events)
	}
	if !strings.HasSuffix(events[0], filepath.Clean(filepath.Join(newDir, "before.txt"))) {
		t.Fatalf("prior upload did not follow the renamed local source: %v", events)
	}

	backend.releaseUpload()
	waitForOrderedRenameEvents(t, backend, 3)
	events = backend.snapshot()
	wantRename := "rename:" + ensureDirSuffix("old") + ":" + ensureDirSuffix("new")
	if events[1] != wantRename ||
		!strings.HasPrefix(events[2], "upload:new/after.txt:") {
		t.Fatalf("unexpected mutation order: %v", events)
	}
}

func waitForOrderedRenameEvents(
	t *testing.T,
	backend *orderedRenameTestBackend,
	want int,
) {
	t.Helper()
	deadline := time.Now().Add(3 * time.Second)
	for time.Now().Before(deadline) {
		if len(backend.snapshot()) >= want {
			return
		}
		time.Sleep(10 * time.Millisecond)
	}
	t.Fatalf("timed out waiting for %d events: %v", want, backend.snapshot())
}
