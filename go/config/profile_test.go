package config

import (
	"os"
	"path/filepath"
	"testing"
)

// Profile migration tests protect upgrades from the old Remote Storage data root.
func TestMigrateDefaultCopiesLegacyConfigToCloudVolumeProfile(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)

	legacyConfigPath := filepath.Join(home, legacyConfigDirName, configFileName)
	if err := os.MkdirAll(filepath.Dir(legacyConfigPath), 0o700); err != nil {
		t.Fatalf("create legacy config dir: %v", err)
	}
	payload := []byte("endpoint = \"https://legacy.example\"\naccess_key_id = \"ak\"\nsecret_access_key = \"sk\"\n")
	if err := os.WriteFile(legacyConfigPath, payload, 0o600); err != nil {
		t.Fatalf("write legacy config: %v", err)
	}

	if err := MigrateDefault(); err != nil {
		t.Fatalf("MigrateDefault returned error: %v", err)
	}

	defaultPath, err := DefaultConfigPath()
	if err != nil {
		t.Fatalf("DefaultConfigPath returned error: %v", err)
	}
	assertFileBytes(t, defaultPath, payload)

	profilePath, err := ProfileConfigPath("default")
	if err != nil {
		t.Fatalf("ProfileConfigPath returned error: %v", err)
	}
	assertFileBytes(t, profilePath, payload)
	assertFileBytes(t, legacyConfigPath, payload)
}

func TestMigrateDefaultCopiesLegacyProfiles(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)

	legacyProfilePath := filepath.Join(home, legacyConfigDirName, profilesDir, "default.toml")
	if err := os.MkdirAll(filepath.Dir(legacyProfilePath), 0o700); err != nil {
		t.Fatalf("create legacy profiles dir: %v", err)
	}
	payload := []byte("endpoint = \"https://profile.example\"\naccess_key_id = \"ak\"\nsecret_access_key = \"sk\"\n")
	if err := os.WriteFile(legacyProfilePath, payload, 0o600); err != nil {
		t.Fatalf("write legacy profile: %v", err)
	}

	if err := MigrateDefault(); err != nil {
		t.Fatalf("MigrateDefault returned error: %v", err)
	}

	defaultPath, err := DefaultConfigPath()
	if err != nil {
		t.Fatalf("DefaultConfigPath returned error: %v", err)
	}
	assertFileBytes(t, defaultPath, payload)

	profilePath, err := ProfileConfigPath("default")
	if err != nil {
		t.Fatalf("ProfileConfigPath returned error: %v", err)
	}
	assertFileBytes(t, profilePath, payload)
}

func assertFileBytes(t *testing.T, path string, want []byte) {
	t.Helper()

	got, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("read %s: %v", path, err)
	}
	if string(got) != string(want) {
		t.Fatalf("%s = %q, want %q", path, string(got), string(want))
	}
}
