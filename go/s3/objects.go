// Object listing, upload, and download operations.

package s3

import (
	"context"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/service/s3"

	storageconfig "remote-storage/go/config"
)

// ObjectInfo holds object metadata returned to the Flutter layer.
type ObjectInfo struct {
	Key          string `json:"key"`
	Size         int64  `json:"size"`
	LastModified string `json:"lastModified,omitempty"`
	IsDir        bool   `json:"isDir"`
}

// HeadObject returns the current remote file metadata used for cache validation.
func HeadObject(cfg storageconfig.RemoteStorageConfig, bucket, key string) (ObjectInfo, error) {
	return HeadObjectContext(Ctx(), cfg, bucket, key)
}

// HeadObjectContext returns remote file metadata with a caller-supplied context.
func HeadObjectContext(
	ctx context.Context,
	cfg storageconfig.RemoteStorageConfig,
	bucket,
	key string,
) (ObjectInfo, error) {
	client := NewClient(cfg)
	out, err := client.HeadObject(ctx, &s3.HeadObjectInput{
		Bucket: &bucket,
		Key:    &key,
	})
	if err != nil {
		return ObjectInfo{}, normalizeNotExistError(err)
	}

	info := ObjectInfo{
		Key:   key,
		Size:  aws.ToInt64(out.ContentLength),
		IsDir: false,
	}
	if out.LastModified != nil {
		info.LastModified = out.LastModified.Format("2006-01-02 15:04:05")
	}
	return info, nil
}

// ListObjects returns objects and common prefixes under a bucket + prefix.
func ListObjects(cfg storageconfig.RemoteStorageConfig, bucket, prefix string) ([]ObjectInfo, error) {
	return ListObjectsContext(Ctx(), cfg, bucket, prefix)
}

// ListObjectsContext returns objects and common prefixes using a caller context.
func ListObjectsContext(
	ctx context.Context,
	cfg storageconfig.RemoteStorageConfig,
	bucket,
	prefix string,
) ([]ObjectInfo, error) {
	client := NewClient(cfg)

	if prefix != "" && !strings.HasSuffix(prefix, "/") {
		prefix += "/"
	}

	out, err := client.ListObjectsV2(ctx, &s3.ListObjectsV2Input{
		Bucket:    &bucket,
		Prefix:    &prefix,
		Delimiter: aws.String("/"),
	})
	if err != nil {
		return nil, err
	}

	var result []ObjectInfo
	for _, cp := range out.CommonPrefixes {
		if cp.Prefix != nil && isRootTrashKey(cfg, *cp.Prefix) {
			continue
		}
		result = append(result, ObjectInfo{Key: *cp.Prefix, IsDir: true})
	}
	for _, obj := range out.Contents {
		if obj.Key != nil && *obj.Key == prefix {
			continue
		}
		if obj.Key != nil && isRootTrashKey(cfg, *obj.Key) {
			continue
		}
		info := ObjectInfo{Key: *obj.Key, Size: *obj.Size}
		if obj.LastModified != nil {
			info.LastModified = obj.LastModified.Format("2006-01-02 15:04:05")
		}
		result = append(result, info)
	}
	if result == nil {
		result = []ObjectInfo{}
	}
	return result, nil
}

func isRootTrashKey(cfg storageconfig.RemoteStorageConfig, key string) bool {
	trimmed := strings.Trim(strings.TrimSpace(key), "/")
	if trimmed == "" {
		return false
	}
	index := strings.Index(trimmed, "/")
	if index >= 0 {
		trimmed = trimmed[:index]
	}
	for _, alias := range storageconfig.TrashDirectoryAliases(cfg.TrashDirectoryName) {
		if trimmed == strings.Trim(strings.TrimSpace(alias), "/") {
			return true
		}
	}
	return false
}

// UploadFile uploads a local file to the given bucket + key.
func UploadFile(
	cfg storageconfig.RemoteStorageConfig,
	bucket,
	key,
	localPath,
	taskID string,
) (err error) {
	return UploadFileContext(Ctx(), cfg, bucket, key, localPath, taskID)
}

// UploadFileContext uploads a local file using the provided context.
func UploadFileContext(
	ctx context.Context,
	cfg storageconfig.RemoteStorageConfig,
	bucket,
	key,
	localPath,
	taskID string,
) (err error) {
	client := NewClient(cfg)
	f, err := os.Open(localPath)
	if err != nil {
		return fmt.Errorf("open local file: %w", err)
	}
	defer f.Close()
	if ctx == nil {
		ctx = Ctx()
	}
	info, statErr := f.Stat()
	if statErr == nil && taskID != "" {
		var cancel context.CancelFunc
		ctx, cancel = context.WithCancel(ctx)
		startTransfer(taskID, "upload", bucket, key, localPath, info.Size(), cancel)
		defer func() { finishTransfer(taskID, err) }()
	}

	body := io.Reader(f)
	if taskID != "" {
		body = &contextReader{
			ctx:    ctx,
			reader: f,
			onRead: func(n int) { advanceTransfer(taskID, int64(n)) },
		}
	}
	_, err = client.PutObject(ctx, &s3.PutObjectInput{
		Bucket: &bucket, Key: &key, Body: body,
	})
	return err
}

// DownloadFile downloads an object to a local path.
func DownloadFile(
	cfg storageconfig.RemoteStorageConfig,
	bucket,
	key,
	localPath,
	taskID string,
) (err error) {
	return DownloadFileContext(Ctx(), cfg, bucket, key, localPath, taskID)
}

// DownloadFileContext downloads an object using the provided context.
func DownloadFileContext(
	ctx context.Context,
	cfg storageconfig.RemoteStorageConfig,
	bucket,
	key,
	localPath,
	taskID string,
) (err error) {
	client := NewClient(cfg)
	if err := os.MkdirAll(filepath.Dir(localPath), 0o755); err != nil {
		return err
	}
	if ctx == nil {
		ctx = Ctx()
	}
	head, err := client.HeadObject(ctx, &s3.HeadObjectInput{
		Bucket: &bucket,
		Key:    &key,
	})
	if err != nil {
		return normalizeNotExistError(err)
	}
	totalBytes := aws.ToInt64(head.ContentLength)
	resumeOffset := existingFileSize(localPath, totalBytes)
	if resumeOffset >= totalBytes && totalBytes > 0 {
		return nil
	}
	if taskID != "" {
		var cancel context.CancelFunc
		ctx, cancel = context.WithCancel(ctx)
		startTransfer(taskID, "download", bucket, key, localPath, totalBytes, cancel)
		defer func() { finishTransfer(taskID, err) }()
	}

	input := &s3.GetObjectInput{
		Bucket: &bucket,
		Key:    &key,
	}
	if resumeOffset > 0 {
		input.Range = aws.String(fmt.Sprintf("bytes=%d-", resumeOffset))
	}
	out, err := client.GetObject(ctx, input)
	if err != nil {
		return normalizeNotExistError(err)
	}
	defer out.Body.Close()

	writeOffset := resolvedResumeOffset(resumeOffset, out.ContentRange)
	if taskID != "" && writeOffset > 0 {
		advanceTransfer(taskID, writeOffset)
	}

	f, err := openDownloadTarget(localPath, writeOffset)
	if err != nil {
		return err
	}
	defer f.Close()

	body := io.Reader(out.Body)
	if taskID != "" {
		body = &contextReader{
			ctx:    ctx,
			reader: out.Body,
			onRead: func(n int) { advanceTransfer(taskID, int64(n)) },
		}
	}

	_, err = io.Copy(f, body)
	return err
}

func existingFileSize(localPath string, totalBytes int64) int64 {
	if info, statErr := os.Stat(localPath); statErr == nil && !info.IsDir() {
		resumeOffset := info.Size()
		if resumeOffset > totalBytes {
			_ = os.Remove(localPath)
			return 0
		}
		return resumeOffset
	}
	return 0
}

func resolvedResumeOffset(resumeOffset int64, contentRange *string) int64 {
	if resumeOffset <= 0 {
		return 0
	}
	if contentRange == nil {
		return 0
	}
	expected := fmt.Sprintf("bytes %d-", resumeOffset)
	if strings.HasPrefix(strings.TrimSpace(*contentRange), expected) {
		return resumeOffset
	}
	return 0
}

func openDownloadTarget(localPath string, writeOffset int64) (*os.File, error) {
	openFlags := os.O_CREATE | os.O_WRONLY
	if writeOffset == 0 {
		openFlags |= os.O_TRUNC
	}
	f, err := os.OpenFile(localPath, openFlags, 0o644)
	if err != nil {
		return nil, err
	}
	if writeOffset > 0 {
		if _, err := f.Seek(writeOffset, io.SeekStart); err != nil {
			_ = f.Close()
			return nil, err
		}
	}
	return f, nil
}

// GetPresignedURL generates a presigned download URL.
func GetPresignedURL(cfg storageconfig.RemoteStorageConfig, bucket, key string, expiresSec int) (string, error) {
	client := NewClient(cfg)
	presigner := s3.NewPresignClient(client)
	duration := time.Duration(expiresSec) * time.Second
	if expiresSec <= 0 {
		duration = 15 * time.Minute
	}
	req, err := presigner.PresignGetObject(Ctx(), &s3.GetObjectInput{
		Bucket: &bucket, Key: &key,
	}, func(opts *s3.PresignOptions) { opts.Expires = duration })
	if err != nil {
		return "", err
	}
	return req.URL, nil
}
