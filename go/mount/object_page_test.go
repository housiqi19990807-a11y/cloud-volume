// Mounted object page tests pin merged local-first paging and ordering for Flutter browsing.
package mount

import (
	"context"
	"os"
	"path/filepath"
	"strings"
	"testing"

	storageconfig "remote-storage/go/config"
	s3ops "remote-storage/go/s3"
)

type mountedListTestBackend struct{}

func (mountedListTestBackend) Initialize(*mountSession) error       { return nil }
func (mountedListTestBackend) Start(*mountSession) error            { return nil }
func (mountedListTestBackend) Stop(*mountSession) error             { return nil }
func (mountedListTestBackend) IsActive(*mountSession) (bool, error) { return true, nil }
func (mountedListTestBackend) CleanupStale(*mountSession) error     { return nil }

type mountedPageListingTestBackend struct {
	mountTestBackend
	items []s3ops.ObjectInfo
}

func (b mountedPageListingTestBackend) ListObjectsPage(
	context.Context,
	string,
	string,
	string,
	int32,
) (s3ops.ObjectPage, error) {
	return s3ops.ObjectPage{Items: cloneObjects(b.items)}, nil
}

func TestPaginateObjectInfos(t *testing.T) {
	t.Parallel()

	items := []s3ops.ObjectInfo{
		{Key: "a/", IsDir: true},
		{Key: "b.txt", IsDir: false},
		{Key: "c.txt", IsDir: false},
	}
	page := paginateObjectInfos(items, "", 2)
	if len(page.Items) != 2 || page.NextToken != "2" {
		t.Fatalf("unexpected first page: %+v", page)
	}

	page = paginateObjectInfos(items, page.NextToken, 2)
	if len(page.Items) != 1 || page.Items[0].Key != "c.txt" || page.NextToken != "" {
		t.Fatalf("unexpected second page: %+v", page)
	}
}

func TestListMountedObjectPageUsesWebDAVSessionView(t *testing.T) {
	access := newTestBucketAccess(t)
	cachePath := filepath.Join(access.cacheRoot, "drafts", "c.zip")
	if err := ensureTestLocalFile(cachePath, []byte("payload")); err != nil {
		t.Fatalf("write local file: %v", err)
	}
	access.registerLocalWrite("drafts/c.zip", cachePath, 7)
	access.cache.storeList("drafts", nil)

	session := &mountSession{
		config: storageconfig.RemoteStorageConfig{
			StorageType:      storageconfig.StorageTypeWebDAV,
			Bucket:           "test-bucket",
			WindowsMountMode: storageconfig.WindowsMountModeCloudFilesCached,
		}.Normalized(),
		bucket:  "test-bucket",
		access:  access,
		backend: mountedListTestBackend{},
		mounted: true,
	}

	previous := globalManager.sessions["test-bucket"]
	globalManager.sessions["test-bucket"] = session
	defer func() {
		if previous == nil {
			delete(globalManager.sessions, "test-bucket")
		} else {
			globalManager.sessions["test-bucket"] = previous
		}
	}()

	page, handled, err := ListMountedObjectPage(
		session.config,
		"test-bucket",
		"drafts",
		"",
		50,
	)
	if err != nil {
		t.Fatalf("ListMountedObjectPage: %v", err)
	}
	if !handled {
		t.Fatal("expected mounted page to be handled")
	}
	if len(page.Items) != 1 || page.Items[0].Key != "drafts/c.zip" {
		t.Fatalf("unexpected WebDAV mounted items: %+v", page.Items)
	}
}

func TestMountedDirectoryPageSnapshotStaysStableDuringLocalWrite(t *testing.T) {
	access := newTestBucketAccess(t)
	access.cache.storeList("docs", []s3ops.ObjectInfo{
		{Key: "docs/a.txt"},
		{Key: "docs/b.txt"},
		{Key: "docs/c.txt"},
	})
	access.backend = mountedPageListingTestBackend{items: []s3ops.ObjectInfo{
		{Key: "docs/a.txt"},
		{Key: "docs/b.txt"},
		{Key: "docs/c.txt"},
	}}
	session := installMountedListTestSession(t, access)

	first, handled, err := ListMountedObjectPage(session.config, "test-bucket", "docs", "", 2)
	if err != nil || !handled {
		t.Fatalf("first mounted page handled=%t err=%v", handled, err)
	}
	if len(first.Items) != 2 || !strings.HasPrefix(first.NextToken, "m:") {
		t.Fatalf("unexpected first snapshot page: %+v", first)
	}

	access.registerLocalWrite("docs/z.txt", filepath.Join(access.cacheRoot, "z.txt"), 1)
	second, handled, err := ListMountedObjectPage(
		session.config,
		"test-bucket",
		"docs",
		first.NextToken,
		2,
	)
	if err != nil || !handled {
		t.Fatalf("second mounted page handled=%t err=%v", handled, err)
	}
	if len(second.Items) != 1 || second.Items[0].Key != "docs/c.txt" {
		t.Fatalf("old snapshot page changed after local write: %+v", second)
	}

	fresh, handled, err := ListMountedObjectPage(session.config, "test-bucket", "docs", "", 10)
	if err != nil || !handled {
		t.Fatalf("fresh mounted page handled=%t err=%v", handled, err)
	}
	if len(fresh.Items) != 4 || fresh.Items[3].Key != "docs/z.txt" {
		t.Fatalf("fresh snapshot missed local write: %+v", fresh)
	}
}

func installMountedListTestSession(t *testing.T, access *bucketAccess) *mountSession {
	t.Helper()
	session := &mountSession{
		config: storageconfig.RemoteStorageConfig{
			StorageType:      storageconfig.StorageTypeWebDAV,
			Bucket:           "test-bucket",
			WindowsMountMode: storageconfig.WindowsMountModeCloudFilesCached,
		}.Normalized(),
		bucket:  "test-bucket",
		access:  access,
		backend: mountedListTestBackend{},
		mounted: true,
	}
	previous := globalManager.sessions["test-bucket"]
	globalManager.sessions["test-bucket"] = session
	t.Cleanup(func() {
		if previous == nil {
			delete(globalManager.sessions, "test-bucket")
		} else {
			globalManager.sessions["test-bucket"] = previous
		}
	})
	return session
}

func ensureTestLocalFile(path string, data []byte) error {
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return err
	}
	return os.WriteFile(path, data, 0o644)
}
