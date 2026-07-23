// Package s3 provides S3-compatible storage operations for the remote-storage app.
package s3

import (
	"context"
	"sync"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	awsCreds "github.com/aws/aws-sdk-go-v2/credentials"
	"github.com/aws/aws-sdk-go-v2/service/s3"

	storageconfig "remote-storage/go/config"
)

const activeEndpointCacheTTL = time.Minute

type activeEndpointCacheEntry struct {
	endpoint  string
	expiresAt time.Time
}

var (
	activeEndpointCacheMu sync.RWMutex
	activeEndpointCache   = make(map[string]activeEndpointCacheEntry)
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

// NewClient resolves the current best S3 endpoint through the failover SDK so
// every existing S3 operation benefits from JWanFS gateway discovery. The
// returned AWS client remains a single-request client; operations needing
// retry-across-upstream semantics can retain a FailoverClient and call
// DoWithFallback directly.
func NewClient(cfg storageconfig.RemoteStorageConfig) *s3.Client {
	if endpoint, ok := cachedActiveEndpoint(cfg); ok {
		return newSingleEndpointClient(cfg, endpoint)
	}
	pool := NewFailoverClient(cfg)
	defer pool.Stop()
	endpoint := pool.DefaultServer()
	if endpoint == "" {
		endpoint = cfg.Endpoint
	}
	cacheActiveEndpoint(cfg, endpoint)
	return newSingleEndpointClient(cfg, endpoint)
}

// cachedActiveEndpoint avoids rediscovering JWanFS gateways for every object
// request while allowing the failover SDK to refresh the active endpoint soon.
func cachedActiveEndpoint(cfg storageconfig.RemoteStorageConfig) (string, bool) {
	key := activeEndpointCacheKey(cfg)
	activeEndpointCacheMu.RLock()
	entry, ok := activeEndpointCache[key]
	activeEndpointCacheMu.RUnlock()
	return entry.endpoint, ok && time.Now().Before(entry.expiresAt)
}

func cacheActiveEndpoint(cfg storageconfig.RemoteStorageConfig, endpoint string) {
	if endpoint == "" {
		return
	}
	activeEndpointCacheMu.Lock()
	activeEndpointCache[activeEndpointCacheKey(cfg)] = activeEndpointCacheEntry{
		endpoint:  endpoint,
		expiresAt: time.Now().Add(activeEndpointCacheTTL),
	}
	activeEndpointCacheMu.Unlock()
}

func activeEndpointCacheKey(cfg storageconfig.RemoteStorageConfig) string {
	normalized := cfg.Normalized()
	return normalized.Endpoint + "|" + normalized.AccessKeyID + "|" + normalized.JWanFSGatewayMode
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
