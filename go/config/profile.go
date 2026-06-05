// Profile management for multi-gateway support.
// Profiles live under the same app data root as the active config file.
// The default profile is named "default" and maps to the existing config.toml.

package config

import (
	"os"
	"path/filepath"
	"sort"
	"strings"
)

const profilesDir = "profiles"

// ProfileInfo describes a stored profile for Flutter.
type ProfileInfo struct {
	Name   string `json:"name"`
	Active bool   `json:"active"`
}

// ProfilesDir returns the path to the profile config directory.
func ProfilesDir() (string, error) {
	rootPath, err := appDataRoot()
	if err != nil {
		return "", err
	}
	return filepath.Join(rootPath, profilesDir), nil
}

// ProfileConfigPath returns the config file path for a named profile.
func ProfileConfigPath(name string) (string, error) {
	dir, err := ProfilesDir()
	if err != nil {
		return "", err
	}
	return filepath.Join(dir, name+".toml"), nil
}

// MigrateDefault moves the legacy config.toml to profiles/default.toml if needed.
func MigrateDefault() error {
	legacyPath, err := DefaultConfigPath()
	if err != nil {
		return err
	}
	dir, err := ProfilesDir()
	if err != nil {
		return err
	}

	// If profiles dir already exists, nothing to migrate.
	if _, err := os.Stat(dir); err == nil {
		return nil
	}

	// Create profiles dir.
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return err
	}

	// If legacy file exists, move it to profiles/default.toml.
	if _, err := os.Stat(legacyPath); err == nil {
		dst := filepath.Join(dir, "default.toml")
		return os.Rename(legacyPath, dst)
	}
	return nil
}

// ListProfiles returns all stored profile names.
func ListProfiles() ([]ProfileInfo, error) {
	dir, err := ProfilesDir()
	if err != nil {
		return nil, err
	}

	if err := os.MkdirAll(dir, 0o700); err != nil {
		return nil, err
	}

	entries, err := os.ReadDir(dir)
	if err != nil {
		return nil, err
	}

	var result []ProfileInfo
	for _, e := range entries {
		if e.IsDir() || !strings.HasSuffix(e.Name(), ".toml") {
			continue
		}
		name := strings.TrimSuffix(e.Name(), ".toml")
		result = append(result, ProfileInfo{Name: name})
	}

	if result == nil {
		result = []ProfileInfo{}
	}

	sort.Slice(result, func(i, j int) bool {
		if result[i].Name == "default" {
			return true
		}
		return result[i].Name < result[j].Name
	})

	return result, nil
}

// SaveProfile persists a config under a named profile.
func SaveProfile(name string, config RemoteStorageConfig) error {
	path, err := ProfileConfigPath(name)
	if err != nil {
		return err
	}
	return NewStore(path).Save(config)
}

// LoadProfile reads a config for a named profile.
func LoadProfile(name string) (RemoteStorageConfig, error) {
	path, err := ProfileConfigPath(name)
	if err != nil {
		return DefaultConfig(), err
	}
	return NewStore(path).Load()
}

// DeleteProfile removes a profile file.
func DeleteProfile(name string) error {
	path, err := ProfileConfigPath(name)
	if err != nil {
		return err
	}
	return os.Remove(path)
}
