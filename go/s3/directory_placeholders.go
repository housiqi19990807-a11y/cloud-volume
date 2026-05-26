// Directory placeholder helpers keep MinIO-style empty-prefix objects compatible across moves.
package s3

import (
	"bytes"
	"context"
	"strings"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/service/s3"
)

func isDirectoryPlaceholderKey(key string) bool {
	return strings.HasSuffix(strings.TrimSpace(key), "/")
}

func putDirectoryPlaceholder(
	ctx context.Context,
	client *s3.Client,
	bucket,
	key string,
) error {
	_, err := client.PutObject(ctx, &s3.PutObjectInput{
		Bucket:      &bucket,
		Key:         aws.String(key),
		Body:        bytes.NewReader(nil),
		ContentType: aws.String("application/x-directory"),
	})
	return err
}
