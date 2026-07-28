// P2P config tests preserve the enabled-by-default rollout for existing profiles.
package config

import (
	"encoding/json"
	"testing"
)

func TestRemoteStorageConfigJSONDefaultsMissingP2PFields(t *testing.T) {
	var cfg RemoteStorageConfig
	if err := json.Unmarshal([]byte(`{"endpoint":"https://example.test"}`), &cfg); err != nil {
		t.Fatal(err)
	}
	if !cfg.P2PEnabled || cfg.P2PChunkSizeMB != defaultP2PChunkSizeMB {
		t.Fatalf("missing P2P defaults enabled=%t chunk=%d", cfg.P2PEnabled, cfg.P2PChunkSizeMB)
	}
}

func TestRemoteStorageConfigJSONRetainsExplicitP2PDisable(t *testing.T) {
	var cfg RemoteStorageConfig
	if err := json.Unmarshal([]byte(`{"p2pEnabled":false,"p2pChunkSizeMb":8}`), &cfg); err != nil {
		t.Fatal(err)
	}
	if cfg.P2PEnabled || cfg.P2PChunkSizeMB != 8 {
		t.Fatalf("explicit P2P config enabled=%t chunk=%d", cfg.P2PEnabled, cfg.P2PChunkSizeMB)
	}
}
