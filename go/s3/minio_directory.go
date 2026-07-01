// MinIO-backed directory creation keeps zero-byte folder placeholders compatible
// with S3-compatible vendors that reject the AWS SDK's newer empty-object flow.
package s3

import (
	"bytes"
	"context"
	"fmt"
	"net/http"
	"net/url"
	"strings"

	"github.com/minio/minio-go/v7"
	"github.com/minio/minio-go/v7/pkg/credentials"

	storageconfig "remote-storage/go/config"
)

// CreateDirectory creates an empty prefix placeholder ending in "/".
func CreateDirectory(cfg storageconfig.RemoteStorageConfig, bucket, prefix, name string) error {
	return CreateDirectoryContext(Ctx(), cfg, bucket, prefix, name)
}

// CreateDirectoryContext creates an empty prefix placeholder with a caller context.
func CreateDirectoryContext(
	ctx context.Context,
	cfg storageconfig.RemoteStorageConfig,
	bucket,
	prefix,
	name string,
) error {
	client, err := NewMinioClient(cfg)
	if err != nil {
		return err
	}

	key, err := directoryKey(prefix, name)
	if err != nil {
		return err
	}

	_, err = client.PutObject(
		ctx,
		bucket,
		key,
		bytes.NewReader(nil),
		0,
		minio.PutObjectOptions{ContentType: "application/x-directory"},
	)
	return err
}

// NewMinioClient creates a narrow MinIO client for compatibility-sensitive flows.
func NewMinioClient(cfg storageconfig.RemoteStorageConfig) (*minio.Client, error) {
	endpoint, secure, err := normalizeMinioEndpoint(cfg.Endpoint)
	if err != nil {
		return nil, err
	}

	options := &minio.Options{
		Creds:  credentials.NewStaticV4(cfg.AccessKeyID, cfg.SecretAccessKey, ""),
		Region: strings.TrimSpace(cfg.Region),
		Secure: secure,
	}
	if cfg.UsePathStyle {
		options.BucketLookup = minio.BucketLookupPath
	}

	// Only override the HTTP transport when the user explicitly chooses direct
	// or custom proxy. In system mode (default) leave MinIO's built-in transport
	// intact so it uses the same net/http defaults as before the proxy feature.
	if cfg.ProxyMode == storageconfig.ProxyModeDirect ||
		cfg.ProxyMode == storageconfig.ProxyModeCustom {
		if ht, ok := storageconfig.ProxyTransport(cfg).(*http.Transport); ok {
			options.Transport = ht
		}
	}

	return minio.New(endpoint, options)
}

func directoryKey(prefix, name string) (string, error) {
	trimmedName := strings.Trim(strings.TrimSpace(name), "/")
	if trimmedName == "" {
		return "", fmt.Errorf("directory name is required")
	}
	if prefix != "" && !strings.HasSuffix(prefix, "/") {
		prefix += "/"
	}
	return prefix + trimmedName + "/", nil
}

func normalizeMinioEndpoint(raw string) (string, bool, error) {
	trimmed := strings.TrimSpace(raw)
	if trimmed == "" {
		return "", false, fmt.Errorf("endpoint is required")
	}

	if !strings.Contains(trimmed, "://") {
		return strings.TrimSuffix(trimmed, "/"), true, nil
	}

	parsed, err := url.Parse(trimmed)
	if err != nil {
		return "", false, fmt.Errorf("invalid endpoint %q: %w", raw, err)
	}
	if parsed.Host == "" {
		return "", false, fmt.Errorf("invalid endpoint %q", raw)
	}
	if parsed.Path != "" && parsed.Path != "/" {
		return "", false, fmt.Errorf("endpoint path is not supported for directory creation")
	}

	return parsed.Host, !strings.EqualFold(parsed.Scheme, "http"), nil
}
