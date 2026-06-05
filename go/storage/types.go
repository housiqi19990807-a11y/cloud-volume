// Package storage routes account operations to concrete S3 or WebDAV backends.
package storage

import (
	"context"
	"io"
	"net/http"

	storageconfig "remote-storage/go/config"
	s3ops "remote-storage/go/s3"
)

type BucketInfo = s3ops.BucketInfo
type ObjectInfo = s3ops.ObjectInfo
type ObjectPage = s3ops.ObjectPage

type Backend interface {
	ListBuckets(context.Context) ([]BucketInfo, error)
	ListObjectsPage(context.Context, string, string, string, int32) (ObjectPage, error)
	HeadObject(context.Context, string, string) (ObjectInfo, error)
	CreateDirectory(context.Context, string, string, string) error
	DeleteObject(context.Context, string, string, bool, string) error
	RenameObject(context.Context, string, string, bool, string) error
	CopyObject(context.Context, string, string, string, bool, string) error
	MoveObject(context.Context, string, string, string, bool, string) error
	UploadFile(context.Context, string, string, string, string) error
	UploadReader(context.Context, string, string, io.Reader, int64, string, string) error
	DownloadFile(context.Context, string, string, string, string) error
	StreamObjectToHTTP(context.Context, string, string, bool, http.ResponseWriter) error
}

func ForConfig(cfg storageconfig.RemoteStorageConfig) Backend {
	normalized := cfg.Normalized()
	if normalized.StorageType == storageconfig.StorageTypeWebDAV {
		return NewWebDAVBackend(normalized)
	}
	return s3Backend{cfg: normalized}
}
