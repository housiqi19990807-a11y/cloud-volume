// Package s3 provides S3-compatible storage operations for the remote-storage app.
package s3

import (
	"context"

	"github.com/aws/aws-sdk-go-v2/aws"
	awsCreds "github.com/aws/aws-sdk-go-v2/credentials"
	"github.com/aws/aws-sdk-go-v2/service/s3"

	storageconfig "remote-storage/go/config"
)

// NewClient creates an S3 client from the stored configuration.
func NewClient(cfg storageconfig.RemoteStorageConfig) *s3.Client {
	credProvider := awsCreds.NewStaticCredentialsProvider(
		cfg.AccessKeyID,
		cfg.SecretAccessKey,
		"",
	)

	opts := s3.Options{
		Credentials: credProvider,
		Region:      cfg.Region,
	}

	if cfg.Endpoint != "" {
		opts.BaseEndpoint = aws.String(cfg.Endpoint)
	}
	if cfg.UsePathStyle {
		opts.UsePathStyle = true
	}

	// Only override the HTTP client when the user explicitly chooses direct or
	// custom proxy. In system mode (default) and inherit mode (which is resolved
	// to a concrete mode by ResolveProxyConfig before reaching here) we let the
	// AWS SDK use its own default client, which already respects
	// HTTP_PROXY / HTTPS_PROXY / NO_PROXY via Go's net/http defaults.
	if cfg.ProxyMode == storageconfig.ProxyModeDirect ||
		cfg.ProxyMode == storageconfig.ProxyModeCustom {
		opts.HTTPClient = storageconfig.ProxyHTTPClient(cfg, 0)
	}

	return s3.New(opts)
}

// Ctx returns a default context for S3 operations.
func Ctx() context.Context {
	return context.Background()
}
