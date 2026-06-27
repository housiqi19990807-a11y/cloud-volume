// helpers.go holds small shared utilities used across reconcile, runner, and
// executor so those files stay focused on their core responsibility.
package sync

import (
	"os"
	"path/filepath"
	"time"
)

// localAbsPath reconstructs the absolute local filesystem path for a relative
// slash-separated key, honoring the platform path separator.
func localAbsPath(profile SyncProfile, rel string) string {
	return filepath.Join(profile.LocalPath, filepath.FromSlash(rel))
}

// localDirSide reports when rel is an existing local directory. scanLocal only
// indexes files, so classify must probe directories explicitly.
func localDirSide(profile SyncProfile, rel string) (localSide, bool) {
	path := localAbsPath(profile, rel)
	info, err := os.Stat(path)
	if err != nil || !info.IsDir() {
		return localSide{}, false
	}
	return localSide{
		mtime:   info.ModTime().UnixNano(),
		present: true,
		isDir:   true,
	}, true
}

// recentlyModified reports whether the file was written to within the window.
// Used by the quiet-period gate to defer hot files to the next cycle.
func recentlyModified(path string, window time.Duration) bool {
	info, err := os.Stat(path)
	if err != nil {
		return false
	}
	return time.Since(info.ModTime()) < window
}
