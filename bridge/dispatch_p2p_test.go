// P2P bridge tests protect manager replacement when captured config changes.
package main

import (
	"testing"

	storageconfig "remote-storage/go/config"
)

func TestP2PManagerKeyChangesWithCapturedConfig(t *testing.T) {
	base := storageconfig.RemoteStorageConfig{
		Endpoint:        "https://example.test",
		AccessKeyID:     "access",
		SecretAccessKey: "secret",
		P2PEnabled:      true,
		P2PChunkSizeMB:  4,
	}.Normalized()
	baseKey, err := p2pManagerKey(base)
	if err != nil {
		t.Fatal(err)
	}
	updated := base
	updated.CacheDirectory = "C:/cache/updated"
	updatedKey, err := p2pManagerKey(updated)
	if err != nil {
		t.Fatal(err)
	}
	if baseKey == updatedKey {
		t.Fatal("captured mount config change did not replace the P2P manager")
	}
}
