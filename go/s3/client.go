// Package s3 provides S3-compatible storage operations for the remote-storage app.
package s3

import (
	"context"
	"net/http"

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

	// Inject global proxy settings into the S3 HTTP transport.
	opts.HTTPClient = &http.Client{Transport: storageconfig.ProxyTransport(cfg)}

	return s3.New(opts)
}

// Ctx returns a default context for S3 operations.
func Ctx() context.Context {
	return context.Background()
}
