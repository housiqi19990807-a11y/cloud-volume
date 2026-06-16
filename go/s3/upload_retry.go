// Multipart upload retry helpers centralise backoff and retry classification
// so part uploads can recover from transient S3/network failures without
// aborting the whole transfer.
package s3

import (
	"context"
	"errors"
	"io"
	"net"
	"strings"
	"syscall"
	"time"

	"github.com/aws/smithy-go"
	smithyhttp "github.com/aws/smithy-go/transport/http"
)

const (
	// maxUploadPartRetries caps how many times a single part is retried.
	maxUploadPartRetries = 10
	// uploadPartRetryStep is the per-attempt backoff increment. Attempt 1
	// retries immediately, attempt N waits (N-1)*step.
	uploadPartRetryStep = 1 * time.Second
)

// uploadPartRetryDelay returns the backoff before the given 0-based attempt
// index is retried (attempt 0 = first retry).
func uploadPartRetryDelay(attempt int) time.Duration {
	if attempt <= 0 {
		return 0
	}
	return time.Duration(attempt) * uploadPartRetryStep
}

// isRetryableUploadError reports whether the S3 error is transient enough to
// retry a part upload. Cancelled contexts and aborts are not retried here.
func isRetryableUploadError(err error) bool {
	if err == nil {
		return false
	}
	if errors.Is(err, context.Canceled) {
		return false
	}
	// A deadline on the per-part context is itself transient (slow network);
	// the caller may retry with a fresh timeout. The parent upload context is
	// checked separately by the caller so a user-initiated cancel still wins.
	if errors.Is(err, context.DeadlineExceeded) {
		return true
	}
	// Network/connection failures.
	if errors.Is(err, io.ErrUnexpectedEOF) ||
		errors.Is(err, io.EOF) ||
		errors.Is(err, syscall.ECONNRESET) ||
		errors.Is(err, syscall.ECONNREFUSED) ||
		errors.Is(err, syscall.EPIPE) ||
		errors.Is(err, net.ErrClosed) {
		return true
	}
	var netErr net.Error
	if errors.As(err, &netErr) && netErr.Timeout() {
		return true
	}

	// Smithy/AWS API errors: retry 5xx and throttling.
	var apiErr smithy.APIError
	if errors.As(err, &apiErr) {
		code := strings.TrimSpace(apiErr.ErrorCode())
		switch {
		case strings.HasPrefix(code, "5"):
			return true
		case code == "RequestTimeout" || code == "RequestTimeoutException":
			return true
		case code == "SlowDown" || code == "Throttling" || code == "ThrottlingException":
			return true
		case code == "InternalError" || code == "ServiceUnavailable":
			return true
		}
	}

	// HTTP response errors raised directly by the SDK transport.
	var httpErr *smithyhttp.ResponseError
	if errors.As(err, &httpErr) && httpErr.Response != nil {
		status := httpErr.Response.StatusCode
		if status >= 500 || status == 408 || status == 429 {
			return true
		}
	}

	// Fallback: connection-reset-style messages from lower layers.
	msg := strings.ToLower(err.Error())
	if strings.Contains(msg, "connection reset") ||
		strings.Contains(msg, "broken pipe") ||
		strings.Contains(msg, "eof") ||
		strings.Contains(msg, "deadline exceeded") ||
		strings.Contains(msg, "temporary failure") {
		return true
	}
	return false
}

// retryUploadPartWithTimeout runs fn with bounded retries using
// uploadPartRetryDelay and isRetryableUploadError. Each attempt gets its own
// detached context with the given timeout so a slow attempt or a parent
// deadline cannot leak into subsequent retries; the parent context is still
// honored between attempts so a user cancel always wins.
func retryUploadPartWithTimeout(
	parent context.Context,
	perAttemptTimeout time.Duration,
	fn func(ctx context.Context) error,
) error {
	var lastErr error
	for attempt := 0; attempt <= maxUploadPartRetries; attempt++ {
		// Only honor user-initiated cancellation. A deadline on the parent is
		// exactly the bug we are fixing: the 30 GB upload's transfer-monitor
		// context had a timeout, and that deadline would normally leak into
		// every part upload and kill them all. Per-part timeouts are now
		// detached in buildPartAttemptContext, so we let retry continue past
		// parent deadlines and surface the parent deadline only if all retries
		// eventually fail.
		if err := parent.Err(); err != nil && !errors.Is(err, context.DeadlineExceeded) {
			if lastErr != nil {
				return errors.Join(err, lastErr)
			}
			return err
		}
		attemptCtx, cancel := buildPartAttemptContext(parent, perAttemptTimeout)
		err := fn(attemptCtx)
		cancel()
		if err == nil {
			return nil
		}
		lastErr = err
		if !isRetryableUploadError(err) {
			return err
		}
		delay := uploadPartRetryDelay(attempt)
		if delay > 0 {
			timer := time.NewTimer(delay)
			select {
			case <-parent.Done():
				// Allow deadline-induced done channels to keep retrying. Only a
				// true Cancel short-circuits the wait.
				if !errors.Is(parent.Err(), context.DeadlineExceeded) {
					timer.Stop()
					return parent.Err()
				}
			case <-timer.C:
			}
		}
	}
	return lastErr
}

// buildPartAttemptContext detaches the parent's cancellation/deadline while
// preserving its values, then applies the per-attempt timeout. Detaching
// matters here: if the parent context is already past its deadline (which is
// exactly what happens for the 30 GB case), every child context would also be
// immediately expired and retries could never run.
func buildPartAttemptContext(parent context.Context, timeout time.Duration) (context.Context, context.CancelFunc) {
	base := context.WithoutCancel(parent)
	if timeout <= 0 {
		return context.WithCancel(base)
	}
	return context.WithTimeout(base, timeout)
}

// retryUploadPart is kept for callers that do not compute a per-part size; it
// delegates to retryUploadPartWithTimeout with the shared constant budget.
func retryUploadPart(parent context.Context, fn func(ctx context.Context) error) error {
	return retryUploadPartWithTimeout(parent, retryUploadAttemptTimeout, fn)
}

// retryUploadAttemptTimeout is the default per-attempt budget when the caller
// does not supply a part-size-aware timeout. It mirrors the legacy per-part
// minimum timeout scaled up to be useful for large parts on slow links.
const retryUploadAttemptTimeout = 30 * time.Minute
