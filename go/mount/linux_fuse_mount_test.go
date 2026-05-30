//go:build linux

package mount

import (
	"os"
	"path/filepath"
	"testing"
	"time"

	gofusefs "github.com/hanwen/go-fuse/v2/fs"
	"github.com/hanwen/go-fuse/v2/fuse"

	storageconfig "remote-storage/go/config"
	s3ops "remote-storage/go/s3"
)

func TestLinuxFuseServesCachedFiles(t *testing.T) {
	if _, err := os.Stat("/dev/fuse"); err != nil {
		t.Skip("/dev/fuse is not available")
	}

	access, err := newBucketAccess(storageconfig.RemoteStorageConfig{}, "demo")
	if err != nil {
		t.Fatalf("newBucketAccess: %v", err)
	}
	t.Cleanup(func() {
		access.writeback.cancel("hello.txt")
		access.cache.removeLocalFile("hello.txt", false)
		_ = access.close()
	})

	cachePath := access.cachePathFor("hello.txt")
	if err := os.MkdirAll(filepath.Dir(cachePath), 0o755); err != nil {
		t.Fatalf("mkdir cache: %v", err)
	}
	if err := os.WriteFile(cachePath, []byte("hello from fuse"), 0o644); err != nil {
		t.Fatalf("seed cache file: %v", err)
	}
	access.registerLocalWrite("hello.txt", cachePath, int64(len("hello from fuse")))
	access.cache.storeList("", []s3ops.ObjectInfo{{
		Key:          "hello.txt",
		Size:         int64(len("hello from fuse")),
		LastModified: time.Now().Format("2006-01-02 15:04:05"),
		IsDir:        false,
	}})

	mountDir := t.TempDir()
	server, err := gofusefs.Mount(mountDir, newLinuxFuseNode(access, true), &gofusefs.Options{
		EntryTimeout: ptrDuration(time.Second),
		AttrTimeout:  ptrDuration(time.Second),
		MountOptions: fuse.MountOptions{DisableXAttrs: true},
	})
	if err != nil {
		t.Fatalf("mount fuse: %v", err)
	}
	defer func() {
		if unmountErr := server.Unmount(); unmountErr != nil {
			t.Fatalf("unmount fuse: %v", unmountErr)
		}
	}()

	data, err := os.ReadFile(filepath.Join(mountDir, "hello.txt"))
	if err != nil {
		t.Fatalf("read mounted file: %v", err)
	}
	if string(data) != "hello from fuse" {
		t.Fatalf("unexpected mounted file contents %q", string(data))
	}
}

func TestLinuxFuseWriteStagesLocalCache(t *testing.T) {
	if _, err := os.Stat("/dev/fuse"); err != nil {
		t.Skip("/dev/fuse is not available")
	}

	access, err := newBucketAccess(storageconfig.RemoteStorageConfig{}, "demo")
	if err != nil {
		t.Fatalf("newBucketAccess: %v", err)
	}
	t.Cleanup(func() {
		access.writeback.cancel("created.txt")
		access.cache.removeLocalFile("created.txt", false)
		_ = access.close()
	})
	access.cache.storeList("", []s3ops.ObjectInfo{})
	access.cache.markDeleted("created.txt", false)

	mountDir := t.TempDir()
	server, err := gofusefs.Mount(mountDir, newLinuxFuseNode(access, true), &gofusefs.Options{
		EntryTimeout: ptrDuration(time.Second),
		AttrTimeout:  ptrDuration(time.Second),
		MountOptions: fuse.MountOptions{DisableXAttrs: true},
	})
	if err != nil {
		t.Fatalf("mount fuse: %v", err)
	}
	defer func() {
		access.writeback.cancel("created.txt")
		if unmountErr := server.Unmount(); unmountErr != nil {
			t.Fatalf("unmount fuse: %v", unmountErr)
		}
	}()

	targetPath := filepath.Join(mountDir, "created.txt")
	if err := os.WriteFile(targetPath, []byte("queued"), 0o644); err != nil {
		t.Fatalf("write mounted file: %v", err)
	}

	item, ok := access.cache.localFile("created.txt")
	if !ok {
		t.Fatal("expected local cache marker for mounted write")
	}
	data, err := os.ReadFile(item.localPath)
	if err != nil {
		t.Fatalf("read staged local cache file: %v", err)
	}
	if string(data) != "queued" {
		t.Fatalf("unexpected staged file contents %q", string(data))
	}
}
