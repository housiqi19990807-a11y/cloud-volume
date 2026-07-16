//go:build windows

// Windows drive mapping tests pin subst parsing and managed-target boundaries.
package mount

import (
	"path/filepath"
	"testing"
)

func TestParseWindowsDriveMappings(t *testing.T) {
	t.Parallel()

	output := "Z:\\: => C:\\Users\\demo\\Cloud Volume\\bucket-a\r\n" +
		"Y:\\: => D:\\custom path\\bucket-b\r\n"
	mappings := parseWindowsDriveMappings(output)
	if len(mappings) != 2 {
		t.Fatalf("expected 2 mappings, got %d", len(mappings))
	}
	if mappings[0].drive != "Z:" || mappings[0].target != `C:\Users\demo\Cloud Volume\bucket-a` {
		t.Fatalf("unexpected first mapping: %#v", mappings[0])
	}
	if mappings[1].drive != "Y:" || mappings[1].target != `D:\custom path\bucket-b` {
		t.Fatalf("unexpected second mapping: %#v", mappings[1])
	}
}

func TestManagedWindowsCloudFilesMappingTargetRequiresDirectChild(t *testing.T) {
	t.Parallel()

	root := filepath.Clean(`C:\Users\demo\Cloud Volume`)
	if !isManagedWindowsCloudFilesMappingTarget(root, filepath.Join(root, "bucket-a")) {
		t.Fatalf("expected direct bucket path to be managed")
	}
	if isManagedWindowsCloudFilesMappingTarget(root, filepath.Join(root, "bucket-a", "nested")) {
		t.Fatalf("expected nested directory not to be treated as a sync root")
	}
	if isManagedWindowsCloudFilesMappingTarget(root, `C:\Users\demo\Cloud Volume Other\bucket-a`) {
		t.Fatalf("expected sibling directory not to be treated as managed")
	}
}
