//go:build !windows
// Non-Windows stubs so the updater compiles on macOS/Linux for development.
package main

import (
	"os"
	"time"
)

func waitForProcess(pid int, timeout time.Duration) {
	// Non-Windows: just sleep briefly since this updater is Windows-only.
	time.Sleep(time.Second)
}

func isFileWritable(path string) bool {
	_, err := os.Stat(path)
	return err == nil || os.IsNotExist(err)
}

// waitForNewApp is a no-op stub on non-Windows (the updater is Windows-only
// in production; this keeps cross-compilation working).
func waitForNewApp(exePath string, oldPID int, timeout time.Duration) int {
	time.Sleep(time.Second)
	return 0
}
