// Writeback rename barriers preserve Explorer mutation order without disabling upload concurrency.
package mount

import (
	"context"
	"fmt"
	"log"
	"path/filepath"
	"strings"
	"time"
)

const writebackBarrierPollInterval = 50 * time.Millisecond

type writebackBarrier struct {
	generation uint64
	finished   bool
}

type writebackSourceRebase struct {
	generation uint64
	oldRoot    string
	newRoot    string
	isDir      bool
}

type queuedWritebackRename struct {
	barrier       *writebackBarrier
	dirBarrier    *dirSyncBarrier
	oldVirtual    string
	newVirtual    string
	oldLocal      string
	newLocal      string
	isDir         bool
	run           func() error
	reportAttempt func(error)
}

func (q *writebackQueue) enqueueRename(
	oldVirtual,
	newVirtual,
	oldLocal,
	newLocal string,
	isDir bool,
	run func() error,
	dirBarrier *dirSyncBarrier,
	reportAttempt func(error),
) error {
	if q == nil || run == nil {
		return fmt.Errorf("writeback rename queue is unavailable")
	}

	q.mu.Lock()
	if q.closed {
		q.mu.Unlock()
		return fmt.Errorf("writeback queue is closed")
	}
	barrier := &writebackBarrier{generation: q.generation}
	q.generation++
	q.barriers = append(q.barriers, barrier)
	rebase := writebackSourceRebase{
		generation: barrier.generation,
		oldRoot:    filepath.Clean(oldLocal),
		newRoot:    filepath.Clean(newLocal),
		isDir:      isDir,
	}
	q.sourceRebases = append(q.sourceRebases, rebase)
	q.rebasePendingSourcesLocked(rebase)
	queue := q.renameQueue
	stop := q.stop
	q.mu.Unlock()

	op := &queuedWritebackRename{
		barrier:       barrier,
		dirBarrier:    dirBarrier,
		oldVirtual:    cleanVirtualPath(oldVirtual),
		newVirtual:    cleanVirtualPath(newVirtual),
		oldLocal:      oldLocal,
		newLocal:      newLocal,
		isDir:         isDir,
		run:           run,
		reportAttempt: reportAttempt,
	}
	log.Printf(
		"[mount/writeback] rename-queued bucket=%q old=%q new=%q generation=%d",
		q.bucketName(),
		op.oldVirtual,
		op.newVirtual,
		barrier.generation,
	)
	select {
	case queue <- op:
		return nil
	case <-stop:
		q.finishRenameBarrier(op, fmt.Errorf("writeback queue stopped before rename"))
		return fmt.Errorf("writeback queue stopped before rename")
	}
}

func (q *writebackQueue) dispatchRenames() {
	defer q.renameWG.Done()
	for {
		select {
		case <-q.stop:
			return
		case op := <-q.renameQueue:
			if op != nil {
				q.executeQueuedRename(op)
			}
		}
	}
}

func (q *writebackQueue) executeQueuedRename(op *queuedWritebackRename) {
	if err := q.drainThroughGeneration(op.barrier.generation); err != nil {
		q.finishRenameBarrier(op, err)
		return
	}
	access := q.currentAccess()
	if access != nil && access.dirSync != nil {
		if err := access.dirSync.wait(context.Background(), op.dirBarrier); err != nil {
			q.finishRenameBarrier(op, err)
			return
		}
	}

	for attempt := 0; ; attempt++ {
		err := op.run()
		if op.reportAttempt != nil {
			op.reportAttempt(err)
		}
		if err == nil {
			q.finishRenameBarrier(op, nil)
			return
		}
		log.Printf(
			"[mount/writeback] rename-retry bucket=%q old=%q new=%q attempt=%d error=%v",
			q.bucketName(),
			op.oldVirtual,
			op.newVirtual,
			attempt+1,
			err,
		)
		delay := nextWritebackRetryDelay(attempt + 1)
		select {
		case <-q.stop:
			q.finishRenameBarrier(op, err)
			return
		case <-time.After(delay):
		}
	}
}

func (q *writebackQueue) drainThroughGeneration(generation uint64) error {
	for {
		ready, pending, running, err := q.prepareBarrierPass(generation)
		if err != nil {
			return err
		}
		for _, entry := range ready {
			select {
			case q.queue <- entry:
			case <-q.stop:
				return fmt.Errorf("writeback queue stopped while draining rename barrier")
			}
		}
		if pending == 0 && running == 0 {
			return nil
		}
		select {
		case <-q.stop:
			return fmt.Errorf("writeback queue stopped while waiting for rename barrier")
		case <-time.After(writebackBarrierPollInterval):
		}
	}
}

func (q *writebackQueue) prepareBarrierPass(
	generation uint64,
) ([]*pendingWriteback, int, int, error) {
	q.mu.Lock()
	defer q.mu.Unlock()
	if q.closed {
		return nil, 0, 0, fmt.Errorf("writeback queue is closed")
	}

	ready := []*pendingWriteback{}
	pending := 0
	running := 0
	for _, entry := range q.entries {
		if entry == nil || entry.generation > generation {
			continue
		}
		pending++
		if entry.queued {
			continue
		}
		if entry.timer != nil {
			entry.timer.Stop()
			entry.timer = nil
		}
		entry.queued = true
		entry.dueAt = time.Now()
		q.persistEntryLocked(entry)
		ready = append(ready, entry)
	}
	for _, entry := range q.running {
		if entry != nil && entry.generation <= generation {
			running++
		}
	}
	return ready, pending, running, nil
}

func (q *writebackQueue) generationBlockedLocked(generation uint64) bool {
	for _, barrier := range q.barriers {
		if barrier != nil && !barrier.finished && generation > barrier.generation {
			return true
		}
	}
	return false
}

func (q *writebackQueue) rebasePendingSourcesLocked(rebase writebackSourceRebase) {
	for _, entry := range q.entries {
		if entry == nil || entry.generation > rebase.generation {
			continue
		}
		if next, ok := rebaseWritebackSource(entry.localPath, rebase); ok {
			entry.localPath = next
			q.persistEntryLocked(entry)
		}
	}
}

func (q *writebackQueue) resolveEntryLocalPath(entry *pendingWriteback) string {
	q.mu.Lock()
	defer q.mu.Unlock()
	if entry == nil {
		return ""
	}

	current := entry.localPath
	for _, rebase := range q.sourceRebases {
		if entry.generation > rebase.generation {
			continue
		}
		if next, ok := rebaseWritebackSource(current, rebase); ok {
			current = next
		}
	}
	if current != entry.localPath {
		entry.localPath = current
		q.persistEntryLocked(entry)
	}
	return current
}

func rebaseWritebackSource(
	localPath string,
	rebase writebackSourceRebase,
) (string, bool) {
	if strings.TrimSpace(localPath) == "" || rebase.oldRoot == "." || rebase.newRoot == "." {
		return localPath, false
	}
	relative, err := filepath.Rel(rebase.oldRoot, filepath.Clean(localPath))
	if err != nil {
		return localPath, false
	}
	if relative == "." {
		return rebase.newRoot, true
	}
	if !rebase.isDir || relative == ".." || strings.HasPrefix(relative, ".."+string(filepath.Separator)) {
		return localPath, false
	}
	return filepath.Join(rebase.newRoot, relative), true
}

func (q *writebackQueue) finishRenameBarrier(op *queuedWritebackRename, err error) {
	q.mu.Lock()
	if op != nil && op.barrier != nil {
		op.barrier.finished = true
		generation := op.barrier.generation
		keptRebases := q.sourceRebases[:0]
		for _, rebase := range q.sourceRebases {
			if rebase.generation != generation {
				keptRebases = append(keptRebases, rebase)
			}
		}
		q.sourceRebases = keptRebases
		for len(q.barriers) > 0 && q.barriers[0].finished {
			q.barriers = q.barriers[1:]
		}
	}
	q.mu.Unlock()

	if op != nil {
		log.Printf(
			"[mount/writeback] rename-finished bucket=%q old=%q new=%q error=%v",
			q.bucketName(),
			op.oldVirtual,
			op.newVirtual,
			err,
		)
	}
}
