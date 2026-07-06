// Resumable installer download helpers for in-app updates.

package main

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strings"

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
//
// When expectedDigest is a non-empty ``sha256:<hex>`` string, the saved file is
// re-read and hashed after the size check; this catches mirrors that return
// same-length-but-wrong content where a size check alone would be fooled.
func downloadInstaller(
	ctx context.Context,
	client *http.Client,
	taskID, url, destPath, expectedDigest string,
	expectedSize int64,
) error {
	usable, err := storageconfig.UsableCachedInstaller(destPath, expectedSize)
	if err != nil {
		return err
	}
	if usable {
		// Even a size-matching cached file can be wrong content (mirror once
		// served a garbage same-length body). If we have a digest, verify the
		// cache is genuinely correct; otherwise fall through to re-download.
		if expectedDigest != "" {
			if digestErr := verifyDownloadedDigest(destPath, expectedDigest); digestErr != nil {
				usable = false
			}
		}
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
	// Close explicitly (not deferred) so the bytes are flushed to disk before
	// we stat the file for the post-download size integrity check.

	buf := make([]byte, 32*1024)
	var received int64
	for {
		n, readErr := resp.Body.Read(buf)
		if n > 0 {
			if _, writeErr := f.Write(buf[:n]); writeErr != nil {
				_ = f.Close()
				return fmt.Errorf("写入文件失败：%w", writeErr)
			}
			received += int64(n)
			s3ops.AdvanceTransfer(taskID, int64(n))
		}
		if readErr == io.EOF {
			break
		}
		if readErr != nil {
			_ = f.Close()
			return fmt.Errorf("读取响应失败：%w", readErr)
		}
	}
	if err := f.Close(); err != nil {
		return fmt.Errorf("关闭文件失败：%w", err)
	}

	if received == 0 && existing == 0 {
		return fmt.Errorf("未收到任何数据")
	}
	if totalBytes <= 0 {
		finalSize := existing + received
		if finalSize > 0 {
			s3ops.AddTransferTotal(taskID, finalSize)
		}
		// No expected size to verify against; leave integrity to the installer.
		return nil
	}

	// The download completed, but mirrors routinely serve a truncated body or
	// an HTML error page while still returning HTTP 200, which produces a
	// corrupt DMG/ZIP that only fails later at mount/extract time with a
	// confusing "image data corrupted" message. Verify the saved file matches
	// the GitHub-reported asset size before handing it to the installer.
	if err := verifyDownloadedSize(destPath, expectedSize); err != nil {
		return err
	}
	// Size alone can be fooled by same-length-wrong-content; the GitHub asset
	// digest (sha256:<hex>) is the authoritative content fingerprint.
	if err := verifyDownloadedDigest(destPath, expectedDigest); err != nil {
		return err
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

// verifyDownloadedSize confirms the on-disk file matches the expected byte
// count reported by GitHub. Mirrors frequently return a truncated body or an
// HTML error page with HTTP 200; without this check the saved file is silently
// handed to hdiutil/unzip, which then fails with a confusing "image data
// corrupted" error. On mismatch the partial file is removed so the next attempt
// starts clean instead of resuming a garbage prefix.
func verifyDownloadedSize(destPath string, expectedSize int64) error {
	if expectedSize <= 0 {
		return nil
	}
	info, err := os.Stat(destPath)
	if err != nil {
		return fmt.Errorf("校验下载文件失败：%w", err)
	}
	if info.Size() != expectedSize {
		_ = os.Remove(destPath)
		return fmt.Errorf(
			"下载文件大小不匹配（实际 %d 字节，应为 %d 字节），镜像可能返回了截断或错误内容",
			info.Size(), expectedSize,
		)
	}
	return nil
}

// verifyDownloadedDigest re-reads the saved file and compares its SHA-256
// against the GitHub asset digest (``sha256:<hex>``). Size alone is not a
// content check: some mirrors return a same-length but wrong payload. The
// mismatched file is removed so the next attempt starts clean.
func verifyDownloadedDigest(destPath, expectedDigest string) error {
	expected := strings.TrimSpace(expectedDigest)
	if expected == "" {
		return nil
	}
	const prefix = "sha256:"
	if !strings.HasPrefix(expected, prefix) {
		return nil
	}
	expectedHex := strings.ToLower(strings.TrimPrefix(expected, prefix))
	if decoded, err := hex.DecodeString(expectedHex); err != nil || len(decoded) != sha256.Size {
		// Not a usable digest; don't block the install on a malformed hint.
		return nil
	}

	f, err := os.Open(destPath)
	if err != nil {
		return fmt.Errorf("校验文件完整性失败：%w", err)
	}
	defer f.Close()

	h := sha256.New()
	if _, err := io.Copy(h, f); err != nil {
		return fmt.Errorf("计算校验和失败：%w", err)
	}
	actual := hex.EncodeToString(h.Sum(nil))
	if !strings.EqualFold(actual, expectedHex) {
		_ = os.Remove(destPath)
		return fmt.Errorf(
			"安装包校验和不匹配：下载内容已被损改，请尝试切换镜像或直连 GitHub 重新更新",
		)
	}
	return nil
}
