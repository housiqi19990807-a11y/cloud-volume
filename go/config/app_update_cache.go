// App update installer packages are cached under the user cache directory so
// a successful download can be reused on retry without re-fetching from GitHub.

package config

import (
	"fmt"
	"os"
	"path/filepath"
)

const appUpdateCacheSubdir = "app_updates"

// ResolveAppUpdateCacheDir returns <cache>/app_updates for persisted installers.
func ResolveAppUpdateCacheDir(cfg RemoteStorageConfig) (string, error) {
	root, err := ResolveCacheDir(cfg)
	if err != nil {
		return "", err
	}
	return filepath.Join(root, appUpdateCacheSubdir), nil
}

// UsableCachedInstaller reports whether path is a complete cached package.
// When expectedSize > 0 the on-disk size must match exactly.
func UsableCachedInstaller(path string, expectedSize int64) (bool, error) {
	info, err := os.Stat(path)
	if err != nil {
		if os.IsNotExist(err) {
			return false, nil
		}
		return false, err
	}
	if info.IsDir() || info.Size() <= 0 {
		return false, nil
	}
	if expectedSize > 0 && info.Size() != expectedSize {
		return false, nil
	}
	return true, nil
}

// InstallerCachePath joins cache dir and file name safely.
func InstallerCachePath(cacheDir, assetName string) (string, error) {
	if assetName == "" || filepath.Base(assetName) != assetName {
		return "", fmt.Errorf("invalid asset name %q", assetName)
	}
	return filepath.Join(cacheDir, assetName), nil
}
