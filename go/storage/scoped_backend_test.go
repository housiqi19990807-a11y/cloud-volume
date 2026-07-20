// Scoped backend tests cover virtual path joining and trash filtering used by
// all providers. The trash filtering test guards against a regression where
// ListTrashPage aliased the underlying provider's backing array.
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
	items              []TrashItem
	restored, deleted  []string
}

func (b *trashStubBackend) ListBuckets(context.Context) ([]BucketInfo, error) { return nil, nil }
func (b *trashStubBackend) ListObjectsPage(context.Context, string, string, string, int32) (ObjectPage, error) {
	return ObjectPage{}, nil
}
func (b *trashStubBackend) ListObjectsRecursive(context.Context, string, string) ([]ObjectInfo, error) {
	return nil, nil
}
func (b *trashStubBackend) HeadObject(context.Context, string, string) (ObjectInfo, error) {
	return ObjectInfo{}, nil
}
func (b *trashStubBackend) ReadObjectRange(context.Context, string, string, int64, int64) ([]byte, error) {
	return nil, nil
}
func (b *trashStubBackend) DirectoryAccess(context.Context, string, string) (DirectoryAccess, error) {
	return DirectoryAccess{}, nil
}
func (b *trashStubBackend) CreateDirectory(context.Context, string, string, string) error { return nil }
func (b *trashStubBackend) DeleteObject(context.Context, string, string, bool, string) error { return nil }
func (b *trashStubBackend) DeleteObjectHard(context.Context, string, string, bool, string) error { return nil }
func (b *trashStubBackend) ListTrashPage(_ context.Context, _ string, _ string, _ int32) (TrashPage, error) {
	// Return the same backing slice each call on purpose: the scoped layer
	// must not mutate it while filtering.
	return TrashPage{Items: b.items}, nil
}
func (b *trashStubBackend) RestoreTrashItem(_ context.Context, _ string, id string) error {
	b.restored = append(b.restored, id)
	return nil
}
func (b *trashStubBackend) DeleteTrashItem(_ context.Context, _ string, id string) error {
	b.deleted = append(b.deleted, id)
	return nil
}
func (b *trashStubBackend) ClearTrash(context.Context, string) error { return nil }
func (b *trashStubBackend) RenameObject(context.Context, string, string, bool, string) error {
	return nil
}
func (b *trashStubBackend) CopyObject(context.Context, string, string, string, bool, string) error {
	return nil
}
func (b *trashStubBackend) MoveObject(context.Context, string, string, string, bool, string) error {
	return nil
}
func (b *trashStubBackend) UploadFile(context.Context, string, string, string, string) error {
	return nil
}
func (b *trashStubBackend) UploadReader(_ context.Context, _ string, _ string, _ io.Reader, _ int64, _ string, _ string) error {
	return nil
}
func (b *trashStubBackend) DownloadFile(context.Context, string, string, string, string) error {
	return nil
}
func (b *trashStubBackend) StreamObjectToHTTP(_ context.Context, _ string, _ string, _ bool, _ http.ResponseWriter) error {
	return nil
}

// TestScopedListTrashPageFiltersAndPreservesProviderItems asserts that the
// scoped layer (1) only surfaces trash whose OriginalKey lives under root,
// (2) rewrites those keys to be view-relative, and (3) leaves the underlying
// provider slice untouched so subsequent unscoped calls still see full keys.
func TestScopedListTrashPageFiltersAndPreservesProviderItems(t *testing.T) {
	providerItems := []TrashItem{
		{ID: "in1", OriginalKey: "archive/2026/photos/a.txt"},
		{ID: "out", OriginalKey: "other/prefix/b.txt"},
		{ID: "in2", OriginalKey: "archive/2026/docs/c.txt"},
	}
	stub := &trashStubBackend{items: providerItems}
	scoped := scopedBackend{Backend: stub, root: "archive/2026"}

	ctx := context.Background()
	page, err := scoped.ListTrashPage(ctx, "demo", "", 50)
	if err != nil {
		t.Fatalf("ListTrashPage: %v", err)
	}
	if len(page.Items) != 2 {
		t.Fatalf("expected 2 filtered items, got %d (%+v)", len(page.Items), page.Items)
	}
	if page.Items[0].ID != "in1" || page.Items[0].OriginalKey != "photos/a.txt" {
		t.Fatalf("first filtered item = %+v", page.Items[0])
	}
	if page.Items[1].ID != "in2" || page.Items[1].OriginalKey != "docs/c.txt" {
		t.Fatalf("second filtered item = %+v", page.Items[1])
	}
	// The provider's slice must remain unmodified — this is the aliasing guard.
	for i, want := range []string{"archive/2026/photos/a.txt", "other/prefix/b.txt", "archive/2026/docs/c.txt"} {
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
