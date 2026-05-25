// S3 error helpers normalize storage-vendor not-found responses for callers.
package s3

import (
	"errors"
	"os"

	"github.com/aws/smithy-go"
	smithyhttp "github.com/aws/smithy-go/transport/http"
)

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
