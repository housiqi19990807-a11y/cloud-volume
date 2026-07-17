// Phase planning tests pin item accounting for copy/delete sweep phases.
package s3

import (
	"context"
	"testing"
)

// A phase re-planned with the same count (progress pre-scan + transfer plan
// enumerating the same tree) must not double the total.
func TestPlanTransferPhaseItemsReplanningDoesNotDoubleCount(t *testing.T) {
	resetTransferMonitorForTest()

	_, cancel := context.WithCancel(context.Background())
	defer cancel()
	startTransfer("task-phase", "delete", "bucket", "dir/", "", 0, cancel)

	PlanTransferPhaseItems("task-phase", transferPhaseDelete, 103)
	PlanTransferPhaseItems("task-phase", transferPhaseCopy, 103)

	snapshot, ok := GetTransferSnapshot("task-phase")
	if !ok {
		t.Fatal("expected task snapshot")
	}
	if snapshot.TotalItems != 206 {
		t.Fatalf("TotalItems = %d, want 206", snapshot.TotalItems)
	}

	// Re-planning the copy phase with the same tree must keep the total.
	PlanTransferPhaseItems("task-phase", transferPhaseCopy, 103)
	snapshot, _ = GetTransferSnapshot("task-phase")
	if snapshot.TotalItems != 206 {
		t.Fatalf("after replan TotalItems = %d, want 206", snapshot.TotalItems)
	}
}

// The cleanup phase resets the running total so the bar restarts at 0/N for
// deletions instead of accumulating past the copy total.
func TestResetTransferPhaseItemsRestartsBar(t *testing.T) {
	resetTransferMonitorForTest()

	_, cancel := context.WithCancel(context.Background())
	defer cancel()
	startTransfer("task-reset", "delete", "bucket", "dir/", "", 0, cancel)

	PlanTransferPhaseItems("task-reset", transferPhaseDelete, 103)
	PlanTransferPhaseItems("task-reset", transferPhaseCopy, 103)
	for i := 0; i < 103; i++ {
		AdvanceTransferItems("task-reset", 1)
	}
	resetTransferPhaseItems("task-reset")

	snapshot, _ := GetTransferSnapshot("task-reset")
	if snapshot.TotalItems != 0 {
		t.Fatalf("after reset TotalItems = %d, want 0", snapshot.TotalItems)
	}
	if snapshot.ItemsCompleted != 103 {
		t.Fatalf("ItemsCompleted = %d, want 103 preserved", snapshot.ItemsCompleted)
	}

	PlanTransferPhaseItems("task-reset", transferPhaseDelete, 103)
	AdvanceTransferItems("task-reset", 1)
	snapshot, _ = GetTransferSnapshot("task-reset")
	if snapshot.TotalItems != 103 || snapshot.ItemsCompleted != 104 {
		t.Fatalf(
			"after replan got %d / %d, want 104 / 103 (bar clamps to 100%%)",
			snapshot.ItemsCompleted,
			snapshot.TotalItems,
		)
	}
}

// finishTransfer must present a clean "total / total" state even when the
// delete phase was over-planned from a narrower source listing.
func TestFinishTransferSettlesItemCounts(t *testing.T) {
	resetTransferMonitorForTest()

	_, cancel := context.WithCancel(context.Background())
	defer cancel()
	startTransfer("task-finish", "delete", "bucket", "dir/", "", 0, cancel)

	PlanTransferPhaseItems("task-finish", transferPhaseCopy, 103)
	for i := 0; i < 206; i++ {
		AdvanceTransferItems("task-finish", 1)
	}
	finishTransfer("task-finish", nil)

	snapshot, _ := GetTransferSnapshot("task-finish")
	if snapshot.Status != "done" {
		t.Fatalf("status = %q, want done", snapshot.Status)
	}
	if snapshot.ItemsCompleted != snapshot.TotalItems {
		t.Fatalf(
			"finished task shows %d / %d, want equal counts",
			snapshot.ItemsCompleted,
			snapshot.TotalItems,
		)
	}
}

