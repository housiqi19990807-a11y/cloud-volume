package main

import (
	"os"
	"path/filepath"
	"runtime"
)

// appRelaunchExecutable selects the public Windows watchdog launcher when it
// exists; older bundles and non-Windows platforms keep using the current exe.
func appRelaunchExecutable(currentExecutable string) string {
	if runtime.GOOS != "windows" {
		return currentExecutable
	}
	launcher := filepath.Join(filepath.Dir(currentExecutable), "cloud-volume.exe")
	if _, err := os.Stat(launcher); err == nil {
		return launcher
	}
	return currentExecutable
}
