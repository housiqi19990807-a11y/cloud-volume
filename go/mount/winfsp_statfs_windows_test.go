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
