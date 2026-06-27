package sync

import (
	"context"
	"testing"

	storageops "remote-storage/go/storage"
)

func TestScanRemoteIncludesNestedObjects(t *testing.T) {
	backend := newFakeBackend()
	backend.objects["sync-root/sub/file.txt"] = storageops.ObjectInfo{
		Key: "sync-root/sub/file.txt", Size: 42, LastModified: "2026-01-02 15:04:05",
	}
	profile := SyncProfile{
		Bucket: "b",
		RemotePrefix: "sync-root/",
		LocalPath: t.TempDir(),
		Direction: DirectionTwoWay,
	}
	rc := NewReconciler(profile, backend, t.TempDir())
	remote, err := rc.scanRemote(context.Background())
	if err != nil {
		t.Fatalf("scanRemote: %v", err)
	}
	if _, ok := remote["sub/file.txt"]; !ok {
		t.Fatalf("expected nested file in remote map, got %#v", remote)
	}
}
