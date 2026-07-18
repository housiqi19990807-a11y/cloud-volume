// Tests keep Windows update relaunches routed through the public watchdog.
package main

import (
	"os"
	"path/filepath"
	"runtime"
	"testing"
)

func TestAppRelaunchExecutablePrefersWindowsLauncher(t *testing.T) {
	root := t.TempDir()
	current := filepath.Join(root, "cloud-volume-app.exe")
	launcher := filepath.Join(root, "cloud-volume.exe")
	if err := os.WriteFile(launcher, []byte("launcher"), 0o600); err != nil {
		t.Fatal(err)
	}

	got := appRelaunchExecutable(current)
	if runtime.GOOS == "windows" {
		if got != launcher {
			t.Fatalf("appRelaunchExecutable() = %q, want %q", got, launcher)
		}
		return
	}
	if got != current {
		t.Fatalf("appRelaunchExecutable() = %q, want current executable %q", got, current)
	}
}
