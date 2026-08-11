//go:build darwin

// System mount parsing tests keep stale-session detection stable.
package mount

import (
	"path/filepath"
	"strings"
	"testing"
)

func TestMountOutputContainsPath(t *testing.T) {
	t.Parallel()

	output := strings.Join([]string{
		"http://127.0.0.1:19090/ on /Users/3000y/Desktop/\u4e91\u5377-demo (webdav, nodev, nosuid, mounted by 3000y)",
		"http://127.0.0.1:19091/ on /Users/3000y/Desktop/My\\040Bucket (webdav, nodev, nosuid, mounted by 3000y)",
	}, "\n")

	if !mountOutputContainsPath(output, "/Users/3000y/Desktop/云卷-demo") {
		t.Fatal("expected unicode mount path to be detected")
	}
	if !mountOutputContainsPath(output, "/Users/3000y/Desktop/My Bucket") {
		t.Fatal("expected escaped-space mount path to be detected")
	}
	if mountOutputContainsPath(output, "/Users/3000y/Desktop/missing") {
		t.Fatal("expected unrelated mount path to be absent")
	}
}

func TestMatchingBucketMountPaths(t *testing.T) {
	t.Parallel()

	paths := []string{
		"/Volumes/云卷-demo",
		"/Volumes/云卷-demo-1",
		"/Volumes/云卷-demo-2",
		"/Volumes/云卷-other",
	}
	matches := matchingBucketMountPaths(paths, "云卷-demo")
	if len(matches) != 3 {
		t.Fatalf("expected 3 matching bucket mount paths, got %d: %+v", len(matches), matches)
	}
	if matches[0] != filepath.FromSlash("/Volumes/云卷-demo") ||
		matches[2] != filepath.FromSlash("/Volumes/云卷-demo-2") {
		t.Fatalf("unexpected matching mount paths: %+v", matches)
	}
}

func TestMatchingManagedMountPaths(t *testing.T) {
	t.Parallel()

	paths := []string{
		"/Volumes/云卷-demo",
		"/Volumes/云卷-demo-1",
		"/Volumes/Other",
	}
	matches := matchingManagedMountPaths(paths)
	if len(matches) != 2 {
		t.Fatalf("expected 2 managed mount paths, got %d: %+v", len(matches), matches)
	}
}

// TestParseMountEntryExtractsSourceURLAndPath pins the macOS `mount -t webdav`
// row format. The source URL (carrying our random loopback port) is essential
// for the mount-success probe — dropping it was the root cause of false
// "mounted" reports, so this test guards against regressing parseMountEntry
// back into a path-only parser.
func TestParseMountEntryExtractsSourceURLAndPath(t *testing.T) {
	t.Parallel()

	const line = "http://127.0.0.1:19090/ on /Users/3000y/Desktop/云卷-demo (webdav, nodev, nosuid, mounted by 3000y)"
	source, path, ok := parseMountEntry(line)
	if !ok {
		t.Fatal("expected mount entry to parse")
	}
	if source != "http://127.0.0.1:19090/" {
		t.Fatalf("source URL = %q; want http://127.0.0.1:19090/", source)
	}
	if path != "/Users/3000y/Desktop/云卷-demo" {
		t.Fatalf("mount path = %q", path)
	}
}

// TestParseMountEntryHandlesEscapedSpaces ensures octal-escaped path segments
// (e.g. "My\\040Bucket") decode the same way they did under the old parser.
func TestParseMountEntryHandlesEscapedSpaces(t *testing.T) {
	t.Parallel()

	const line = "http://127.0.0.1:60123/scope/ on /Volumes/My\\040Bucket (webdav, nodev, nosuid, mounted by 3000y)"
	source, path, ok := parseMountEntry(line)
	if !ok {
		t.Fatal("expected escaped-space mount entry to parse")
	}
	if source != "http://127.0.0.1:60123/scope/" {
		t.Fatalf("source URL = %q", source)
	}
	if path != "/Volumes/My Bucket" {
		t.Fatalf("mount path = %q; want /Volumes/My Bucket", path)
	}
}
