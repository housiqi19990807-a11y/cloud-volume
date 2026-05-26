// Copy source helpers keep S3 CopyObject headers valid for non-ASCII object keys.
package s3

import (
	"net/url"
	"strings"
)

func encodeCopySource(bucket, key string) string {
	trimmedBucket := strings.TrimSpace(bucket)
	trimmedKey := strings.TrimPrefix(strings.TrimSpace(key), "/")
	if trimmedKey == "" {
		return url.PathEscape(trimmedBucket)
	}
	return url.PathEscape(trimmedBucket + "/" + trimmedKey)
}
