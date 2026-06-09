// Directory upload walks local folders in the backend so Flutter stays responsive.
package storage

import (
	"context"
	"fmt"
	"io"
	"os"
	"path"
	"path/filepath"
	"strings"

	s3ops "remote-storage/go/s3"
)

// UploadDirectory recursively creates remote directories and uploads files.
func UploadDirectory(
	ctx context.Context,
	backend Backend,
	bucket,
	prefix,
	localPath,
	taskID string,
) (err error) {
	cleanPrefix := strings.Trim(strings.TrimSpace(prefix), "/")
	if cleanPrefix != "" {
		cleanPrefix += "/"
	}
	if ctx == nil {
		ctx = context.Background()
	}
	ctx, cancel := context.WithCancel(ctx)
	defer cancel()
	rootName := filepath.Base(filepath.Clean(localPath))
	rootKey := cleanRemoteJoin(cleanPrefix, rootName)
	if taskID != "" {
		s3ops.StartQueuedTransfer(taskID, "upload", bucket, rootKey, localPath, 0, cancel)
		s3ops.SetTransferStatusDetail(taskID, "scanning")
		defer func() { s3ops.FinishQueuedTransfer(taskID, err) }()
	}
	rootInfo, err := os.Stat(localPath)
	if err != nil {
		return fmt.Errorf("stat local directory: %w", err)
	}
	if !rootInfo.IsDir() {
		return fmt.Errorf("local path is not a directory: %s", localPath)
	}
	plan, err := planDirectoryUpload(ctx, localPath, cleanPrefix, taskID)
	if err != nil {
		return err
	}
	for _, remoteKey := range plan.directories {
		if err := ctx.Err(); err != nil {
			return err
		}
		if taskID != "" {
			s3ops.SetTransferTarget(taskID, remoteKey+"/")
		}
		if err := createDirectoryPath(ctx, backend, bucket, remoteKey); err != nil {
			return err
		}
	}
	if taskID != "" {
		s3ops.SetTransferStatusDetail(taskID, "uploading")
	}
	for _, file := range plan.files {
		if err := ctx.Err(); err != nil {
			return err
		}
		if taskID != "" {
			s3ops.SetTransferTarget(taskID, file.remoteKey)
		}
		if err := uploadDirectoryFile(ctx, backend, bucket, file.remoteKey, file.localPath, file.size, taskID); err != nil {
			return err
		}
		if taskID != "" {
			s3ops.AdvanceTransferItems(taskID, 1)
		}
	}
	return nil
}

func planDirectoryUpload(
	ctx context.Context,
	localPath,
	cleanPrefix,
	taskID string,
) (directoryUploadPlan, error) {
	plan := directoryUploadPlan{}
	err := filepath.WalkDir(localPath, func(currentPath string, entry os.DirEntry, walkErr error) error {
		if walkErr != nil {
			return walkErr
		}
		if err := ctx.Err(); err != nil {
			return err
		}
		remoteKey, err := directoryUploadRemoteKey(localPath, currentPath, cleanPrefix)
		if err != nil {
			return err
		}
		if entry.IsDir() {
			plan.directories = append(plan.directories, remoteKey)
			return nil
		}
		if entry.Type()&os.ModeType != 0 {
			return nil
		}
		info, err := entry.Info()
		if err != nil {
			return err
		}
		if taskID != "" {
			s3ops.AddTransferTotal(taskID, info.Size())
			s3ops.AddTransferItems(taskID, 1)
			s3ops.SetTransferTarget(taskID, remoteKey)
		}
		plan.files = append(plan.files, directoryUploadFile{
			localPath: currentPath,
			remoteKey: remoteKey,
			size:      info.Size(),
		})
		return nil
	})
	return plan, err
}

func uploadDirectoryFile(
	ctx context.Context,
	backend Backend,
	bucket,
	key,
	localPath string,
	size int64,
	taskID string,
) error {
	file, err := os.Open(localPath)
	if err != nil {
		return fmt.Errorf("open local file: %w", err)
	}
	defer file.Close()
	reader := io.Reader(file)
	if taskID != "" {
		reader = &directoryProgressReader{
			ctx:    ctx,
			reader: file,
			taskID: taskID,
		}
	}
	return backend.UploadReader(ctx, bucket, key, reader, size, "", path.Base(localPath))
}

func directoryUploadRemoteKey(rootPath, currentPath, cleanPrefix string) (string, error) {
	parent := filepath.Dir(filepath.Clean(rootPath))
	relativePath, err := filepath.Rel(parent, currentPath)
	if err != nil {
		return "", err
	}
	parts := strings.Split(filepath.ToSlash(relativePath), "/")
	cleaned := make([]string, 0, len(parts))
	for _, part := range parts {
		if part == "" || part == "." {
			continue
		}
		cleaned = append(cleaned, part)
	}
	return cleanRemoteJoin(cleanPrefix, path.Join(cleaned...)), nil
}

func createDirectoryPath(ctx context.Context, backend Backend, bucket, remoteKey string) error {
	cleanKey := strings.Trim(strings.TrimSpace(remoteKey), "/")
	if cleanKey == "" {
		return nil
	}
	parent, name := path.Split(cleanKey)
	return backend.CreateDirectory(ctx, bucket, parent, name)
}

func cleanRemoteJoin(prefix, key string) string {
	cleanPrefix := strings.Trim(strings.TrimSpace(prefix), "/")
	cleanKey := strings.Trim(strings.TrimSpace(key), "/")
	if cleanPrefix == "" {
		return cleanKey
	}
	if cleanKey == "" {
		return cleanPrefix
	}
	return cleanPrefix + "/" + cleanKey
}

type directoryProgressReader struct {
	ctx    context.Context
	reader io.Reader
	taskID string
}

type directoryUploadPlan struct {
	directories []string
	files       []directoryUploadFile
}

type directoryUploadFile struct {
	localPath string
	remoteKey string
	size      int64
}

func (r *directoryProgressReader) Read(p []byte) (int, error) {
	if err := r.ctx.Err(); err != nil {
		return 0, err
	}
	n, err := r.reader.Read(p)
	if n > 0 {
		s3ops.AdvanceTransfer(r.taskID, int64(n))
	}
	return n, err
}
