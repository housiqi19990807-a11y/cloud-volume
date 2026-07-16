//go:build windows

// Embedded WinFsp MSI assets ship with the bridge so the app can offer an
// in-app silent install without downloading from the network at runtime.
package mount

import _ "embed"

//go:embed embedded/winfsp.msi
var embeddedWinFspMSI []byte

// EmbeddedWinFspMSI returns the bundled WinFsp installer payload. The slice is
// the raw MSI bytes and should be written to a temporary file before install.
func EmbeddedWinFspMSI() []byte {
	return embeddedWinFspMSI
}
