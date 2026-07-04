// Resumable installer download helpers for in-app updates.

package main

import (
	"context"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"

	storageconfig "remote-storage/go/config"
	s3ops "remote-storage/go/s3"
)

func resolveInstallerDestPath(cfg storageconfig.RemoteStorageConfig, assetName string) (string, error) {
	cacheDir, err := storageconfig.ResolveAppUpdateCacheDir(cfg)
	if err != nil {
		return "", err
	}
	if err := os.MkdirAll(cacheDir, 0o755); err != nil {
		return "", fmt.Errorf("创建缓存目录失败：%w", err)
	}
	return storageconfig.InstallerCachePath(cacheDir, assetName)
}

// downloadInstaller fetches the release asset with HTTP Range resume. A complete
// cached file matching expectedSize is reused without network I/O.
func downloadInstaller(
	ctx context.Context,
	client *http.Client,
	taskID, url, destPath string,
	expectedSize int64,
) error {
	usable, err := storageconfig.UsableCachedInstaller(destPath, expectedSize)
	if err != nil {
		return err
	}
	if usable {
		if expectedSize > 0 {
			s3ops.AddTransferTotal(taskID, expectedSize)
			s3ops.SetTransferCurrentFile(taskID, filepath.Base(destPath), expectedSize)
			s3ops.AdvanceTransfer(taskID, expectedSize)
		} else if info, statErr := os.Stat(destPath); statErr == nil {
			s3ops.AddTransferTotal(taskID, info.Size())
			s3ops.SetTransferCurrentFile(taskID, filepath.Base(destPath), info.Size())
			s3ops.AdvanceTransfer(taskID, info.Size())
		}
		s3ops.SetTransferStatusDetail(taskID, "cached")
		return nil
	}

	existing, err := existingPartialBytes(destPath, expectedSize)
	if err != nil {
		return err
	}
	if existing > 0 {
		s3ops.AdvanceTransfer(taskID, existing)
	}

	req, err := http.NewRequestWithContext(ctx, "GET", url, nil)
	if err != nil {
		return fmt.Errorf("创建请求失败：%w", err)
	}
	if existing > 0 {
		req.Header.Set("Range", fmt.Sprintf("bytes=%d-", existing))
	}

	resp, err := client.Do(req)
	if err != nil {
		return fmt.Errorf("请求失败：%w", err)
	}
	defer resp.Body.Close()

	switch resp.StatusCode {
	case http.StatusOK:
		if existing > 0 {
			// Server ignored Range; restart from scratch.
			_ = os.Remove(destPath)
			existing = 0
			s3ops.SetTransferStatusDetail(taskID, "downloading")
		}
	case http.StatusPartialContent:
		// Resume as expected.
	case http.StatusRequestedRangeNotSatisfiable:
		if usable, checkErr := storageconfig.UsableCachedInstaller(destPath, expectedSize); checkErr == nil && usable {
			return nil
		}
		return fmt.Errorf("HTTP %d", resp.StatusCode)
	default:
		if resp.StatusCode < 200 || resp.StatusCode >= 300 {
			return fmt.Errorf("HTTP %d", resp.StatusCode)
		}
	}

	totalBytes := expectedSize
	if totalBytes <= 0 && resp.ContentLength > 0 {
		if resp.StatusCode == http.StatusPartialContent {
			totalBytes = existing + resp.ContentLength
		} else {
			totalBytes = resp.ContentLength
		}
	}
	if totalBytes > 0 {
		s3ops.AddTransferTotal(taskID, totalBytes)
		s3ops.SetTransferCurrentFile(taskID, filepath.Base(destPath), totalBytes)
	}

	flags := os.O_CREATE | os.O_WRONLY
	if existing > 0 && resp.StatusCode == http.StatusPartialContent {
		flags |= os.O_APPEND
	} else {
		flags |= os.O_TRUNC
	}
	f, err := os.OpenFile(destPath, flags, 0o644)
	if err != nil {
		return fmt.Errorf("打开文件失败：%w", err)
	}
	defer f.Close()

	buf := make([]byte, 32*1024)
	var received int64
	for {
		n, readErr := resp.Body.Read(buf)
		if n > 0 {
			if _, writeErr := f.Write(buf[:n]); writeErr != nil {
				return fmt.Errorf("写入文件失败：%w", writeErr)
			}
			received += int64(n)
			s3ops.AdvanceTransfer(taskID, int64(n))
		}
		if readErr == io.EOF {
			break
		}
		if readErr != nil {
			return fmt.Errorf("读取响应失败：%w", readErr)
		}
	}

	if received == 0 && existing == 0 {
		return fmt.Errorf("未收到任何数据")
	}
	if totalBytes <= 0 {
		finalSize := existing + received
		if finalSize > 0 {
			s3ops.AddTransferTotal(taskID, finalSize)
		}
	}
	return nil
}

func existingPartialBytes(path string, expectedSize int64) (int64, error) {
	info, err := os.Stat(path)
	if err != nil {
		if os.IsNotExist(err) {
			return 0, nil
		}
		return 0, err
	}
	if info.IsDir() || info.Size() <= 0 {
		_ = os.Remove(path)
		return 0, nil
	}
	if expectedSize > 0 && info.Size() > expectedSize {
		_ = os.Remove(path)
		return 0, nil
	}
	if expectedSize > 0 && info.Size() == expectedSize {
		return 0, nil
	}
	return info.Size(), nil
}
