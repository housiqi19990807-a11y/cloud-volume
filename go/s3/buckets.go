// Bucket listing operations.

package s3

import (
	"context"
	"log"
	"time"

	"github.com/aws/aws-sdk-go-v2/service/s3"

	storageconfig "remote-storage/go/config"
)

// bucketListTimeout bounds a single ListBuckets call. It is intentionally
// shorter than the bridge list_buckets timeout so an unreachable endpoint
// fails fast and the bridge's negative cache can record the failure before the
// UI's per-account timeout fires. Combined with singleflight dedup, one bad
// account surfaces in ~8s instead of stalling the load for 15-45s.
const bucketListTimeout = 8 * time.Second

// BucketInfo holds bucket metadata returned to the Flutter layer.
type BucketInfo struct {
	Name       string `json:"name"`
	QuotaBytes int64  `json:"quotaBytes,omitempty"`
	UsedBytes  int64  `json:"usedBytes,omitempty"`
	QuotaKnown bool   `json:"quotaKnown,omitempty"`
}

// ListBuckets returns all buckets accessible by the configured credentials.
func ListBuckets(cfg storageconfig.RemoteStorageConfig) ([]BucketInfo, error) {
	client := NewClient(cfg)
	ctx, cancel := context.WithTimeout(Ctx(), bucketListTimeout)
	defer cancel()
	startedAt := time.Now()
	log.Printf("[s3/buckets] start")
	out, err := client.ListBuckets(ctx, &s3.ListBucketsInput{})
	if err != nil {
		log.Printf("[s3/buckets] error duration=%s err=%v", time.Since(startedAt).Round(time.Millisecond), err)
		return nil, err
	}

	var result []BucketInfo
	for _, b := range out.Buckets {
		result = append(result, BucketInfo{Name: *b.Name})
	}
	if result == nil {
		result = []BucketInfo{}
	}
	log.Printf("[s3/buckets] done duration=%s count=%d", time.Since(startedAt).Round(time.Millisecond), len(result))
	return result, nil
}
