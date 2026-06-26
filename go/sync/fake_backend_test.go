package sync

import (
	"context"
	"io"
	"net/http"

	storageops "remote-storage/go/storage"
)

// fakeBackend is a minimal in-memory Backend for unit tests.
type fakeBackend struct {
	objects map[string]storageops.ObjectInfo
}

func newFakeBackend() *fakeBackend {
	return &fakeBackend{objects: map[string]storageops.ObjectInfo{}}
}

func (f *fakeBackend) ListBuckets(context.Context) ([]storageops.BucketInfo, error) {
	return nil, nil
}
func (f *fakeBackend) ListObjectsPage(_ context.Context, _, prefix, _ string, _ int32) (storageops.ObjectPage, error) {
	var items []storageops.ObjectInfo
	for key, info := range f.objects {
		items = append(items, info)
		_ = key
	}
	return storageops.ObjectPage{Items: items}, nil
}
func (f *fakeBackend) HeadObject(_ context.Context, _, key string) (storageops.ObjectInfo, error) {
	return f.objects[key], nil
}
func (f *fakeBackend) ReadObjectRange(context.Context, string, string, int64, int64) ([]byte, error) {
	return nil, nil
}
func (f *fakeBackend) DirectoryAccess(context.Context, string, string) (storageops.DirectoryAccess, error) {
	return storageops.DirectoryAccess{Writable: true, Known: true}, nil
}
func (f *fakeBackend) CreateDirectory(context.Context, string, string, string) error { return nil }
func (f *fakeBackend) DeleteObject(_ context.Context, _, key string, _ bool, _ string) error {
	delete(f.objects, key)
	return nil
}
func (f *fakeBackend) DeleteObjectHard(ctx context.Context, b, k string, d bool, s string) error {
	return f.DeleteObject(ctx, b, k, d, s)
}
func (f *fakeBackend) ListTrashPage(context.Context, string, string, int32) (storageops.TrashPage, error) {
	return storageops.TrashPage{}, nil
}
func (f *fakeBackend) RestoreTrashItem(context.Context, string, string) error    { return nil }
func (f *fakeBackend) DeleteTrashItem(context.Context, string, string) error     { return nil }
func (f *fakeBackend) ClearTrash(context.Context, string) error                  { return nil }
func (f *fakeBackend) RenameObject(context.Context, string, string, bool, string) error { return nil }
func (f *fakeBackend) CopyObject(context.Context, string, string, string, bool, string) error {
	return nil
}
func (f *fakeBackend) MoveObject(context.Context, string, string, string, bool, string) error {
	return nil
}
func (f *fakeBackend) UploadFile(context.Context, string, string, string, string) error { return nil }
func (f *fakeBackend) UploadReader(context.Context, string, string, io.Reader, int64, string, string) error {
	return nil
}
func (f *fakeBackend) DownloadFile(context.Context, string, string, string, string) error { return nil }
func (f *fakeBackend) StreamObjectToHTTP(context.Context, string, string, bool, http.ResponseWriter) error {
	return nil
}
