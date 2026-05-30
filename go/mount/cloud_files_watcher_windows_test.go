//go:build windows && cgo

// Windows Cloud Files watcher tests pin placeholder ignore behavior for nested writes.
package mount

import (
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/fsnotify/fsnotify"
)

func TestWindowsPathStatePlaceholderIgnoreDoesNotHideChildren(t *testing.T) {
	t.Parallel()

	state := &windowsPathState{
		ignored:   map[string]windowsIgnoredPath{},
		hydrating: map[string]bool{},
		kinds:     map[string]bool{},
		files:     map[string]windowsObservedFile{},
	}

	placeholderDir := filepath.Join(`C:\sync-root`, `docs`)
	childFile := filepath.Join(placeholderDir, `draft.txt`)
	state.ignore(placeholderDir, time.Minute, false)

	if !state.shouldIgnore(placeholderDir) {
		t.Fatal("expected placeholder directory event to be ignored")
	}
	if state.shouldIgnore(childFile) {
		t.Fatal("expected child writes below placeholder directory to stay visible")
	}
}

func TestWindowsPathStateHydratingStillHidesChildren(t *testing.T) {
	t.Parallel()

	state := &windowsPathState{
		ignored:   map[string]windowsIgnoredPath{},
		hydrating: map[string]bool{},
		kinds:     map[string]bool{},
		files:     map[string]windowsObservedFile{},
	}

	hydratingDir := filepath.Join(`C:\sync-root`, `docs`)
	childFile := filepath.Join(hydratingDir, `draft.txt`)
	state.markHydrating(hydratingDir)

	if !state.shouldIgnore(childFile) {
		t.Fatal("expected hydrating subtree events to be ignored")
	}
}

func TestIngestDirectoryTreeQueuesExistingNestedFiles(t *testing.T) {
	t.Parallel()

	access := newTestBucketAccess(t)
	root := t.TempDir()
	dirPath := filepath.Join(root, "parent", "nested")
	filePath := filepath.Join(dirPath, "draft.txt")
	if err := os.MkdirAll(dirPath, 0o755); err != nil {
		t.Fatalf("mkdir tree: %v", err)
	}
	if err := os.WriteFile(filePath, []byte("payload"), 0o644); err != nil {
		t.Fatalf("write nested file: %v", err)
	}

	rawWatcher, err := fsnotify.NewWatcher()
	if err != nil {
		t.Fatalf("new watcher: %v", err)
	}
	defer rawWatcher.Close()

	watcher := &windowsSyncWatcher{
		root:   root,
		access: access,
		raw:    rawWatcher,
		state: &windowsPathState{
			ignored:   map[string]windowsIgnoredPath{},
			hydrating: map[string]bool{},
			kinds:     map[string]bool{},
			files:     map[string]windowsObservedFile{},
		},
		done: make(chan struct{}),
	}

	if _, _, err := watcher.ingestDirectoryTree(filepath.Join(root, "parent")); err != nil {
		t.Fatalf("ingest directory tree: %v", err)
	}

	if _, ok := access.cache.cachedObject("parent/nested"); !ok {
		t.Fatal("expected nested directory to be staged locally")
	}
	if _, ok := access.cache.localFile("parent/nested/draft.txt"); !ok {
		t.Fatal("expected nested file to be registered for local-first upload")
	}
	if !access.writeback.hasPendingAtOrBelow("parent", true) {
		t.Fatal("expected delayed writeback entry for nested file")
	}
}

func TestDirectoryWriteTriggersHarvest(t *testing.T) {
	t.Parallel()

	access := newTestBucketAccess(t)
	root := t.TempDir()
	parentDir := filepath.Join(root, "parent")
	nestedDir := filepath.Join(parentDir, "nested")
	nestedFile := filepath.Join(nestedDir, "draft.txt")
	if err := os.MkdirAll(nestedDir, 0o755); err != nil {
		t.Fatalf("mkdir tree: %v", err)
	}
	if err := os.WriteFile(nestedFile, []byte("payload"), 0o644); err != nil {
		t.Fatalf("write nested file: %v", err)
	}

	rawWatcher, err := fsnotify.NewWatcher()
	if err != nil {
		t.Fatalf("new watcher: %v", err)
	}
	defer rawWatcher.Close()

	watcher := &windowsSyncWatcher{
		root:   root,
		access: access,
		raw:    rawWatcher,
		state: &windowsPathState{
			ignored:   map[string]windowsIgnoredPath{},
			hydrating: map[string]bool{},
			kinds:     map[string]bool{},
			files:     map[string]windowsObservedFile{},
		},
		done:           make(chan struct{}),
		activeHarvests: map[string]bool{},
	}

	watcher.handleWrite(parentDir, "parent")

	deadline := time.Now().Add(3 * time.Second)
	for time.Now().Before(deadline) {
		if _, ok := access.cache.localFile("parent/nested/draft.txt"); ok &&
			access.writeback.hasPendingAtOrBelow("parent", true) {
			return
		}
		time.Sleep(50 * time.Millisecond)
	}

	t.Fatal("expected directory write to trigger recursive harvest and queue nested file")
}
