//go:build !windows
// Non-Windows builds run the update headless (the updater is Windows-only
// in production, but this keeps cross-compilation and `go vet` working).
package main

func runWithWindow(zipPath, installDir string, oldPID int, exeName string) {
	if err := performUpdate(zipPath, installDir, oldPID, exeName, func(string) {}); err != nil {
		fail("更新失败", err)
	}
}
