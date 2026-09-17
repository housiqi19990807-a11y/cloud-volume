//go:build windows && cgo

// Mutation queue tests protect callback throughput and shutdown durability.
package mount

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	"remote-storage/go/mount/metadata"
)

func TestWindowsWatcherMutationQueueAcceptsBulkWorkWithoutBlocking(t *testing.T) {
	queue := newWindowsWatcherMutationQueue()
	queue.start()

	started := make(chan struct{})
	release := make(chan struct{})
	var completed atomic.Int64
	if !queue.submit(func() {
		close(started)
		<-release
		completed.Add(1)
	}) {
		t.Fatal("expected first mutation to be accepted")
	}
	<-started

	deadline := time.After(500 * time.Millisecond)
	for index := 0; index < 2000; index++ {
		select {
		case <-deadline:
			t.Fatalf("bulk mutation submission blocked after %d entries", index)
		default:
		}
		if !queue.submit(func() { completed.Add(1) }) {
			t.Fatalf("mutation %d was rejected before shutdown", index)
		}
	}
	close(release)
	queue.stopAndDrain()
	if got := completed.Load(); got != 2001 {
		t.Fatalf("completed mutations = %d, want 2001", got)
	}
}

func TestWindowsWatcherQueuedWriteSurvivesImmediateRename(t *testing.T) {
	access := newTestBucketAccess(t)
	backend := newMetadataMountWriteBackend()
	_, handle := attachMetadataWriteService(t, access, backend)
	root := t.TempDir()
	oldPath := filepath.Join(root, "before.txt")
	newPath := filepath.Join(root, "after.txt")
	if err := os.WriteFile(oldPath, []byte("payload"), 0o644); err != nil {
		t.Fatalf("write source: %v", err)
	}
	watcher := newMutationTestWatcher(root, access)
	watcher.mutations = newWindowsWatcherMutationQueue()
	watcher.mutations.start()

	started := make(chan struct{})
	release := make(chan struct{})
	watcher.submitMutation(func() {
		close(started)
		<-release
	})
	<-started
	if !watcher.scheduleUpload(oldPath, "before.txt", false) {
		t.Fatal("expected source write to enter the mutation queue")
	}
	if err := os.Rename(oldPath, newPath); err != nil {
		t.Fatalf("rename open source: %v", err)
	}
	if !watcher.enqueueRenamePath("before.txt", "after.txt", oldPath, newPath, false, nil) {
		t.Fatal("expected rename to enter the mutation queue")
	}
	close(release)
	watcher.mutations.stopAndDrain()

	if _, err := handle.Service.StatPath(context.Background(), "before.txt"); err == nil {
		t.Fatal("queued rename retained the source metadata")
	}
	if _, err := handle.Service.StatPath(context.Background(), "after.txt"); err != nil {
		t.Fatalf("queued write handle did not survive rename: %v", err)
	}
}

func TestWindowsWatcherRealFilesystemDeleteReachesRemote(t *testing.T) {
	access := newTestBucketAccess(t)
	backend := newMetadataMountWriteBackend()
	manager, handle := attachMetadataWriteService(t, access, backend)
	root := t.TempDir()
	watcher, err := newWindowsSyncWatcher(root, access)
	if err != nil {
		t.Fatalf("new watcher: %v", err)
	}
	if err := watcher.Start(); err != nil {
		t.Fatalf("start watcher: %v", err)
	}
	defer watcher.Close()
	waitForWindowsWatch(t, watcher, root)

	localPath := filepath.Join(root, "real-delete.txt")
	if err := os.WriteFile(localPath, []byte("real fsnotify payload"), 0o644); err != nil {
		t.Fatalf("write local file: %v", err)
	}
	waitForMetadataPath(t, handle, "real-delete.txt", true)
	if err := manager.DrainAll(context.Background()); err != nil {
		t.Fatalf("drain upload: %v", err)
	}
	if err := os.Remove(localPath); err != nil {
		t.Fatalf("remove local file: %v", err)
	}
	waitForMetadataPath(t, handle, "real-delete.txt", false)
	if err := manager.DrainAll(context.Background()); err != nil {
		t.Fatalf("drain delete: %v", err)
	}
	backend.mu.Lock()
	_, exists := backend.objects["real-delete.txt"]
	backend.mu.Unlock()
	if exists {
		t.Fatal("real fsnotify removal left the remote object behind")
	}
}

func TestWindowsWatcherRealFilesystemBulkRenameConverges(t *testing.T) {
	access := newTestBucketAccess(t)
	backend := newMetadataMountWriteBackend()
	_, handle := attachMetadataWriteService(t, access, backend)
	root := t.TempDir()
	const fileCount = 128
	for index := 0; index < fileCount; index++ {
		name := fmt.Sprintf("before-%03d.txt", index)
		payload := strings.Repeat("x", index+1)
		if err := os.WriteFile(filepath.Join(root, name), []byte(payload), 0o644); err != nil {
			t.Fatalf("write %s: %v", name, err)
		}
	}
	watcher, err := newWindowsSyncWatcher(root, access)
	if err != nil {
		t.Fatalf("new watcher: %v", err)
	}
	if err := watcher.Start(); err != nil {
		t.Fatalf("start watcher: %v", err)
	}
	defer watcher.Close()
	if _, queued, err := watcher.ingestDirectoryTree(root); err != nil || queued != fileCount {
		t.Fatalf("seed watcher state: queued=%d err=%v", queued, err)
	}
	for index := 0; index < fileCount; index++ {
		waitForMetadataPath(t, handle, fmt.Sprintf("before-%03d.txt", index), true)
	}

	for index := 0; index < fileCount; index++ {
		oldName := fmt.Sprintf("before-%03d.txt", index)
		newName := fmt.Sprintf("after-%03d.txt", index)
		if err := os.Rename(filepath.Join(root, oldName), filepath.Join(root, newName)); err != nil {
			t.Fatalf("rename %s: %v", oldName, err)
		}
	}
	deadline := time.Now().Add(30 * time.Second)
	for index := 0; index < fileCount; index++ {
		oldName := fmt.Sprintf("before-%03d.txt", index)
		newName := fmt.Sprintf("after-%03d.txt", index)
		for {
			_, oldErr := handle.Service.StatPath(context.Background(), oldName)
			_, newErr := handle.Service.StatPath(context.Background(), newName)
			if oldErr != nil && newErr == nil {
				break
			}
			if time.Now().After(deadline) {
				t.Fatalf("bulk rename did not converge for %s -> %s: old=%v new=%v", oldName, newName, oldErr, newErr)
			}
			time.Sleep(10 * time.Millisecond)
		}
	}
}

func TestWindowsWatcherRemoveOfUploadedLocalFileJournalsRemoteDelete(t *testing.T) {
	access := newTestBucketAccess(t)
	backend := newMetadataMountWriteBackend()
	manager, handle := attachMetadataWriteService(t, access, backend)
	root := t.TempDir()
	localPath := filepath.Join(root, "uploaded.txt")
	if err := os.WriteFile(localPath, []byte("uploaded payload"), 0o644); err != nil {
		t.Fatalf("write local file: %v", err)
	}

	watcher := newMutationTestWatcher(root, access)
	watcher.handleCreate(localPath, "uploaded.txt")
	if err := manager.DrainAll(context.Background()); err != nil {
		t.Fatalf("drain initial upload: %v", err)
	}
	backend.mu.Lock()
	_, uploaded := backend.objects["uploaded.txt"]
	backend.mu.Unlock()
	if !uploaded {
		t.Fatal("expected local file to reach the remote backend before removal")
	}

	if err := os.Remove(localPath); err != nil {
		t.Fatalf("remove local file: %v", err)
	}
	// Normal files can receive only this fsnotify event: there is no CFAPI
	// delete completion callback to carry the durable deletion for us.
	watcher.handleRemovedSource(localPath, "uploaded.txt")
	if _, err := handle.Service.StatPath(context.Background(), "uploaded.txt"); err == nil {
		t.Fatal("removed file remained in the Desired metadata view")
	}
	if err := manager.DrainAll(context.Background()); err != nil {
		t.Fatalf("drain remote delete: %v", err)
	}
	backend.mu.Lock()
	_, uploaded = backend.objects["uploaded.txt"]
	backend.mu.Unlock()
	if uploaded {
		t.Fatal("expected watcher removal to delete the uploaded remote object")
	}
}

func TestWindowsWatcherRemoveLeavesPlaceholderDeleteToCFAPI(t *testing.T) {
	access := newTestBucketAccess(t)
	backend := newMetadataMountWriteBackend()
	_, handle := attachMetadataWriteService(t, access, backend)
	if _, _, err := handle.Service.WritePath(
		context.Background(), "projected.txt", strings.NewReader("remote"), 6,
		metadata.WriteOptions{Origin: "test"},
	); err != nil {
		t.Fatalf("seed projected metadata: %v", err)
	}
	root := t.TempDir()
	localPath := filepath.Join(root, "projected.txt")
	watcher := newMutationTestWatcher(root, access)
	watcher.state.kinds[localPath] = false
	watcher.state.markPlaceholder(localPath)

	watcher.handleRemovedSource(localPath, "projected.txt")
	if _, err := handle.Service.StatPath(context.Background(), "projected.txt"); err != nil {
		t.Fatalf("placeholder fsnotify event bypassed CFAPI ownership: %v", err)
	}
	if !watcher.state.isProjected(localPath) {
		t.Fatal("watcher-first removal discarded projection state needed by CFAPI")
	}
	if _, ok := watcher.state.kinds[localPath]; !ok {
		t.Fatal("watcher-first removal discarded the kind needed by CFAPI")
	}
}

func TestWindowsWatcherHydratedPlaceholderDeleteStaysWithCFAPI(t *testing.T) {
	access := newTestBucketAccess(t)
	backend := newMetadataMountWriteBackend()
	_, handle := attachMetadataWriteService(t, access, backend)
	if _, _, err := handle.Service.WritePath(
		context.Background(), "hydrated.txt", strings.NewReader("remote"), 6,
		metadata.WriteOptions{Origin: "test"},
	); err != nil {
		t.Fatalf("seed hydrated metadata: %v", err)
	}
	root := t.TempDir()
	localPath := filepath.Join(root, "hydrated.txt")
	if err := os.WriteFile(localPath, []byte("remote"), 0o644); err != nil {
		t.Fatalf("write hydrated file: %v", err)
	}
	watcher := newMutationTestWatcher(root, access)
	watcher.state.remember(localPath, false)
	watcher.state.markPlaceholder(localPath)
	watcher.state.markHydrated(localPath)

	if err := os.Remove(localPath); err != nil {
		t.Fatalf("remove hydrated placeholder: %v", err)
	}
	watcher.handleRemovedSource(localPath, "hydrated.txt")
	if _, err := handle.Service.StatPath(context.Background(), "hydrated.txt"); err != nil {
		t.Fatalf("hydrated placeholder bypassed CFAPI ownership: %v", err)
	}
}

func TestWindowsDeleteCompletionSuppressesTrailingWatcherRemove(t *testing.T) {
	access := newTestBucketAccess(t)
	backend := newMetadataMountWriteBackend()
	_, handle := attachMetadataWriteService(t, access, backend)
	if _, _, err := handle.Service.WritePath(
		context.Background(), "projected.txt", strings.NewReader("remote"), 6,
		metadata.WriteOptions{Origin: "test"},
	); err != nil {
		t.Fatalf("seed projected metadata: %v", err)
	}
	root := t.TempDir()
	localPath := filepath.Join(root, "projected.txt")
	watcher := newMutationTestWatcher(root, access)
	watcher.state.remember(localPath, false)
	watcher.state.markPlaceholder(localPath)
	session := &mountSession{mountPath: root, access: access}

	(&windowsCloudFilesBackend{}).handleDelete(session, watcher)(localPath)
	if !watcher.state.shouldIgnore(localPath) {
		t.Fatal("delete completion did not suppress the trailing watcher event")
	}
	if _, err := handle.Service.StatPath(context.Background(), "projected.txt"); err == nil {
		t.Fatal("delete completion did not remove projected metadata")
	}
}

func TestWindowsRenameDedupeUsesIndependentLongTTL(t *testing.T) {
	state := &windowsPathState{completedRenames: map[string]time.Time{}}
	oldPath := filepath.Join(`C:\sync-root`, "before.txt")
	newPath := filepath.Join(`C:\sync-root`, "after.txt")
	before := time.Now()
	state.markFallbackRenameHandled(oldPath, newPath)

	until := state.completedRenames[windowsRenamePairKey(oldPath, newPath)]
	if until.Sub(before) < 30*time.Second {
		t.Fatalf("rename dedupe TTL = %s, want at least 30 seconds", until.Sub(before))
	}
}

func TestWindowsLateRenameCompletionRunsAfterQueuedWatcherFailure(t *testing.T) {
	access := newTestBucketAccess(t)
	backend := newMetadataMountWriteBackend()
	_, handle := attachMetadataWriteService(t, access, backend)
	if _, _, err := handle.Service.WritePath(
		context.Background(), "before.txt", strings.NewReader("payload"), 7,
		metadata.WriteOptions{Origin: "test"},
	); err != nil {
		t.Fatalf("seed rename source: %v", err)
	}
	root := t.TempDir()
	oldPath := filepath.Join(root, "before.txt")
	newPath := filepath.Join(root, "after.txt")
	watcher := newMutationTestWatcher(root, access)
	watcher.mutations = newWindowsWatcherMutationQueue()
	watcher.mutations.start()
	watcher.state.remember(oldPath, false)
	watcher.state.markFallbackRenameHandled(oldPath, newPath)

	// Simulate the already-admitted watcher job failing before the queued
	// completion fallback reaches the FIFO worker.
	watcher.submitMutation(func() {
		watcher.state.clearFallbackRenameHandled(oldPath, newPath)
	})
	if !watcher.enqueueRenameFallbackIfNeeded(
		"before.txt", "after.txt", oldPath, newPath, false, nil,
	) {
		t.Fatal("late completion fallback was not queued")
	}
	watcher.mutations.stopAndDrain()
	if _, err := handle.Service.StatPath(context.Background(), "before.txt"); err == nil {
		t.Fatal("late completion fallback retained the source metadata")
	}
	if _, err := handle.Service.StatPath(context.Background(), "after.txt"); err != nil {
		t.Fatalf("late completion fallback did not rename metadata: %v", err)
	}
}

func TestWindowsWatcherRenameAdmissionFailureFallsBackToWrite(t *testing.T) {
	access := newTestBucketAccess(t)
	backend := newMetadataMountWriteBackend()
	manager, handle := attachMetadataWriteService(t, access, backend)
	root := t.TempDir()
	oldPath := filepath.Join(root, "before.txt")
	newPath := filepath.Join(root, "after.txt")
	if err := os.WriteFile(oldPath, []byte("watcher fallback"), 0o644); err != nil {
		t.Fatalf("write rename source: %v", err)
	}
	info, err := os.Stat(oldPath)
	if err != nil {
		t.Fatalf("stat rename source: %v", err)
	}
	watcher := newMutationTestWatcher(root, access)
	watcher.mutations = newWindowsWatcherMutationQueue()
	watcher.mutations.start()
	watcher.state.remember(oldPath, false)
	watcher.state.files[oldPath] = windowsObservedFile{
		size: info.Size(), modTime: info.ModTime().UnixNano(),
	}
	if !watcher.state.beginPendingFileRename(oldPath) {
		t.Fatal("rename source did not enter pending state")
	}
	if err := os.Rename(oldPath, newPath); err != nil {
		t.Fatalf("rename local source: %v", err)
	}
	newInfo, err := os.Stat(newPath)
	if err != nil {
		t.Fatalf("stat rename target: %v", err)
	}

	// No source exists in metadata, so rename admission must fail and the
	// watcher-only path must preserve the physical target as a write.
	if !watcher.completePendingFileRename(newPath, "after.txt", newInfo) {
		t.Fatal("watcher did not consume the physical rename pair")
	}
	watcher.mutations.stopAndDrain()
	if _, err := handle.Service.StatPath(context.Background(), "after.txt"); err != nil {
		t.Fatalf("watcher fallback did not write target metadata: %v", err)
	}
	if err := manager.DrainAll(context.Background()); err != nil {
		t.Fatalf("drain watcher fallback: %v", err)
	}
	backend.mu.Lock()
	_, uploaded := backend.objects["after.txt"]
	backend.mu.Unlock()
	if !uploaded {
		t.Fatal("watcher fallback did not upload the physical target")
	}
}

func TestWindowsCallbackRenameAdmissionFailureFallsBackToWrite(t *testing.T) {
	access := newTestBucketAccess(t)
	backend := newMetadataMountWriteBackend()
	manager, handle := attachMetadataWriteService(t, access, backend)
	root := t.TempDir()
	oldPath := filepath.Join(root, "before.txt")
	newPath := filepath.Join(root, "after.txt")
	if err := os.WriteFile(newPath, []byte("callback fallback"), 0o644); err != nil {
		t.Fatalf("write callback target: %v", err)
	}
	watcher := newMutationTestWatcher(root, access)
	watcher.mutations = newWindowsWatcherMutationQueue()
	watcher.mutations.start()
	session := &mountSession{mountPath: root, access: access}

	// As above, the absent metadata source forces the callback-first admission
	// to recover from the already-moved target instead of losing the mutation.
	(&windowsCloudFilesBackend{}).handleRename(session, watcher)(oldPath, newPath)
	watcher.mutations.stopAndDrain()
	if _, err := handle.Service.StatPath(context.Background(), "after.txt"); err != nil {
		t.Fatalf("callback fallback did not write target metadata: %v", err)
	}
	if err := manager.DrainAll(context.Background()); err != nil {
		t.Fatalf("drain callback fallback: %v", err)
	}
	backend.mu.Lock()
	_, uploaded := backend.objects["after.txt"]
	backend.mu.Unlock()
	if !uploaded {
		t.Fatal("callback fallback did not upload the physical target")
	}
}

func newMutationTestWatcher(root string, access *bucketAccess) *windowsSyncWatcher {
	return &windowsSyncWatcher{
		root:   root,
		access: access,
		state: &windowsPathState{
			ignored:      map[string]windowsIgnoredPath{},
			hydrating:    map[string]bool{},
			kinds:        map[string]bool{},
			files:        map[string]windowsObservedFile{},
			placeholders: map[string]bool{},
			projected:    map[string]bool{},
		},
	}
}

func waitForMetadataPath(t *testing.T, handle *metadata.AcquireHandle, path string, want bool) {
	t.Helper()
	deadline := time.Now().Add(10 * time.Second)
	for time.Now().Before(deadline) {
		_, err := handle.Service.StatPath(context.Background(), path)
		if (err == nil) == want {
			return
		}
		time.Sleep(10 * time.Millisecond)
	}
	t.Fatalf("metadata path %q presence did not become %t", path, want)
}
