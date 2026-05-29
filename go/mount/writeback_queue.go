// Writeback queue delays mounted file uploads until the local file stays quiet for a while.
package mount

import (
	"context"
	"errors"
	"os"
	"strings"
	"time"

	"github.com/google/uuid"

	s3ops "remote-storage/go/s3"
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
	entry.timer = time.AfterFunc(writebackQuietPeriod, func() {
		q.flush(clean)
	})
	q.entries[clean] = entry
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

func (q *writebackQueue) flush(virtualPath string) {
	q.mu.Lock()
	if q.closed {
		q.mu.Unlock()
		return
	}
	entry, ok := q.entries[cleanVirtualPath(virtualPath)]
	if !ok {
		q.mu.Unlock()
		return
	}
	delete(q.entries, entry.virtualPath)
	q.running[entry.taskID] = entry
	q.mu.Unlock()

	err := q.flushNow(entry)
	q.mu.Lock()
	delete(q.running, entry.taskID)
	discard := entry.discard
	q.mu.Unlock()
	if err != nil && !discard && !errors.Is(err, context.Canceled) {
		q.enqueue(entry.virtualPath, entry.localPath, entry.size)
	}
}

func (q *writebackQueue) flushNow(entry *pendingWriteback) error {
	err := s3ops.UploadFileContextResumable(
		context.Background(),
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
			q.flush(newClean)
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
			q.flush(nextKey)
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
	for key, candidate := range q.entries {
		if candidate.taskID != taskID {
			continue
		}
		entry = candidate
		if entry.timer != nil {
			entry.timer.Stop()
		}
		delete(q.entries, key)
		break
	}
	q.mu.Unlock()
	if entry == nil {
		return false
	}
	q.mu.Lock()
	q.running[entry.taskID] = entry
	q.mu.Unlock()
	go func(item *pendingWriteback) {
		if err := q.flushNow(item); err != nil {
			q.mu.Lock()
			delete(q.running, item.taskID)
			discard := item.discard
			q.mu.Unlock()
			if discard || errors.Is(err, context.Canceled) {
				return
			}
			q.enqueue(item.virtualPath, item.localPath, item.size)
			return
		}
		q.mu.Lock()
		delete(q.running, item.taskID)
		q.mu.Unlock()
	}(entry)
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
		entries = append(entries, entry)
		delete(q.entries, key)
	}
	q.mu.Unlock()

	for _, entry := range entries {
		if entry == nil {
			continue
		}
		_ = q.flushNow(entry)
	}
	return nil
}

func (q *writebackQueue) discardEntryLocalState(entry *pendingWriteback) {
	q.access.cache.removeLocalFile(entry.virtualPath, false)
	q.access.cache.invalidatePath(entry.virtualPath)
	_ = s3ops.DiscardResumableUpload(q.access.config, entry.localPath)
}
