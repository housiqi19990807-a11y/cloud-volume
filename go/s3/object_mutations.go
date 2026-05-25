// Object mutation helpers cover delete and rename flows for files and prefixes.

package s3

import (
	"context"
	"fmt"
	"strings"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/service/s3"

	storageconfig "remote-storage/go/config"
)

// DeleteObject removes either a single object or all objects under a prefix.
func DeleteObject(cfg storageconfig.RemoteStorageConfig, bucket, key string, isDirectory bool) error {
	return DeleteObjectContext(Ctx(), cfg, bucket, key, isDirectory)
}

// DeleteObjectContext removes either a single object or all objects under a prefix.
func DeleteObjectContext(
	ctx context.Context,
	cfg storageconfig.RemoteStorageConfig,
	bucket,
	key string,
	isDirectory bool,
) error {
	client := NewClient(cfg)
	keys, err := mutationKeys(ctx, client, bucket, key, isDirectory)
	if err != nil {
		return err
	}
	if len(keys) == 0 {
		return nil
	}
	for _, objectKey := range keys {
		_, err = client.DeleteObject(ctx, &s3.DeleteObjectInput{
			Bucket: &bucket,
			Key:    aws.String(objectKey),
		})
		if err != nil {
			return err
		}
	}
	return nil
}

// RenameObject emulates rename by copying to a sibling key and removing the source.
func RenameObject(
	cfg storageconfig.RemoteStorageConfig,
	bucket,
	key string,
	isDirectory bool,
	newName string,
) error {
	return RenameObjectContext(Ctx(), cfg, bucket, key, isDirectory, newName)
}

// RenameObjectContext emulates rename with a caller-supplied context.
func RenameObjectContext(
	ctx context.Context,
	cfg storageconfig.RemoteStorageConfig,
	bucket,
	key string,
	isDirectory bool,
	newName string,
) error {
	client := NewClient(cfg)
	trimmedName := strings.Trim(strings.TrimSpace(newName), "/")
	if trimmedName == "" {
		return fmt.Errorf("new name is required")
	}

	keys, err := mutationKeys(ctx, client, bucket, key, isDirectory)
	if err != nil {
		return err
	}
	if len(keys) == 0 {
		return nil
	}

	targetPrefix, err := renamedKeyTarget(key, isDirectory, trimmedName)
	if err != nil {
		return err
	}
	sourcePrefix := key
	if isDirectory && !strings.HasSuffix(sourcePrefix, "/") {
		sourcePrefix += "/"
	}

	for _, sourceKey := range keys {
		targetKey := targetPrefix
		if isDirectory {
			targetKey += strings.TrimPrefix(sourceKey, sourcePrefix)
		}
		copySource := bucket + "/" + sourceKey
		_, err = client.CopyObject(ctx, &s3.CopyObjectInput{
			Bucket:     &bucket,
			Key:        aws.String(targetKey),
			CopySource: aws.String(copySource),
		})
		if err != nil {
			return err
		}
	}

	return DeleteObjectContext(ctx, cfg, bucket, key, isDirectory)
}

func mutationKeys(
	ctx context.Context,
	client *s3.Client,
	bucket,
	key string,
	isDirectory bool,
) ([]string, error) {
	if !isDirectory {
		return []string{key}, nil
	}

	prefix := key
	if prefix != "" && !strings.HasSuffix(prefix, "/") {
		prefix += "/"
	}
	pager := s3.NewListObjectsV2Paginator(client, &s3.ListObjectsV2Input{
		Bucket: &bucket,
		Prefix: aws.String(prefix),
	})

	keys := make([]string, 0)
	for pager.HasMorePages() {
		page, err := pager.NextPage(ctx)
		if err != nil {
			return nil, err
		}
		for _, object := range page.Contents {
			if object.Key == nil {
				continue
			}
			keys = append(keys, *object.Key)
		}
	}

	if len(keys) == 0 {
		keys = append(keys, prefix)
	}
	return keys, nil
}

func renamedKeyTarget(key string, isDirectory bool, newName string) (string, error) {
	if !isDirectory {
		index := strings.LastIndex(key, "/")
		if index < 0 {
			return newName, nil
		}
		return key[:index+1] + newName, nil
	}

	trimmed := strings.TrimSuffix(key, "/")
	index := strings.LastIndex(trimmed, "/")
	if index < 0 {
		return newName + "/", nil
	}
	return trimmed[:index+1] + newName + "/", nil
}
