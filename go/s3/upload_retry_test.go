package s3

import (
	"context"
	"errors"
	"io"
	"net"
	"syscall"
	"testing"
	"time"

	"github.com/aws/smithy-go"
)

// Upload retry tests pin the backoff math, retry classification and per-attempt
// context isolation that large-file uploads depend on.

func TestUploadPartRetryDelayStepsByAttempt(t *testing.T) {
	cases := []struct {
		attempt int
		want    time.Duration
	}{
		{attempt: 0, want: 0},
		{attempt: 1, want: 1 * time.Second},
		{attempt: 2, want: 2 * time.Second},
		{attempt: 3, want: 3 * time.Second},
		{attempt: 10, want: 10 * time.Second},
	}
	for _, tc := range cases {
		if got := uploadPartRetryDelay(tc.attempt); got != tc.want {
			t.Fatalf("uploadPartRetryDelay(%d) = %s, want %s", tc.attempt, got, tc.want)
		}
	}
}

func TestIsRetryableUploadErrorClassifies(t *testing.T) {
	retryable := []error{
		context.DeadlineExceeded,
		io.ErrUnexpectedEOF,
		io.EOF,
		syscall.ECONNRESET,
		syscall.ECONNREFUSED,
		syscall.EPIPE,
		net.ErrClosed,
		&net.OpError{Err: errors.New("connection reset")},
		errors.New("read tcp: connection reset by peer"),
		errors.New("write tcp: broken pipe"),
		errors.New("http: unexpected EOF reading body"),
		&smithy.GenericAPIError{Code: "RequestTimeout", Message: "x"},
		&smithy.GenericAPIError{Code: "SlowDown", Message: "x"},
		&smithy.GenericAPIError{Code: "Throttling", Message: "x"},
		&smithy.GenericAPIError{Code: "InternalError", Message: "x"},
		&smithy.GenericAPIError{Code: "ServiceUnavailable", Message: "x"},
		&smithy.GenericAPIError{Code: "503", Message: "x"},
	}
	notRetryable := []error{
		nil,
		context.Canceled,
		errors.New("AccessDenied"),
		&smithy.GenericAPIError{Code: "AccessDenied", Message: "x"},
		&smithy.GenericAPIError{Code: "InvalidPart", Message: "x"},
		&smithy.GenericAPIError{Code: "NoSuchBucket", Message: "x"},
	}
	for _, err := range retryable {
		if !isRetryableUploadError(err) {
			t.Fatalf("expected %v to be retryable", err)
		}
	}
	for _, err := range notRetryable {
		if isRetryableUploadError(err) {
			t.Fatalf("expected %v to NOT be retryable", err)
		}
	}
}

func TestRetryUploadPartSucceedsAfterTransientFailures(t *testing.T) {
	calls := 0
	err := retryUploadPartWithTimeout(
		context.Background(),
		100*time.Millisecond,
		func(ctx context.Context) error {
			calls++
			if ctx.Err() != nil {
				return ctx.Err()
			}
			if calls < 3 {
				return context.DeadlineExceeded
			}
			return nil
		},
	)
	if err != nil {
		t.Fatalf("expected success, got %v", err)
	}
	if calls != 3 {
		t.Fatalf("expected 3 attempts, got %d", calls)
	}
}

func TestRetryUploadPartRespectsParentCancel(t *testing.T) {
	parent, cancel := context.WithCancel(context.Background())
	calls := 0
	err := retryUploadPartWithTimeout(
		parent,
		100*time.Millisecond,
		func(ctx context.Context) error {
			calls++
			if calls == 2 {
				cancel()
			}
			return context.DeadlineExceeded
		},
	)
	if !errors.Is(err, context.Canceled) {
		t.Fatalf("expected parent cancel to surface, got %v", err)
	}
	if calls > 2 {
		t.Fatalf("expected retry to stop after parent cancel, got %d calls", calls)
	}
}

func TestRetryUploadPartStopsOnNonRetryableError(t *testing.T) {
	calls := 0
	sentinel := errors.New("AccessDenied")
	err := retryUploadPartWithTimeout(
		context.Background(),
		100*time.Millisecond,
		func(ctx context.Context) error {
			calls++
			return sentinel
		},
	)
	if !errors.Is(err, sentinel) {
		t.Fatalf("expected sentinel error, got %v", err)
	}
	if calls != 1 {
		t.Fatalf("expected a single attempt for non-retryable error, got %d", calls)
	}
}

func TestRetryUploadPartBoundedByMaxAttempts(t *testing.T) {
	calls := 0
	err := retryUploadPartWithTimeout(
		context.Background(),
		100*time.Millisecond,
		func(ctx context.Context) error {
			calls++
			return context.DeadlineExceeded
		},
	)
	if err == nil {
		t.Fatal("expected final error after retries exhausted")
	}
	if calls != maxUploadPartRetries+1 {
		t.Fatalf("expected %d attempts (1 + %d retries), got %d", maxUploadPartRetries+1, maxUploadPartRetries, calls)
	}
}

func TestRetryUploadPartDetachesAttemptContextFromParentDeadline(t *testing.T) {
	// Parent is already past its deadline; without WithoutCancel, every child
	// attempt would also be immediately cancelled and retry could never run.
	parent, cancel := context.WithTimeout(context.Background(), 1*time.Nanosecond)
	defer cancel()
	<-time.After(2 * time.Millisecond)

	calls := 0
	err := retryUploadPartWithTimeout(
		parent,
		100*time.Millisecond,
		func(ctx context.Context) error {
			calls++
			// The per-attempt context must still be live despite the parent being done.
			if ctx.Err() != nil {
				t.Fatalf("attempt context should be detached from parent deadline, got %v", ctx.Err())
			}
			if calls >= 2 {
				return nil
			}
			return context.DeadlineExceeded
		},
	)
	if err != nil {
		t.Fatalf("expected retry to recover past parent deadline, got %v", err)
	}
	if calls < 2 {
		t.Fatalf("expected retry to actually run, got %d calls", calls)
	}
}
