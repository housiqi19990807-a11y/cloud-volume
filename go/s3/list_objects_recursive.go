// list_objects_recursive.go lists every object key under a prefix for sync scans.
// Unlike ListObjectsPageContext, this does not use a delimiter so nested files are included.
package s3

import (
	"context"
	"log"
	"strings"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/service/s3"

	storageconfig "remote-storage/go/config"
)

// ListObjectsRecursiveContext returns files and empty directory placeholders under prefix.
func ListObjectsRecursiveContext(
	ctx context.Context,
	cfg storageconfig.RemoteStorageConfig,
	bucket, prefix string,
) ([]ObjectInfo, error) {
	client := NewClient(cfg)
	if ctx == nil {
		ctx = Ctx()
	}
	ctx, cancel := context.WithTimeout(ctx, objectListTimeout)
	defer cancel()
	startedAt := time.Now()
	if prefix != "" && !strings.HasSuffix(prefix, "/") {
		prefix += "/"
	}
	logPrefix := strings.TrimSuffix(prefix, "/")
	log.Printf("[s3/list-recursive] start bucket=%q prefix=%q", bucket, logPrefix)

	input := &s3.ListObjectsV2Input{
		Bucket: aws.String(bucket),
		Prefix: aws.String(prefix),
	}
	pager := s3.NewListObjectsV2Paginator(client, input)
	items := make([]ObjectInfo, 0, 64)
	for pager.HasMorePages() {
		if ctx.Err() != nil {
			return nil, ctx.Err()
		}
		page, err := pager.NextPage(ctx)
		if err != nil {
			log.Printf("[s3/list-recursive] error bucket=%q prefix=%q duration=%s err=%v", bucket, logPrefix, time.Since(startedAt).Round(time.Millisecond), err)
			return nil, err
		}
		for _, obj := range page.Contents {
			if obj.Key == nil {
				continue
			}
			key := *obj.Key
			if key == prefix {
				continue
			}
			if isRootTrashKey(cfg, key) {
				continue
			}
			if strings.HasSuffix(key, "/") {
				info := ObjectInfo{Key: key, Size: 0, IsDir: true}
				info.LastModified = formatObjectLastModified(obj.LastModified)
				items = append(items, info)
				continue
			}
			info := ObjectInfo{Key: key, Size: aws.ToInt64(obj.Size)}
			info.LastModified = formatObjectLastModified(obj.LastModified)
			info.ETag = aws.ToString(obj.ETag)
			items = append(items, info)
		}
	}
	if items == nil {
		items = []ObjectInfo{}
	}
	log.Printf("[s3/list-recursive] done bucket=%q prefix=%q duration=%s items=%d", bucket, logPrefix, time.Since(startedAt).Round(time.Millisecond), len(items))
	return items, nil
}
