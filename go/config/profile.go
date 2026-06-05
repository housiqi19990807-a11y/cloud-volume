// Profile management for multi-gateway support.
// Profiles live under the same app data root as the active config file.
// The default profile is named "default" and maps to the existing config.toml.

package config

import (
	"errors"
	"io"
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

// MigrateDefault copies legacy config files into the current default locations.
func MigrateDefault() error {
	if err := migrateLegacyConfigRoot(); err != nil {
		return err
	}

	defaultPath, err := DefaultConfigPath()
	if err != nil {
		return err
	}
	dir, err := ProfilesDir()
	if err != nil {
		return err
	}

	if err := os.MkdirAll(dir, 0o700); err != nil {
		return err
	}

	defaultProfilePath := filepath.Join(dir, "default.toml")
	if pathExists(defaultProfilePath) || !pathExists(defaultPath) {
		return nil
	}
	return copyFileIfMissing(defaultPath, defaultProfilePath)
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

func migrateLegacyConfigRoot() error {
	legacyRoot, err := legacyAppDataRoot()
	if err != nil {
		return err
	}
	currentRoot, err := appDataRoot()
	if err != nil {
		return err
	}
	if filepath.Clean(legacyRoot) == filepath.Clean(currentRoot) {
		return nil
	}

	currentConfigPath, err := DefaultConfigPath()
	if err != nil {
		return err
	}
	legacyConfigPath := filepath.Join(legacyRoot, configFileName)
	legacyDefaultProfilePath := filepath.Join(legacyRoot, profilesDir, "default.toml")
	if !pathExists(currentConfigPath) {
		if pathExists(legacyConfigPath) {
			if err := copyFileIfMissing(legacyConfigPath, currentConfigPath); err != nil {
				return err
			}
		} else if pathExists(legacyDefaultProfilePath) {
			if err := copyFileIfMissing(legacyDefaultProfilePath, currentConfigPath); err != nil {
				return err
			}
		}
	}

	legacyProfilesDir := filepath.Join(legacyRoot, profilesDir)
	currentProfilesDir, err := ProfilesDir()
	if err != nil {
		return err
	}
	return copyProfileFilesIfMissing(legacyProfilesDir, currentProfilesDir)
}

func copyProfileFilesIfMissing(srcDir, dstDir string) error {
	entries, err := os.ReadDir(srcDir)
	if errors.Is(err, os.ErrNotExist) {
		return nil
	}
	if err != nil {
		return err
	}
	if err := os.MkdirAll(dstDir, 0o700); err != nil {
		return err
	}
	for _, entry := range entries {
		if entry.IsDir() || !strings.HasSuffix(entry.Name(), ".toml") {
			continue
		}
		src := filepath.Join(srcDir, entry.Name())
		dst := filepath.Join(dstDir, entry.Name())
		if err := copyFileIfMissing(src, dst); err != nil {
			return err
		}
	}
	return nil
}

func copyFileIfMissing(src, dst string) error {
	if pathExists(dst) {
		return nil
	}
	input, err := os.Open(src)
	if err != nil {
		return err
	}
	defer input.Close()

	if err := os.MkdirAll(filepath.Dir(dst), 0o700); err != nil {
		return err
	}
	output, err := os.OpenFile(dst, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0o600)
	if err != nil {
		return err
	}

	if _, err := io.Copy(output, input); err != nil {
		_ = output.Close()
		return err
	}
	return output.Close()
}

func pathExists(path string) bool {
	_, err := os.Stat(path)
	return err == nil
}
