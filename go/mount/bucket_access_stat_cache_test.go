// Stat cache tests keep Finder destination probes on the local-first path.
package mount

import (
	"context"
	"os"
	"sync/atomic"
	"testing"
	"time"

	storageops "remote-storage/go/storage"
)

type countingHeadBackend struct {
	storageops.Backend
	headCalls atomic.Int32
}

func (b *countingHeadBackend) HeadObject(
	context.Context,
	string,
	string,
) (storageops.ObjectInfo, error) {
	b.headCalls.Add(1)
	return storageops.ObjectInfo{}, os.ErrNotExist
}

func TestStatPathUsesFreshDirectoryListingAsNegativeCache(t *testing.T) {
	access := newTestBucketAccess(t)
	backend := &countingHeadBackend{Backend: access.backend}
	access.backend = backend
	access.cache.storeList("docs", []storageops.ObjectInfo{{Key: "docs/known.txt"}})

	if _, err := access.statPath(context.Background(), "docs/new.txt"); !os.IsNotExist(err) {
		t.Fatalf("stat missing cached child: %v", err)
	}
	if calls := backend.headCalls.Load(); calls != 0 {
		t.Fatalf("remote HeadObject calls = %d, want 0", calls)
	}
}

func TestStatPathKeepsChildrenOfLocalDirectoryOffRemote(t *testing.T) {
	access := newTestBucketAccess(t)
	backend := &countingHeadBackend{Backend: access.backend}
	access.backend = backend
	access.stageLocalDirectory("docs", time.Now())

	if _, err := access.statPath(context.Background(), "docs/new.txt"); !os.IsNotExist(err) {
		t.Fatalf("stat missing local child: %v", err)
	}
	if calls := backend.headCalls.Load(); calls != 0 {
		t.Fatalf("remote HeadObject calls = %d, want 0", calls)
	}
}
