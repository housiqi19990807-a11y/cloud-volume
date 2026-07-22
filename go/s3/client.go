// Package s3 provides S3-compatible storage operations for the remote-storage app.
package s3

import (
	"context"

	"github.com/aws/aws-sdk-go-v2/aws"
	awsCreds "github.com/aws/aws-sdk-go-v2/credentials"
	"github.com/aws/aws-sdk-go-v2/service/s3"

	storageconfig "remote-storage/go/config"
)

// singleObjectCallOptions returns per-call options for low-level single-object
// APIs (CopyObject, HeadObject, DeleteObject, placeholder PutObject) inside
// multi-object sweeps. The wider retry budget keeps a flaky gateway from
// aborting a whole tree operation, without changing global client behavior for
// listing, uploads, or presigning.
func singleObjectCallOptions() []func(*s3.Options) {
	retryer := newSingleObjectRetryer()
	return []func(*s3.Options){
		func(options *s3.Options) {
			options.Retryer = retryer
		},
	}
}

// NewClient creates an S3 client bound to the configured endpoint. For
// multi-endpoint failover use NewFailoverClient; this entry point is kept for
// callers that only need a plain single-endpoint client (presigning, health
// checks, internal helpers that already manage their own failover).
func NewClient(cfg storageconfig.RemoteStorageConfig) *s3.Client {
	return newSingleEndpointClient(cfg, cfg.Endpoint)
}

// newSingleEndpointClient builds an aws-sdk-go-v2 S3 client pointing at one
// endpoint, applying credentials, region, path-style, and proxy settings from cfg.
func newSingleEndpointClient(cfg storageconfig.RemoteStorageConfig, endpoint string) *s3.Client {
	credProvider := awsCreds.NewStaticCredentialsProvider(
		cfg.AccessKeyID,
		cfg.SecretAccessKey,
		"",
	)

	opts := s3.Options{
		Credentials: credProvider,
		Region:      cfg.Region,
	}

	if endpoint != "" {
		opts.BaseEndpoint = aws.String(endpoint)
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
