//go:build windows && cgo

// The mutation queue keeps fsnotify and Cloud Files callbacks off bbolt commits.
package mount

import (
	"context"
	"errors"
	"log"
	"sync"

	"remote-storage/go/mount/metadata"
)

// windowsWatcherMutationQueue accepts watcher work without back-pressuring the
// fsnotify read loop. One worker preserves filesystem event order at the
// metadata journal boundary, and Stop drains already accepted work.
type windowsWatcherMutationQueue struct {
	mu       sync.Mutex
	ready    *sync.Cond
	jobs     []func()
	started  bool
	stopping bool
	done     chan struct{}
}

func newWindowsWatcherMutationQueue() *windowsWatcherMutationQueue {
	queue := &windowsWatcherMutationQueue{done: make(chan struct{})}
	queue.ready = sync.NewCond(&queue.mu)
	return queue
}

func (q *windowsWatcherMutationQueue) start() {
	if q == nil {
		return
	}
	q.mu.Lock()
	if q.started {
		q.mu.Unlock()
		return
	}
	q.started = true
	q.mu.Unlock()
	go q.run()
}

// submit is deliberately unbounded: blocking here can overflow fsnotify's
// kernel-backed stream during a large Explorer rename. Stop drains the slice
// before the metadata handle is released.
func (q *windowsWatcherMutationQueue) submit(job func()) bool {
	if q == nil {
		job()
		return true
	}
	q.mu.Lock()
	defer q.mu.Unlock()
	if q.stopping {
		return false
	}
	q.jobs = append(q.jobs, job)
	q.ready.Signal()
	return true
}

func (q *windowsWatcherMutationQueue) stopAndDrain() {
	if q == nil {
		return
	}
	q.mu.Lock()
	if !q.started {
		q.mu.Unlock()
		return
	}
	q.stopping = true
	q.ready.Broadcast()
	done := q.done
	q.mu.Unlock()
	<-done
}

func (q *windowsWatcherMutationQueue) run() {
	defer close(q.done)
	for {
		q.mu.Lock()
		for len(q.jobs) == 0 && !q.stopping {
			q.ready.Wait()
		}
		if len(q.jobs) == 0 {
			q.mu.Unlock()
			return
		}
		job := q.jobs[0]
		if len(q.jobs) == 1 {
			q.jobs = nil
		} else {
			q.jobs[0] = nil
			q.jobs = q.jobs[1:]
		}
		q.mu.Unlock()
		job()
	}
}

// enqueueDeletePath keeps an externally completed removal ordered behind any
// accepted rename without blocking the fsnotify reader or CFAPI callback.
func (w *windowsSyncWatcher) enqueueDeletePath(virtualPath string, isDir bool, onError func(error)) {
	w.submitMutation(func() {
		if err := w.access.deletePath(context.Background(), virtualPath, isDir); err != nil {
			log.Printf("[mount/cloud-files] delete path=%q error=%v", virtualPath, err)
			if onError != nil {
				onError(err)
			}
		}
	})
}

func (w *windowsSyncWatcher) enqueueCreateDirectory(virtualPath string) {
	w.submitMutation(func() {
		if err := w.access.createDirectory(context.Background(), virtualPath); err != nil {
			log.Printf("[mount/cloud-files] create directory %q: %v", virtualPath, err)
		}
	})
}

func (w *windowsSyncWatcher) enqueueLocalWrite(virtualPath, localPath string) bool {
	file, err := openMetadataWriteSource(localPath)
	if err != nil {
		log.Printf("[mount/cloud-files] open metadata write %q: %v", virtualPath, err)
		return false
	}
	if !w.submitMutation(func() {
		defer file.Close()
		if err := w.access.stageMetadataWriteFromOpenSource(virtualPath, localPath, file); err != nil {
			log.Printf("[mount/cloud-files] stage metadata write %q: %v", virtualPath, err)
		}
	}) {
		_ = file.Close()
		return false
	}
	return true
}

// enqueueRenamePath serializes durable rename admission while leaving the
// watcher loop free to keep consuming a burst of Explorer events.
func (w *windowsSyncWatcher) enqueueRenamePath(
	oldVirtualPath, newVirtualPath, oldLocalPath, newLocalPath string,
	isDir bool,
	onError func(error),
) bool {
	return w.submitMutation(func() {
		w.applyQueuedRename(
			oldVirtualPath, newVirtualPath, oldLocalPath, newLocalPath, isDir, onError,
		)
	})
}

// enqueueRenameFallbackIfNeeded retains a late CFAPI completion behind an
// already queued watcher rename. It runs only if that earlier admission fails
// and clears the dedupe marker, so an in-flight marker cannot lose the sole
// fallback event and a successful rename is still journaled exactly once.
func (w *windowsSyncWatcher) enqueueRenameFallbackIfNeeded(
	oldVirtualPath, newVirtualPath, oldLocalPath, newLocalPath string,
	isDir bool,
	onError func(error),
) bool {
	return w.submitMutation(func() {
		w.renameMu.Lock()
		defer w.renameMu.Unlock()
		if w.state.fallbackRenameHandled(oldLocalPath, newLocalPath) {
			return
		}
		w.state.markFallbackRenameHandled(oldLocalPath, newLocalPath)
		w.applyQueuedRename(
			oldVirtualPath, newVirtualPath, oldLocalPath, newLocalPath, isDir, onError,
		)
	})
}

func (w *windowsSyncWatcher) applyQueuedRename(
	oldVirtualPath, newVirtualPath, oldLocalPath, newLocalPath string,
	isDir bool,
	onError func(error),
) {
	err := w.access.enqueueRenamePath(
		oldVirtualPath, newVirtualPath, oldLocalPath, newLocalPath, isDir,
	)
	if err != nil && !isDir {
		// The physical file already has its new name. Preserve it by admitting a
		// write at the target before tombstoning a still-present Desired source.
		renameErr := err
		err = w.fallbackFailedFileRename(oldVirtualPath, newVirtualPath, newLocalPath)
		if err == nil {
			log.Printf(
				"[mount/cloud-files] rename fallback old=%q new=%q admission_error=%v",
				oldVirtualPath,
				newVirtualPath,
				renameErr,
			)
		}
	}
	if err != nil {
		w.state.clearFallbackRenameHandled(oldLocalPath, newLocalPath)
		log.Printf(
			"[mount/cloud-files] rename old=%q new=%q error=%v",
			oldVirtualPath,
			newVirtualPath,
			err,
		)
		if onError != nil {
			onError(err)
		}
		return
	}
	w.Rebase(oldLocalPath, newLocalPath, isDir)
}

func (w *windowsSyncWatcher) fallbackFailedFileRename(
	oldVirtualPath, newVirtualPath, newLocalPath string,
) error {
	file, err := openMetadataWriteSource(newLocalPath)
	if err != nil {
		return err
	}
	defer file.Close()
	if err := w.access.stageMetadataWriteFromOpenSource(newVirtualPath, newLocalPath, file); err != nil {
		return err
	}
	if err := w.access.deletePath(context.Background(), oldVirtualPath, false); err != nil &&
		!errors.Is(err, metadata.ErrNotFound) {
		return err
	}
	return nil
}

func (w *windowsSyncWatcher) submitMutation(job func()) bool {
	if w.mutations == nil {
		job()
		return true
	}
	return w.mutations.submit(job)
}
