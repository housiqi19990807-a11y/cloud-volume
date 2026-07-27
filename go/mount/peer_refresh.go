// Peer-refresh exposes a mount-session refresh entry point for the P2P layer.
// When a LAN peer signals "this bucket/path may have changed", the P2P
// manager calls RefreshRemoteDirectory to trigger an immediate re-list,
// without waiting for the P0 polling interval.
package mount

import (
	"context"
	"log"

	storageconfig "remote-storage/go/config"
)

// RefreshRemoteDirectory triggers an immediate remote list refresh for the
// active mount session matching cfg+bucket+prefix. It is the P2P counterpart
// to NotifyExternalUpload: instead of acting on a local mutation, it re-fetches
// remote state so the mount and UI reflect peer-side changes instantly.
//
// The prefix is a virtual directory path (no leading/trailing slashes).
// If no mount session matches, this is a no-op.
func RefreshRemoteDirectory(
	cfg storageconfig.RemoteStorageConfig,
	bucket, virtualPrefix string,
) {
	globalManager.notifyExternalMutation(cfg, bucket, func(access *bucketAccess) {
		ctx, cancel := context.WithTimeout(context.Background(), access.requestTimeout)
		defer cancel()
		log.Printf("[mount/peer] refresh bucket=%q prefix=%q", bucket, virtualPrefix)
		_ = access.pollRemoteDirectory(ctx, virtualPrefix)
	})
}

// ActiveMountBuckets returns the bucket names of all currently mounted sessions.
// The P2P layer uses this to know which buckets are locally active and can
// receive peer events.
func ActiveMountBuckets() []string {
	globalManager.mu.Lock()
	defer globalManager.mu.Unlock()
	out := make([]string, 0, len(globalManager.sessions))
	for bucket := range globalManager.sessions {
		out = append(out, bucket)
	}
	return out
}
