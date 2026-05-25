// S3 error helper tests keep not-found normalization stable for WebDAV callers.
package s3

import (
	"errors"
	"net/http"
	"os"
	"testing"

	"github.com/aws/smithy-go"
	smithyhttp "github.com/aws/smithy-go/transport/http"
)

func TestNormalizeNotExistErrorFromHTTPStatus(t *testing.T) {
	t.Parallel()

	err := &smithyhttp.ResponseError{
		Response: &smithyhttp.Response{
			Response: &http.Response{StatusCode: http.StatusNotFound},
		},
		Err: errors.New("missing"),
	}

	if got := normalizeNotExistError(err); !errors.Is(got, os.ErrNotExist) {
		t.Fatalf("expected os.ErrNotExist, got %v", got)
	}
}

func TestNormalizeNotExistErrorFromAPIErrorCode(t *testing.T) {
	t.Parallel()

	err := &smithy.GenericAPIError{Code: "NoSuchKey", Message: "missing"}
	if got := normalizeNotExistError(err); !errors.Is(got, os.ErrNotExist) {
		t.Fatalf("expected os.ErrNotExist, got %v", got)
	}
}

func TestNormalizeNotExistErrorLeavesOtherErrorsUntouched(t *testing.T) {
	t.Parallel()

	err := errors.New("boom")
	if got := normalizeNotExistError(err); !errors.Is(got, err) {
		t.Fatalf("expected original error, got %v", got)
	}
}
