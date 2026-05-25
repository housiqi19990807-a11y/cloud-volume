package config

import (
	"fmt"
	"os"
	"path/filepath"
)

const runtimeDirName = "runtime"

// RuntimeDir returns the user-scoped runtime directory used for mount state,
// temporary transfer buffers, and other non-config app data.
func RuntimeDir() (string, error) {
	homePath, err := os.UserHomeDir()
	if err != nil {
		return "", fmt.Errorf("resolve user home: %w", err)
	}
	return filepath.Join(homePath, configDirName, runtimeDirName), nil
}

// MountRuntimeDir returns the directory used by mount helpers for cache files
// and per-bucket WebDAV buffer state.
func MountRuntimeDir() (string, error) {
	runtimeDir, err := RuntimeDir()
	if err != nil {
		return "", err
	}
	return filepath.Join(runtimeDir, "mounts"), nil
}
