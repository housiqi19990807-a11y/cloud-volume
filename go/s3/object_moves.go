// Object move helpers support full-path renames across directories.
package s3

import (
	"context"
	"fmt"
	"strings"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/service/s3"

	storageconfig "remote-storage/go/config"
)

// MoveObject copies a file or prefix to a new full target key and removes the source.
func MoveObject(
	cfg storageconfig.RemoteStorageConfig,
	bucket,
	sourceKey,
	targetKey string,
	isDirectory bool,
) error {
	return MoveObjectContext(Ctx(), cfg, bucket, sourceKey, targetKey, isDirectory)
}

// MoveObjectContext copies a file or prefix to a new full target key with caller context.
func MoveObjectContext(
	ctx context.Context,
	cfg storageconfig.RemoteStorageConfig,
	bucket,
	sourceKey,
	targetKey string,
	isDirectory bool,
) error {
	client := NewClient(cfg)

	sourceKey = strings.TrimSpace(sourceKey)
	targetKey = strings.TrimSpace(targetKey)
	if sourceKey == "" || targetKey == "" {
		return fmt.Errorf("source and target keys are required")
	}
	if sourceKey == targetKey {
		return nil
	}

	keys, err := mutationKeys(ctx, client, bucket, sourceKey, isDirectory)
	if err != nil {
		return err
	}
	if len(keys) == 0 {
		return nil
	}

	sourcePrefix := sourceKey
	targetPrefix := targetKey
	if isDirectory {
		sourcePrefix = ensureRemoteDirSuffix(sourcePrefix)
		targetPrefix = ensureRemoteDirSuffix(targetPrefix)
	}

	for _, currentKey := range keys {
		nextKey := targetPrefix
		if isDirectory {
			nextKey += strings.TrimPrefix(currentKey, sourcePrefix)
		}
		copySource := bucket + "/" + currentKey
		_, err = client.CopyObject(ctx, &s3.CopyObjectInput{
			Bucket:     &bucket,
			Key:        aws.String(nextKey),
			CopySource: aws.String(copySource),
		})
		if err != nil {
			return err
		}
	}

	return DeleteObjectHardContext(ctx, cfg, bucket, sourceKey, isDirectory)
}

func ensureRemoteDirSuffix(value string) string {
	trimmed := strings.TrimSuffix(strings.TrimSpace(value), "/")
	if trimmed == "" {
		return ""
	}
	return trimmed + "/"
}
