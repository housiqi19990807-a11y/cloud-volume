//go:build windows && cgo && !winfsp

// When the bridge is built with CGO (for Cloud Files) but the optional `winfsp`
// build tag is not set, the WinFsp engine reports unavailable. This keeps the
// default dev/release build free of the WinFsp header dependency; users who
// install WinFsp rebuild with `-tags winfsp`.
package mount

import (
	"fmt"

	storageconfig "remote-storage/go/config"
)

func newWindowsWinFspBackend(cfg storageconfig.RemoteStorageConfig) (mountBackend, error) {
	return nil, fmt.Errorf("WinFsp engine requires rebuilding with the `winfsp` build tag")
}

func cleanupManagedWindowsWinFspArtifacts() error {
	return nil
}
