// Diagnostic logger for the standalone updater.
//
// Opens a log file at %TEMP%\cloud-volume-updater-<pid>.log on startup and
// appends timestamped lines for every step. This is critical for debugging
// update failures on user machines: the user can paste the log back so we can
// see exactly which step failed (download OK but extract failed? file lock?
// relaunch never started?). The logger is process-wide and safe for concurrent
// use from the UI goroutine and the update goroutine.
package main

import (
	"fmt"
	"os"
	"path/filepath"
	"sync"
	"time"
)

var (
	logMu  sync.Mutex
	logFile *os.File
)

// initLogger opens (or creates) the log file. Safe to call once at startup.
// If the file cannot be opened, logging silently degrades to no-op so the
// update still proceeds.
func initLogger() {
	tempDir := os.Getenv("TEMP")
	if tempDir == "" {
		tempDir = os.TempDir()
	}
	name := fmt.Sprintf("cloud-volume-updater-%d.log", os.Getpid())
	path := filepath.Join(tempDir, name)
	f, err := os.OpenFile(path, os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0644)
	if err != nil {
		return
	}
	logFile = f
	logf("=== cloud-volume-updater log opened %s ===", time.Now().Format(time.RFC3339))
}

// logf writes a timestamped line to the log file if it is open.
func logf(format string, args ...any) {
	logMu.Lock()
	defer logMu.Unlock()
	if logFile == nil {
		return
	}
	ts := time.Now().Format("2006-01-02 15:04:05.000")
	msg := fmt.Sprintf(format, args...)
	fmt.Fprintf(logFile, "[%s] %s\n", ts, msg)
	logFile.Sync()
}

