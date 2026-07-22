// JWanFS gateway detection: determines whether a configured S3 endpoint is a
// JWanFS file gateway (and thus supports the extended FGW business APIs) by
// probing the auth-info FGW route. The result is cached so repeated lookups
// during a session are free.
package jwanfs

import (
	"context"
	"sync"
	"time"

	storageconfig "remote-storage/go/config"
)

// DetectionMode controls how JWanFS gateway capabilities are resolved.
type DetectionMode string

const (
	// DetectionAuto probes the auth-info FGW route once; if it returns a valid
	// FGWResp the endpoint is treated as JWanFS. On any error it is treated as
	// a generic S3 endpoint. This is the default.
	DetectionAuto DetectionMode = "auto"
	// DetectionForceOn skips probing and assumes the endpoint is JWanFS.
	DetectionForceOn DetectionMode = "jwanfs"
	// DetectionForceOff skips probing and assumes a generic S3 endpoint.
	DetectionForceOff DetectionMode = "generic_s3"
)

// detectionResult caches the outcome of a probe so it only runs once per
// endpoint+credentials within the cache TTL.
type detectionResult struct {
	isJWanFS  bool
	expiresAt time.Time
}

var (
	detectionMu      sync.RWMutex
	detectionCache   = make(map[string]detectionResult)
	detectionCacheTTL = 10 * time.Minute
)

// cacheKey derives a stable cache key from config + mode.
func detectionCacheKey(cfg storageconfig.RemoteStorageConfig, mode DetectionMode) string {
	return cfg.Endpoint + "|" + cfg.AccessKeyID + "|" + string(mode)
}

// IsJWanFSGateway reports whether the endpoint referenced by cfg is a JWanFS
// file gateway. The result is cached for detectionCacheTTL.
//
// Resolution order:
//  1. mode == DetectionForceOn  → true
//  2. mode == DetectionForceOff → false
//  3. mode == DetectionAuto     → probe auth-info; success = true
//
// Non-S3 storage types (WebDAV, BaiduPan) always return false.
func IsJWanFSGateway(ctx context.Context, cfg storageconfig.RemoteStorageConfig, mode DetectionMode) bool {
	if cfg.Normalized().StorageType != storageconfig.StorageTypeS3 {
		return false
	}

	switch mode {
	case DetectionForceOn:
		return true
	case DetectionForceOff:
		return false
	default:
		// DetectionAuto: fall through to probe.
	}

	key := detectionCacheKey(cfg, mode)

	detectionMu.RLock()
	if cached, ok := detectionCache[key]; ok && time.Now().Before(cached.expiresAt) {
		detectionMu.RUnlock()
		return cached.isJWanFS
	}
	detectionMu.RUnlock()

	normalized := cfg.Normalized()
	isJWanFS := probeJWanFSGateway(ctx, normalized)

	detectionMu.Lock()
	detectionCache[key] = detectionResult{
		isJWanFS:  isJWanFS,
		expiresAt: time.Now().Add(detectionCacheTTL),
	}
	detectionMu.Unlock()

	return isJWanFS
}

// probeJWanFSGateway builds a transient JWanFS client and calls AuthInfo.
// A successful response means the endpoint speaks the FGW protocol.
func probeJWanFSGateway(ctx context.Context, cfg storageconfig.RemoteStorageConfig) bool {
	client, err := NewClient(&ClientOption{
		Ak:      cfg.AccessKeyID,
		Sk:      cfg.SecretAccessKey,
		Servers: []string{cfg.Endpoint},
	})
	if err != nil {
		return false
	}
	defer client.balancer.Stop()

	if _, err := client.AuthInfo(ctx); err != nil {
		return false
	}
	return true
}

// InvalidateDetectionCache clears the cached detection result for cfg, forcing
// the next IsJWanFSGateway call to re-probe. Call this when the user changes
// endpoint or credentials.
func InvalidateDetectionCache(cfg storageconfig.RemoteStorageConfig) {
	detectionMu.Lock()
	defer detectionMu.Unlock()
	// Clear all entries for this endpoint regardless of mode.
	prefix := cfg.Endpoint + "|"
	for key := range detectionCache {
		if len(key) >= len(prefix) && key[:len(prefix)] == prefix {
			delete(detectionCache, key)
		}
	}
}

// ParseDetectionMode normalizes a raw string into a DetectionMode, defaulting
// to DetectionAuto for unrecognized values (including empty).
func ParseDetectionMode(raw string) DetectionMode {
	switch DetectionMode(raw) {
	case DetectionForceOn:
		return DetectionForceOn
	case DetectionForceOff:
		return DetectionForceOff
	default:
		return DetectionAuto
	}
}
