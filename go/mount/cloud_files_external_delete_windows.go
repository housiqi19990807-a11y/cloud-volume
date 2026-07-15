//go:build windows && cgo

// Windows external deletion projects remote mutations into the Cloud Files sync root.
package mount

import (
	"fmt"
	"log"
	"os"
	"path/filepath"
	"strings"
)

func (b *windowsCloudFilesBackend) removeExternalPlaceholder(
	session *mountSession,
	watcher *windowsSyncWatcher,
	virtualPath string,
	isDir bool,
) error {
	if session == nil || watcher == nil {
		return nil
	}
	clean := cleanVirtualPath(virtualPath)
	if clean == "" {
		return fmt.Errorf("refusing to remove Cloud Files sync root")
	}

	localPath := cloudFilesVirtualPathToLocal(session.mountPath, clean)
	if !isLocalPathWithinRoot(session.mountPath, localPath) {
		return fmt.Errorf("placeholder path escapes sync root: %q", clean)
	}
	info, err := os.Lstat(localPath)
	if err != nil {
		if os.IsNotExist(err) {
			watcher.Forget(localPath)
			return nil
		}
		return fmt.Errorf("stat external delete placeholder: %w", err)
	}

	removeTree := isDir || info.IsDir()
	watcher.MarkProviderDelete(localPath, removeTree)
	if removeTree {
		err = os.RemoveAll(localPath)
	} else {
		err = os.Remove(localPath)
	}
	if err != nil {
		watcher.ClearProviderDelete(localPath)
		return fmt.Errorf("remove external delete placeholder: %w", err)
	}
	watcher.Forget(localPath)
	log.Printf(
		"[mount/cloud-files] external-delete-local path=%q virtual=%q isDir=%t",
		localPath,
		clean,
		removeTree,
	)
	return nil
}

func isLocalPathWithinRoot(rootPath, localPath string) bool {
	root := filepath.Clean(rootPath)
	current := filepath.Clean(localPath)
	return current != root &&
		strings.HasPrefix(strings.ToLower(current), strings.ToLower(root)+string(os.PathSeparator))
}

func (w *windowsSyncWatcher) MarkProviderDelete(localPath string, isDir bool) {
	w.state.markProviderDelete(localPath, isDir)
}

func (w *windowsSyncWatcher) ClearProviderDelete(localPath string) {
	w.state.clearProviderDelete(localPath)
}

func (w *windowsSyncWatcher) IsProviderDelete(localPath string) bool {
	return w.state.isProviderDelete(localPath)
}
