// Remote poller tests cover cache refresh and activity-window backoff behavior.
package mount

import (
	"context"
	"fmt"
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

func TestDirectoryActivityBacksOffWithoutExpiring(t *testing.T) {
	now := time.Now()
	tracker := newDirectoryActivityTracker()
	tracker.noteAt("active", now.Add(-time.Second))
	tracker.noteAt("warm", now.Add(-remotePollActiveWindow-time.Second))
	tracker.noteAt("idle", now.Add(-5*time.Minute))

	const activeDelay = 7 * time.Second
	if delay := tracker.nextDelay(now, activeDelay); delay != activeDelay {
		t.Fatalf("active delay = %s, want %s", delay, activeDelay)
	}
	prefixes := tracker.recent(now)
	if len(prefixes) != 3 || prefixes[0] != "active" || prefixes[1] != "idle" || prefixes[2] != "warm" {
		t.Fatalf("recent prefixes = %v, want active, idle, and warm retained", prefixes)
	}

	tracker.noteAt("active", now.Add(-remotePollActiveWindow-time.Second))
	if delay := tracker.nextDelay(now, activeDelay); delay != remotePollWarmDelay {
		t.Fatalf("warm delay = %s, want %s", delay, remotePollWarmDelay)
	}
}

func TestRemotePollerRefreshesAnIdleObservedDirectory(t *testing.T) {
	access := newTestBucketAccess(t)
	backend := remotePollTestBackend{
		items: []storageops.ObjectInfo{{Key: "docs/from-linux.txt", Size: 9}},
	}
	access.backend = backend
	access.cache.storeList("docs", []storageops.ObjectInfo{{Key: "docs/stale.txt", Size: 1}})
	access.noteDirectoryActivity("docs")
	// Age the observation past every activity window: an idle but still
	// observed directory must keep refreshing.
	access.directoryActivity.mu.Lock()
	access.directoryActivity.dirs["docs"] = time.Now().Add(-remotePollWarmWindow - time.Minute)
	access.directoryActivity.mu.Unlock()

	var projectedPrefix string
	access.externalDirectoryRefresh = func(
		prefix string,
		items []storageops.ObjectInfo,
	) error {
		projectedPrefix = prefix
		if len(items) != 1 || items[0].Key != "docs/from-linux.txt" {
			t.Fatalf("unexpected projection items: %+v", items)
		}
		return nil
	}

	poller := &remoteDirectoryPoller{access: access, bucket: "test-bucket"}
	poller.pollOnce(context.Background())

	if projectedPrefix != "docs" {
		t.Fatalf("idle observed directory was not refreshed, projected=%q", projectedPrefix)
	}
	items, ok := access.cache.cachedList("docs")
	if !ok || len(items) != 1 || items[0].Key != "docs/from-linux.txt" {
		t.Fatalf("idle poll did not refresh docs cache: ok=%t items=%+v", ok, items)
	}
}

func TestDirectoryActivityStillHonorsTheTwelveDirectoryCap(t *testing.T) {
	now := time.Now()
	tracker := newDirectoryActivityTracker()
	for index := 0; index < 13; index++ {
		tracker.noteAt(fmt.Sprintf("dir-%02d", index), now.Add(time.Duration(index)*time.Second))
	}

	prefixes := tracker.recent(now)
	if len(prefixes) != remotePollDirectoryCap {
		t.Fatalf("recent prefixes = %d, want %d", len(prefixes), remotePollDirectoryCap)
	}
	if prefix := prefixes[0]; prefix != "dir-01" {
		t.Fatalf("oldest entry %q survived the cap; want dir-01 first", prefix)
	}
	tracker.mu.Lock()
	_, retained := tracker.dirs["dir-00"]
	tracker.mu.Unlock()
	if retained {
		t.Fatal("oldest observed directory was not evicted at the cap")
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
