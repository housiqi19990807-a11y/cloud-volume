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

	const activeDelay = 7 * time.Second
	if delay := tracker.nextDelay(now, activeDelay); delay != activeDelay {
		t.Fatalf("active delay = %s, want %s", delay, activeDelay)
	}
	prefixes := tracker.recent(now)
	if len(prefixes) != 2 || prefixes[0] != "active" || prefixes[1] != "warm" {
		t.Fatalf("recent prefixes = %v, want active and warm", prefixes)
	}

	tracker.noteAt("active", now.Add(-remotePollActiveWindow-time.Second))
	if delay := tracker.nextDelay(now, activeDelay); delay != remotePollWarmDelay {
		t.Fatalf("warm delay = %s, want %s", delay, remotePollWarmDelay)
	}
}

func TestDirectoryActivitySignalsPollerAfterIdle(t *testing.T) {
	tracker := newDirectoryActivityTracker()
	tracker.noteAt("docs", time.Now())

	select {
	case <-tracker.changes():
	case <-time.After(time.Second):
		t.Fatal("directory activity did not wake the poller")
	}
}

func TestRemotePollerStaysDisabledForConnectionSensitiveBackend(t *testing.T) {
	access := newTestBucketAccess(t)
	access.allowRemotePoll = false
	session := &mountSession{access: access, bucket: "test-bucket"}
	if poller := newRemoteDirectoryPoller(session); poller != nil {
		t.Fatal("disabled backend unexpectedly created a remote poller")
	}
}
