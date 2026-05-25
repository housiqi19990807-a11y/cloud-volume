// Transfer monitor: keeps short-lived object operation snapshots for Flutter.

package s3

import (
	"context"
	"errors"
	"io"
	"sort"
	"sync"
	"time"
)

// TransferSnapshot is polled by Flutter to render sidebar and transfers UI.
type TransferSnapshot struct {
	ID             string  `json:"id"`
	Type           string  `json:"type"`
	Bucket         string  `json:"bucket"`
	Key            string  `json:"key"`
	LocalPath      string  `json:"localPath"`
	TargetPath     string  `json:"targetPath,omitempty"`
	Status         string  `json:"status"`
	BytesCompleted int64   `json:"bytesCompleted"`
	TotalBytes     int64   `json:"totalBytes"`
	SpeedBytes     float64 `json:"speedBytes"`
	Error          string  `json:"error,omitempty"`
}

type transferState struct {
	snapshot  TransferSnapshot
	startedAt time.Time
	updatedAt time.Time
	cancel    context.CancelFunc
}

type transferMonitor struct {
	mu             sync.Mutex
	tasks          map[string]*transferState
	pendingCancels map[string]time.Time
}

var globalTransferMonitor = &transferMonitor{
	tasks:          map[string]*transferState{},
	pendingCancels: map[string]time.Time{},
}

func startTransfer(
	id,
	kind,
	bucket,
	key,
	localPath string,
	totalBytes int64,
	cancel context.CancelFunc,
) {
	now := time.Now()
	globalTransferMonitor.mu.Lock()
	defer globalTransferMonitor.mu.Unlock()

	globalTransferMonitor.tasks[id] = &transferState{
		snapshot: TransferSnapshot{
			ID:         id,
			Type:       kind,
			Bucket:     bucket,
			Key:        key,
			LocalPath:  localPath,
			Status:     "running",
			TotalBytes: totalBytes,
		},
		startedAt: now,
		updatedAt: now,
		cancel:    cancel,
	}
	if _, ok := globalTransferMonitor.pendingCancels[id]; ok {
		delete(globalTransferMonitor.pendingCancels, id)
		globalTransferMonitor.tasks[id].snapshot.Status = "canceled"
		globalTransferMonitor.tasks[id].updatedAt = now
		if cancel != nil {
			cancel()
		}
	}
}

func setTransferTotal(id string, totalBytes int64) {
	globalTransferMonitor.mu.Lock()
	defer globalTransferMonitor.mu.Unlock()

	task, ok := globalTransferMonitor.tasks[id]
	if !ok {
		return
	}
	task.snapshot.TotalBytes = totalBytes
	task.updatedAt = time.Now()
}

func setTransferTarget(id string, targetPath string) {
	globalTransferMonitor.mu.Lock()
	defer globalTransferMonitor.mu.Unlock()

	task, ok := globalTransferMonitor.tasks[id]
	if !ok {
		return
	}
	task.snapshot.TargetPath = targetPath
	task.updatedAt = time.Now()
}

func advanceTransfer(id string, delta int64) {
	globalTransferMonitor.mu.Lock()
	defer globalTransferMonitor.mu.Unlock()

	task, ok := globalTransferMonitor.tasks[id]
	if !ok {
		return
	}
	task.snapshot.BytesCompleted += delta
	task.updatedAt = time.Now()

	elapsed := task.updatedAt.Sub(task.startedAt).Seconds()
	if elapsed > 0 {
		task.snapshot.SpeedBytes = float64(task.snapshot.BytesCompleted) / elapsed
	}
}

func finishTransfer(id string, err error) {
	globalTransferMonitor.mu.Lock()
	defer globalTransferMonitor.mu.Unlock()

	task, ok := globalTransferMonitor.tasks[id]
	if !ok {
		return
	}
	task.updatedAt = time.Now()
	task.cancel = nil
	task.snapshot.SpeedBytes = 0
	if errors.Is(err, context.Canceled) {
		task.snapshot.Status = "canceled"
		task.snapshot.Error = ""
		return
	}
	if err != nil {
		task.snapshot.Status = "failed"
		task.snapshot.Error = err.Error()
		return
	}
	task.snapshot.Status = "done"
	if task.snapshot.TotalBytes > 0 {
		task.snapshot.BytesCompleted = task.snapshot.TotalBytes
	}
}

// CancelTransfer stops an in-flight transfer when the task is still registered.
func CancelTransfer(id string) bool {
	globalTransferMonitor.mu.Lock()
	task, ok := globalTransferMonitor.tasks[id]
	if !ok {
		globalTransferMonitor.pendingCancels[id] = time.Now()
		globalTransferMonitor.mu.Unlock()
		return true
	}
	if task.snapshot.Status == "done" || task.snapshot.Status == "failed" {
		globalTransferMonitor.mu.Unlock()
		return false
	}
	cancel := task.cancel
	task.cancel = nil
	task.snapshot.Status = "canceled"
	task.snapshot.SpeedBytes = 0
	task.snapshot.Error = ""
	task.updatedAt = time.Now()
	globalTransferMonitor.mu.Unlock()

	if cancel != nil {
		cancel()
	}
	return true
}

// ListTransferSnapshots returns a recent-first list so the newest task stays visible.
func ListTransferSnapshots() []TransferSnapshot {
	globalTransferMonitor.mu.Lock()
	defer globalTransferMonitor.mu.Unlock()

	type item struct {
		snapshot  TransferSnapshot
		updatedAt time.Time
	}

	now := time.Now()
	for id, requestedAt := range globalTransferMonitor.pendingCancels {
		if now.Sub(requestedAt) > 10*time.Minute {
			delete(globalTransferMonitor.pendingCancels, id)
		}
	}
	result := make([]item, 0, len(globalTransferMonitor.tasks))
	for id, task := range globalTransferMonitor.tasks {
		if task.snapshot.Status != "running" && now.Sub(task.updatedAt) > 10*time.Minute {
			delete(globalTransferMonitor.tasks, id)
			continue
		}
		result = append(result, item{
			snapshot:  task.snapshot,
			updatedAt: task.updatedAt,
		})
	}

	sort.Slice(result, func(i, j int) bool {
		return result[i].updatedAt.After(result[j].updatedAt)
	})

	out := make([]TransferSnapshot, 0, len(result))
	for _, item := range result {
		out = append(out, item.snapshot)
	}
	return out
}

type countingReader struct {
	reader io.Reader
	onRead func(int)
}

func (r *countingReader) Read(p []byte) (int, error) {
	n, err := r.reader.Read(p)
	if n > 0 && r.onRead != nil {
		r.onRead(n)
	}
	return n, err
}

type contextReader struct {
	ctx    context.Context
	reader io.Reader
	onRead func(int)
}

func (r *contextReader) Read(p []byte) (int, error) {
	select {
	case <-r.ctx.Done():
		return 0, r.ctx.Err()
	default:
	}

	n, err := r.reader.Read(p)
	if n > 0 && r.onRead != nil {
		r.onRead(n)
	}
	if err != nil {
		return n, err
	}

	select {
	case <-r.ctx.Done():
		return n, r.ctx.Err()
	default:
		return n, nil
	}
}
