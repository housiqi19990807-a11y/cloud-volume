// Mount access tests guard the RootPrefix ownership contract between the
// mount layer and storage.scopedBackend. The mount layer must be the sole
// owner of prefix translation, otherwise provider keys end up double-prefixed.
package mount

import (
	"testing"

	storageconfig "remote-storage/go/config"
	storageops "remote-storage/go/storage"
)

// TestNewBucketAccessUsesUnscopedBackend asserts that the constructed backend
// is not wrapped by storage.scopedBackend. If it were, the mount layer and the
// storage wrapper would both prepend RootPrefix, sending every provider call
// to <root>/<root>/<key>.
func TestNewBucketAccessUsesUnscopedBackend(t *testing.T) {
	cfg := storageconfig.RemoteStorageConfig{
		RootPrefix: "archive/2026",
	}
	access, err := newBucketAccess(cfg, "demo")
	if err != nil {
		t.Fatalf("newBucketAccess: %v", err)
	}
	if storageops.IsScoped(access.backend) {
		t.Fatalf("backend is scoped; newBucketAccess must clear RootPrefix before ForConfig")
	}
	if access.rootPrefix != "archive/2026" {
		t.Fatalf("access.rootPrefix = %q, want %q", access.rootPrefix, "archive/2026")
	}
}

