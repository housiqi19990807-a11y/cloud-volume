// Baidu Pan backend adapts xpan into the app's single-bucket storage contract.
package storage

import (
	"context"
	"fmt"
	"path"
	"strconv"
	"strings"

	"github.com/google/uuid"
	xpanclient "github.com/lfhy/xpan/client"
	xpanfile "github.com/lfhy/xpan/file"
	xpantypes "github.com/lfhy/xpan/types"

	storageconfig "remote-storage/go/config"
)

type baiduPanBackend struct {
	cfg storageconfig.RemoteStorageConfig
}

func newBaiduPanBackend(cfg storageconfig.RemoteStorageConfig) Backend {
	return baiduPanBackend{cfg: cfg.Normalized()}
}

// SupportsMountPrefetch disables directory preview prefetch to avoid Baidu Pan rate limits.
func (b baiduPanBackend) SupportsMountPrefetch() bool {
	return false
}

func (b baiduPanBackend) bucketConfig(bucket string) storageconfig.RemoteStorageConfig {
	return b.cfg.WithBucketSettingsApplied(bucket)
}

func (b baiduPanBackend) ListBuckets(context.Context) ([]BucketInfo, error) {
	return []BucketInfo{{Name: baiduPanBucketLabel(b.cfg)}}, nil
}

func (b baiduPanBackend) ListObjectsPage(
	_ context.Context,
	bucket string,
	prefix string,
	nextToken string,
	pageSize int32,
) (ObjectPage, error) {
	start := 0
	if strings.TrimSpace(nextToken) != "" {
		parsed, err := strconv.Atoi(strings.TrimSpace(nextToken))
		if err != nil {
			return ObjectPage{}, fmt.Errorf("invalid next token: %w", err)
		}
		start = parsed
	}
	if pageSize <= 0 {
		pageSize = 200
	}
	remoteDir := baiduPanDirectoryPath(prefix)
	return withBaiduPanClient(b.bucketConfig(bucket), func(client *xpanclient.Client) (ObjectPage, error) {
		res, err := client.ListObjects(remoteDir, &xpanfile.ListAllReq{
			Start: start,
			Limit: int(pageSize),
			Order: xpantypes.ListOrderName,
		})
		if err != nil {
			return ObjectPage{}, err
		}
		items := make([]ObjectInfo, 0, len(res.List))
		for _, item := range res.List {
			items = append(items, baiduPanObjectInfo(item))
		}
		page := ObjectPage{Items: items}
		if res.HasMore == xpantypes.BoolIntTrue {
			page.NextToken = strconv.Itoa(res.Cursor)
		}
		return page, nil
	})
}

func (b baiduPanBackend) HeadObject(
	_ context.Context,
	bucket string,
	key string,
) (ObjectInfo, error) {
	clean := baiduPanCleanKey(key)
	if clean == "" {
		return ObjectInfo{Key: "", IsDir: true}, nil
	}
	remotePath := baiduPanObjectPath(clean)
	return withBaiduPanClient(b.bucketConfig(bucket), func(client *xpanclient.Client) (ObjectInfo, error) {
		meta, err := client.StatObject(remotePath)
		if err != nil {
			return ObjectInfo{}, err
		}
		return baiduPanObjectInfoFromMeta(clean, meta), nil
	})
}

func (b baiduPanBackend) ReadObjectRange(
	ctx context.Context,
	bucket string,
	key string,
	offset, length int64,
) ([]byte, error) {
	return b.readObjectRange(ctx, bucket, key, offset, length)
}

func (b baiduPanBackend) DirectoryAccess(
	_ context.Context,
	bucket string,
	_ string,
) (DirectoryAccess, error) {
	return DirectoryAccess{
		Writable: !b.bucketConfig(bucket).BucketSettingsFor(bucket).ReadOnly,
		Known:    true,
	}, nil
}

func (b baiduPanBackend) CreateDirectory(
	_ context.Context,
	bucket string,
	prefix string,
	name string,
) error {
	if err := b.ensureBucketWritable(bucket); err != nil {
		return err
	}
	remotePath := baiduPanObjectPath(path.Join(baiduPanCleanKey(prefix), strings.Trim(strings.TrimSpace(name), "/")))
	_, err := withBaiduPanClient(b.bucketConfig(bucket), func(client *xpanclient.Client) (struct{}, error) {
		if err := ensureBaiduPanDir(client, path.Dir(remotePath)); err != nil {
			return struct{}{}, err
		}
		_, err := client.Mkdir(remotePath)
		if err != nil {
			if dirErr := ensureExistingBaiduPanDir(client, remotePath, err); dirErr == nil {
				return struct{}{}, nil
			}
			return struct{}{}, err
		}
		return struct{}{}, nil
	})
	return err
}

func (b baiduPanBackend) DeleteObject(
	_ context.Context,
	bucket string,
	key string,
	_ bool,
	_ string,
) error {
	if err := b.ensureBucketWritable(bucket); err != nil {
		return err
	}
	_, err := withBaiduPanClient(b.bucketConfig(bucket), func(client *xpanclient.Client) (struct{}, error) {
		_, err := client.DeleteObject(baiduPanObjectPath(key))
		return struct{}{}, err
	})
	return err
}

func (b baiduPanBackend) DeleteObjectHard(
	ctx context.Context,
	bucket string,
	key string,
	isDirectory bool,
	taskID string,
) error {
	return b.DeleteObject(ctx, bucket, key, isDirectory, taskID)
}

func (b baiduPanBackend) ListTrashPage(
	_ context.Context,
	_ string,
	_ string,
	_ int32,
) (TrashPage, error) {
	return TrashPage{Items: []TrashItem{}}, nil
}

func (b baiduPanBackend) RestoreTrashItem(_ context.Context, _, _ string) error {
	return fmt.Errorf("百度网盘账号暂不支持应用级回收站恢复")
}

func (b baiduPanBackend) DeleteTrashItem(_ context.Context, _, _ string) error {
	return fmt.Errorf("百度网盘账号暂不支持应用级回收站删除")
}

func (b baiduPanBackend) ClearTrash(_ context.Context, _ string) error {
	return fmt.Errorf("百度网盘账号暂不支持应用级回收站清空")
}

func (b baiduPanBackend) RenameObject(
	_ context.Context,
	bucket string,
	key string,
	_ bool,
	newName string,
) error {
	if err := b.ensureBucketWritable(bucket); err != nil {
		return err
	}
	_, err := withBaiduPanClient(b.bucketConfig(bucket), func(client *xpanclient.Client) (struct{}, error) {
		_, err := client.RenameObject(
			baiduPanObjectPath(key),
			strings.Trim(strings.TrimSpace(newName), "/"),
		)
		return struct{}{}, err
	})
	return err
}

func (b baiduPanBackend) CopyObject(
	_ context.Context,
	bucket string,
	sourceKey string,
	targetKey string,
	_ bool,
	_ string,
) error {
	if err := b.ensureBucketWritable(bucket); err != nil {
		return err
	}
	destDir, newName := baiduPanMoveTarget(targetKey)
	_, err := withBaiduPanClient(b.bucketConfig(bucket), func(client *xpanclient.Client) (struct{}, error) {
		if err := ensureBaiduPanDir(client, destDir); err != nil {
			return struct{}{}, err
		}
		_, err := client.CopyObject(baiduPanObjectPath(sourceKey), destDir, newName)
		return struct{}{}, err
	})
	return err
}

func (b baiduPanBackend) MoveObject(
	_ context.Context,
	bucket string,
	sourceKey string,
	targetKey string,
	_ bool,
	_ string,
) error {
	if err := b.ensureBucketWritable(bucket); err != nil {
		return err
	}
	destDir, newName := baiduPanMoveTarget(targetKey)
	_, err := withBaiduPanClient(b.bucketConfig(bucket), func(client *xpanclient.Client) (struct{}, error) {
		if err := ensureBaiduPanDir(client, destDir); err != nil {
			return struct{}{}, err
		}
		_, err := client.MoveObject(baiduPanObjectPath(sourceKey), destDir, newName)
		return struct{}{}, err
	})
	return err
}

func (b baiduPanBackend) ensureBucketWritable(bucket string) error {
	if b.bucketConfig(bucket).BucketSettingsFor(bucket).ReadOnly {
		return fmt.Errorf("当前存储桶已配置为只读，无法写入")
	}
	return nil
}

func baiduPanObjectInfo(item *xpanfile.ListItem) ObjectInfo {
	key := strings.TrimPrefix(strings.TrimSpace(item.Path), "/")
	isDir := item.IsDir == xpantypes.BoolIntTrue
	if isDir && key != "" && !strings.HasSuffix(key, "/") {
		key += "/"
	}
	return ObjectInfo{
		Key:          key,
		Size:         int64(item.Size),
		LastModified: item.ServerMtime.String(),
		IsDir:        isDir,
	}
}

func baiduPanObjectInfoFromMeta(
	key string,
	meta *xpanfile.FilemetasItem,
) ObjectInfo {
	isDir := meta.IsDir == xpantypes.BoolIntTrue
	clean := baiduPanCleanKey(key)
	if isDir && clean != "" && !strings.HasSuffix(clean, "/") {
		clean += "/"
	}
	return ObjectInfo{
		Key:          clean,
		Size:         int64(meta.Size),
		LastModified: meta.ServerMtime.String(),
		IsDir:        isDir,
	}
}

func baiduPanDirectoryPath(prefix string) string {
	clean := baiduPanCleanKey(prefix)
	if clean == "" {
		return "/"
	}
	return "/" + strings.TrimSuffix(clean, "/")
}

func baiduPanObjectPath(key string) string {
	clean := baiduPanCleanKey(key)
	if clean == "" {
		return "/"
	}
	return "/" + clean
}

func baiduPanCleanKey(key string) string {
	trimmed := strings.TrimSpace(key)
	if trimmed == "" || trimmed == "/" {
		return ""
	}
	clean := path.Clean("/" + strings.Trim(trimmed, "/"))
	if clean == "/" || clean == "." {
		return ""
	}
	return strings.TrimPrefix(clean, "/")
}

func baiduPanMoveTarget(targetKey string) (destDir string, newName string) {
	remotePath := baiduPanObjectPath(targetKey)
	clean := strings.TrimSuffix(remotePath, "/")
	return path.Dir(clean), path.Base(clean)
}

func baiduPanTempUploadPath(fileName string, key string) string {
	base := strings.TrimSpace(fileName)
	if base == "" {
		base = path.Base(baiduPanObjectPath(key))
	}
	base = strings.TrimSpace(base)
	if base == "" || base == "." || base == "/" {
		base = "upload.bin"
	}
	return baiduPanUploadRoot + "/" + uuid.NewString() + "-" + base
}

func ensureBaiduPanDir(client *xpanclient.Client, remoteDir string) error {
	clean := path.Clean(strings.TrimSpace(remoteDir))
	if clean == "." || clean == "/" || clean == "" {
		return nil
	}
	parts := strings.Split(strings.TrimPrefix(clean, "/"), "/")
	current := ""
	for _, part := range parts {
		if strings.TrimSpace(part) == "" {
			continue
		}
		current += "/" + part
		if _, err := client.Mkdir(current); err != nil {
			if statErr := ensureExistingBaiduPanDir(client, current, err); statErr != nil {
				return err
			}
		}
	}
	return nil
}

func ensureExistingBaiduPanDir(
	client *xpanclient.Client,
	remoteDir string,
	originalErr error,
) error {
	meta, err := client.StatObject(remoteDir)
	if err != nil {
		return originalErr
	}
	if meta.IsDir == xpantypes.BoolIntTrue {
		return nil
	}
	return originalErr
}
