// Peer-broadcast hook for the mount layer. The bridge layer installs a
// broadcast callback after starting the P2P manager; mount code calls
// PeerBroadcastHook() to notify peers of remote-confirmed mutations without
// importing the p2p package (which would create an import cycle).
package mount

import "sync/atomic"

// BroadcastPayload carries the minimal info needed to fan out a peer event.
type BroadcastPayload struct {
	Bucket      string
	VirtualPath string
	IsDir       bool
	OldPath     string // empty for non-rename operations
	Operation   string // "upload" | "delete" | "rename"
	VersionHint string // ETag / mtime+size / ""
}

var peerBroadcastCallback atomic.Pointer[func(BroadcastPayload)]

// SetPeerBroadcastCallback installs the function that mount code calls after
// a remote-confirmed mutation. Called once by the bridge during startup.
func SetPeerBroadcastCallback(cb func(BroadcastPayload)) {
	fn := cb
	peerBroadcastCallback.Store(&fn)
}

// PeerBroadcastHook returns the installed callback, or nil if P2P is disabled.
func PeerBroadcastHook() func(BroadcastPayload) {
	fn := peerBroadcastCallback.Load()
	if fn == nil {
		return nil
	}
	return *fn
}
