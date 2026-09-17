// Test config roots close the process-wide bbolt handle before TempDir cleanup.
package webapi

import (
	"testing"

	storageconfig "remote-storage/go/config"
)

func useWebAPITestRoot(t *testing.T) {
	t.Helper()
	root := t.TempDir()
	releaseRoot := t.TempDir()
	if err := storageconfig.SetAppDataRoot(root); err != nil {
		t.Fatalf("set test app data root: %v", err)
	}
	t.Cleanup(func() {
		if err := storageconfig.SetAppDataRoot(releaseRoot); err != nil {
			t.Errorf("release test config db: %v", err)
		}
	})
}
