// S3 error helpers normalize storage-vendor not-found responses for callers.
package s3

import (
	"errors"
	"os"

	"github.com/aws/smithy-go"
	smithyhttp "github.com/aws/smithy-go/transport/http"
)

// s3HTTPStatus extracts the HTTP status code from an aws-sdk-go-v2 error chain
// (used by failover classification). Returns 0 when no status is available.
func s3HTTPStatus(err error) int {
	if err == nil {
		return 0
	}
	var responseErr *smithyhttp.ResponseError
	if errors.As(err, &responseErr) {
		return responseErr.HTTPStatusCode()
	}
	return 0
}

func normalizeNotExistError(err error) error {
	if err == nil {
		return nil
	}
	var responseErr *smithyhttp.ResponseError
	if errors.As(err, &responseErr) && responseErr.HTTPStatusCode() == 404 {
		return os.ErrNotExist
	}
	var apiErr smithy.APIError
	if errors.As(err, &apiErr) {
		switch apiErr.ErrorCode() {
		case "NotFound", "NoSuchKey", "NoSuchBucket":
			return os.ErrNotExist
		}
	}
	return err
}
