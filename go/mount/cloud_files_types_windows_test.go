//go:build windows && cgo

// Windows Cloud Files tests pin local/virtual path translation and watcher state helpers.
package mount

import (
	"path/filepath"
	"testing"
	"time"
)

func TestCloudFilesLocalPathToVirtual(t *testing.T) {
	t.Parallel()

	root := filepath.Clean(`C:\Users\demo\Cloud Volume\bucket`)
	if got := cloudFilesLocalPathToVirtual(root, root); got != "" {
		t.Fatalf("expected root path to map to empty virtual path, got %q", got)
	}
	if got := cloudFilesLocalPathToVirtual(root, filepath.Join(root, "dir", "file.txt")); got != "dir/file.txt" {
		t.Fatalf("unexpected virtual path: %q", got)
	}
}

func TestWindowsPathStateRebase(t *testing.T) {
	t.Parallel()

	state := &windowsPathState{
		ignored: map[string]time.Time{},
		kinds: map[string]bool{
			filepath.Clean(`C:\root\old`):          true,
			filepath.Clean(`C:\root\old\file.txt`): false,
		},
	}
	state.rebase(`C:\root\old`, `C:\root\new`, true)

	if !state.isDir(`C:\root\new`) {
		t.Fatal("expected renamed directory to stay tracked as a directory")
	}
	if state.isDir(`C:\root\new\file.txt`) {
		t.Fatal("expected child file to stay tracked as a file")
	}
}

func TestWindowsLocalOnlyPath(t *testing.T) {
	t.Parallel()

	if !isWindowsLocalOnlyPath("desktop.ini") {
		t.Fatal("expected desktop.ini to stay local-only")
	}
	if isWindowsLocalOnlyPath("documents/report.txt") {
		t.Fatal("expected normal object paths to stay syncable")
	}
}
