// Directory upload walks local folders in the backend so Flutter stays responsive.
package storage

import (
	"context"
	"errors"
	"fmt"
	"io"
	"os"
	"path"
	"path/filepath"
	"strings"
	"sync"

	s3ops "remote-storage/go/s3"
)

const directoryUploadConcurrency = 4

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
	return uploadDirectoryFiles(ctx, backend, bucket, plan.files, taskID)
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
			key:    key,
		}
	}
	return backend.UploadReader(ctx, bucket, key, reader, size, "", path.Base(localPath))
}

func uploadDirectoryFiles(
	ctx context.Context,
	backend Backend,
	bucket string,
	files []directoryUploadFile,
	taskID string,
) error {
	if len(files) == 0 {
		return nil
	}
	ctx, cancel := context.WithCancel(ctx)
	defer cancel()
	jobs := make(chan directoryUploadFile)
	var wg sync.WaitGroup
	var mu sync.Mutex
	failures := directoryUploadFailures{}
	workerCount := directoryUploadWorkerCount(backend, len(files))
	if len(files) < workerCount {
		workerCount = len(files)
	}
	for range workerCount {
		wg.Add(1)
		go func() {
			defer wg.Done()
			for file := range jobs {
				if err := ctx.Err(); err != nil {
					recordDirectoryUploadError(&mu, &failures, err, cancel)
					return
				}
				if taskID != "" {
					s3ops.SetTransferTarget(taskID, file.remoteKey)
					s3ops.SetTransferCurrentFile(taskID, file.remoteKey, file.size)
				}
				if err := uploadDirectoryFile(ctx, backend, bucket, file.remoteKey, file.localPath, file.size, taskID); err != nil {
					recordDirectoryUploadError(
						&mu,
						&failures,
						fmt.Errorf("upload %s to %s: %w", file.localPath, file.remoteKey, err),
						cancel,
					)
					if isDirectoryUploadStopError(err) {
						return
					}
					continue
				}
				if taskID != "" {
					s3ops.AdvanceTransferItems(taskID, 1)
				}
			}
		}()
	}
sendFiles:
	for _, file := range files {
		select {
		case <-ctx.Done():
			break sendFiles
		case jobs <- file:
		}
	}
	close(jobs)
	wg.Wait()
	return failures.Err()
}

func recordDirectoryUploadError(
	mu *sync.Mutex,
	failures *directoryUploadFailures,
	err error,
	cancel context.CancelFunc,
) {
	mu.Lock()
	defer mu.Unlock()
	failures.Add(err)
	if isDirectoryUploadStopError(err) {
		cancel()
	}
}

func directoryUploadWorkerCount(backend Backend, fileCount int) int {
	workerCount := directoryUploadConcurrency
	if tuned, ok := backend.(interface{ DirectoryUploadConcurrency() int }); ok {
		if value := tuned.DirectoryUploadConcurrency(); value > 0 {
			workerCount = value
		}
	}
	if fileCount > 0 && fileCount < workerCount {
		return fileCount
	}
	return workerCount
}

func isDirectoryUploadStopError(err error) bool {
	return errors.Is(err, context.Canceled) || errors.Is(err, context.DeadlineExceeded)
}

type directoryUploadFailures struct {
	errs []error
}

func (f *directoryUploadFailures) Add(err error) {
	if err == nil {
		return
	}
	f.errs = append(f.errs, err)
}

func (f *directoryUploadFailures) Err() error {
	if len(f.errs) == 0 {
		return nil
	}
	return f
}

func (f *directoryUploadFailures) Error() string {
	if len(f.errs) == 1 {
		return f.errs[0].Error()
	}
	return fmt.Sprintf("%d files failed; first error: %v", len(f.errs), f.errs[0])
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
	key    string
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
		s3ops.AdvanceTransferCurrentFile(r.taskID, r.key, int64(n))
	}
	return n, err
}
