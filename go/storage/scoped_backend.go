// scoped_backend.go applies an account bucket-view root to every object call.
package storage

import (
	"context"
	"io"
	"net/http"
	"os"
	"strings"
	"time"

	"remote-storage/go/s3"
)

type scopedBackend struct {
	Backend
	root string
}

func scopeKey(root, key string) string {
	root = strings.Trim(strings.TrimSpace(root), "/")
	key = strings.Trim(strings.TrimSpace(key), "/")
	if root == "" {
		return key
	}
	if key == "" {
		return root + "/"
	}
	return root + "/" + key
}

func (b scopedBackend) unscopedKey(key string) string {
	key = strings.TrimPrefix(key, b.root)
	return strings.TrimLeft(key, "/")
}

func (b scopedBackend) unscopeInfo(info s3.ObjectInfo) s3.ObjectInfo {
	info.Key = b.unscopedKey(info.Key)
	return info
}

func (b scopedBackend) ListObjectsPage(ctx context.Context, bucket, prefix, token string, size int32) (ObjectPage, error) {
	page, err := b.Backend.ListObjectsPage(ctx, bucket, scopeKey(b.root, prefix), token, size)
	if err != nil {
		return page, err
	}
	for i := range page.Items {
		page.Items[i] = b.unscopeInfo(page.Items[i])
	}
	return page, nil
}

func (b scopedBackend) ListObjectsRecursive(ctx context.Context, bucket, prefix string) ([]ObjectInfo, error) {
	items, err := b.Backend.ListObjectsRecursive(ctx, bucket, scopeKey(b.root, prefix))
	if err != nil {
		return nil, err
	}
	for i := range items {
		items[i] = b.unscopeInfo(items[i])
	}
	return items, nil
}

func (b scopedBackend) HeadObject(ctx context.Context, bucket, key string) (ObjectInfo, error) {
	info, err := b.Backend.HeadObject(ctx, bucket, scopeKey(b.root, key))
	if err != nil {
		return info, err
	}
	return b.unscopeInfo(info), nil
}

func (b scopedBackend) ReadObjectRange(ctx context.Context, bucket, key string, offset, length int64) ([]byte, error) {
	return b.Backend.ReadObjectRange(ctx, bucket, scopeKey(b.root, key), offset, length)
}

func (b scopedBackend) DirectoryAccess(ctx context.Context, bucket, prefix string) (DirectoryAccess, error) {
	return b.Backend.DirectoryAccess(ctx, bucket, scopeKey(b.root, prefix))
}

func (b scopedBackend) CreateDirectory(ctx context.Context, bucket, prefix, name string) error {
	return b.Backend.CreateDirectory(ctx, bucket, scopeKey(b.root, prefix), name)
}

func (b scopedBackend) DeleteObject(ctx context.Context, bucket, key string, dir bool, task string) error {
	return b.Backend.DeleteObject(ctx, bucket, scopeKey(b.root, key), dir, task)
}

func (b scopedBackend) DeleteObjectHard(ctx context.Context, bucket, key string, dir bool, task string) error {
	return b.Backend.DeleteObjectHard(ctx, bucket, scopeKey(b.root, key), dir, task)
}

func (b scopedBackend) RenameObject(ctx context.Context, bucket, key string, dir bool, name string) error {
	return b.Backend.RenameObject(ctx, bucket, scopeKey(b.root, key), dir, name)
}

func (b scopedBackend) CopyObject(ctx context.Context, bucket, source, target string, dir bool, task string) error {
	return b.Backend.CopyObject(ctx, bucket, scopeKey(b.root, source), scopeKey(b.root, target), dir, task)
}

func (b scopedBackend) MoveObject(ctx context.Context, bucket, source, target string, dir bool, task string) error {
	return b.Backend.MoveObject(ctx, bucket, scopeKey(b.root, source), scopeKey(b.root, target), dir, task)
}

func (b scopedBackend) UploadFile(ctx context.Context, bucket, key, local, task string) error {
	return b.Backend.UploadFile(ctx, bucket, scopeKey(b.root, key), local, task)
}

func (b scopedBackend) UploadReader(ctx context.Context, bucket, key string, body io.Reader, size int64, task, name string) error {
	return b.Backend.UploadReader(ctx, bucket, scopeKey(b.root, key), body, size, task, name)
}

func (b scopedBackend) DownloadFile(ctx context.Context, bucket, key, local, task string) error {
	return b.Backend.DownloadFile(ctx, bucket, scopeKey(b.root, key), local, task)
}

func (b scopedBackend) StreamObjectToHTTP(ctx context.Context, bucket, key string, inline bool, w http.ResponseWriter) error {
	return b.Backend.StreamObjectToHTTP(ctx, bucket, scopeKey(b.root, key), inline, w)
}

func (b scopedBackend) ListTrashPage(ctx context.Context, bucket, token string, size int32) (TrashPage, error) {
	page, err := b.Backend.ListTrashPage(ctx, bucket, token, size)
	if err != nil {
		return page, err
	}
	items := page.Items[:0]
	root := strings.Trim(b.root, "/") + "/"
	for _, item := range page.Items {
		if strings.HasPrefix(strings.TrimLeft(item.OriginalKey, "/"), root) {
			item.OriginalKey = strings.TrimPrefix(strings.TrimLeft(item.OriginalKey, "/"), root)
			items = append(items, item)
		}
	}
	page.Items = items
	return page, nil
}
func (b scopedBackend) RestoreTrashItem(ctx context.Context, bucket, id string) error {
	return b.Backend.RestoreTrashItem(ctx, bucket, id)
}
func (b scopedBackend) DeleteTrashItem(ctx context.Context, bucket, id string) error {
	return b.Backend.DeleteTrashItem(ctx, bucket, id)
}
func (b scopedBackend) ClearTrash(ctx context.Context, bucket string) error {
	for {
		page, err := b.ListTrashPage(ctx, bucket, "", 200)
		if err != nil {
			return err
		}
		if len(page.Items) == 0 {
			return nil
		}
		for _, item := range page.Items {
			if err := b.Backend.DeleteTrashItem(ctx, bucket, item.ID); err != nil {
				return err
			}
		}
	}
}

func (b scopedBackend) UploadFilePrefix(ctx context.Context, bucket, key, local string, info os.FileInfo, ready int64, workers int) error {
	uploader, ok := b.Backend.(PartialFileUploader)
	if !ok {
		return b.Backend.UploadFile(ctx, bucket, scopeKey(b.root, key), local, "")
	}
	return uploader.UploadFilePrefix(ctx, bucket, scopeKey(b.root, key), local, info, ready, workers)
}

func (b scopedBackend) SupportsMountPrefetch() bool { return SupportsMountPrefetch(b.Backend) }
func (b scopedBackend) DirectoryUploadConcurrency() int {
	if v, ok := b.Backend.(interface{ DirectoryUploadConcurrency() int }); ok {
		return v.DirectoryUploadConcurrency()
	}
	return 0
}
func (b scopedBackend) DirectoryUploadRetryDelay(err error, attempt int) (time.Duration, bool) {
	if v, ok := b.Backend.(interface {
		DirectoryUploadRetryDelay(error, int) (time.Duration, bool)
	}); ok {
		return v.DirectoryUploadRetryDelay(err, attempt)
	}
	return 0, false
}

func (b scopedBackend) BucketQuota(ctx context.Context, bucket string) (BucketInfo, error) {
	provider, ok := b.Backend.(BucketQuotaProvider)
	if !ok {
		return BucketInfo{Name: bucket}, nil
	}
	return provider.BucketQuota(ctx, bucket)
}
