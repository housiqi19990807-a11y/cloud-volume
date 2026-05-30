//go:build windows && cgo

// Watcher lifecycle helpers keep Cloud Files shutdown and harvest bookkeeping
// out of the main event-routing file.
package mount

import (
	"log"
	"os"
	"path/filepath"
	"strings"
	"time"
)

func (w *windowsSyncWatcher) signalStop() {
	w.closeOnce.Do(func() {
		close(w.done)
	})
}

func (w *windowsSyncWatcher) shouldStop() bool {
	select {
	case <-w.done:
		return true
	default:
		return false
	}
}

func (w *windowsSyncWatcher) addWatch(localPath string) {
	if w.shouldStop() {
		return
	}
	clean := filepath.Clean(localPath)
	info, err := os.Stat(clean)
	if err != nil || !info.IsDir() {
		return
	}
	w.rawMu.Lock()
	defer w.rawMu.Unlock()
	if w.rawClosed || w.raw == nil {
		return
	}
	if w.watched == nil {
		w.watched = map[string]bool{}
	}
	if w.watched[clean] {
		return
	}
	if err := w.raw.Add(clean); err != nil {
		log.Printf("[mount/cloud-files] watcher-add path=%q error=%v", clean, err)
		return
	}
	w.watched[clean] = true
}

func (w *windowsSyncWatcher) watchPlaceholderDirectories(baseDir string, items []cloudPlaceholderInfo) {
	for _, item := range items {
		if !item.IsDirectory {
			continue
		}
		fullPath := filepath.Join(baseDir, filepath.FromSlash(item.RelativePath))
		w.addWatch(fullPath)
	}
}

func (w *windowsSyncWatcher) removeWatchTree(localPath string) {
	clean := filepath.Clean(localPath)
	w.rawMu.Lock()
	defer w.rawMu.Unlock()
	if w.rawClosed || w.raw == nil || len(w.watched) == 0 {
		return
	}
	for watchedPath := range w.watched {
		if watchedPath == clean || strings.HasPrefix(watchedPath, clean+string(os.PathSeparator)) {
			_ = w.raw.Remove(watchedPath)
			delete(w.watched, watchedPath)
		}
	}
}

func (w *windowsSyncWatcher) closeRaw() error {
	w.rawMu.Lock()
	defer w.rawMu.Unlock()
	if w.rawClosed || w.raw == nil {
		return nil
	}
	w.rawClosed = true
	return w.raw.Close()
}

func (w *windowsSyncWatcher) touchActiveHarvestAncestors(localPath string) {
	clean := filepath.Clean(localPath)
	root := filepath.Clean(w.root)
	if clean != root && !strings.HasPrefix(clean, root+string(os.PathSeparator)) {
		return
	}

	now := time.Now()
	w.harvestMu.Lock()
	defer w.harvestMu.Unlock()

	for {
		if _, ok := w.activeHarvests[clean]; ok {
			w.activeHarvests[clean] = now
		}
		if clean == root {
			return
		}
		parent := filepath.Dir(clean)
		if parent == clean {
			return
		}
		clean = parent
	}
}

func isResumableUploadStatePath(localPath string) bool {
	return strings.HasSuffix(strings.ToLower(filepath.Clean(localPath)), ".uploading.json")
}
