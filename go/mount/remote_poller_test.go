// Remote poller tests cover cache refresh and activity-window backoff behavior.
package mount

import (
	"context"
	"testing"
	"time"

	storageops "remote-storage/go/storage"
)

type remotePollTestBackend struct {
	mountTestBackend
	items []storageops.ObjectInfo
}

func (b remotePollTestBackend) ListObjectsPage(
	context.Context,
	string,
	string,
	string,
	int32,
) (storageops.ObjectPage, error) {
	return storageops.ObjectPage{Items: b.items}, nil
}

func TestRemotePollerRefreshesOnlyRecentDirectories(t *testing.T) {
	access := newTestBucketAccess(t)
	access.backend = remotePollTestBackend{
		items: []storageops.ObjectInfo{{Key: "docs/from-other-device.txt", Size: 9}},
	}
	access.cache.storeList("docs", []storageops.ObjectInfo{{Key: "docs/stale.txt", Size: 1}})
	access.noteDirectoryActivity("docs")

	var projectedPrefix string
	access.externalDirectoryRefresh = func(
		prefix string,
		items []storageops.ObjectInfo,
	) error {
		projectedPrefix = prefix
		if len(items) != 1 || items[0].Key != "docs/from-other-device.txt" {
			t.Fatalf("unexpected projection items: %+v", items)
		}
		return nil
	}

	poller := &remoteDirectoryPoller{access: access, bucket: "test-bucket"}
	poller.pollOnce(context.Background())

	items, ok := access.cache.cachedList("docs")
	if !ok || len(items) != 1 || items[0].Key != "docs/from-other-device.txt" {
		t.Fatalf("remote poll did not refresh docs cache: ok=%t items=%+v", ok, items)
	}
	if projectedPrefix != "docs" {
		t.Fatalf("projected prefix = %q, want docs", projectedPrefix)
	}
}

func TestDirectoryActivityBacksOffAndExpires(t *testing.T) {
	now := time.Now()
	tracker := newDirectoryActivityTracker()
	tracker.noteAt("active", now.Add(-time.Second))
	tracker.noteAt("warm", now.Add(-remotePollActiveWindow-time.Second))
	tracker.noteAt("expired", now.Add(-remotePollWarmWindow-time.Second))

	if delay := tracker.nextDelay(now); delay != remotePollActiveDelay {
		t.Fatalf("active delay = %s, want %s", delay, remotePollActiveDelay)
	}
	prefixes := tracker.recent(now)
	if len(prefixes) != 2 || prefixes[0] != "active" || prefixes[1] != "warm" {
		t.Fatalf("recent prefixes = %v, want active and warm", prefixes)
	}

	tracker.noteAt("active", now.Add(-remotePollActiveWindow-time.Second))
	if delay := tracker.nextDelay(now); delay != remotePollWarmDelay {
		t.Fatalf("warm delay = %s, want %s", delay, remotePollWarmDelay)
	}
}
