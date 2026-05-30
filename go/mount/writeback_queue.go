// Writeback queue delays mounted file uploads until the local file stays quiet for a while.
package mount

import (
	"context"
	"errors"
	"log"
	"os"
	"strings"
	"time"

	"github.com/google/uuid"

	s3ops "remote-storage/go/s3"
)

const (
	writebackRetryBaseDelay = 15 * time.Second
	writebackRetryMaxDelay  = 2 * time.Minute
)

func (q *writebackQueue) enqueue(virtualPath, localPath string, size int64) {
	q.mu.Lock()
	defer q.mu.Unlock()

	if q.closed {
		return
	}
	clean := cleanVirtualPath(virtualPath)
	taskID := "mount-writeback-" + uuid.NewString()
	if existing, ok := q.entries[clean]; ok {
		if existing.timer != nil {
			existing.timer.Stop()
		}
		taskID = existing.taskID
	}
	q.supersedeRunningLocked(clean, localPath)
	entry := &pendingWriteback{
		taskID:      taskID,
		virtualPath: clean,
		localPath:   localPath,
		size:        size,
	}
	s3ops.QueueTransfer(
		entry.taskID,
		"upload",
		q.access.bucket,
		entry.virtualPath,
		entry.localPath,
		entry.size,
	)
	q.entries[clean] = entry
	q.armTimerLocked(entry, writebackQuietPeriod)
	q.access.projectSyncState(entry.virtualPath, false)
}

func (q *writebackQueue) supersedeRunningLocked(virtualPath, localPath string) {
	for taskID, entry := range q.running {
		if entry.virtualPath != virtualPath {
			continue
		}
		entry.discard = true
		s3ops.CancelTransfer(taskID)
		s3ops.ForgetTransfer(taskID)
		if entry.localPath != "" {
			_ = s3ops.DiscardResumableUpload(q.access.config, entry.localPath)
		}
		break
	}
}

func (q *writebackQueue) dispatch() {
	defer q.wg.Done()
	for entry := range q.queue {
		if entry == nil {
			continue
		}
		q.wg.Add(1)
		err := q.pool.Submit(func() {
			defer q.wg.Done()
			q.flush(entry)
		})
		if err == nil {
			continue
		}
		q.wg.Done()
		log.Printf(
			"[mount/writeback] pool-submit bucket=%q path=%q error=%v",
			q.access.bucket,
			entry.virtualPath,
			err,
		)
		q.requeue(entry, writebackRetryBaseDelay)
	}
}

func (q *writebackQueue) armTimerLocked(
	entry *pendingWriteback,
	delay time.Duration,
) {
	if entry.timer != nil {
		entry.timer.Stop()
	}
	entry.timer = time.AfterFunc(delay, func() {
		q.enqueueReady(entry.virtualPath)
	})
}

func (q *writebackQueue) enqueueReady(virtualPath string) {
	q.mu.Lock()
	if q.closed {
		q.mu.Unlock()
		return
	}
	entry, ok := q.entries[cleanVirtualPath(virtualPath)]
	if !ok || entry.queued {
		q.mu.Unlock()
		return
	}
	entry.queued = true
	queue := q.queue
	q.mu.Unlock()
	queue <- entry
}

func (q *writebackQueue) claim(entry *pendingWriteback) bool {
	q.mu.Lock()
	defer q.mu.Unlock()

	current, ok := q.entries[entry.virtualPath]
	if !ok || current.taskID != entry.taskID || !current.queued {
		return false
	}
	current.queued = false
	delete(q.entries, current.virtualPath)
	q.running[current.taskID] = current
	return true
}

func (q *writebackQueue) flush(entry *pendingWriteback) {
	if !q.claim(entry) {
		return
	}

	err := q.flushNow(entry)
	q.mu.Lock()
	delete(q.running, entry.taskID)
	discard := entry.discard
	q.mu.Unlock()
	if err != nil && !discard && !errors.Is(err, context.Canceled) {
		q.requeue(entry, nextWritebackRetryDelay(entry.retryCount+1))
	}
}

func (q *writebackQueue) requeue(entry *pendingWriteback, delay time.Duration) {
	q.mu.Lock()
	defer q.mu.Unlock()

	if q.closed || entry.discard {
		return
	}
	entry.retryCount++
	entry.queued = false
	s3ops.QueueTransfer(
		entry.taskID,
		"upload",
		q.access.bucket,
		entry.virtualPath,
		entry.localPath,
		entry.size,
	)
	q.entries[entry.virtualPath] = entry
	q.armTimerLocked(entry, delay)
	q.access.projectSyncState(entry.virtualPath, false)
}

func (q *writebackQueue) flushNow(entry *pendingWriteback) error {
	ctx, cancel := q.access.withTransferTimeout(context.Background())
	defer cancel()

	err := s3ops.UploadFileContextResumable(
		ctx,
		q.access.config,
		q.access.bucket,
		q.access.remoteKey(entry.virtualPath),
		entry.localPath,
		entry.taskID,
	)
	if err != nil {
		return err
	}
	if info, statErr := os.Stat(entry.localPath); statErr == nil {
		q.access.cache.clearLocalFileMarker(entry.virtualPath)
		q.access.cache.storeObject(entry.virtualPath, s3ops.ObjectInfo{
			Key:          entry.virtualPath,
			Size:         info.Size(),
			LastModified: info.ModTime().Format("2006-01-02 15:04:05"),
			IsDir:        false,
		})
	}
	q.access.cache.invalidatePath(entry.virtualPath)
	q.access.projectSyncState(entry.virtualPath, true)
	return nil
}

func (q *writebackQueue) cancel(virtualPath string) bool {
	q.mu.Lock()
	defer q.mu.Unlock()

	clean := cleanVirtualPath(virtualPath)
	if entry, ok := q.entries[clean]; ok {
		if entry.timer != nil {
			entry.timer.Stop()
		}
		delete(q.entries, clean)
		entry.discard = true
		s3ops.CancelTransfer(entry.taskID)
		q.discardEntryLocalState(entry)
		return true
	}
	for _, entry := range q.running {
		if entry.virtualPath != clean {
			continue
		}
		entry.discard = true
		s3ops.CancelTransfer(entry.taskID)
		q.discardEntryLocalState(entry)
		return true
	}
	return false
}

func (q *writebackQueue) cancelAtOrBelow(virtualPath string, isDir bool) {
	q.mu.Lock()
	defer q.mu.Unlock()

	clean := cleanVirtualPath(virtualPath)
	if !isDir {
		if entry, ok := q.entries[clean]; ok {
			if entry.timer != nil {
				entry.timer.Stop()
			}
			entry.discard = true
			q.discardEntryLocalState(entry)
			s3ops.CancelTransfer(entry.taskID)
			delete(q.entries, clean)
		}
		for _, entry := range q.running {
			if entry.virtualPath != clean {
				continue
			}
			entry.discard = true
			q.discardEntryLocalState(entry)
			s3ops.CancelTransfer(entry.taskID)
		}
		return
	}
	prefix := ensureDirSuffix(clean)
	for key, entry := range q.entries {
		if strings.HasPrefix(key, prefix) {
			if entry.timer != nil {
				entry.timer.Stop()
			}
			entry.discard = true
			q.discardEntryLocalState(entry)
			s3ops.CancelTransfer(entry.taskID)
			delete(q.entries, key)
		}
	}
	for _, entry := range q.running {
		if strings.HasPrefix(entry.virtualPath, prefix) {
			entry.discard = true
			q.discardEntryLocalState(entry)
			s3ops.CancelTransfer(entry.taskID)
		}
	}
}

func (q *writebackQueue) rename(oldVirtualPath, newVirtualPath string, isDir bool) bool {
	q.mu.Lock()
	defer q.mu.Unlock()

	oldClean := cleanVirtualPath(oldVirtualPath)
	newClean := cleanVirtualPath(newVirtualPath)
	renamed := false
	if !isDir {
		entry, ok := q.entries[oldClean]
		if !ok {
			return false
		}
		if entry.timer != nil {
			entry.timer.Stop()
		}
		delete(q.entries, oldClean)
		entry.virtualPath = newClean
		entry.timer = time.AfterFunc(writebackQuietPeriod, func() {
			q.enqueueReady(newClean)
		})
		q.entries[newClean] = entry
		q.access.projectSyncState(entry.virtualPath, false)
		return true
	}

	oldPrefix := ensureDirSuffix(oldClean)
	newPrefix := ensureDirSuffix(newClean)
	for key, entry := range q.entries {
		if !strings.HasPrefix(key, oldPrefix) {
			continue
		}
		if entry.timer != nil {
			entry.timer.Stop()
		}
		delete(q.entries, key)
		entry.virtualPath = newPrefix + strings.TrimPrefix(key, oldPrefix)
		nextKey := entry.virtualPath
		entry.timer = time.AfterFunc(writebackQuietPeriod, func() {
			q.enqueueReady(nextKey)
		})
		q.entries[nextKey] = entry
		q.access.projectSyncState(entry.virtualPath, false)
		renamed = true
	}
	return renamed
}

func (q *writebackQueue) hasPendingAtOrBelow(virtualPath string, isDir bool) bool {
	q.mu.Lock()
	defer q.mu.Unlock()

	clean := cleanVirtualPath(virtualPath)
	if !isDir {
		_, ok := q.entries[clean]
		return ok
	}
	prefix := ensureDirSuffix(clean)
	for key := range q.entries {
		if strings.HasPrefix(key, prefix) {
			return true
		}
	}
	return false
}

func (q *writebackQueue) cancelTask(taskID string) bool {
	q.mu.Lock()
	defer q.mu.Unlock()

	for key, entry := range q.entries {
		if entry.taskID != taskID {
			continue
		}
		if entry.timer != nil {
			entry.timer.Stop()
		}
		delete(q.entries, key)
		entry.discard = true
		s3ops.CancelTransfer(entry.taskID)
		q.discardEntryLocalState(entry)
		return true
	}
	if entry, ok := q.running[taskID]; ok {
		entry.discard = true
		s3ops.CancelTransfer(entry.taskID)
		q.discardEntryLocalState(entry)
		return true
	}
	return false
}

func (q *writebackQueue) triggerTask(taskID string) bool {
	q.mu.Lock()
	if q.closed {
		q.mu.Unlock()
		return false
	}
	var entry *pendingWriteback
	for _, candidate := range q.entries {
		if candidate.taskID != taskID {
			continue
		}
		entry = candidate
		if entry.timer != nil {
			entry.timer.Stop()
		}
		entry.queued = true
		break
	}
	queue := q.queue
	q.mu.Unlock()
	if entry == nil {
		return false
	}
	queue <- entry
	return true
}

func (q *writebackQueue) shutdown() error {
	q.mu.Lock()
	if q.closed {
		q.mu.Unlock()
		return nil
	}
	q.closed = true
	entries := make([]*pendingWriteback, 0, len(q.entries))
	for key, entry := range q.entries {
		if entry.timer != nil {
			entry.timer.Stop()
		}
		entry.queued = false
		entries = append(entries, entry)
		delete(q.entries, key)
	}
	queue := q.queue
	q.mu.Unlock()

	close(queue)
	q.wg.Wait()
	q.pool.Release()

	for _, entry := range entries {
		if entry == nil {
			continue
		}
		log.Printf(
			"[mount/writeback] shutdown-flush bucket=%q path=%q local=%q size=%d",
			q.access.bucket,
			entry.virtualPath,
			entry.localPath,
			entry.size,
		)
		if err := q.flushNow(entry); err != nil {
			log.Printf(
				"[mount/writeback] shutdown-flush-error bucket=%q path=%q error=%v",
				q.access.bucket,
				entry.virtualPath,
				err,
			)
		}
	}
	return nil
}

func nextWritebackRetryDelay(retryCount int) time.Duration {
	if retryCount <= 0 {
		return writebackRetryBaseDelay
	}
	delay := writebackRetryBaseDelay
	for attempt := 1; attempt < retryCount; attempt++ {
		if delay >= writebackRetryMaxDelay {
			return writebackRetryMaxDelay
		}
		delay *= 2
	}
	if delay > writebackRetryMaxDelay {
		return writebackRetryMaxDelay
	}
	return delay
}

func (q *writebackQueue) discardEntryLocalState(entry *pendingWriteback) {
	q.access.cache.removeLocalFile(entry.virtualPath, false)
	q.access.cache.invalidatePath(entry.virtualPath)
	_ = s3ops.DiscardResumableUpload(q.access.config, entry.localPath)
}
