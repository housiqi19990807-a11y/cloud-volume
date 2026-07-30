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

func TestRunLoggedCommandUntilSuccessReturnsWhenProbeFindsMount(t *testing.T) {
	startedAt := time.Now()
	_, recovered, err := runLoggedCommandUntilSuccess(
		5*time.Second,
		10*time.Millisecond,
		"test-command-success-probe",
		func() (string, bool) { return "/Volumes/云卷-test", true },
		"/bin/sleep",
		"5",
	)
	if err != nil {
		t.Fatalf("runLoggedCommandUntilSuccess: %v", err)
	}
	if recovered != "/Volumes/云卷-test" {
		t.Fatalf("recovered path = %q", recovered)
	}
	if elapsed := time.Since(startedAt); elapsed > time.Second {
		t.Fatalf("mount confirmation waited for command completion: %v", elapsed)
	}
}
