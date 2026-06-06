// S3 backend adapts the existing S3-compatible implementation to storage.Backend.
package storage

import (
	"context"
	"io"
	"net/http"

	storageconfig "remote-storage/go/config"
	s3ops "remote-storage/go/s3"
)

type s3Backend struct {
	cfg storageconfig.RemoteStorageConfig
}

func (b s3Backend) ListBuckets(context.Context) ([]BucketInfo, error) {
	return s3ops.ListBuckets(b.cfg)
}

func (b s3Backend) ListObjectsPage(
	ctx context.Context,
	bucket, prefix, nextToken string,
	pageSize int32,
) (ObjectPage, error) {
	return s3ops.ListObjectsPageContext(ctx, b.cfg, bucket, prefix, nextToken, pageSize)
}

func (b s3Backend) HeadObject(ctx context.Context, bucket, key string) (ObjectInfo, error) {
	return s3ops.HeadObjectContext(ctx, b.cfg, bucket, key)
}

func (b s3Backend) DirectoryAccess(context.Context, string, string) (DirectoryAccess, error) {
	return DirectoryAccess{Writable: true, Known: true}, nil
}

func (b s3Backend) CreateDirectory(ctx context.Context, bucket, prefix, name string) error {
	return s3ops.CreateDirectoryContext(ctx, b.cfg, bucket, prefix, name)
}

func (b s3Backend) DeleteObject(
	ctx context.Context,
	bucket, key string,
	isDirectory bool,
	taskID string,
) error {
	return s3ops.DeleteObjectContextWithTask(ctx, b.cfg, bucket, key, isDirectory, taskID)
}

func (b s3Backend) RenameObject(
	ctx context.Context,
	bucket, key string,
	isDirectory bool,
	newName string,
) error {
	return s3ops.RenameObjectContext(ctx, b.cfg, bucket, key, isDirectory, newName)
}

func (b s3Backend) CopyObject(
	ctx context.Context,
	bucket, sourceKey, targetKey string,
	isDirectory bool,
	taskID string,
) error {
	return s3ops.CopyObjectContext(ctx, b.cfg, bucket, sourceKey, targetKey, isDirectory, taskID)
}

func (b s3Backend) MoveObject(
	ctx context.Context,
	bucket, sourceKey, targetKey string,
	isDirectory bool,
	taskID string,
) error {
	return s3ops.MoveObjectContextWithTask(ctx, b.cfg, bucket, sourceKey, targetKey, isDirectory, taskID)
}

func (b s3Backend) UploadFile(
	ctx context.Context,
	bucket, key, localPath, taskID string,
) error {
	return s3ops.UploadFileContext(ctx, b.cfg, bucket, key, localPath, taskID)
}

func (b s3Backend) UploadReader(
	ctx context.Context,
	bucket, key string,
	body io.Reader,
	size int64,
	taskID, fileName string,
) error {
	return s3ops.UploadReader(ctx, b.cfg, bucket, key, body, size, taskID, fileName)
}

func (b s3Backend) DownloadFile(
	ctx context.Context,
	bucket, key, localPath, taskID string,
) error {
	return s3ops.DownloadFileContext(ctx, b.cfg, bucket, key, localPath, taskID)
}

func (b s3Backend) StreamObjectToHTTP(
	ctx context.Context,
	bucket, key string,
	inline bool,
	w http.ResponseWriter,
) error {
	return s3ops.StreamObjectToHTTP(ctx, b.cfg, bucket, key, inline, w)
}
