package config

import (
	"fmt"
	"os"
	"path/filepath"
)

const (
	configDirName  = ".remote-storage"
	configFileName = "config.toml"
)

// DefaultConfigPath resolves the user-scoped TOML path used by the desktop app.
func DefaultConfigPath() (string, error) {
	homePath, err := os.UserHomeDir()
	if err != nil {
		return "", fmt.Errorf("resolve user home: %w", err)
	}
	return filepath.Join(homePath, configDirName, configFileName), nil
}
