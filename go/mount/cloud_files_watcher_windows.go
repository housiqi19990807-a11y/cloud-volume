//go:build windows && cgo

// The sync-root watcher turns local Explorer edits into the existing bucket writeback flows.
package mount

import (
	"context"
	"log"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"

	"github.com/fsnotify/fsnotify"
)

type windowsPathState struct {
	mu        sync.Mutex
	ignored   map[string]time.Time
	hydrating map[string]bool
	kinds     map[string]bool
}

type windowsSyncWatcher struct {
	root   string
	access *bucketAccess
	raw    *fsnotify.Watcher
	state  *windowsPathState
	done   chan struct{}
	wg     sync.WaitGroup
}

func newWindowsSyncWatcher(root string, access *bucketAccess) (*windowsSyncWatcher, error) {
	rawWatcher, err := fsnotify.NewWatcher()
	if err != nil {
		return nil, err
	}
	return &windowsSyncWatcher{
		root:   filepath.Clean(root),
		access: access,
		raw:    rawWatcher,
		state: &windowsPathState{
			ignored:   map[string]time.Time{},
			hydrating: map[string]bool{},
			kinds:     map[string]bool{},
		},
		done: make(chan struct{}),
	}, nil
}

func (w *windowsSyncWatcher) Start() error {
	if err := w.rescanDirectories(); err != nil {
		return err
	}
	w.wg.Add(2)
	go w.run()
	go w.rescanLoop()
	return nil
}

func (w *windowsSyncWatcher) Close() error {
	close(w.done)
	w.wg.Wait()
	return w.raw.Close()
}

func (w *windowsSyncWatcher) RememberPlaceholders(baseDir string, items []cloudPlaceholderInfo) {
	for _, item := range items {
		fullPath := filepath.Join(baseDir, filepath.FromSlash(item.RelativePath))
		w.state.remember(fullPath, item.IsDirectory)
		w.state.ignore(fullPath, windowsCFEventIgnoreTTL)
	}
}

func (w *windowsSyncWatcher) MarkHydrating(localPath string) {
	w.state.markHydrating(localPath)
}

func (w *windowsSyncWatcher) MarkHydrated(localPath string) {
	w.state.markHydrated(localPath)
}

func (w *windowsSyncWatcher) IsDir(localPath string) bool {
	if info, err := os.Stat(localPath); err == nil {
		return info.IsDir()
	}
	return w.state.isDir(localPath)
}

func (w *windowsSyncWatcher) Forget(localPath string) {
	w.state.forget(localPath)
	_ = w.raw.Remove(localPath)
}

func (w *windowsSyncWatcher) Rebase(oldPath, newPath string, isDir bool) {
	w.state.rebase(oldPath, newPath, isDir)
}

func (w *windowsSyncWatcher) run() {
	defer w.wg.Done()
	for {
		select {
		case <-w.done:
			return
		case event, ok := <-w.raw.Events:
			if !ok {
				return
			}
			w.handleEvent(event)
		case err, ok := <-w.raw.Errors:
			if !ok {
				return
			}
			log.Printf("[mount/cloud-files] watcher error: %v", err)
		}
	}
}

func (w *windowsSyncWatcher) rescanLoop() {
	defer w.wg.Done()
	ticker := time.NewTicker(2 * time.Second)
	defer ticker.Stop()
	for {
		select {
		case <-w.done:
			return
		case <-ticker.C:
			if err := w.rescanDirectories(); err != nil {
				log.Printf("[mount/cloud-files] watcher rescan error: %v", err)
			}
		}
	}
}

func (w *windowsSyncWatcher) rescanDirectories() error {
	return filepath.WalkDir(w.root, func(current string, entry os.DirEntry, walkErr error) error {
		if walkErr != nil {
			return nil
		}
		if !entry.IsDir() {
			return nil
		}
		w.state.remember(current, true)
		_ = w.raw.Add(current)
		return nil
	})
}

func (w *windowsSyncWatcher) handleEvent(event fsnotify.Event) {
	localPath := filepath.Clean(event.Name)
	if isResumableUploadStatePath(localPath) {
		log.Printf("[mount/cloud-files] watcher-ignore-state path=%q", localPath)
		return
	}
	if w.state.shouldIgnore(localPath) {
		log.Printf("[mount/cloud-files] watcher-ignore event=%s path=%q", event.Op.String(), localPath)
		return
	}
	virtualPath := cloudFilesLocalPathToVirtual(w.root, localPath)
	if isWindowsLocalOnlyPath(virtualPath) {
		log.Printf("[mount/cloud-files] watcher-local-only event=%s path=%q", event.Op.String(), localPath)
		return
	}
	log.Printf(
		"[mount/cloud-files] watcher-event event=%s path=%q virtual=%q",
		event.Op.String(),
		localPath,
		virtualPath,
	)

	if event.Has(fsnotify.Create) {
		w.handleCreate(localPath, virtualPath)
	}
	if event.Has(fsnotify.Write) {
		w.handleWrite(localPath, virtualPath)
	}
	if event.Has(fsnotify.Remove) || event.Has(fsnotify.Rename) {
		w.Forget(localPath)
	}
}

func (w *windowsSyncWatcher) handleCreate(localPath, virtualPath string) {
	info, err := os.Stat(localPath)
	if err == nil && info.IsDir() {
		w.state.remember(localPath, true)
		_ = w.raw.Add(localPath)
		if err := w.access.createDirectory(context.Background(), virtualPath); err != nil {
			log.Printf("[mount/cloud-files] create directory %q: %v", virtualPath, err)
		}
		return
	}
	w.state.remember(localPath, false)
	w.scheduleUpload(localPath, virtualPath)
}

func (w *windowsSyncWatcher) handleWrite(localPath, virtualPath string) {
	if w.IsDir(localPath) {
		return
	}
	w.state.remember(localPath, false)
	w.scheduleUpload(localPath, virtualPath)
}

func (w *windowsSyncWatcher) scheduleUpload(localPath, virtualPath string) {
	clean := cleanVirtualPath(virtualPath)
	if clean == "" || strings.HasSuffix(clean, "/") {
		return
	}
	log.Printf(
		"[mount/cloud-files] queue-upload virtual=%q local=%q size=%d",
		clean,
		localPath,
		fileSize(localPath),
	)
	w.access.registerLocalWrite(clean, localPath, fileSize(localPath))
	w.access.scheduleUpload(clean, localPath)
}

func (s *windowsPathState) ignore(localPath string, ttl time.Duration) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.ignored[filepath.Clean(localPath)] = time.Now().Add(ttl)
}

func (s *windowsPathState) shouldIgnore(localPath string) bool {
	s.mu.Lock()
	defer s.mu.Unlock()

	now := time.Now()
	clean := filepath.Clean(localPath)
	for path := range s.hydrating {
		if clean == path || strings.HasPrefix(clean, path+string(os.PathSeparator)) {
			return true
		}
	}
	for path, until := range s.ignored {
		if now.After(until) {
			delete(s.ignored, path)
			continue
		}
		if clean == path || strings.HasPrefix(clean, path+string(os.PathSeparator)) {
			return true
		}
	}
	return false
}

func (s *windowsPathState) markHydrating(localPath string) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.hydrating[filepath.Clean(localPath)] = true
}

func (s *windowsPathState) markHydrated(localPath string) {
	s.mu.Lock()
	defer s.mu.Unlock()
	delete(s.hydrating, filepath.Clean(localPath))
}

func (s *windowsPathState) remember(localPath string, isDir bool) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.kinds[filepath.Clean(localPath)] = isDir
}

func (s *windowsPathState) isDir(localPath string) bool {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.kinds[filepath.Clean(localPath)]
}

func (s *windowsPathState) forget(localPath string) {
	s.mu.Lock()
	defer s.mu.Unlock()

	clean := filepath.Clean(localPath)
	for current := range s.hydrating {
		if current == clean || strings.HasPrefix(current, clean+string(os.PathSeparator)) {
			delete(s.hydrating, current)
		}
	}
	for current := range s.kinds {
		if current == clean || strings.HasPrefix(current, clean+string(os.PathSeparator)) {
			delete(s.kinds, current)
		}
	}
}

func (s *windowsPathState) rebase(oldPath, newPath string, isDir bool) {
	s.mu.Lock()
	defer s.mu.Unlock()

	oldClean := filepath.Clean(oldPath)
	newClean := filepath.Clean(newPath)
	updates := map[string]bool{}
	hydratingUpdates := map[string]bool{}
	for current := range s.hydrating {
		if current == oldClean || strings.HasPrefix(current, oldClean+string(os.PathSeparator)) {
			replacement := strings.Replace(current, oldClean, newClean, 1)
			hydratingUpdates[replacement] = true
			delete(s.hydrating, current)
		}
	}
	for current, currentIsDir := range s.kinds {
		if current == oldClean || strings.HasPrefix(current, oldClean+string(os.PathSeparator)) {
			replacement := strings.Replace(current, oldClean, newClean, 1)
			updates[replacement] = currentIsDir
			delete(s.kinds, current)
		}
	}
	if len(updates) == 0 {
		updates[newClean] = isDir
	}
	for current, currentIsDir := range updates {
		s.kinds[current] = currentIsDir
	}
	for current := range hydratingUpdates {
		s.hydrating[current] = true
	}
}

func isResumableUploadStatePath(localPath string) bool {
	return strings.HasSuffix(strings.ToLower(filepath.Clean(localPath)), ".uploading.json")
}
