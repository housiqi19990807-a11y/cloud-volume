// Transfer monitor: keeps short-lived in-memory transfer snapshots for Flutter.

package s3

import (
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
}

type transferMonitor struct {
	mu    sync.Mutex
	tasks map[string]*transferState
}

var globalTransferMonitor = &transferMonitor{
	tasks: map[string]*transferState{},
}

func startTransfer(id, kind, bucket, key, localPath string, totalBytes int64) {
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
	}
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
	task.snapshot.SpeedBytes = 0
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

// ListTransferSnapshots returns a recent-first list so the newest task stays visible.
func ListTransferSnapshots() []TransferSnapshot {
	globalTransferMonitor.mu.Lock()
	defer globalTransferMonitor.mu.Unlock()

	type item struct {
		snapshot  TransferSnapshot
		updatedAt time.Time
	}

	now := time.Now()
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
	reader interface{ Read([]byte) (int, error) }
	onRead func(int)
}

func (r *countingReader) Read(p []byte) (int, error) {
	n, err := r.reader.Read(p)
	if n > 0 && r.onRead != nil {
		r.onRead(n)
	}
	return n, err
}
