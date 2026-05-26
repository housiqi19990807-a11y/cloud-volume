// Writeback queue delays mounted file uploads until the local file stays quiet for a while.
package mount

import (
	"context"
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
	q.mu.Unlock()

	err := q.flushNow(entry)
	if err != nil {
		q.enqueue(entry.virtualPath, entry.localPath, entry.size)
	}
}

func (q *writebackQueue) flushNow(entry *pendingWriteback) error {
	ctx, cancel := context.WithTimeout(context.Background(), q.access.transferTimeout)
	defer cancel()

	err := s3ops.UploadFileContext(
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
	return nil
}

func (q *writebackQueue) cancel(virtualPath string) bool {
	q.mu.Lock()
	defer q.mu.Unlock()

	entry, ok := q.entries[cleanVirtualPath(virtualPath)]
	if !ok {
		return false
	}
	if entry.timer != nil {
		entry.timer.Stop()
	}
	delete(q.entries, cleanVirtualPath(virtualPath))
	s3ops.CancelTransfer(entry.taskID)
	return true
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
			s3ops.CancelTransfer(entry.taskID)
			delete(q.entries, clean)
		}
		return
	}
	prefix := ensureDirSuffix(clean)
	for key, entry := range q.entries {
		if strings.HasPrefix(key, prefix) {
			if entry.timer != nil {
				entry.timer.Stop()
			}
			s3ops.CancelTransfer(entry.taskID)
			delete(q.entries, key)
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
		s3ops.CancelTransfer(entry.taskID)
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
	go func(item *pendingWriteback) {
		if err := q.flushNow(item); err != nil {
			q.enqueue(item.virtualPath, item.localPath, item.size)
		}
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
