// Account-disable config tests pin the enabled-by-default behavior: a missing
// field stays enabled (Disabled=false), and an explicitly saved choice is
// honored either way.
package config

import (
	"encoding/json"
	"testing"
)

// TestRemoteStorageConfigDisabledDefaultsFalse confirms the zero-value / missing
// field behavior: an account without the field is enabled, so disabling is
// always an explicit user action.
func TestRemoteStorageConfigDisabledDefaultsFalse(t *testing.T) {
	var cfg RemoteStorageConfig
	if err := json.Unmarshal([]byte(`{"endpoint":"https://example.test"}`), &cfg); err != nil {
		t.Fatal(err)
	}
	if cfg.Disabled {
		t.Fatal("missing disabled field must default to false (enabled)")
	}
}

// TestRemoteStorageConfigDisabledRetainsExplicitTrue protects an opted-out
// account: a profile that explicitly saved disabled:true must stay disabled
// across a reload.
func TestRemoteStorageConfigDisabledRetainsExplicitTrue(t *testing.T) {
	var cfg RemoteStorageConfig
	if err := json.Unmarshal([]byte(`{"endpoint":"https://example.test","disabled":true}`), &cfg); err != nil {
		t.Fatal(err)
	}
	if !cfg.Disabled {
		t.Fatal("explicit disabled:true not retained")
	}
}

// TestRemoteStorageConfigDisabledRetainsExplicitFalse protects an enabled
// account that explicitly saved disabled:false.
func TestRemoteStorageConfigDisabledRetainsExplicitFalse(t *testing.T) {
	var cfg RemoteStorageConfig
	if err := json.Unmarshal([]byte(`{"endpoint":"https://example.test","disabled":false}`), &cfg); err != nil {
		t.Fatal(err)
	}
	if cfg.Disabled {
		t.Fatal("explicit disabled:false not retained")
	}
}

// TestDefaultConfigAccountEnabled pins DefaultConfig so a future edit cannot
// accidentally disable new accounts.
func TestDefaultConfigAccountEnabled(t *testing.T) {
	if cfg := DefaultConfig(); cfg.Disabled {
		t.Fatal("DefaultConfig must not disable new accounts")
	}
}

// TestNormalizedPreservesDisabled confirms the disable flag survives the
// normalization that runs before every profile save/list.
func TestNormalizedPreservesDisabled(t *testing.T) {
	cfg := RemoteStorageConfig{Endpoint: "https://example.test", Disabled: true}
	if normalized := cfg.Normalized(); !normalized.Disabled {
		t.Fatal("Normalized dropped Disabled=true")
	}
	cfg.Disabled = false
	if normalized := cfg.Normalized(); normalized.Disabled {
		t.Fatal("Normalized did not clear Disabled=false")
	}
}
