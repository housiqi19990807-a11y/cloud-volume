// Negative cache + singleflight for the bucket-list path.
//
// A single unreachable S3 endpoint can otherwise stall the multi-account
// bucket load for ~15-45s: the AWS SDK retries, multiple concurrent callers
// (file manager, global trash, quota prefetch) each dial the same dead
// endpoint, and every page reload re-dials accounts that just failed.
//
// This file collapses those cases:
//   - singleflight deduplicates concurrent ListBuckets calls for the same
//     connection identity so only one dial happens at a time;
//   - a short negative cache returns the previous failure immediately for
//     listBucketsNegativeCacheTTL, so a known-bad account does not block the
//     UI again until the user has had a chance to reconfigure it.
package storage

import (
	"context"
	"crypto/sha256"
	"encoding/json"
	"log"
	"sync"
	"time"

	storageconfig "remote-storage/go/config"
)

// listBucketsNegativeCacheTTL bounds how long a failed ListBuckets is remembered.
// It is intentionally short: long enough to stop repeated page loads from
// re-dialing a dead account within one session, short enough that the user
// fixing their network/credentials and reloading (or an explicit refresh)
// actually retries.
const listBucketsNegativeCacheTTL = 20 * time.Second

// listBucketsDialCooldown bounds singleflight key reuse after a call completes,
// so a second burst of callers right after the first finishes still deduplicates
// instead of starting a fresh dial while the negative cache is being written.
type listBucketsNegativeEntry struct {
	err       error
	expiresAt time.Time
}

var listBucketsCooldown = struct {
	sync.Mutex
	groups map[[32]byte]*listBucketsFlight
}{
	groups: make(map[[32]byte]*listBucketsFlight),
}

var listBucketsNegativeCache = struct {
	sync.RWMutex
	entries map[[32]byte]listBucketsNegativeEntry
}{
	entries: make(map[[32]byte]listBucketsNegativeEntry),
}

// listBucketsFlight tracks one in-flight ListBuckets call so concurrent callers
// share its result instead of each dialing the upstream.
type listBucketsFlight struct {
	done   chan struct{}
	result []BucketInfo
	err    error
}

// ListBucketsDedup wraps a ListBuckets call (passed as listFn so callers can
// inject any backend) with singleflight + a short negative cache keyed on
// connection identity. Concurrent callers for the same cfg share one upstream
// call; a recent failure is returned immediately without re-dialing, so an
// unreachable account cannot repeatedly block the UI. When force is true the
// negative cache is skipped so an explicit user refresh can retry a known-bad
// account immediately.
func ListBucketsDedup(
	ctx context.Context,
	cfg storageconfig.RemoteStorageConfig,
	listFn func(context.Context) ([]BucketInfo, error),
	force bool,
) ([]BucketInfo, error) {
	key := bucketListIdentityKey(cfg)

	// Fast path: a recent failure is returned immediately. This is what stops a
	// known-bad account from re-blocking every page load and every concurrent
	// caller while the user has not yet reconfigured it. An explicit refresh
	// (force) bypasses this so the user can retry after fixing connectivity.
	if !force {
		if entry, ok := lookupListBucketsNegative(key); ok {
			log.Printf("[storage/list-cache] negative-hit key=%x", key[:6])
			return nil, entry.err
		}
	}

	// Singleflight: if another goroutine is already listing this account, wait
	// for it and reuse the result. This collapses the N concurrent list_buckets
	// calls the UI fans out into one upstream dial.
	leader, follower := acquireListBucketsFlight(key)
	if leader != nil {
		// We are the leader; perform the call, then publish the result.
		result, err := listFn(ctx)
		leader.result, leader.err = result, err
		close(leader.done)
		releaseListBucketsFlight(key)
		if err != nil {
			rememberListBucketsFailure(key, err)
		} else {
			// A success clears any stale negative entry so the next reload is fast.
			forgetListBucketsFailure(key)
		}
		return result, err
	}

	// Follower: wait for the leader. The leader's ctx governs the dial; a
	// follower's own ctx still bounds how long it waits for that result.
	select {
	case <-follower.done:
		return follower.result, follower.err
	case <-ctx.Done():
		return nil, ctx.Err()
	}
}

// acquireListBucketsFlight claims leadership for key. Exactly one of the
// returned flights is non-nil: the leader performs the call (then calls
// releaseListBucketsFlight), followers wait on the returned follower flight.
func acquireListBucketsFlight(key [32]byte) (leader, follower *listBucketsFlight) {
	listBucketsCooldown.Lock()
	defer listBucketsCooldown.Unlock()
	if existing, ok := listBucketsCooldown.groups[key]; ok {
		return nil, existing // caller becomes a follower of the existing flight
	}
	flight := &listBucketsFlight{done: make(chan struct{})}
	listBucketsCooldown.groups[key] = flight
	return flight, nil
}

func releaseListBucketsFlight(key [32]byte) {
	listBucketsCooldown.Lock()
	delete(listBucketsCooldown.groups, key)
	listBucketsCooldown.Unlock()
}

func lookupListBucketsNegative(key [32]byte) (listBucketsNegativeEntry, bool) {
	listBucketsNegativeCache.RLock()
	entry, ok := listBucketsNegativeCache.entries[key]
	listBucketsNegativeCache.RUnlock()
	if !ok || time.Now().After(entry.expiresAt) {
		return listBucketsNegativeEntry{}, false
	}
	return entry, true
}

func rememberListBucketsFailure(key [32]byte, err error) {
	listBucketsNegativeCache.Lock()
	listBucketsNegativeCache.entries[key] = listBucketsNegativeEntry{
		err:       err,
		expiresAt: time.Now().Add(listBucketsNegativeCacheTTL),
	}
	listBucketsNegativeCache.Unlock()
}

func forgetListBucketsFailure(key [32]byte) {
	listBucketsNegativeCache.Lock()
	delete(listBucketsNegativeCache.entries, key)
	listBucketsNegativeCache.Unlock()
}

// bucketListIdentityKey hashes the connection-identity fields that determine
// which upstream an account talks to. It deliberately mirrors
// bucketQuotaCacheKey's identity subset (storage type, endpoint, credentials,
// provider mode, proxy) but omits bucket/presentation fields, because
// ListBuckets is account-scoped, not bucket-scoped.
func bucketListIdentityKey(cfg storageconfig.RemoteStorageConfig) [32]byte {
	normalized := cfg.Normalized()
	payload, _ := json.Marshal(struct {
		StorageType     string `json:"storageType"`
		ProviderType    string `json:"providerType"`
		Endpoint        string `json:"endpoint"`
		Region          string `json:"region"`
		AccessKeyID     string `json:"accessKeyId"`
		SecretAccessKey string `json:"secretAccessKey"`
		WebDAVUsername  string `json:"webdavUsername"`
		WebDAVPassword  string `json:"webdavPassword"`
		FTPUsername     string `json:"ftpUsername"`
		FTPPassword     string `json:"ftpPassword"`
		FTPPort         int    `json:"ftpPort"`
		FTPAnonymous    bool   `json:"ftpAnonymous"`
		UsePathStyle    bool   `json:"usePathStyle"`
		JWanMode        string `json:"jwanMode"`
		ProxyMode       string `json:"proxyMode"`
		ProxyType       string `json:"proxyType"`
		ProxyHost       string `json:"proxyHost"`
		ProxyPort       string `json:"proxyPort"`
		ProxyUsername   string `json:"proxyUsername"`
		ProxyPassword   string `json:"proxyPassword"`
	}{
		StorageType: normalized.StorageType, ProviderType: normalized.ProviderType,
		Endpoint: normalized.Endpoint, Region: normalized.Region,
		AccessKeyID: normalized.AccessKeyID, SecretAccessKey: normalized.SecretAccessKey,
		WebDAVUsername: normalized.WebDAVUsername, WebDAVPassword: normalized.WebDAVPassword,
		FTPUsername: normalized.FTPUsername, FTPPassword: normalized.FTPPassword,
		FTPPort: normalized.FTPPort, FTPAnonymous: normalized.FTPAnonymous,
		UsePathStyle: normalized.UsePathStyle, JWanMode: normalized.JWanFSGatewayMode,
		ProxyMode: normalized.ProxyMode, ProxyType: normalized.ProxyType,
		ProxyHost: normalized.ProxyHost, ProxyPort: normalized.ProxyPort,
		ProxyUsername: normalized.ProxyUsername, ProxyPassword: normalized.ProxyPassword,
	})
	return sha256.Sum256(payload)
}
