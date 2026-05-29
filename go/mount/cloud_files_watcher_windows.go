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
	ignored   map[string]windowsIgnoredPath
	hydrating map[string]bool
	kinds     map[string]bool
	files     map[string]windowsObservedFile
}

type windowsIgnoredPath struct {
	until             time.Time
	ignoreDescendants bool
}

type windowsObservedFile struct {
	size    int64
	modTime int64
}

type windowsSyncWatcher struct {
	root   string
	access *bucketAccess
	raw    *fsnotify.Watcher
	state  *windowsPathState
	done   chan struct{}
	wg     sync.WaitGroup

	harvestMu      sync.Mutex
	activeHarvests map[string]bool
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
			ignored:   map[string]windowsIgnoredPath{},
			hydrating: map[string]bool{},
			kinds:     map[string]bool{},
			files:     map[string]windowsObservedFile{},
		},
		done:           make(chan struct{}),
		activeHarvests: map[string]bool{},
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
		// Ignore only the placeholder path itself so a freshly opened child
		// directory can still surface immediate user writes below it.
		w.state.ignore(fullPath, windowsCFEventIgnoreTTL, false)
		if item.IsDirectory {
			_ = w.raw.Add(fullPath)
		}
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
		w.harvestDirectoryTree(localPath)
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
	info, err := os.Stat(localPath)
	if err != nil || info.IsDir() {
		return
	}
	if !w.state.observeFile(localPath, info.Size(), info.ModTime()) {
		return
	}
	log.Printf(
		"[mount/cloud-files] queue-upload virtual=%q local=%q size=%d",
		clean,
		localPath,
		info.Size(),
	)
	w.access.registerLocalWrite(clean, localPath, info.Size())
	w.access.scheduleUpload(clean, localPath)
}

func (w *windowsSyncWatcher) harvestDirectoryTree(localPath string) {
	root := filepath.Clean(localPath)
	w.harvestMu.Lock()
	if w.activeHarvests[root] {
		w.harvestMu.Unlock()
		return
	}
	w.activeHarvests[root] = true
	w.harvestMu.Unlock()

	go func(root string) {
		defer func() {
			w.harvestMu.Lock()
			delete(w.activeHarvests, root)
			w.harvestMu.Unlock()
		}()

		// Large Explorer directory copies can keep materializing files for
		// several seconds after the parent directory CREATE event arrives.
		ticker := time.NewTicker(windowsCFDirectoryHarvestInterval)
		defer ticker.Stop()
		deadline := time.NewTimer(windowsCFDirectoryHarvestWindow)
		defer deadline.Stop()

		for {
			if err := w.ingestDirectoryTree(root); err != nil {
				log.Printf("[mount/cloud-files] harvest-directory path=%q error=%v", root, err)
			}
			select {
			case <-w.done:
				return
			case <-deadline.C:
				return
			case <-ticker.C:
			}
		}
	}(root)
}

func (w *windowsSyncWatcher) ingestDirectoryTree(localRoot string) error {
	root := filepath.Clean(localRoot)
	return filepath.WalkDir(root, func(current string, entry os.DirEntry, walkErr error) error {
		if walkErr != nil {
			return nil
		}
		if current == root {
			return nil
		}

		virtualPath := cloudFilesLocalPathToVirtual(w.root, current)
		if virtualPath == "" || isResumableUploadStatePath(current) {
			if entry.IsDir() {
				return filepath.SkipDir
			}
			return nil
		}
		if isWindowsLocalOnlyPath(virtualPath) {
			if entry.IsDir() {
				return filepath.SkipDir
			}
			return nil
		}

		w.state.remember(current, entry.IsDir())
		if entry.IsDir() {
			_ = w.raw.Add(current)
			if err := w.access.createDirectory(context.Background(), virtualPath); err != nil {
				log.Printf("[mount/cloud-files] create directory %q: %v", virtualPath, err)
			}
			return nil
		}

		w.scheduleUpload(current, virtualPath)
		return nil
	})
}

func (s *windowsPathState) ignore(
	localPath string,
	ttl time.Duration,
	ignoreDescendants bool,
) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.ignored[filepath.Clean(localPath)] = windowsIgnoredPath{
		until:             time.Now().Add(ttl),
		ignoreDescendants: ignoreDescendants,
	}
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
	for path, ignored := range s.ignored {
		if now.After(ignored.until) {
			delete(s.ignored, path)
			continue
		}
		if clean == path {
			return true
		}
		if ignored.ignoreDescendants &&
			strings.HasPrefix(clean, path+string(os.PathSeparator)) {
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

func (s *windowsPathState) observeFile(
	localPath string,
	size int64,
	modTime time.Time,
) bool {
	s.mu.Lock()
	defer s.mu.Unlock()

	clean := filepath.Clean(localPath)
	next := windowsObservedFile{
		size:    size,
		modTime: modTime.UnixNano(),
	}
	current, ok := s.files[clean]
	if ok && current == next {
		return false
	}
	s.files[clean] = next
	return true
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
	for current := range s.files {
		if current == clean || strings.HasPrefix(current, clean+string(os.PathSeparator)) {
			delete(s.files, current)
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
	fileUpdates := map[string]windowsObservedFile{}
	for current, file := range s.files {
		if current == oldClean || strings.HasPrefix(current, oldClean+string(os.PathSeparator)) {
			replacement := strings.Replace(current, oldClean, newClean, 1)
			fileUpdates[replacement] = file
			delete(s.files, current)
		}
	}
	if len(updates) == 0 {
		updates[newClean] = isDir
	}
	for current, currentIsDir := range updates {
		s.kinds[current] = currentIsDir
	}
	for current, file := range fileUpdates {
		s.files[current] = file
	}
	for current := range hydratingUpdates {
		s.hydrating[current] = true
	}
}

func isResumableUploadStatePath(localPath string) bool {
	return strings.HasSuffix(strings.ToLower(filepath.Clean(localPath)), ".uploading.json")
}
