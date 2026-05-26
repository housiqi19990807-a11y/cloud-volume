// Local overlay tests keep Finder-specific writable temp path behavior pinned down.
package mount

import (
	"fmt"
	"os"
	"path/filepath"
	"testing"
)

func TestLocalMountOverlaySeedsWritableSystemPaths(t *testing.T) {
	t.Parallel()

	root := t.TempDir()
	overlay, err := newLocalMountOverlay(root)
	if err != nil {
		t.Fatalf("newLocalMountOverlay: %v", err)
	}

	trashUID := fmt.Sprintf("%d", os.Getuid())
	requiredPaths := []string{
		filepath.Join(root, ".TemporaryItems"),
		filepath.Join(root, ".fseventsd"),
		filepath.Join(root, ".metadata_never_index"),
	}
	for _, path := range requiredPaths {
		info, statErr := os.Stat(path)
		if statErr != nil {
			t.Fatalf("stat %q: %v", path, statErr)
		}
		if path == filepath.Join(root, ".metadata_never_index") {
			if info.IsDir() {
				t.Fatalf("%q should be a file", path)
			}
			continue
		}
		if !info.IsDir() {
			t.Fatalf("%q is not a directory", path)
		}
	}

	if !overlay.handles(".TemporaryItems") {
		t.Fatal("expected overlay to handle .TemporaryItems")
	}
	if overlay.handles(".Trash") {
		t.Fatal("expected overlay to stop handling .Trash")
	}
	if overlay.handles(".Trashes") {
		t.Fatal("expected overlay to stop handling .Trashes")
	}
	if !overlay.isTrashPath(".Trash/example.txt") {
		t.Fatal("expected .Trash path to be treated as trash")
	}
	if !overlay.isTrashPath(".Trash-" + trashUID + "/example.txt") {
		t.Fatal("expected .Trash-<uid> path to be treated as trash")
	}
	if !overlay.isTrashPath(".Trashes/" + trashUID + "/example.txt") {
		t.Fatal("expected .Trashes/<uid> path to be treated as trash")
	}
}
