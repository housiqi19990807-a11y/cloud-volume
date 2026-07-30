//go:build darwin

// macOS command tests keep process and inherited-pipe timeouts genuinely bounded.
package mount

import (
	"testing"
	"time"
)

func TestRunLoggedCommandBoundsInheritedPipeWait(t *testing.T) {
	startedAt := time.Now()
	_, err := runLoggedCommand(
		50*time.Millisecond,
		"test-inherited-pipe-timeout",
		"/bin/sh",
		"-c",
		"sleep 5 & wait",
	)
	if err == nil {
		t.Fatal("command unexpectedly completed without timeout")
	}
	if elapsed := time.Since(startedAt); elapsed > time.Second {
		t.Fatalf("command timeout remained blocked by inherited pipe for %v", elapsed)
	}
}
