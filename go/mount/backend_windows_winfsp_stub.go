//go:build windows && !cgo

// Without CGO the WinFsp virtual file system engine stays unavailable; the
// selector reports a clear error instead of silently falling back, so the
// settings UI and mount dialog can guide the user to Cloud Files / WebDAV.
// The cgo build always compiles the real WinFsp backend in, so the only
// remaining stub path is a pure-Go (CGO_ENABLED=0) Windows build, which also
// cannot host the Cloud Files provider.
package mount

import (
	"fmt"

	storageconfig "remote-storage/go/config"
)

func newWindowsWinFspBackend(cfg storageconfig.RemoteStorageConfig) (mountBackend, error) {
	return nil, fmt.Errorf("WinFsp engine requires a CGO build of the bridge (CGO_ENABLED=1)")
}

func cleanupManagedWindowsWinFspArtifacts() error {
	return nil
}
