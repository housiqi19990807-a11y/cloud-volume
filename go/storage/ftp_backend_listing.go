// FTP listing and object inspection operations.
package storage

import (
	"context"
	"fmt"
	"os"
	"sort"
	"strings"
)

func (b ftpBackend) ListObjectsPage(
	ctx context.Context,
	_, prefix, _ string,
	_ int32,
) (ObjectPage, error) {
	return b.ftpListPage(ctx, prefix)
}

func (b ftpBackend) ListObjectsRecursive(
	ctx context.Context,
	bucket, prefix string,
) ([]ObjectInfo, error) {
	return b.ftpListRecursive(ctx, bucket, prefix)
}

// ftpListPage lists a single directory level on the FTP server.
func (b ftpBackend) ftpListPage(ctx context.Context, prefix string) (ObjectPage, error) {
	conn, err := b.ftpConnect(ctx)
	if err != nil {
		return ObjectPage{}, err
	}
	defer func() { _ = conn.Quit() }()

	entries, err := conn.List(ftpRemotePath(prefix))
	if err != nil {
		return ObjectPage{}, fmt.Errorf("ftp list %q: %w", prefix, err)
	}
	items := make([]ObjectInfo, 0, len(entries))
	parentDir := ftpRemotePath(prefix)
	for _, entry := range entries {
		if entry.Name == "." || entry.Name == ".." {
			continue
		}
		info := ftpEntryFromInfo(parentDir, entry)
		if info.Key != "" {
			items = append(items, info)
		}
	}
	ftpSortObjects(items)
	return ObjectPage{Items: items}, nil
}

// ftpListRecursive walks the directory tree, returning only file objects.
// FTP does not have a recursive list command so we walk directory by directory.
func (b ftpBackend) ftpListRecursive(
	ctx context.Context,
	bucket, prefix string,
) ([]ObjectInfo, error) {
	result := make([]ObjectInfo, 0, 64)
	queue := []string{strings.Trim(strings.TrimSpace(prefix), "/")}
	seen := map[string]struct{}{}
	for len(queue) > 0 {
		if ctx.Err() != nil {
			return nil, ctx.Err()
		}
		dir := queue[0]
		queue = queue[1:]
		if _, ok := seen[dir]; ok {
			continue
		}
		seen[dir] = struct{}{}
		page, err := b.ftpListPage(ctx, dir)
		if err != nil {
			return nil, err
		}
		for _, item := range page.Items {
			if item.IsDir {
				queue = append(queue, strings.TrimSuffix(item.Key, "/"))
				continue
			}
			result = append(result, item)
		}
	}
	return result, nil
}

func (b ftpBackend) HeadObject(
	ctx context.Context,
	_, key string,
) (ObjectInfo, error) {
	conn, err := b.ftpConnect(ctx)
	if err != nil {
		return ObjectInfo{}, err
	}
	defer func() { _ = conn.Quit() }()

	remotePath := ftpRemotePath(key)
	// For directories, check via list of parent.
	parentDir := ftpRemoteDir(remotePath)
	baseName := strings.TrimSuffix(strings.TrimRight(remotePath, "/"), "/")
	baseName = baseName[strings.LastIndexByte(baseName, '/')+1:]
	if baseName == "" {
		baseName = strings.TrimSuffix(key, "/")
		baseName = baseName[strings.LastIndexByte(baseName, '/')+1:]
	}

	entries, err := conn.List(parentDir)
	if err != nil {
		return ObjectInfo{}, fmt.Errorf("ftp list for head %q: %w", key, err)
	}
	for _, entry := range entries {
		if entry.Name == baseName {
			info := ftpEntryFromInfo(parentDir, entry)
			if info.Key == "" {
				info.Key = strings.TrimPrefix(strings.TrimPrefix(remotePath, "/"), "/")
				if entry.Type == 1 && !strings.HasSuffix(info.Key, "/") {
					info.Key += "/"
				}
			}
			return info, nil
		}
	}
	return ObjectInfo{}, os.ErrNotExist
}

// ftpRemoteDir returns the directory portion of an FTP path.
func ftpRemoteDir(remotePath string) string {
	trimmed := strings.TrimRight(remotePath, "/")
	idx := strings.LastIndexByte(trimmed, '/')
	if idx <= 0 {
		return "/"
	}
	return trimmed[:idx]
}

// ftpSortObjects mirrors WebDAV/S3 ordering: directories first, then by name.
func ftpSortObjects(items []ObjectInfo) {
	sort.SliceStable(items, func(i, j int) bool {
		left := items[i]
		right := items[j]
		if left.IsDir != right.IsDir {
			return left.IsDir
		}
		return strings.ToLower(left.Key) < strings.ToLower(right.Key)
	})
}
