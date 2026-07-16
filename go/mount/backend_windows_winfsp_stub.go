//go:build windows && !cgo

// Without CGO the WinFsp virtual file system engine stays unavailable; the
// selector reports a clear error instead of silently falling back, so the
// settings UI and mount dialog can guide the user to Cloud Files / WebDAV.
//
// A second stub variant (windows && cgo && !winfsp) covers the common case
// where the bridge is built with CGO for Cloud Files but WinFsp headers are
// not installed, so the default dev/release build never needs WinFsp.
package mount

import (
	"fmt"

	storageconfig "remote-storage/go/config"
)

func newWindowsWinFspBackend(cfg storageconfig.RemoteStorageConfig) (mountBackend, error) {
	return nil, fmt.Errorf("WinFsp engine requires CGO_ENABLED=1 and the `winfsp` build tag")
}

func cleanupManagedWindowsWinFspArtifacts() error {
	return nil
}
