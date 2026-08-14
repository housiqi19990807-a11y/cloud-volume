// Directory sync test support models strict directory markers and observable queue ordering.
package mount

import (
	"context"
	"errors"
	"os"
	"strings"
	"sync"
	"testing"
	"time"

	storageops "remote-storage/go/storage"
)

type directorySyncTestBackend struct {
	mountTestBackend

	mu             sync.Mutex
	events         []string
	directories    map[string]bool
	createStarted  chan string
	renameStarted  chan struct{}
	releaseCreate  chan struct{}
	blockedPaths   map[string]chan struct{}
	createFailures map[string]int
	blockCreate    bool
	renameOnce     sync.Once
}

func newDirectorySyncTestBackend() *directorySyncTestBackend {
	return &directorySyncTestBackend{
		directories:    make(map[string]bool),
		createStarted:  make(chan string, 1024),
		renameStarted:  make(chan struct{}),
		releaseCreate:  make(chan struct{}),
		blockedPaths:   make(map[string]chan struct{}),
		createFailures: make(map[string]int),
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
	shouldFail := b.createFailures[path] > 0
	if shouldFail {
		b.createFailures[path]--
	}
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
	if shouldFail {
		return errors.New("injected directory create failure")
	}
	b.mu.Lock()
	b.directories[path] = true
	b.events = append(b.events, "create-finished:"+path)
	b.mu.Unlock()
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
	b.mu.Lock()
	b.events = append(b.events, "rename:"+oldClean+":"+newClean)
	sourceExists := b.directories[oldClean]
	if !sourceExists {
		for path := range b.directories {
			if strings.HasPrefix(path, oldClean+"/") {
				sourceExists = true
				break
			}
		}
	}
	if !sourceExists {
		b.mu.Unlock()
		b.renameOnce.Do(func() { close(b.renameStarted) })
		return os.ErrNotExist
	}
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
	b.mu.Unlock()
	b.renameOnce.Do(func() { close(b.renameStarted) })
	return nil
}

func (b *directorySyncTestBackend) HeadObject(
	_ context.Context,
	_ string,
	key string,
) (storageops.ObjectInfo, error) {
	path := strings.Trim(key, "/")
	b.mu.Lock()
	defer b.mu.Unlock()
	if b.directories[path] {
		return storageops.ObjectInfo{Key: key, IsDir: true}, nil
	}
	return storageops.ObjectInfo{}, os.ErrNotExist
}

func (b *directorySyncTestBackend) ListObjectsPage(
	_ context.Context,
	_ string,
	prefix string,
	_ string,
	_ int32,
) (storageops.ObjectPage, error) {
	want := strings.Trim(prefix, "/")
	b.mu.Lock()
	defer b.mu.Unlock()
	for path := range b.directories {
		if path == want || strings.HasPrefix(path, want+"/") {
			return storageops.ObjectPage{
				Items: []storageops.ObjectInfo{{Key: path, IsDir: true}},
			}, nil
		}
	}
	return storageops.ObjectPage{}, nil
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

func (b *directorySyncTestBackend) eventCount(event string) int {
	b.mu.Lock()
	defer b.mu.Unlock()
	count := 0
	for _, candidate := range b.events {
		if candidate == event {
			count++
		}
	}
	return count
}

func newDirectorySyncTestAccess(t *testing.T, backend *directorySyncTestBackend) *bucketAccess {
	t.Helper()
	access := newTestBucketAccess(t)
	access.backend = backend
	access.dirSync = newDirSyncQueue(access)
	t.Cleanup(func() { access.dirSync.shutdown() })
	return access
}

func releaseDirectoryTestBlock(release chan struct{}) {
	select {
	case <-release:
	default:
		close(release)
	}
}

func cleanupDirectoryTestBlock(t *testing.T, release chan struct{}) {
	t.Helper()
	t.Cleanup(func() { releaseDirectoryTestBlock(release) })
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

func assertDirectoryEventBefore(t *testing.T, events []string, first, second string) {
	t.Helper()
	firstIndex := -1
	secondIndex := -1
	for index, event := range events {
		if event == first && firstIndex < 0 {
			firstIndex = index
		}
		if event == second && secondIndex < 0 {
			secondIndex = index
		}
	}
	if firstIndex < 0 || secondIndex < 0 || firstIndex >= secondIndex {
		t.Fatalf("expected %q before %q: %v", first, second, events)
	}
}
