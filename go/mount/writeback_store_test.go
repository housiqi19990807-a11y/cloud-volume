// Writeback store error tests keep lock-recovery messaging actionable.
package mount

import (
	"errors"
	"strings"
	"testing"

	bolt "go.etcd.io/bbolt"
)

func TestFormatWritebackStoreOpenErrorIncludesCleanupHintForTimeout(t *testing.T) {
	t.Parallel()

	err := formatWritebackStoreOpenError("C:/tmp/writeback.db", bolt.ErrTimeout)
	message := err.Error()
	if !strings.Contains(message, "writeback.db") {
		t.Fatalf("expected locked-store error to include path, got %q", message)
	}
	if !strings.Contains(message, "remote_storage.exe") {
		t.Fatalf("expected locked-store error to mention stale process cleanup, got %q", message)
	}
	if !strings.Contains(message, "结束残留占用进程") {
		t.Fatalf("expected locked-store error to mention settings recovery action, got %q", message)
	}
}

func TestFormatWritebackStoreOpenErrorLeavesGenericErrorsUnchanged(t *testing.T) {
	t.Parallel()

	err := formatWritebackStoreOpenError("C:/tmp/writeback.db", errors.New("permission denied"))
	message := err.Error()
	if !strings.Contains(message, "permission denied") {
		t.Fatalf("expected generic store error to preserve source failure, got %q", message)
	}
	if strings.Contains(message, "remote_storage.exe") {
		t.Fatalf("expected generic store error to avoid stale-process hint, got %q", message)
	}
}
