// P2P config tests pin the off-by-default beta behavior: a missing field stays
// disabled, but an explicitly saved choice (either way) is honored.
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
	// P2P is an off-by-default experimental feature: a profile saved without
	// the field must stay disabled so it does not start mDNS until the user
	// opts in from Settings.
	if cfg.P2PEnabled || cfg.P2PChunkSizeMB != defaultP2PChunkSizeMB {
		t.Fatalf("missing P2P defaults enabled=%t chunk=%d (want false)", cfg.P2PEnabled, cfg.P2PChunkSizeMB)
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

// TestRemoteStorageConfigJSONRetainsExplicitP2PEnable protects users who
// already opted in: a profile that explicitly saved p2pEnabled:true must keep
// P2P running after the off-by-default change.
func TestRemoteStorageConfigJSONRetainsExplicitP2PEnable(t *testing.T) {
	var cfg RemoteStorageConfig
	if err := json.Unmarshal([]byte(`{"p2pEnabled":true,"p2pChunkSizeMb":4}`), &cfg); err != nil {
		t.Fatal(err)
	}
	if !cfg.P2PEnabled || cfg.P2PChunkSizeMB != 4 {
		t.Fatalf("explicit P2P enable not retained: enabled=%t chunk=%d", cfg.P2PEnabled, cfg.P2PChunkSizeMB)
	}
}

// TestDefaultConfigP2PDisabled pins the DefaultConfig default so a future edit
// cannot accidentally re-enable P2P for new accounts.
func TestDefaultConfigP2PDisabled(t *testing.T) {
	if cfg := DefaultConfig(); cfg.P2PEnabled {
		t.Fatal("DefaultConfig must not enable P2P; it is an opt-in beta feature")
	}
}
