//go:build windows

// Windows Cloud Files path helpers keep managed sync-root locations consistent.
package mount

import (
	"fmt"
	"os"
	"path/filepath"
	"sync/atomic"
	"time"
)

const windowsMountFolderName = "Cloud Volume"

var windowsCloudFilesMountCounter atomic.Uint64

func windowsCloudFilesRootPath() (string, error) {
	homeDir, err := os.UserHomeDir()
	if err != nil {
		return "", fmt.Errorf("resolve user home: %w", err)
	}
	return filepath.Join(homeDir, windowsMountFolderName), nil
}

func windowsCloudFilesMountPath(bucket string) (string, error) {
	rootPath, err := windowsCloudFilesRootPath()
	if err != nil {
		return "", err
	}
	return filepath.Join(rootPath, windowsCloudFilesMountDirName(bucket)), nil
}

func windowsCloudFilesMountDirName(bucket string) string {
	// Each mount gets a fresh sync-root directory so stale Cloud Files state
	// cannot be silently reused after an incomplete deregistration.
	sequence := windowsCloudFilesMountCounter.Add(1)
	return fmt.Sprintf(
		"%s-%s-%06d",
		safeSegment(bucket),
		time.Now().UTC().Format("20060102-150405-000000000"),
		sequence,
	)
}
