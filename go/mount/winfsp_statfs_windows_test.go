//go:build windows && cgo

// WinFsp Statfs tests verify Explorer-facing capacity fields.
package mount

import (
	"testing"

	"github.com/winfsp/cgofuse/fuse"
)

func TestWinFspStatfsReportsConfiguredCapacity(t *testing.T) {
	t.Parallel()

	const capacity = uint64(1536 * 1024 * 1024)
	fs := newWinFspBucketFS(nil, "test", capacity, false)
	t.Cleanup(fs.Destroy)

	var stat fuse.Statfs_t
	if errno := fs.Statfs("/", &stat); errno != 0 {
		t.Fatalf("Statfs errno = %d", errno)
	}
	wantBlocks := capacity / winFspBlockBytes
	if stat.Blocks != wantBlocks || stat.Bfree != wantBlocks || stat.Bavail != wantBlocks {
		t.Fatalf(
			"blocks/free/available = %d/%d/%d, want %d",
			stat.Blocks,
			stat.Bfree,
			stat.Bavail,
			wantBlocks,
		)
	}
	if stat.Bsize != winFspBlockBytes || stat.Frsize != winFspBlockBytes {
		t.Fatalf("block sizes = %d/%d, want %d", stat.Bsize, stat.Frsize, winFspBlockBytes)
	}
}

func TestWinFspMountOptionsMatchStatfsGeometry(t *testing.T) {
	t.Parallel()

	want := []string{
		"-o", "volname=Cloud Volume test",
		"-o", "FileSystemName=CloudVolume",
		"-o", "SectorSize=4096",
		"-o", "SectorsPerAllocationUnit=1",
	}
	got := winFspMountOptions("Cloud Volume test")
	if len(got) != len(want) {
		t.Fatalf("option count = %d, want %d", len(got), len(want))
	}
	for index, value := range want {
		if got[index] != value {
			t.Fatalf("option %d = %q, want %q", index, got[index], value)
		}
	}
}
