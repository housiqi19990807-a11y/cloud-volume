//go:build windows

// Windows mount selection keeps Cloud Files variants, WebDAV fallback and the
// optional WinFsp virtual file system side by side. Cloud Files stays the
// default engine; WinFsp is selected only when the user opts in and the
// runtime reports that the WinFsp driver/service is installed.
package mount

import (
	"fmt"
	"log"
	"strings"

	storageconfig "remote-storage/go/config"
)

func newPlatformMountBackend(cfg storageconfig.RemoteStorageConfig) (mountBackend, error) {
	engine := cfg.WindowsMountEngine
	mode := normalizeWindowsMountMode(cfg.WindowsMountMode)
	log.Printf("[mount/windows] select-backend engine=%q mode=%q", engine, mode)

	if engine == storageconfig.WindowsMountEngineWinFsp {
		// WinFsp is only meaningful when CGO + the driver are available; the
		// cgo build file falls back to a clear error when WinFsp is missing.
		return newWindowsWinFspBackend(cfg)
	}

	switch mode {
	case storageconfig.WindowsMountModeWebDAV:
		return &windowsWebDAVBackend{}, nil
	case storageconfig.WindowsMountModeCloudFilesCached:
		return newWindowsCloudFilesBackend(storageconfig.WindowsMountModeCloudFilesCached)
	case storageconfig.WindowsMountModeCloudFilesDirect:
		return newWindowsCloudFilesBackend(storageconfig.WindowsMountModeCloudFilesDirect)
	default:
		return nil, fmt.Errorf("unsupported Windows mount mode %q", cfg.WindowsMountMode)
	}
}

func cleanupAllManagedMounts() error {
	if err := cleanupManagedWindowsCloudFilesArtifacts(); err != nil {
		return err
	}
	if err := cleanupManagedWindowsWinFspArtifacts(); err != nil {
		return err
	}
	return cleanupManagedWindowsWebDAVMounts()
}

func normalizeWindowsMountMode(value string) string {
	switch strings.ToLower(strings.TrimSpace(value)) {
	case storageconfig.WindowsMountModeCloudFilesDirect:
		return storageconfig.WindowsMountModeCloudFilesDirect
	case storageconfig.WindowsMountModeWebDAV:
		return storageconfig.WindowsMountModeWebDAV
	default:
		return storageconfig.WindowsMountModeCloudFilesCached
	}
}
