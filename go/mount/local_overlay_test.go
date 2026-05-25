// Local overlay tests keep Finder-specific trash bootstrap behavior pinned down.
package mount

import (
	"fmt"
	"os"
	"path/filepath"
	"testing"
)

func TestLocalMountOverlaySeedsTrashFamilies(t *testing.T) {
	t.Parallel()

	root := t.TempDir()
	overlay, err := newLocalMountOverlay(root)
	if err != nil {
		t.Fatalf("newLocalMountOverlay: %v", err)
	}

	trashUID := fmt.Sprintf("%d", os.Getuid())
	requiredPaths := []string{
		filepath.Join(root, ".Trash"),
		filepath.Join(root, ".Trash-"+trashUID),
		filepath.Join(root, ".Trashes"),
		filepath.Join(root, ".Trashes", trashUID),
	}
	for _, path := range requiredPaths {
		info, statErr := os.Stat(path)
		if statErr != nil {
			t.Fatalf("stat %q: %v", path, statErr)
		}
		if !info.IsDir() {
			t.Fatalf("%q is not a directory", path)
		}
	}

	if !overlay.handles(".Trash") {
		t.Fatal("expected overlay to handle .Trash")
	}
	if !overlay.handles(".Trash-" + trashUID) {
		t.Fatal("expected overlay to handle .Trash-<uid>")
	}
	if !overlay.handles(".Trashes") {
		t.Fatal("expected overlay to handle .Trashes")
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
