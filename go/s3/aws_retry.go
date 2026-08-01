// AWS SDK client configuration shared by the S3 client factory.
package s3

import (
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/aws/retry"
)

// Extra attempts for single-object calls such as CopyObject/DeleteObject. S3
// returns no side effects for a retried copy, so transient 5xx/HTML gateway
// responses from S3-compatible endpoints are absorbed here instead of failing
// the whole multi-object operation after the SDK's default three attempts.
const singleObjectCallMaxAttempts = 5

// singleObjectCallMaxBackoff caps the retry wait so a stuck gateway cannot park
// a delete/move task for minutes.
const singleObjectCallMaxBackoff = 15 * time.Second

// newSingleObjectRetryer builds the standard-mode retryer used for low-level
// single-object calls. Retryable HTTP classes (5xx, throttling, connection
// resets) stay governed by the SDK's standard retry rules.
func newSingleObjectRetryer() aws.Retryer {
	return retry.NewStandard(func(options *retry.StandardOptions) {
		options.MaxAttempts = singleObjectCallMaxAttempts
		options.MaxBackoff = singleObjectCallMaxBackoff
	})
}

// newListBucketsRetryer makes ListBuckets fail fast on connectivity errors.
// The AWS SDK default retries up to 3 times; for an unreachable endpoint each
// attempt waits on the 3s dial timeout, so 3 attempts burn the whole 8s
// bucketListTimeout before surfacing the error. ListBuckets is an account-level
// connectivity probe behind the singleflight + negative cache, so one attempt
// (no retry) lets the failure reach the negative cache promptly.
func newListBucketsRetryer() aws.Retryer {
	return retry.NewStandard(func(options *retry.StandardOptions) {
		options.MaxAttempts = 1
	})
}

