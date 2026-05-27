// Trash index helpers keep listable metadata in object keys so trash pages avoid per-row GETs.
package s3

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"sort"
	"strings"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/service/s3"

	storageconfig "remote-storage/go/config"
)

const (
	trashIndexSuffix              = ".trashidx"
	maxTrashIndexKeyLength        = 900
	reverseTrashTimeCeilingMillis = int64(9999999999999)
	indexedTrashPageMode          = "index"
	legacyTrashPageMode           = "legacy"
)

type trashIndexPayload struct {
	OriginalKey string `json:"k"`
	DeletedAt   string `json:"d"`
	IsDir       bool   `json:"i"`
	Size        int64  `json:"s"`
	ObjectCount int    `json:"c"`
}

type trashEntryLocator struct {
	item              TrashItem
	legacyMetadataKey string
	byTimeIndexKey    string
	byIDIndexKey      string
}

func trashIndexPrefix(cfg storageconfig.RemoteStorageConfig) string {
	return trashPrefix(cfg) + "index/"
}

func trashIndexByTimePrefix(cfg storageconfig.RemoteStorageConfig) string {
	return trashIndexPrefix(cfg) + "by-time/"
}

func trashIndexByIDPrefix(cfg storageconfig.RemoteStorageConfig) string {
	return trashIndexPrefix(cfg) + "by-id/"
}

func persistTrashMetadata(
	ctx context.Context,
	client *s3.Client,
	cfg storageconfig.RemoteStorageConfig,
	bucket string,
	metadata trashMetadata,
) error {
	byTimeKey, byIDKey, err := buildTrashIndexKeys(cfg, metadata)
	if err != nil || len(byTimeKey) > maxTrashIndexKeyLength || len(byIDKey) > maxTrashIndexKeyLength {
		return putTrashMetadataLegacy(ctx, client, cfg, bucket, metadata)
	}
	if err := putTrashIndexObject(ctx, client, bucket, byTimeKey); err != nil {
		return err
	}
	if err := putTrashIndexObject(ctx, client, bucket, byIDKey); err != nil {
		_ = deleteObjectKeyIfExists(ctx, client, bucket, byTimeKey)
		return err
	}
	return nil
}

func putTrashIndexObject(
	ctx context.Context,
	client *s3.Client,
	bucket string,
	key string,
) error {
	_, err := client.PutObject(ctx, &s3.PutObjectInput{
		Bucket:      &bucket,
		Key:         aws.String(key),
		Body:        bytes.NewReader(nil),
		ContentType: aws.String("application/x-trash-index"),
	})
	return err
}

func putTrashMetadataLegacy(
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

func buildTrashIndexKeys(
	cfg storageconfig.RemoteStorageConfig,
	metadata trashMetadata,
) (string, string, error) {
	payload, err := encodeTrashIndexPayload(trashIndexPayload{
		OriginalKey: metadata.OriginalKey,
		DeletedAt:   metadata.DeletedAt,
		IsDir:       metadata.IsDir,
		Size:        metadata.Size,
		ObjectCount: metadata.ObjectCount,
	})
	if err != nil {
		return "", "", err
	}
	sortKey, err := reverseTrashTimeSortKey(metadata.DeletedAt)
	if err != nil {
		return "", "", err
	}
	byTimeKey := fmt.Sprintf(
		"%s%s__%s__%s%s",
		trashIndexByTimePrefix(cfg),
		sortKey,
		metadata.ID,
		payload,
		trashIndexSuffix,
	)
	byIDKey := fmt.Sprintf(
		"%s%s__%s%s",
		trashIndexByIDPrefix(cfg),
		metadata.ID,
		payload,
		trashIndexSuffix,
	)
	return byTimeKey, byIDKey, nil
}

func encodeTrashIndexPayload(payload trashIndexPayload) (string, error) {
	data, err := json.Marshal(payload)
	if err != nil {
		return "", err
	}
	return base64.RawURLEncoding.EncodeToString(data), nil
}

func reverseTrashTimeSortKey(deletedAt string) (string, error) {
	parsed, err := time.Parse(time.RFC3339, strings.TrimSpace(deletedAt))
	if err != nil {
		return "", err
	}
	reversed := reverseTrashTimeCeilingMillis - parsed.UTC().UnixMilli()
	if reversed < 0 {
		reversed = 0
	}
	return fmt.Sprintf("%013d", reversed), nil
}

func parseTrashIndexPayload(encoded string) (trashIndexPayload, error) {
	data, err := base64.RawURLEncoding.DecodeString(encoded)
	if err != nil {
		return trashIndexPayload{}, err
	}
	var payload trashIndexPayload
	if err := json.Unmarshal(data, &payload); err != nil {
		return trashIndexPayload{}, err
	}
	payload.OriginalKey = strings.Trim(strings.TrimSpace(payload.OriginalKey), "/")
	payload.DeletedAt = strings.TrimSpace(payload.DeletedAt)
	return payload, nil
}

func parseTrashItemFromByTimeIndexKey(
	cfg storageconfig.RemoteStorageConfig,
	key string,
) (TrashItem, error) {
	trimmed := strings.TrimPrefix(strings.TrimSpace(key), trashIndexByTimePrefix(cfg))
	trimmed = strings.TrimSuffix(trimmed, trashIndexSuffix)
	parts := strings.SplitN(trimmed, "__", 3)
	if len(parts) != 3 {
		return TrashItem{}, fmt.Errorf("invalid trash index key: %s", key)
	}
	return trashItemFromIndexPayload(cfg, parts[1], parts[2])
}

func parseTrashItemFromByIDIndexKey(
	cfg storageconfig.RemoteStorageConfig,
	key string,
) (TrashItem, error) {
	trimmed := strings.TrimPrefix(strings.TrimSpace(key), trashIndexByIDPrefix(cfg))
	trimmed = strings.TrimSuffix(trimmed, trashIndexSuffix)
	parts := strings.SplitN(trimmed, "__", 2)
	if len(parts) != 2 {
		return TrashItem{}, fmt.Errorf("invalid trash id index key: %s", key)
	}
	return trashItemFromIndexPayload(cfg, parts[0], parts[1])
}

func trashItemFromIndexPayload(
	cfg storageconfig.RemoteStorageConfig,
	id string,
	encodedPayload string,
) (TrashItem, error) {
	payload, err := parseTrashIndexPayload(encodedPayload)
	if err != nil {
		return TrashItem{}, err
	}
	trashKey := trashObjectTarget(cfg, id, payload.OriginalKey)
	if payload.IsDir {
		trashKey = ensureRemoteDirSuffix(trashKey)
	}
	return TrashItem{
		ID:          strings.TrimSpace(id),
		Name:        trashDisplayName(payload.OriginalKey),
		OriginalKey: payload.OriginalKey,
		TrashKey:    trashKey,
		DeletedAt:   payload.DeletedAt,
		IsDir:       payload.IsDir,
		Size:        payload.Size,
		ObjectCount: payload.ObjectCount,
	}, nil
}

func loadTrashEntry(
	ctx context.Context,
	client *s3.Client,
	cfg storageconfig.RemoteStorageConfig,
	bucket string,
	trashID string,
) (trashEntryLocator, error) {
	indexedEntry, err := loadIndexedTrashEntry(ctx, client, cfg, bucket, trashID)
	if err == nil {
		return indexedEntry, nil
	}
	if !errors.Is(err, os.ErrNotExist) {
		return trashEntryLocator{}, err
	}
	metadata, err := loadTrashMetadataByKey(ctx, client, bucket, trashMetadataKey(cfg, trashID))
	if err != nil {
		return trashEntryLocator{}, err
	}
	return trashEntryLocator{
		item:              trashItemFromMetadata(metadata),
		legacyMetadataKey: trashMetadataKey(cfg, trashID),
	}, nil
}

func loadIndexedTrashEntry(
	ctx context.Context,
	client *s3.Client,
	cfg storageconfig.RemoteStorageConfig,
	bucket string,
	trashID string,
) (trashEntryLocator, error) {
	prefix := trashIndexByIDPrefix(cfg) + strings.TrimSpace(trashID) + "__"
	out, err := client.ListObjectsV2(ctx, &s3.ListObjectsV2Input{
		Bucket:  &bucket,
		Prefix:  aws.String(prefix),
		MaxKeys: aws.Int32(1),
	})
	if err != nil {
		return trashEntryLocator{}, err
	}
	if len(out.Contents) == 0 || out.Contents[0].Key == nil {
		return trashEntryLocator{}, os.ErrNotExist
	}
	byIDKey := *out.Contents[0].Key
	item, err := parseTrashItemFromByIDIndexKey(cfg, byIDKey)
	if err != nil {
		return trashEntryLocator{}, err
	}
	metadata := trashMetadata{
		ID:          item.ID,
		Name:        item.Name,
		OriginalKey: item.OriginalKey,
		TrashKey:    item.TrashKey,
		DeletedAt:   item.DeletedAt,
		IsDir:       item.IsDir,
		Size:        item.Size,
		ObjectCount: item.ObjectCount,
	}
	byTimeKey, _, err := buildTrashIndexKeys(cfg, metadata)
	if err != nil {
		return trashEntryLocator{}, err
	}
	return trashEntryLocator{
		item:           item,
		byTimeIndexKey: byTimeKey,
		byIDIndexKey:   byIDKey,
	}, nil
}

func deleteTrashEntryMetadata(
	ctx context.Context,
	client *s3.Client,
	bucket string,
	entry trashEntryLocator,
) error {
	keys := []string{
		entry.byTimeIndexKey,
		entry.byIDIndexKey,
		entry.legacyMetadataKey,
	}
	sort.Strings(keys)
	previous := ""
	for _, key := range keys {
		key = strings.TrimSpace(key)
		if key == "" || key == previous {
			continue
		}
		if err := deleteObjectKeyIfExists(ctx, client, bucket, key); err != nil {
			return err
		}
		previous = key
	}
	return nil
}

func deleteObjectKeyIfExists(
	ctx context.Context,
	client *s3.Client,
	bucket string,
	key string,
) error {
	if strings.TrimSpace(key) == "" {
		return nil
	}
	err := deleteObjectKey(ctx, client, bucket, key)
	if errors.Is(normalizeNotExistError(err), os.ErrNotExist) {
		return nil
	}
	return err
}
