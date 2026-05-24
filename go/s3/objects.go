// Object listing, upload, and download operations.

package s3

import (
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

// ListObjects returns objects and common prefixes under a bucket + prefix.
func ListObjects(cfg storageconfig.RemoteStorageConfig, bucket, prefix string) ([]ObjectInfo, error) {
	client := NewClient(cfg)

	if prefix != "" && !strings.HasSuffix(prefix, "/") {
		prefix += "/"
	}

	out, err := client.ListObjectsV2(Ctx(), &s3.ListObjectsV2Input{
		Bucket:    &bucket,
		Prefix:    &prefix,
		Delimiter: aws.String("/"),
	})
	if err != nil {
		return nil, err
	}

	var result []ObjectInfo
	for _, cp := range out.CommonPrefixes {
		result = append(result, ObjectInfo{Key: *cp.Prefix, IsDir: true})
	}
	for _, obj := range out.Contents {
		if obj.Key != nil && *obj.Key == prefix {
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

// UploadFile uploads a local file to the given bucket + key.
func UploadFile(cfg storageconfig.RemoteStorageConfig, bucket, key, localPath, taskID string) error {
	client := NewClient(cfg)
	f, err := os.Open(localPath)
	if err != nil {
		return fmt.Errorf("open local file: %w", err)
	}
	defer f.Close()
	info, statErr := f.Stat()
	if statErr == nil && taskID != "" {
		startTransfer(taskID, "upload", bucket, key, localPath, info.Size())
		defer func() { finishTransfer(taskID, err) }()
	}

	body := io.Reader(f)
	if taskID != "" {
		body = &countingReader{
			reader: f,
			onRead: func(n int) { advanceTransfer(taskID, int64(n)) },
		}
	}
	_, err = client.PutObject(Ctx(), &s3.PutObjectInput{
		Bucket: &bucket, Key: &key, Body: body,
	})
	return err
}

// DownloadFile downloads an object to a local path.
func DownloadFile(cfg storageconfig.RemoteStorageConfig, bucket, key, localPath, taskID string) error {
	client := NewClient(cfg)
	if err := os.MkdirAll(filepath.Dir(localPath), 0o755); err != nil {
		return err
	}

	out, err := client.GetObject(Ctx(), &s3.GetObjectInput{
		Bucket: &bucket, Key: &key,
	})
	if err != nil {
		return err
	}
	defer out.Body.Close()
	if taskID != "" {
		startTransfer(
			taskID,
			"download",
			bucket,
			key,
			localPath,
			aws.ToInt64(out.ContentLength),
		)
		defer func() { finishTransfer(taskID, err) }()
	}

	f, err := os.Create(localPath)
	if err != nil {
		return err
	}
	defer f.Close()

	body := io.Reader(out.Body)
	if taskID != "" {
		body = &countingReader{
			reader: out.Body,
			onRead: func(n int) { advanceTransfer(taskID, int64(n)) },
		}
	}

	_, err = io.Copy(f, body)
	return err
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
