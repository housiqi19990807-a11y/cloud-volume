// WebDAV metadata tests keep Finder PROPPATCH probes out of delayed writeback.
package mount

import (
	"context"
	"os"
	"testing"

	s3ops "remote-storage/go/s3"
)

func TestWebDAVMetadataOpenDoesNotQueueContentWrite(t *testing.T) {
	t.Parallel()

	access := newTestBucketAccess(t)
	virtualPath := "docs/note.txt"
	localPath := createTempFile(t, access.cacheRoot, "source.txt", "original")
	access.cache.storeLocalFile(virtualPath, localPath, s3ops.ObjectInfo{
		Key:  virtualPath,
		Size: 8,
	})

	file, err := (&webDAVFS{access: access}).OpenFile(
		context.Background(),
		virtualPath,
		os.O_RDWR,
		0,
	)
	if err != nil {
		t.Fatalf("metadata OpenFile: %v", err)
	}
	if err := file.Close(); err != nil {
		t.Fatalf("metadata Close: %v", err)
	}

	if access.writeback.hasPendingAtOrBelow(virtualPath, false) {
		t.Fatal("metadata-only open unexpectedly queued content writeback")
	}
	if _, err := os.Stat(access.stagePathFor(virtualPath)); !os.IsNotExist(err) {
		t.Fatalf("metadata-only open created staging content: %v", err)
	}
}

func TestWebDAVTruncatingWriteRemainsLocalFirst(t *testing.T) {
	t.Parallel()

	access := newTestBucketAccess(t)
	virtualPath := "docs/new.txt"
	file, err := (&webDAVFS{access: access}).OpenFile(
		context.Background(),
		virtualPath,
		os.O_RDWR|os.O_CREATE|os.O_TRUNC,
		0o644,
	)
	if err != nil {
		t.Fatalf("content OpenFile: %v", err)
	}
	if _, err := file.Write([]byte("local first")); err != nil {
		t.Fatalf("content Write: %v", err)
	}
	if err := file.Close(); err != nil {
		t.Fatalf("content Close: %v", err)
	}

	entry, ok := access.cache.localFile(virtualPath)
	if !ok {
		t.Fatal("content write did not register local cache entry")
	}
	data, err := os.ReadFile(entry.localPath)
	if err != nil {
		t.Fatalf("read local cache entry: %v", err)
	}
	if string(data) != "local first" {
		t.Fatalf("local cache content = %q", data)
	}
	if !access.writeback.hasPendingAtOrBelow(virtualPath, false) {
		t.Fatal("content write did not enter delayed writeback")
	}
}
