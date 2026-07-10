//go:build windows

// Headless updater for Windows: no window, no message pump.
// The updater silently waits for the old process, replaces files,
// relaunches the app, and exits. All diagnostics go to the log file.
package main

import "os"

// runWithWindow runs the update headlessly (the name is kept for call-site
// compatibility). No progress window is shown to avoid Win32 message-pump
// issues across threads and UAC elevation boundaries.
func runWithWindow(zipPath, installDir string, oldPID int, exeName string) {
	err := performUpdate(zipPath, installDir, oldPID, exeName, func(msg string) {
		logf("status: %s", msg)
	})
	if err != nil {
		logf("updater exiting with error: %v", err)
		os.Exit(1)
	}
	logf("updater exiting successfully")
	os.Exit(0)
}