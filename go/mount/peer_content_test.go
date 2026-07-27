// Peer-source tests ensure a bridge upload is offered only for its exact version.
package mount

import (
	"os"
	"path/filepath"
	"testing"

	storageconfig "remote-storage/go/config"
	s3ops "remote-storage/go/s3"
)

func TestRememberPeerContentRequiresMatchingVersion(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "source.bin")
	if err := os.WriteFile(path, []byte("content"), 0o600); err != nil { t.Fatal(err) }
	cfg := storageconfig.RemoteStorageConfig{Endpoint: "https://example.test", AccessKeyID: "access", SecretAccessKey: "secret"}
	info := s3ops.ObjectInfo{Key: "folder/file", Size: 7, LastModified: "v1"}
	RememberPeerContent(cfg, "bucket", "folder/file", path, info)
	resolved, size, ok := LocalPeerContentPath(cfg, "bucket", "folder/file", "v1")
	if !ok || resolved != path || size != 7 { t.Fatalf("unexpected source result path=%q size=%d ok=%t", resolved, size, ok) }
	if _, _, ok := LocalPeerContentPath(cfg, "bucket", "folder/file", "v2"); ok { t.Fatal("stale version was offered") }
}
