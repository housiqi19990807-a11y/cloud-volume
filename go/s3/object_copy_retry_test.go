// Sweep retry classification tests pin which errors earn extra spaced attempts.
package s3

import (
	"context"
	"errors"
	"fmt"
	"testing"
	"time"

	"github.com/aws/smithy-go"
)

// stubAPIError is a minimal smithy.APIError for classification tests.
type stubAPIError struct {
	code    string
	message string
}

func (e stubAPIError) Error() string                 { return fmt.Sprintf("%s: %s", e.code, e.message) }
func (e stubAPIError) ErrorCode() string             { return e.code }
func (e stubAPIError) ErrorMessage() string          { return e.message }
func (e stubAPIError) ErrorFault() smithy.ErrorFault { return smithy.FaultServer }

func TestIsSweepWorthyError(t *testing.T) {
	t.Parallel()

	cases := []struct {
		name string
		err  error
		want bool
	}{
		{name: "nil", err: nil, want: false},
		{name: "vendor invalid argument glitch", err: stubAPIError{code: "InvalidArgument"}, want: true},
		{name: "vendor invalid request glitch", err: stubAPIError{code: "InvalidRequest"}, want: true},
		{name: "non-retryable 5xx code", err: stubAPIError{code: "ServiceUnavailable"}, want: true},
		{name: "access denied stays fatal", err: stubAPIError{code: "AccessDenied"}, want: false},
		{name: "not found stays fatal", err: stubAPIError{code: "NoSuchKey"}, want: false},
		{name: "transport error retried", err: errors.New("connection reset by peer"), want: true},
		{name: "wrapped api error", err: fmt.Errorf("copy: %w", stubAPIError{code: "InvalidArgument"}), want: true},
	}

	for _, tc := range cases {
		tc := tc
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			if got := isSweepWorthyError(tc.err); got != tc.want {
				t.Fatalf("isSweepWorthyError(%v) = %v, want %v", tc.err, got, tc.want)
			}
		})
	}
}

func TestRunSingleObjectSweepRetriesFlakyError(t *testing.T) {
	t.Parallel()

	restoreDelay := singleObjectSweepRetryDelay
	singleObjectSweepRetryDelay = 0
	defer func() { singleObjectSweepRetryDelay = restoreDelay }()

	attempts := 0
	err := runSingleObjectSweep(context.Background(), func(context.Context) error {
		attempts++
		if attempts < 3 {
			return stubAPIError{code: "InvalidArgument", message: "vendor glitch"}
		}
		return nil
	})
	if err != nil {
		t.Fatalf("runSingleObjectSweep returned %v, want nil", err)
	}
	if attempts != 3 {
		t.Fatalf("attempts = %d, want 3", attempts)
	}
}

func TestRunSingleObjectSweepDoesNotRetryFatalError(t *testing.T) {
	t.Parallel()

	attempts := 0
	err := runSingleObjectSweep(context.Background(), func(context.Context) error {
		attempts++
		return stubAPIError{code: "AccessDenied", message: "denied"}
	})
	if err == nil {
		t.Fatal("runSingleObjectSweep returned nil, want AccessDenied error")
	}
	if attempts != 1 {
		t.Fatalf("attempts = %d, want 1", attempts)
	}
}

func TestRunSingleObjectSweepGivesUpAfterExtraAttempts(t *testing.T) {
	t.Parallel()

	restoreDelay := singleObjectSweepRetryDelay
	singleObjectSweepRetryDelay = 0
	defer func() { singleObjectSweepRetryDelay = restoreDelay }()

	attempts := 0
	err := runSingleObjectSweep(context.Background(), func(context.Context) error {
		attempts++
		return stubAPIError{code: "InvalidArgument", message: "persistent"}
	})
	if err == nil {
		t.Fatal("runSingleObjectSweep returned nil, want persistent error")
	}
	wantAttempts := singleObjectSweepExtraAttempts + 1
	if attempts != wantAttempts {
		t.Fatalf("attempts = %d, want %d", attempts, wantAttempts)
	}
}

func TestWaitBeforeSweepRetryHonorsCancellation(t *testing.T) {
	t.Parallel()

	restoreDelay := singleObjectSweepRetryDelay
	singleObjectSweepRetryDelay = time.Minute
	defer func() { singleObjectSweepRetryDelay = restoreDelay }()

	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	if err := waitBeforeSweepRetry(ctx); err == nil {
		t.Fatal("waitBeforeSweepRetry returned nil for a cancelled context")
	}
}

func TestNewSingleObjectRetryerBudget(t *testing.T) {
	t.Parallel()

	retryer := newSingleObjectRetryer()
	if retryer == nil {
		t.Fatal("newSingleObjectRetryer returned nil")
	}
	if !retryer.IsErrorRetryable(stubAPIError{code: "RequestTimeout"}) {
		t.Fatal("standard retryer should keep RequestTimeout retryable")
	}
	if !retryer.IsErrorRetryable(stubAPIError{code: "SlowDown"}) {
		t.Fatal("standard retryer should keep SlowDown retryable")
	}
	if retryer.IsErrorRetryable(stubAPIError{code: "AccessDenied"}) {
		t.Fatal("standard retryer must not retry AccessDenied")
	}
	if maxAttempts := retryer.MaxAttempts(); maxAttempts != singleObjectCallMaxAttempts {
		t.Fatalf("MaxAttempts = %d, want %d", maxAttempts, singleObjectCallMaxAttempts)
	}
}
