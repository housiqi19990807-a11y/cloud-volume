//go:build linux

// Linux Statfs tests verify the FUSE-facing custom quota fields.
package mount

import (
	"context"
	"testing"

	"github.com/hanwen/go-fuse/v2/fuse"

	storageconfig "remote-storage/go/config"
)

func TestLinuxFuseStatfsReportsCustomQuota(t *testing.T) {
	t.Parallel()

	const quota = int64(2 * 1024 * 1024 * 1024)
	access, err := newBucketAccess(storageconfig.RemoteStorageConfig{
		BucketSettings: map[string]storageconfig.BucketSettings{
			"demo": {CustomQuotaBytes: quota},
		},
	}, "demo")
	if err != nil {
		t.Fatalf("newBucketAccess: %v", err)
	}
	t.Cleanup(func() { _ = access.close() })

	var stat fuse.StatfsOut
	if errno := newLinuxFuseNode(access, true).Statfs(context.Background(), &stat); errno != 0 {
		t.Fatalf("Statfs errno = %d", errno)
	}
	wantBlocks := uint64(quota) / 4096
	if stat.Blocks != wantBlocks || stat.Bfree != wantBlocks || stat.Bavail != wantBlocks {
		t.Fatalf(
			"blocks/free/available = %d/%d/%d, want %d",
			stat.Blocks,
			stat.Bfree,
			stat.Bavail,
			wantBlocks,
		)
	}
}
