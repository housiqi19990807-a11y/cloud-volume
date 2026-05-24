// Transfer monitor tests lock down cancellation state transitions.

package s3

import (
	"context"
	"testing"
	"time"
)

func TestCancelTransferBeforeStartCancelsOnRegistration(t *testing.T) {
	resetTransferMonitorForTest()

	if ok := CancelTransfer("task-pre-cancel"); !ok {
		t.Fatalf("expected pending cancel to be accepted")
	}

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	startTransfer(
		"task-pre-cancel",
		"upload",
		"bucket-a",
		"folder/demo.txt",
		"/tmp/demo.txt",
		128,
		cancel,
	)

	snapshots := ListTransferSnapshots()
	if len(snapshots) != 1 {
		t.Fatalf("expected 1 snapshot, got %d", len(snapshots))
	}
	if snapshots[0].Status != "canceled" {
		t.Fatalf("expected canceled status, got %q", snapshots[0].Status)
	}
	if ctx.Err() != context.Canceled {
		t.Fatalf("expected context to be canceled, got %v", ctx.Err())
	}
}

func TestFinishTransferMapsContextCanceledToCanceledStatus(t *testing.T) {
	resetTransferMonitorForTest()

	ctx, cancel := context.WithCancel(context.Background())
	startTransfer(
		"task-runtime-cancel",
		"download",
		"bucket-b",
		"movie.mp4",
		"/tmp/movie.mp4",
		0,
		cancel,
	)
	cancel()
	finishTransfer("task-runtime-cancel", ctx.Err())

	snapshots := ListTransferSnapshots()
	if len(snapshots) != 1 {
		t.Fatalf("expected 1 snapshot, got %d", len(snapshots))
	}
	if snapshots[0].Status != "canceled" {
		t.Fatalf("expected canceled status, got %q", snapshots[0].Status)
	}
}

func resetTransferMonitorForTest() {
	globalTransferMonitor.mu.Lock()
	defer globalTransferMonitor.mu.Unlock()
	globalTransferMonitor.tasks = map[string]*transferState{}
	globalTransferMonitor.pendingCancels = map[string]time.Time{}
}
