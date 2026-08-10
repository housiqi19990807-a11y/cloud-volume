//go:build windows && cgo

// Windows Cloud Files tests pin local/virtual path translation and watcher state helpers.
package mount

import (
	"path/filepath"
	"testing"
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

func TestCloudFilesLocalPathToVirtualRejectsOutsideRoot(t *testing.T) {
	root := filepath.Clean(`C:\Users\demo\Cloud Volume\bucket`)
	if _, ok := cloudFilesLocalPathToVirtualChecked(root, `C:\Users\demo\other`); ok {
		t.Fatal("path outside the sync root must be rejected")
	}
	if _, ok := cloudFilesLocalPathToVirtualChecked(root, `D:\bucket\docs`); ok {
		t.Fatal("path on another volume must be rejected")
	}
	if got, ok := cloudFilesLocalPathToVirtualChecked(root, filepath.Join(root, "docs")); !ok || got != "docs" {
		t.Fatalf("valid child = %q, ok=%t; want docs, true", got, ok)
	}
}

func TestWindowsPathStateRebase(t *testing.T) {
	t.Parallel()

	state := &windowsPathState{
		ignored: map[string]windowsIgnoredPath{},
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

func TestResumableUploadStatePathIgnored(t *testing.T) {
	t.Parallel()

	if !isResumableUploadStatePath(filepath.Clean(`C:\root\dir\c.zip.uploading.json`)) {
		t.Fatal("expected resumable upload state file to be ignored")
	}
	if isResumableUploadStatePath(filepath.Clean(`C:\root\dir\c.zip`)) {
		t.Fatal("expected normal object path to stay syncable")
	}
}

func TestCloudFilesAlignedTransferRange(t *testing.T) {
	t.Parallel()

	cases := []struct {
		name     string
		offset   int64
		length   int64
		fileSize int64
		want     cloudFilesTransferRange
	}{
		{
			name:     "aligns down and up within file",
			offset:   123,
			length:   2000,
			fileSize: 20000,
			want:     cloudFilesTransferRange{Offset: 0, Length: 4096},
		},
		{
			name:     "preserves eof tail without extra padding",
			offset:   5000,
			length:   4096,
			fileSize: 7000,
			want:     cloudFilesTransferRange{Offset: 4096, Length: 2904},
		},
		{
			name:     "caps oversized request at file size",
			offset:   8192,
			length:   8192,
			fileSize: 9000,
			want:     cloudFilesTransferRange{Offset: 8192, Length: 808},
		},
	}

	for _, tc := range cases {
		tc := tc
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()

			got := cloudFilesAlignedTransferRange(tc.offset, tc.length, tc.fileSize)
			if got != tc.want {
				t.Fatalf(
					"cloudFilesAlignedTransferRange(%d, %d, %d) = %+v, want %+v",
					tc.offset,
					tc.length,
					tc.fileSize,
					got,
					tc.want,
				)
			}
		})
	}
}
