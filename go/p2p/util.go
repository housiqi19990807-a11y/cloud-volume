// Small shared helpers for the p2p package.
package p2p

import (
	"crypto/rand"
	"encoding/hex"
)

// randomHex returns n random bytes hex-encoded (2*n chars).
func randomHex(n int) string {
	b := make([]byte, n)
	_, _ = rand.Read(b)
	return hex.EncodeToString(b)
}
