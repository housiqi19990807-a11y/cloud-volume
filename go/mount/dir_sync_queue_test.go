// Directory sync tests verify that queued marker creates follow local directory renames.
package mount

import (
	"context"
	"runtime"
	"strings"
	"sync"
	"testing"
	"time"
)

type directorySyncTestBackend struct {
	mountTestBackend

	mu            sync.Mutex
	events        []string
	directories   map[string]bool
	createStarted chan string
	renameStarted chan struct{}
	releaseCreate chan struct{}
	blockedPaths  map[string]chan struct{}
	blockCreate   bool
	renameOnce    sync.Once
}

func newDirectorySyncTestBackend() *directorySyncTestBackend {
	return &directorySyncTestBackend{
		directories:   make(map[string]bool),
		createStarted: make(chan string, 1024),
		renameStarted: make(chan struct{}),
		releaseCreate: make(chan struct{}),
		blockedPaths:  make(map[string]chan struct{}),
	}
}

func (b *directorySyncTestBackend) CreateDirectory(
	ctx context.Context,
	_ string,
	prefix string,
	name string,
) error {
	path := strings.Trim(prefix, "/")
	if path != "" {
		path += "/"
	}
	path += strings.Trim(name, "/")
	b.mu.Lock()
	b.events = append(b.events, "create:"+path)
	b.directories[path] = true
	pathBlock := b.blockedPaths[path]
	b.mu.Unlock()
	select {
	case b.createStarted <- path:
	default:
	}
	if pathBlock != nil {
		select {
		case <-pathBlock:
		case <-ctx.Done():
			return ctx.Err()
		}
	} else if b.blockCreate {
		select {
		case <-b.releaseCreate:
		case <-ctx.Done():
			return ctx.Err()
		}
	}
	return nil
}

func (b *directorySyncTestBackend) blockPath(path string) chan struct{} {
	b.mu.Lock()
	defer b.mu.Unlock()
	release := make(chan struct{})
	b.blockedPaths[cleanVirtualPath(path)] = release
	return release
}

func (b *directorySyncTestBackend) MoveObject(
	_ context.Context,
	_ string,
	oldPath string,
	newPath string,
	_ bool,
	_ string,
) error {
	oldClean := strings.Trim(oldPath, "/")
	newClean := strings.Trim(newPath, "/")
	b.renameOnce.Do(func() { close(b.renameStarted) })
	b.mu.Lock()
	defer b.mu.Unlock()
	b.events = append(b.events, "rename:"+oldClean+":"+newClean)
	updated := make(map[string]bool, len(b.directories))
	for path := range b.directories {
		switch {
		case path == oldClean:
			updated[newClean] = true
		case strings.HasPrefix(path, oldClean+"/"):
			updated[newClean+strings.TrimPrefix(path, oldClean)] = true
		default:
			updated[path] = true
		}
	}
	b.directories = updated
	return nil
}

func (b *directorySyncTestBackend) eventsSnapshot() []string {
	b.mu.Lock()
	defer b.mu.Unlock()
	return append([]string(nil), b.events...)
}

func (b *directorySyncTestBackend) hasDirectory(path string) bool {
	b.mu.Lock()
	defer b.mu.Unlock()
	return b.directories[cleanVirtualPath(path)]
}

func (b *directorySyncTestBackend) hasEventPrefix(prefix string) bool {
	b.mu.Lock()
	defer b.mu.Unlock()
	for _, event := range b.events {
		if strings.HasPrefix(event, prefix) {
			return true
		}
	}
	return false
}

func newDirectorySyncTestAccess(t *testing.T, backend *directorySyncTestBackend) *bucketAccess {
	t.Helper()
	access := newTestBucketAccess(t)
	access.backend = backend
	access.dirSync = newDirSyncQueue(access)
	t.Cleanup(func() { access.dirSync.shutdown() })
	return access
}

func waitForDirectorySync(t *testing.T, check func() bool) {
	t.Helper()
	deadline := time.Now().Add(3 * time.Second)
	for time.Now().Before(deadline) {
		if check() {
			return
		}
		time.Sleep(10 * time.Millisecond)
	}
	t.Fatal("timed out waiting for directory sync")
}

func waitForDirectoryCreateStarts(
	t *testing.T,
	backend *directorySyncTestBackend,
	want int,
) {
	t.Helper()
	deadline := time.After(3 * time.Second)
	for started := 0; started < want; started++ {
		select {
		case <-backend.createStarted:
		case <-deadline:
			t.Fatalf("only %d of %d directory creates started", started, want)
		}
	}
}

func waitForDirectoryEntryRunning(t *testing.T, q *dirSyncQueue, path string) {
	t.Helper()
	want := cleanVirtualPath(path)
	waitForDirectorySync(t, func() bool {
		q.mu.Lock()
		defer q.mu.Unlock()
		entry := q.entries[want]
		return entry != nil && entry.running
	})
}

func TestDirectoryCreateIsRebasedBeforeRename(t *testing.T) {
	backend := newDirectorySyncTestBackend()
	backend.blockCreate = true
	access := newDirectorySyncTestAccess(t, backend)

	access.dirSync.enqueue("worker-one")
	access.dirSync.enqueue("worker-two")
	waitForDirectoryCreateStarts(t, backend, 2)
	access.dirSync.enqueue("dispatcher-wait")
	waitForDirectoryEntryRunning(t, access.dirSync, "dispatcher-wait")
	access.dirSync.enqueue("New Folder")
	if err := access.enqueueRenamePath(
		"New Folder", "Reports", "", "", true, nil,
	); err != nil {
		t.Fatalf("enqueue rename: %v", err)
	}
	close(backend.releaseCreate)

	waitForDirectorySync(t, func() bool {
		return backend.hasDirectory("Reports") && backend.hasEventPrefix("rename:New Folder:Reports")
	})
	if backend.hasDirectory("New Folder") {
		t.Fatalf("old directory marker remains: %v", backend.eventsSnapshot())
	}
	if len(backend.eventsSnapshot()) == 0 {
		t.Fatal("expected remote directory mutation events")
	}
	if backend.hasEventPrefix("create:New Folder") {
		t.Fatalf("queued create used the old path: %v", backend.eventsSnapshot())
	}
}

func TestNestedDirectoryCreatesRebaseAsOneTree(t *testing.T) {
	backend := newDirectorySyncTestBackend()
	backend.blockCreate = true
	access := newDirectorySyncTestAccess(t, backend)

	access.dirSync.enqueue("worker-one")
	access.dirSync.enqueue("worker-two")
	waitForDirectoryCreateStarts(t, backend, 2)
	access.dirSync.enqueue("dispatcher-wait")
	waitForDirectoryEntryRunning(t, access.dirSync, "dispatcher-wait")
	access.dirSync.enqueue("New Folder")
	access.dirSync.enqueue("New Folder/sub")
	if err := access.enqueueRenamePath(
		"New Folder", "Reports", "", "", true, nil,
	); err != nil {
		t.Fatalf("enqueue rename: %v", err)
	}
	close(backend.releaseCreate)

	deadline := time.Now().Add(3 * time.Second)
	for time.Now().Before(deadline) && !(backend.hasDirectory("Reports") &&
		backend.hasDirectory("Reports/sub") && backend.hasEventPrefix("rename:New Folder:Reports")) {
		time.Sleep(10 * time.Millisecond)
	}
	if !backend.hasDirectory("Reports") || !backend.hasDirectory("Reports/sub") ||
		!backend.hasEventPrefix("rename:New Folder:Reports") {
		t.Fatalf("timed out waiting for directory sync: %v", backend.eventsSnapshot())
	}
	if backend.hasDirectory("New Folder") || backend.hasDirectory("New Folder/sub") {
		t.Fatalf("old directory tree remains: %v", backend.eventsSnapshot())
	}
	if backend.hasEventPrefix("create:New Folder") {
		t.Fatalf("queued tree used an old path: %v", backend.eventsSnapshot())
	}
}

func TestDirectoryQueueBackpressureDoesNotBlockRebase(t *testing.T) {
	queue := &dirSyncQueue{
		entries: make(map[string]*dirSyncEntry),
		queue:   make(chan *dirSyncEntry),
	}
	enqueueDone := make(chan struct{})
	go func() {
		queue.enqueue("overflow")
		close(enqueueDone)
	}()

	lockAvailable := false
	deadline := time.Now().Add(250 * time.Millisecond)
	for time.Now().Before(deadline) {
		if queue.mu.TryLock() {
			entryQueued := queue.entries["overflow"] != nil
			queue.mu.Unlock()
			if entryQueued {
				lockAvailable = true
				break
			}
		}
		runtime.Gosched()
	}
	go func() { <-queue.queue }()
	<-enqueueDone
	if !lockAvailable {
		t.Fatal("directory queue held its mutex while backpressured")
	}
}

func TestRunningDirectoryCollisionWaitsForExistingTarget(t *testing.T) {
	backend := newDirectorySyncTestBackend()
	releaseOld := backend.blockPath("New Folder/sub")
	releaseTarget := backend.blockPath("Reports/sub")
	access := newDirectorySyncTestAccess(t, backend)

	access.dirSync.enqueue("New Folder/sub")
	access.dirSync.enqueue("Reports/sub")
	waitForDirectoryCreateStarts(t, backend, 2)
	if err := access.enqueueRenamePath(
		"New Folder", "Reports", "", "", true, nil,
	); err != nil {
		t.Fatalf("enqueue rename: %v", err)
	}

	close(releaseOld)
	select {
	case <-backend.renameStarted:
		close(releaseTarget)
		t.Fatal("rename started before the existing target create finished")
	case <-time.After(100 * time.Millisecond):
	}
	close(releaseTarget)
	select {
	case <-backend.renameStarted:
	case <-time.After(3 * time.Second):
		t.Fatal("rename did not start after both directory creates finished")
	}
}

func TestRunningDirectoryCreateFinishesBeforeRename(t *testing.T) {
	backend := newDirectorySyncTestBackend()
	backend.blockCreate = true
	access := newDirectorySyncTestAccess(t, backend)

	access.dirSync.enqueue("New Folder")
	select {
	case <-backend.createStarted:
	case <-time.After(3 * time.Second):
		t.Fatal("directory create did not start")
	}
	if err := access.enqueueRenamePath(
		"New Folder", "Reports", "", "", true, nil,
	); err != nil {
		t.Fatalf("enqueue rename: %v", err)
	}

	select {
	case <-backend.renameStarted:
		t.Fatalf("rename started while directory create was blocked: %v", backend.eventsSnapshot())
	case <-time.After(100 * time.Millisecond):
	}
	close(backend.releaseCreate)
	waitForDirectorySync(t, func() bool { return backend.hasDirectory("Reports") })
	if !backend.hasDirectory("Reports") || backend.hasDirectory("New Folder") {
		t.Fatalf("unexpected final remote state: %v", backend.eventsSnapshot())
	}
}
