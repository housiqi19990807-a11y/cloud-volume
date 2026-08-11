//go:build linux

// Linux FUSE ownership tests keep default_permissions aligned with the desktop user.
package mount

import (
	"os"
	"testing"

	"github.com/hanwen/go-fuse/v2/fuse"
)

func TestLinuxFuseAttrsUseMountingUser(t *testing.T) {
	root := fuse.AttrOut{}
	fillLinuxFuseRootAttr(&root)
	if root.Uid != uint32(os.Getuid()) || root.Gid != uint32(os.Getgid()) {
		t.Fatalf("root owner = %d:%d, want %d:%d", root.Uid, root.Gid, os.Getuid(), os.Getgid())
	}

	file, err := os.CreateTemp(t.TempDir(), "owner")
	if err != nil {
		t.Fatalf("create temp file: %v", err)
	}
	defer file.Close()
	info, err := file.Stat()
	if err != nil {
		t.Fatalf("stat temp file: %v", err)
	}
	attr := fuse.Attr{}
	fillLinuxFuseLocalAttr(&attr, info, false)
	if attr.Uid != uint32(os.Getuid()) || attr.Gid != uint32(os.Getgid()) {
		t.Fatalf("file owner = %d:%d, want %d:%d", attr.Uid, attr.Gid, os.Getuid(), os.Getgid())
	}
}
