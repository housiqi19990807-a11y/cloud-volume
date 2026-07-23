// Scoped backend tests cover virtual path joining and trash rewriting used by
// all providers. Trash itself lives under the view root (see trashPrefix /
// webDAVTrashPrefix), so ListTrashPage only rewrites OriginalKey from
// provider-absolute form to view-relative form and must not alias the
// provider's backing array.
package storage

import (
	"context"
	"io"
	"net/http"
	"testing"
)

func TestScopeKey(t *testing.T) {
	tests := []struct {
		root, key, want string
	}{
		{"archive/2026", "", "archive/2026/"},
		{"archive/2026", "photos/", "archive/2026/photos"},
		{"", "photos", "photos"},
	}
	for _, tt := range tests {
		if got := scopeKey(tt.root, tt.key); got != tt.want {
			t.Errorf("scopeKey(%q, %q) = %q, want %q", tt.root, tt.key, got, tt.want)
		}
	}
}

func TestUnscopedKey(t *testing.T) {
	b := scopedBackend{root: "archive/2026"}
	if got := b.unscopedKey("archive/2026/photos/a.txt"); got != "photos/a.txt" {
		t.Fatalf("unscoped key = %q", got)
	}
}

// trashStubBackend serves a fixed trash page for ListTrashPage and records
// restore/delete IDs so tests can assert delegation.
type trashStubBackend struct {
	items             []TrashItem
	restored, deleted []string
	quota             BucketInfo
}

func (s *trashStubBackend) ListTrashPage(context.Context, string, string, int32) (TrashPage, error) {
	// Return a slice that aliases the stub's backing array so tests can
	// detect accidental mutation of shared provider state.
	return TrashPage{Items: s.items}, nil
}

func (s *trashStubBackend) RestoreTrashItem(_ context.Context, _, id string) error {
	s.restored = append(s.restored, id)
	return nil
}

func (s *trashStubBackend) DeleteTrashItem(_ context.Context, _, id string) error {
	s.deleted = append(s.deleted, id)
	return nil
}

// Unused Backend methods — satisfy the interface for the trash-only stub.
func (s *trashStubBackend) ListBuckets(context.Context) ([]BucketInfo, error) {
	return nil, nil
}
func (s *trashStubBackend) ListObjectsPage(context.Context, string, string, string, int32) (ObjectPage, error) {
	return ObjectPage{}, nil
}
func (s *trashStubBackend) ListObjectsRecursive(context.Context, string, string) ([]ObjectInfo, error) {
	return nil, nil
}
func (s *trashStubBackend) HeadObject(context.Context, string, string) (ObjectInfo, error) {
	return ObjectInfo{}, nil
}
func (s *trashStubBackend) ReadObjectRange(context.Context, string, string, int64, int64) ([]byte, error) {
	return nil, nil
}
func (s *trashStubBackend) DirectoryAccess(context.Context, string, string) (DirectoryAccess, error) {
	return DirectoryAccess{}, nil
}
func (s *trashStubBackend) CreateDirectory(context.Context, string, string, string) error {
	return nil
}
func (s *trashStubBackend) DeleteObject(context.Context, string, string, bool, string) error {
	return nil
}
func (s *trashStubBackend) DeleteObjectHard(context.Context, string, string, bool, string) error {
	return nil
}
func (s *trashStubBackend) RenameObject(context.Context, string, string, bool, string) error {
	return nil
}
func (s *trashStubBackend) CopyObject(context.Context, string, string, string, bool, string) error {
	return nil
}
func (s *trashStubBackend) MoveObject(context.Context, string, string, string, bool, string) error {
	return nil
}
func (s *trashStubBackend) UploadFile(context.Context, string, string, string, string) error {
	return nil
}
func (s *trashStubBackend) UploadReader(context.Context, string, string, io.Reader, int64, string, string) error {
	return nil
}
func (s *trashStubBackend) DownloadFile(context.Context, string, string, string, string) error {
	return nil
}
func (s *trashStubBackend) StreamObjectToHTTP(context.Context, string, string, bool, http.ResponseWriter) error {
	return nil
}
func (s *trashStubBackend) ClearTrash(context.Context, string) error { return nil }

// BucketQuota lets the scoped wrapper test its optional capability forwarding.
func (s *trashStubBackend) BucketQuota(context.Context, string) (BucketInfo, error) {
	return s.quota, nil
}

// TestScopedListTrashPageRewritesOriginalKeysAndPreservesProviderItems
// asserts that scoped ListTrashPage:
//  1. rewrites OriginalKey relative to the view root,
//  2. does not drop entries that already live under the view-rooted trash,
//  3. leaves the provider's backing slice untouched.
func TestScopedListTrashPageRewritesOriginalKeysAndPreservesProviderItems(t *testing.T) {
	providerItems := []TrashItem{
		{ID: "in1", OriginalKey: "archive/2026/photos/a.txt"},
		{ID: "in2", OriginalKey: "archive/2026/docs/c.txt"},
	}
	// Snapshot the original keys so we can detect mutation after the call.
	originalKeys := []string{
		providerItems[0].OriginalKey,
		providerItems[1].OriginalKey,
	}
	stub := &trashStubBackend{items: providerItems}
	scoped := scopedBackend{Backend: stub, root: "archive/2026"}

	ctx := context.Background()
	page, err := scoped.ListTrashPage(ctx, "demo", "", 50)
	if err != nil {
		t.Fatalf("ListTrashPage: %v", err)
	}
	if len(page.Items) != 2 {
		t.Fatalf("expected 2 items, got %d (%+v)", len(page.Items), page.Items)
	}
	if page.Items[0].ID != "in1" || page.Items[0].OriginalKey != "photos/a.txt" {
		t.Fatalf("first item = %+v", page.Items[0])
	}
	if page.Items[1].ID != "in2" || page.Items[1].OriginalKey != "docs/c.txt" {
		t.Fatalf("second item = %+v", page.Items[1])
	}
	// The provider's slice must remain unmodified — this is the aliasing guard.
	for i, want := range originalKeys {
		if got := providerItems[i].OriginalKey; got != want {
			t.Fatalf("provider item %d mutated: got %q want %q", i, got, want)
		}
	}

	// Restore/Delete must delegate the original trashID without rewrites.
	if err := scoped.RestoreTrashItem(ctx, "demo", "in1"); err != nil {
		t.Fatalf("RestoreTrashItem: %v", err)
	}
	if err := scoped.DeleteTrashItem(ctx, "demo", "in2"); err != nil {
		t.Fatalf("DeleteTrashItem: %v", err)
	}
	if len(stub.restored) != 1 || stub.restored[0] != "in1" {
		t.Fatalf("unexpected restored ids: %+v", stub.restored)
	}
	if len(stub.deleted) != 1 || stub.deleted[0] != "in2" {
		t.Fatalf("unexpected deleted ids: %+v", stub.deleted)
	}
}

func TestScopedBackendForwardsBucketQuota(t *testing.T) {
	stub := &trashStubBackend{quota: BucketInfo{Name: "demo", QuotaBytes: 100, UsedBytes: 25, QuotaKnown: true}}
	scoped := scopedBackend{Backend: stub, root: "archive/2026"}
	provider, ok := any(scoped).(BucketQuotaProvider)
	if !ok {
		t.Fatal("scoped backend must retain the bucket quota capability")
	}
	quota, err := provider.BucketQuota(t.Context(), "demo")
	if err != nil {
		t.Fatalf("BucketQuota: %v", err)
	}
	if quota != stub.quota {
		t.Fatalf("quota = %+v, want %+v", quota, stub.quota)
	}
}
