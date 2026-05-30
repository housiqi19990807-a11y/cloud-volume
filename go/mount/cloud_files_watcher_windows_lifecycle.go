//go:build windows && cgo

// Watcher lifecycle helpers keep Cloud Files shutdown and harvest bookkeeping
// out of the main event-routing file.
package mount

import (
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
	_ = w.raw.Add(localPath)
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
