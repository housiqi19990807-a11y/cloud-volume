// Paged listing helpers expose continuation-token based object and trash pages.
package s3

import (
	"context"
	"sort"
	"strings"
	"sync"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/service/s3"

	storageconfig "remote-storage/go/config"
)

const defaultListPageSize int32 = 200
const trashMetadataPageConcurrency = 8

type ObjectPage struct {
	Items     []ObjectInfo `json:"items"`
	NextToken string       `json:"nextToken"`
}

type TrashPage struct {
	Items     []TrashItem `json:"items"`
	NextToken string      `json:"nextToken"`
}

func ListObjectsPage(
	cfg storageconfig.RemoteStorageConfig,
	bucket,
	prefix,
	nextToken string,
	pageSize int32,
) (ObjectPage, error) {
	return ListObjectsPageContext(Ctx(), cfg, bucket, prefix, nextToken, pageSize)
}

func ListObjectsPageContext(
	ctx context.Context,
	cfg storageconfig.RemoteStorageConfig,
	bucket,
	prefix,
	nextToken string,
	pageSize int32,
) (ObjectPage, error) {
	client := NewClient(cfg)
	if ctx == nil {
		ctx = Ctx()
	}
	if prefix != "" && !strings.HasSuffix(prefix, "/") {
		prefix += "/"
	}
	if pageSize <= 0 {
		pageSize = defaultListPageSize
	}
	input := &s3.ListObjectsV2Input{
		Bucket:    &bucket,
		Prefix:    &prefix,
		Delimiter: aws.String("/"),
		MaxKeys:   aws.Int32(pageSize),
	}
	if strings.TrimSpace(nextToken) != "" {
		input.ContinuationToken = aws.String(strings.TrimSpace(nextToken))
	}
	out, err := client.ListObjectsV2(ctx, input)
	if err != nil {
		return ObjectPage{}, err
	}

	items := make([]ObjectInfo, 0, len(out.CommonPrefixes)+len(out.Contents))
	for _, cp := range out.CommonPrefixes {
		if cp.Prefix != nil && isRootTrashKey(cfg, *cp.Prefix) {
			continue
		}
		items = append(items, ObjectInfo{Key: *cp.Prefix, IsDir: true})
	}
	for _, obj := range out.Contents {
		if obj.Key != nil && *obj.Key == prefix {
			continue
		}
		if obj.Key != nil && isRootTrashKey(cfg, *obj.Key) {
			continue
		}
		info := ObjectInfo{Key: *obj.Key, Size: *obj.Size}
		if obj.LastModified != nil {
			info.LastModified = obj.LastModified.Format("2006-01-02 15:04:05")
		}
		items = append(items, info)
	}
	if items == nil {
		items = []ObjectInfo{}
	}
	return ObjectPage{
		Items:     items,
		NextToken: aws.ToString(out.NextContinuationToken),
	}, nil
}

func ListTrashPage(
	cfg storageconfig.RemoteStorageConfig,
	bucket,
	nextToken string,
	pageSize int32,
) (TrashPage, error) {
	return ListTrashPageContext(Ctx(), cfg, bucket, nextToken, pageSize)
}

func ListTrashPageContext(
	ctx context.Context,
	cfg storageconfig.RemoteStorageConfig,
	bucket,
	nextToken string,
	pageSize int32,
) (TrashPage, error) {
	client := NewClient(cfg)
	if ctx == nil {
		ctx = Ctx()
	}
	scheduleExpiredTrashPurge(cfg, bucket)
	if pageSize <= 0 {
		pageSize = defaultListPageSize
	}
	input := &s3.ListObjectsV2Input{
		Bucket:  &bucket,
		Prefix:  aws.String(trashMetadataPrefix(cfg)),
		MaxKeys: aws.Int32(pageSize),
	}
	if strings.TrimSpace(nextToken) != "" {
		input.ContinuationToken = aws.String(strings.TrimSpace(nextToken))
	}
	out, err := client.ListObjectsV2(ctx, input)
	if err != nil {
		return TrashPage{}, err
	}

	metadataKeys := make([]string, 0, len(out.Contents))
	for _, obj := range out.Contents {
		if obj.Key == nil || !strings.HasSuffix(*obj.Key, trashMetadataSuffix) {
			continue
		}
		metadataKeys = append(metadataKeys, *obj.Key)
	}
	items, err := loadTrashItemsPage(ctx, client, bucket, metadataKeys)
	if err != nil {
		return TrashPage{}, err
	}
	sort.Slice(items, func(i, j int) bool {
		return items[i].DeletedAt > items[j].DeletedAt
	})
	return TrashPage{
		Items:     items,
		NextToken: aws.ToString(out.NextContinuationToken),
	}, nil
}

func loadTrashItemsPage(
	ctx context.Context,
	client *s3.Client,
	bucket string,
	metadataKeys []string,
) ([]TrashItem, error) {
	if len(metadataKeys) == 0 {
		return []TrashItem{}, nil
	}

	items := make([]TrashItem, len(metadataKeys))
	var (
		wg       sync.WaitGroup
		mu       sync.Mutex
		firstErr error
		sem      = make(chan struct{}, trashMetadataPageConcurrency)
	)

	for index, metadataKey := range metadataKeys {
		wg.Add(1)
		sem <- struct{}{}
		go func(index int, metadataKey string) {
			defer wg.Done()
			defer func() {
				<-sem
			}()

			metadata, err := loadTrashMetadataByKey(ctx, client, bucket, metadataKey)
			if err != nil {
				mu.Lock()
				if firstErr == nil {
					firstErr = err
				}
				mu.Unlock()
				return
			}
			items[index] = trashItemFromMetadata(metadata)
		}(index, metadataKey)
	}

	wg.Wait()
	if firstErr != nil {
		return nil, firstErr
	}

	filtered := items[:0]
	for _, item := range items {
		if strings.TrimSpace(item.ID) == "" {
			continue
		}
		filtered = append(filtered, item)
	}
	return filtered, nil
}
