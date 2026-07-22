// JWanFS gateway integration for the S3 storage backend.
//
// When the endpoint is detected (or forced) to be a JWanFS file gateway, the
// FGW routes provide server-side atomic operations that are cheaper and safer
// than the generic S3 copy+delete emulation:
//   - BucketQuota: FGW bucket-quota route
//   - MoveObject / RenameObject: FGW file-move route (single server call)
//
// For generic S3 endpoints every method gracefully falls back so the s3Backend
// still satisfies BucketQuotaProvider and the Backend interface without changes.
package storage

import (
	"context"
	"fmt"
	"strings"
	"time"

	jwanfs "remote-storage/go/jwanfs"
)

// jwanfsCallTimeout bounds FGW calls so a slow/unreachable gateway does not
// stall bucket-capacity resolution or move operations.
const jwanfsCallTimeout = 8 * time.Second

// jwanfsClient builds a transient JWanFS client for the configured endpoint.
// Returns nil when the endpoint is not a JWanFS gateway or the client cannot
// be constructed; callers must check for nil.
func (b s3Backend) jwanfsClient(ctx context.Context) *jwanfs.Client {
	cfg := b.cfg.Normalized()
	if !jwanfs.IsJWanFSGateway(ctx, cfg, jwanfs.ParseDetectionMode(cfg.JWanFSGatewayMode)) {
		return nil
	}
	client, err := jwanfs.NewClient(&jwanfs.ClientOption{
		Ak:      cfg.AccessKeyID,
		Sk:      cfg.SecretAccessKey,
		Servers: []string{cfg.Endpoint},
	})
	if err != nil {
		return nil
	}
	return client
}

// BucketQuota implements BucketQuotaProvider. When the endpoint is a JWanFS
// gateway, it queries the FGW bucket-quota route. For generic S3 endpoints it
// returns a quota-less BucketInfo so callers can gracefully skip capacity display.
func (b s3Backend) BucketQuota(ctx context.Context, bucket string) (BucketInfo, error) {
	client := b.jwanfsClient(ctx)
	if client == nil {
		return BucketInfo{Name: bucket}, nil
	}
	defer client.BalancerStop()

	baseCtx := context.Background()
	if ctx != nil {
		baseCtx = ctx
	}
	quotaCtx, cancel := context.WithTimeout(baseCtx, jwanfsCallTimeout)
	defer cancel()

	res, err := client.BucketQuota(quotaCtx, bucket)
	if err != nil || res == nil {
		return BucketInfo{Name: bucket}, nil
	}

	return BucketInfo{
		Name:       bucket,
		QuotaBytes: res.Total,
		UsedBytes:  res.Used,
		QuotaKnown: res.Total > 0,
	}, nil
}

// tryJWanFSMoveObject attempts a server-side FGW file-move. It returns
// (true, nil) on success, (false, nil) when the endpoint is not a JWanFS
// gateway or the route is unavailable (caller should fall back to copy+delete),
// and (false, err) when the move was attempted but failed with a real error.
func (b s3Backend) tryJWanFSMoveObject(
	ctx context.Context,
	bucket, sourceKey, targetKey string,
) (bool, error) {
	client := b.jwanfsClient(ctx)
	if client == nil {
		return false, nil
	}
	defer client.BalancerStop()

	baseCtx := context.Background()
	if ctx != nil {
		baseCtx = ctx
	}
	moveCtx, cancel := context.WithTimeout(baseCtx, jwanfsCallTimeout)
	defer cancel()

	if err := client.MoveObject(moveCtx, bucket, sourceKey, targetKey); err != nil {
		// FGW route exists but the call failed — surface the real error.
		return false, fmt.Errorf("jwanfs move: %w", err)
	}
	return true, nil
}

// renamedTargetKey computes the full destination key for a rename operation.
// It replaces the last path segment of key with newName. For directories the
// trailing "/" is preserved. This mirrors the logic in
// s3ops.RenameObjectContext so the JWanFS fast path produces the same target
// key the generic fallback would.
func renamedTargetKey(key string, isDirectory bool, newName string) (string, error) {
	trimmedName := strings.Trim(strings.TrimSpace(newName), "/")
	if trimmedName == "" {
		return "", fmt.Errorf("new name is required")
	}
	if !isDirectory {
		index := strings.LastIndex(key, "/")
		if index < 0 {
			return trimmedName, nil
		}
		return key[:index+1] + trimmedName, nil
	}
	trimmed := strings.TrimSuffix(key, "/")
	index := strings.LastIndex(trimmed, "/")
	if index < 0 {
		return trimmedName + "/", nil
	}
	return trimmed[:index+1] + trimmedName + "/", nil
}
