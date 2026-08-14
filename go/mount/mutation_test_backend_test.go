// Mutation move test backend models independent source/destination state and partial failures.
package mount

import (
	"context"
	"errors"
	"os"
	"strings"
	"sync"

	storageops "remote-storage/go/storage"
)

// mutationMoveTestBackend models a strict provider: MoveObject fails when the
// source is absent, copy and hard-delete can fail independently, and the
// source/destination trees can be seeded or observed separately.
type mutationMoveTestBackend struct {
	mountTestBackend

	mu          sync.Mutex
	files       map[string]bool
	copyFails   int
	deleteFails int
	moveFails   int
	moveCalls   int
	copyCalls   int
	deleteCalls int
}

func newMutationMoveTestBackend() *mutationMoveTestBackend {
	return &mutationMoveTestBackend{files: map[string]bool{}}
}

func (b *mutationMoveTestBackend) HeadObject(
	_ context.Context,
	_ string,
	key string,
) (storageops.ObjectInfo, error) {
	clean := strings.Trim(key, "/")
	b.mu.Lock()
	defer b.mu.Unlock()
	if b.files[clean] {
		return storageops.ObjectInfo{Key: key}, nil
	}
	return storageops.ObjectInfo{}, os.ErrNotExist
}

func (b *mutationMoveTestBackend) ListObjectsPage(
	_ context.Context,
	_ string,
	prefix string,
	_ string,
	_ int32,
) (storageops.ObjectPage, error) {
	want := strings.Trim(prefix, "/")
	b.mu.Lock()
	defer b.mu.Unlock()
	items := []storageops.ObjectInfo{}
	for path := range b.files {
		if path == want || strings.HasPrefix(path, want+"/") {
			items = append(items, storageops.ObjectInfo{Key: path})
		}
	}
	return storageops.ObjectPage{Items: items}, nil
}

func (b *mutationMoveTestBackend) hasTree(clean string) bool {
	if b.files[clean] {
		return true
	}
	for path := range b.files {
		if strings.HasPrefix(path, clean+"/") {
			return true
		}
	}
	return false
}

func (b *mutationMoveTestBackend) MoveObject(
	_ context.Context,
	_ string,
	source,
	target string,
	_ bool,
	_ string,
) error {
	sourceClean := strings.Trim(source, "/")
	targetClean := strings.Trim(target, "/")
	b.mu.Lock()
	b.moveCalls++
	if b.moveFails > 0 {
		b.moveFails--
		b.mu.Unlock()
		return errors.New("injected move failure")
	}
	if !b.hasTree(sourceClean) {
		b.mu.Unlock()
		return os.ErrNotExist
	}
	updated := make(map[string]bool, len(b.files))
	for path := range b.files {
		switch {
		case path == sourceClean:
			updated[targetClean] = true
		case strings.HasPrefix(path, sourceClean+"/"):
			updated[targetClean+strings.TrimPrefix(path, sourceClean)] = true
		default:
			updated[path] = true
		}
	}
	b.files = updated
	b.mu.Unlock()
	return nil
}

func (b *mutationMoveTestBackend) CopyObject(
	_ context.Context,
	_ string,
	source,
	target string,
	_ bool,
	_ string,
) error {
	sourceClean := strings.Trim(source, "/")
	targetClean := strings.Trim(target, "/")
	b.mu.Lock()
	defer b.mu.Unlock()
	b.copyCalls++
	if b.copyFails > 0 {
		b.copyFails--
		return errors.New("injected copy failure")
	}
	if !b.files[sourceClean] {
		return os.ErrNotExist
	}
	for path := range b.files {
		if path == sourceClean || strings.HasPrefix(path, sourceClean+"/") {
			rebased := targetClean
			if path != sourceClean {
				rebased += strings.TrimPrefix(path, sourceClean)
			}
			b.files[rebased] = true
		}
	}
	return nil
}

func (b *mutationMoveTestBackend) DeleteObjectHard(
	_ context.Context,
	_ string,
	key string,
	_ bool,
	_ string,
) error {
	clean := strings.TrimSuffix(strings.Trim(key, "/"), "/")
	b.mu.Lock()
	defer b.mu.Unlock()
	b.deleteCalls++
	if b.deleteFails > 0 {
		b.deleteFails--
		return errors.New("injected delete failure")
	}
	for path := range b.files {
		if path == clean || strings.HasPrefix(path, clean+"/") {
			delete(b.files, path)
		}
	}
	return nil
}

func (b *mutationMoveTestBackend) has(path string) bool {
	b.mu.Lock()
	defer b.mu.Unlock()
	return b.files[strings.Trim(path, "/")]
}

func (b *mutationMoveTestBackend) counters() (int, int, int) {
	b.mu.Lock()
	defer b.mu.Unlock()
	return b.moveCalls, b.copyCalls, b.deleteCalls
}
