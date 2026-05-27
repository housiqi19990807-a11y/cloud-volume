// Trash operations provide app-level soft delete independent of Finder/system trash.
package s3

import (
	"bytes"
	"context"
	"io"
	"sort"
	"strings"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/service/s3"
	"github.com/google/uuid"

	storageconfig "remote-storage/go/config"
)

// MoveObjectToTrash soft-deletes a file or directory tree into the configured trash directory.
func MoveObjectToTrash(
	cfg storageconfig.RemoteStorageConfig,
	bucket string,
	key string,
	isDirectory bool,
) error {
	return MoveObjectToTrashContext(Ctx(), cfg, bucket, key, isDirectory)
}

// MoveObjectToTrashContext soft-deletes a file or directory tree into the configured trash directory.
func MoveObjectToTrashContext(
	ctx context.Context,
	cfg storageconfig.RemoteStorageConfig,
	bucket string,
	key string,
	isDirectory bool,
) error {
	client := NewClient(cfg)
	if ctx == nil {
		ctx = Ctx()
	}

	sourceKey := strings.Trim(strings.TrimSpace(key), "/")
	if sourceKey == "" || isTrashKey(cfg, sourceKey) {
		return nil
	}

	keys, err := mutationKeys(ctx, client, bucket, sourceKey, isDirectory)
	if err != nil {
		return err
	}
	if len(keys) == 0 {
		return nil
	}

	trashID := uuid.NewString()
	targetKey := trashObjectTarget(cfg, trashID, sourceKey)
	if isDirectory {
		targetKey = ensureRemoteDirSuffix(targetKey)
	}
	if err := MoveObjectContext(ctx, cfg, bucket, sourceKey, targetKey, isDirectory); err != nil {
		return err
	}

	metadata := buildTrashMetadata(
		trashID,
		trashDisplayName(sourceKey),
		sourceKey,
		targetKey,
		isDirectory,
		estimateTrashSize(ctx, cfg, bucket, sourceKey, isDirectory, len(keys)),
		len(keys),
	)
	return putTrashMetadata(ctx, client, cfg, bucket, metadata)
}

// ListTrash returns all current trash entries for the bucket after optional retention cleanup.
func ListTrash(cfg storageconfig.RemoteStorageConfig, bucket string) ([]TrashItem, error) {
	return ListTrashContext(Ctx(), cfg, bucket)
}

// ListTrashContext returns all current trash entries for the bucket after optional retention cleanup.
func ListTrashContext(
	ctx context.Context,
	cfg storageconfig.RemoteStorageConfig,
	bucket string,
) ([]TrashItem, error) {
	nextToken := ""
	items := make([]TrashItem, 0)
	for {
		page, err := ListTrashPageContext(ctx, cfg, bucket, nextToken, 1000)
		if err != nil {
			return nil, err
		}
		items = append(items, page.Items...)
		if page.NextToken == "" {
			break
		}
		nextToken = page.NextToken
	}
	sort.Slice(items, func(i, j int) bool {
		return items[i].DeletedAt > items[j].DeletedAt
	})
	return items, nil
}

// RestoreTrashItem moves a soft-deleted entry back to its original key.
func RestoreTrashItem(cfg storageconfig.RemoteStorageConfig, bucket, trashID string) error {
	return RestoreTrashItemContext(Ctx(), cfg, bucket, trashID)
}

// RestoreTrashItemContext moves a soft-deleted entry back to its original key.
func RestoreTrashItemContext(
	ctx context.Context,
	cfg storageconfig.RemoteStorageConfig,
	bucket string,
	trashID string,
) error {
	client := NewClient(cfg)
	if ctx == nil {
		ctx = Ctx()
	}

	metadata, err := loadTrashMetadata(ctx, client, cfg, bucket, trashID)
	if err != nil {
		return err
	}
	if err := MoveObjectContext(
		ctx,
		cfg,
		bucket,
		metadata.TrashKey,
		metadata.OriginalKey,
		metadata.IsDir,
	); err != nil {
		return err
	}
	return deleteObjectKey(ctx, client, bucket, trashMetadataKey(cfg, trashID))
}

// DeleteTrashItem permanently removes a trash entry and its metadata.
func DeleteTrashItem(cfg storageconfig.RemoteStorageConfig, bucket, trashID string) error {
	return DeleteTrashItemContext(Ctx(), cfg, bucket, trashID)
}

// DeleteTrashItemContext permanently removes a trash entry and its metadata.
func DeleteTrashItemContext(
	ctx context.Context,
	cfg storageconfig.RemoteStorageConfig,
	bucket string,
	trashID string,
) error {
	client := NewClient(cfg)
	if ctx == nil {
		ctx = Ctx()
	}
	return deleteTrashByID(ctx, client, cfg, bucket, trashID)
}

func listTrashMetadata(
	ctx context.Context,
	client *s3.Client,
	cfg storageconfig.RemoteStorageConfig,
	bucket string,
) ([]TrashItem, error) {
	prefix := trashMetadataPrefix(cfg)
	pager := s3.NewListObjectsV2Paginator(client, &s3.ListObjectsV2Input{
		Bucket: &bucket,
		Prefix: aws.String(prefix),
	})

	items := make([]TrashItem, 0)
	for pager.HasMorePages() {
		page, err := pager.NextPage(ctx)
		if err != nil {
			return nil, err
		}
		for _, obj := range page.Contents {
			if obj.Key == nil || !strings.HasSuffix(*obj.Key, trashMetadataSuffix) {
				continue
			}
			metadata, err := loadTrashMetadataByKey(ctx, client, bucket, *obj.Key)
			if err != nil {
				return nil, err
			}
			items = append(items, trashItemFromMetadata(metadata))
		}
	}
	return items, nil
}

func loadTrashMetadata(
	ctx context.Context,
	client *s3.Client,
	cfg storageconfig.RemoteStorageConfig,
	bucket string,
	trashID string,
) (trashMetadata, error) {
	return loadTrashMetadataByKey(ctx, client, bucket, trashMetadataKey(cfg, trashID))
}

func loadTrashMetadataByKey(
	ctx context.Context,
	client *s3.Client,
	bucket string,
	metadataKey string,
) (trashMetadata, error) {
	out, err := client.GetObject(ctx, &s3.GetObjectInput{
		Bucket: &bucket,
		Key:    aws.String(metadataKey),
	})
	if err != nil {
		return trashMetadata{}, normalizeNotExistError(err)
	}
	defer out.Body.Close()

	body, err := io.ReadAll(out.Body)
	if err != nil {
		return trashMetadata{}, err
	}
	return parseTrashMetadata(body)
}

func putTrashMetadata(
	ctx context.Context,
	client *s3.Client,
	cfg storageconfig.RemoteStorageConfig,
	bucket string,
	metadata trashMetadata,
) error {
	body, err := encodeTrashMetadata(metadata)
	if err != nil {
		return err
	}
	_, err = client.PutObject(ctx, &s3.PutObjectInput{
		Bucket:      &bucket,
		Key:         aws.String(trashMetadataKey(cfg, metadata.ID)),
		Body:        bytes.NewReader(body),
		ContentType: aws.String("application/json"),
	})
	return err
}

func purgeExpiredTrash(
	ctx context.Context,
	client *s3.Client,
	cfg storageconfig.RemoteStorageConfig,
	bucket string,
) error {
	retention := cfg.TrashRetentionDays
	if retention < 0 {
		return nil
	}
	cutoff := time.Now().UTC().Add(-time.Duration(retention) * 24 * time.Hour)
	items, err := listTrashMetadata(ctx, client, cfg, bucket)
	if err != nil {
		return err
	}
	for _, item := range items {
		deletedAt, err := time.Parse(time.RFC3339, item.DeletedAt)
		if err != nil || deletedAt.After(cutoff) {
			continue
		}
		if err := deleteTrashByID(ctx, client, cfg, bucket, item.ID); err != nil {
			return err
		}
	}
	return nil
}

func deleteTrashByID(
	ctx context.Context,
	client *s3.Client,
	cfg storageconfig.RemoteStorageConfig,
	bucket string,
	trashID string,
) error {
	metadata, err := loadTrashMetadata(ctx, client, cfg, bucket, trashID)
	if err != nil {
		return err
	}
	if err := DeleteObjectHardContext(ctx, cfg, bucket, metadata.TrashKey, metadata.IsDir); err != nil {
		return err
	}
	return deleteObjectKey(ctx, client, bucket, trashMetadataKey(cfg, trashID))
}

func deleteObjectKey(
	ctx context.Context,
	client *s3.Client,
	bucket string,
	key string,
) error {
	_, err := client.DeleteObject(ctx, &s3.DeleteObjectInput{
		Bucket: &bucket,
		Key:    aws.String(key),
	})
	return err
}

func estimateTrashSize(
	ctx context.Context,
	cfg storageconfig.RemoteStorageConfig,
	bucket string,
	sourceKey string,
	isDirectory bool,
	objectCount int,
) int64 {
	if objectCount == 0 {
		return 0
	}
	if isDirectory {
		return 0
	}
	info, err := HeadObjectContext(ctx, cfg, bucket, sourceKey)
	if err != nil {
		return 0
	}
	return info.Size
}

func isTrashListingPrefix(cfg storageconfig.RemoteStorageConfig, prefix string) bool {
	trimmed := strings.Trim(strings.TrimSpace(prefix), "/")
	if trimmed == "" {
		return false
	}
	trashRoot := strings.TrimSuffix(trashPrefix(cfg), "/")
	return trimmed == trashRoot || strings.HasPrefix(trimmed, trashRoot+"/")
}

func trimTrashPrefix(cfg storageconfig.RemoteStorageConfig, key string) string {
	trimmed := strings.Trim(strings.TrimSpace(key), "/")
	root := strings.TrimSuffix(trashPrefix(cfg), "/")
	return strings.TrimPrefix(trimmed, root+"/")
}
