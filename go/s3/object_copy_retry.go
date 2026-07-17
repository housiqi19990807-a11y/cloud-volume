// Resilient single-object helpers absorb transient per-object failures during
// copy/move/delete sweeps so one flaky object does not abort the whole tree.
package s3

import (
	"context"
	"errors"
	"strings"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/service/s3"
	"github.com/aws/smithy-go"
)

// Extra attempts for a single copy/delete that keeps failing with non-retryable
// errors. Some S3-compatible vendors return intermittent 4xx (for example a
// malformed InvalidArgument on CopyObject) even though a later attempt succeeds,
// so plan execution gives those a few spaced chances before giving up.
const singleObjectSweepExtraAttempts = 3

// singleObjectSweepRetryDelay is the fixed wait between sweep retries. It is a
// variable so tests can shrink it.
var singleObjectSweepRetryDelay = 2 * time.Second

// copyObjectResilient performs one CopyObject with per-call retries for
// non-retryable vendor glitches on top of the client's built-in retryer.
func copyObjectResilient(
	ctx context.Context,
	client *s3.Client,
	bucket string,
	sourceKey string,
	targetKey string,
) error {
	copySource := encodeCopySource(bucket, sourceKey)
	return runSingleObjectSweep(ctx, func(callCtx context.Context) error {
		_, err := client.CopyObject(callCtx, &s3.CopyObjectInput{
			Bucket:     &bucket,
			Key:        aws.String(targetKey),
			CopySource: aws.String(copySource),
		}, singleObjectCallOptions()...)
		return err
	})
}

// putDirectoryPlaceholderResilient is the retrying counterpart of
// putDirectoryPlaceholder used by multi-object copy sweeps.
func putDirectoryPlaceholderResilient(
	ctx context.Context,
	client *s3.Client,
	bucket string,
	key string,
) error {
	return runSingleObjectSweep(ctx, func(callCtx context.Context) error {
		return putDirectoryPlaceholder(callCtx, client, bucket, key)
	})
}

// headObjectResilient retries a HeadObject used for transfer progress sizing.
func headObjectResilient(
	ctx context.Context,
	client *s3.Client,
	bucket string,
	key string,
) (*s3.HeadObjectOutput, error) {
	var output *s3.HeadObjectOutput
	err := runSingleObjectSweep(ctx, func(callCtx context.Context) error {
		head, err := client.HeadObject(callCtx, &s3.HeadObjectInput{
			Bucket: &bucket,
			Key:    aws.String(key),
		}, singleObjectCallOptions()...)
		if err != nil {
			return err
		}
		output = head
		return nil
	})
	return output, err
}

// deleteObjectKeyResilient deletes one key with sweep retries.
func deleteObjectKeyResilient(
	ctx context.Context,
	client *s3.Client,
	bucket string,
	key string,
) error {
	return runSingleObjectSweep(ctx, func(callCtx context.Context) error {
		return deleteObjectKey(callCtx, client, bucket, key)
	})
}

// runSingleObjectSweep retries a single-object call a few times when the error
// is not one the SDK retryer handles (typically vendor 4xx flakiness). Retryable
// errors already exhausted the client's retryer, so they bubble up immediately.
func runSingleObjectSweep(ctx context.Context, call func(context.Context) error) error {
	var err error
	for attempt := 0; attempt <= singleObjectSweepExtraAttempts; attempt++ {
		if err = call(ctx); err == nil {
			return nil
		}
		if attempt == singleObjectSweepExtraAttempts || !isSweepWorthyError(err) {
			return err
		}
		if waitErr := waitBeforeSweepRetry(ctx); waitErr != nil {
			return waitErr
		}
	}
	return err
}

// isSweepWorthyError reports whether a failed single-object call deserves an
// extra spaced retry beyond the SDK's own retryer.
func isSweepWorthyError(err error) bool {
	if err == nil {
		return false
	}
	var apiErr smithy.APIError
	if errors.As(err, &apiErr) {
		code := apiErr.ErrorCode()
		// CopyObject against vendors behind gateways intermittently answers with
		// a bare InvalidArgument/InvalidRequest that succeeds on a later attempt.
		if code == "InvalidArgument" || code == "InvalidRequest" {
			return true
		}
		// Non-retryable 5xx codes (InternalError is retryable and already handled
		// by the client retryer) still deserve one more spaced chance.
		if strings.Contains(code, "Internal") || strings.Contains(code, "Unavailable") {
			return true
		}
		return false
	}
	// Transport-level failures (connection reset, EOF, timeouts) are worth a
	// spaced retry even when the SDK classified them as non-retryable.
	return true
}

// waitBeforeSweepRetry sleeps between sweep attempts, honoring cancellation.
func waitBeforeSweepRetry(ctx context.Context) error {
	if singleObjectSweepRetryDelay <= 0 {
		return nil
	}
	timer := time.NewTimer(singleObjectSweepRetryDelay)
	defer timer.Stop()
	select {
	case <-ctx.Done():
		return ctx.Err()
	case <-timer.C:
		return nil
	}
}
