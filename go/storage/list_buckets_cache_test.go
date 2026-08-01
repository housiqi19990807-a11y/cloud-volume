// List-buckets dedup + negative cache tests pin the fast-fail behavior that
// keeps one unreachable account from blocking the multi-account load.
package storage

import (
	"context"
	"errors"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	storageconfig "remote-storage/go/config"
)

// sync is still used by the WaitGroup in the concurrent-collapser test below.

// countingListFn returns a listFn that counts calls and simulates a slow or
// failing upstream without dialing for real.
func countingListFn(calls *int32, delay time.Duration, err error) func(context.Context) ([]BucketInfo, error) {
	return func(ctx context.Context) ([]BucketInfo, error) {
		atomic.AddInt32(calls, 1)
		if delay > 0 {
			select {
			case <-time.After(delay):
			case <-ctx.Done():
				return nil, ctx.Err()
			}
		}
		if err != nil {
			return nil, err
		}
		return []BucketInfo{{Name: "bucket-x"}}, nil
	}
}

func dedupTestConfig(tag string) storageconfig.RemoteStorageConfig {
	return storageconfig.RemoteStorageConfig{
		StorageType: storageconfig.StorageTypeS3,
		Endpoint:    "http://" + tag,
		AccessKeyID: "ak-" + tag,
	}
}

// TestListBucketsDedupCollapsesConcurrentCallers is the core fix: N concurrent
// callers for the same account share ONE upstream call instead of each dialing.
func TestListBucketsDedupCollapsesConcurrentCallers(t *testing.T) {
	var calls int32
	cfg := dedupTestConfig("collapse")
	forgetListBucketsFailure(bucketListIdentityKey(cfg))
	listFn := countingListFn(&calls, 50*time.Millisecond, nil)

	const callers = 5
	var wg sync.WaitGroup
	start := make(chan struct{})
	wg.Add(callers)
	results := make([][]BucketInfo, callers)
	errs := make([]error, callers)
	for i := 0; i < callers; i++ {
		i := i
		go func() {
			defer wg.Done()
			<-start
			results[i], errs[i] = ListBucketsDedup(context.Background(), cfg, listFn, false)
		}()
	}
	close(start)
	wg.Wait()

	if got := atomic.LoadInt32(&calls); got != 1 {
		t.Fatalf("expected 1 upstream call for %d concurrent callers, got %d", callers, got)
	}
	for i := 0; i < callers; i++ {
		if errs[i] != nil {
			t.Fatalf("caller %d errored: %v", i, errs[i])
		}
		if len(results[i]) != 1 || results[i][0].Name != "bucket-x" {
			t.Fatalf("caller %d got %+v", i, results[i])
		}
	}
}

// TestListBucketsDedupReturnsCachedFailureImmediately pins the fast-fail path:
// after a failure, subsequent callers get the cached error instantly, without
// re-dialing the unreachable upstream.
func TestListBucketsDedupReturnsCachedFailureImmediately(t *testing.T) {
	var calls int32
	cfg := dedupTestConfig("negcache")
	forgetListBucketsFailure(bucketListIdentityKey(cfg))
	listFn := countingListFn(&calls, 0, errors.New("upstream unreachable"))

	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()

	// First call dials and fails (recorded in the negative cache).
	if _, err := ListBucketsDedup(ctx, cfg, listFn, false); err == nil {
		t.Fatal("expected first call to fail")
	}
	if got := atomic.LoadInt32(&calls); got != 1 {
		t.Fatalf("expected 1 call after first failure, got %d", got)
	}

	// Second call must return the cached failure immediately and NOT dial again.
	start := time.Now()
	if _, err := ListBucketsDedup(ctx, cfg, listFn, false); err == nil {
		t.Fatal("expected cached failure on second call")
	}
	elapsed := time.Since(start)
	if elapsed > 50*time.Millisecond {
		t.Fatalf("cached failure took %v; should be near-instant", elapsed)
	}
	if got := atomic.LoadInt32(&calls); got != 1 {
		t.Fatalf("expected cached failure to skip the dial (1 call), got %d", got)
	}
}

// TestListBucketsDedupSuccessClearsNegativeCache ensures an explicit refresh
// (force) bypasses the negative cache and, on success, clears it so the next
// ordinary reload is not stuck returning the stale error. This models the user
// fixing connectivity and clicking "refresh".
func TestListBucketsDedupSuccessClearsNegativeCache(t *testing.T) {
	cfg := dedupTestConfig("clear")
	forgetListBucketsFailure(bucketListIdentityKey(cfg))

	var failCalls int32
	if _, err := ListBucketsDedup(
		context.Background(),
		cfg,
		countingListFn(&failCalls, 0, errors.New("down")),
		false,
	); err == nil {
		t.Fatal("expected first call to fail")
	}

	// A non-forced call would still hit the negative cache; the user must be
	// able to force a retry once they have fixed the account.
	if _, err := ListBucketsDedup(
		context.Background(),
		cfg,
		countingListFn(&failCalls, 0, nil),
		false,
	); err == nil {
		t.Fatal("expected non-forced call to still hit the negative cache")
	}

	// Now the account recovers. An explicit refresh (force) must bypass the
	// negative cache, dial again, and clear the entry on success.
	var healthyCalls int32
	got, err := ListBucketsDedup(
		context.Background(),
		cfg,
		countingListFn(&healthyCalls, 0, nil),
		true,
	)
	if err != nil {
		t.Fatalf("expected success after forced retry, got %v", err)
	}
	if len(got) != 1 || got[0].Name != "bucket-x" {
		t.Fatalf("unexpected buckets: %+v", got)
	}

	// A follow-up non-forced call must now dial again (cache cleared), not
	// return the stale error.
	var followCalls int32
	if _, err := ListBucketsDedup(
		context.Background(),
		cfg,
		countingListFn(&followCalls, 0, nil),
		false,
	); err != nil {
		t.Fatalf("follow-up after cleared cache failed: %v", err)
	}
	if got := atomic.LoadInt32(&followCalls); got != 1 {
		t.Fatalf("expected follow-up to dial after cache clear, got %d calls", got)
	}
}

// TestListBucketsDedupIsolatesAccounts confirms two different accounts do not
// share a flight or a negative cache entry.
func TestListBucketsDedupIsolatesAccounts(t *testing.T) {
	cfgA := dedupTestConfig("iso-a")
	cfgB := dedupTestConfig("iso-b")
	forgetListBucketsFailure(bucketListIdentityKey(cfgA))
	forgetListBucketsFailure(bucketListIdentityKey(cfgB))

	var callsA int32
	if _, err := ListBucketsDedup(
		context.Background(),
		cfgA,
		countingListFn(&callsA, 0, errors.New("a down")),
		false,
	); err == nil {
		t.Fatal("expected account A to fail")
	}
	// Account B must not inherit A's failure.
	var callsB int32
	if _, err := ListBucketsDedup(
		context.Background(),
		cfgB,
		countingListFn(&callsB, 0, nil),
		false,
	); err != nil {
		t.Fatalf("account B failed because of account A: %v", err)
	}
}
