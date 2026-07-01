// Store owns legacy TOML config file IO. It is only used during the one-time
// TOML→bbolt migration. All runtime config access goes through bbolt.
package config

import (
	"errors"
	"os"
	"path/filepath"
	"strings"

	toml "github.com/pelletier/go-toml/v2"
)

// Store is a thin wrapper for reading/writing a single TOML config file.
type Store struct {
	configPath string
}

func NewStore(configPath string) Store {
	return Store{configPath: configPath}
}

// Load reads TOML when present and otherwise returns a default config.
func (s Store) Load() (RemoteStorageConfig, error) {
	if err := s.validate(); err != nil {
		return DefaultConfig(), err
	}
	config := DefaultConfig()
	data, err := os.ReadFile(s.configPath)
	if errors.Is(err, os.ErrNotExist) {
		return config, nil
	}
	if err != nil {
		return config, err
	}
	if strings.TrimSpace(string(data)) == "" {
		return config, nil
	}
	if err := toml.Unmarshal(data, &config); err != nil {
		return config, err
	}
	return config.Normalized(), nil
}

func (s Store) validate() error {
	if strings.TrimSpace(s.configPath) == "" {
		return errors.New("config path is empty")
	}
	return nil
}

// Save writes a TOML config file (CLI only — runtime uses bbolt).
func (s Store) Save(config RemoteStorageConfig) error {
	normalized := config.Normalized().WithDefaultWebDAVCredentials()
	if err := os.MkdirAll(filepath.Dir(s.configPath), 0o700); err != nil {
		return err
	}
	body, err := toml.Marshal(normalized)
	if err != nil {
		return err
	}
	payload := append([]byte("# Remote Storage configuration.\n"), body...)
	return os.WriteFile(s.configPath, payload, 0o600)
}

// SaveProfileWithValidation persists a config and rejects incomplete submissions.
// Used by SaveProfile to keep the same first-run validation as the old TOML path.
func SaveProfileWithValidation(name string, config RemoteStorageConfig) error {
	normalized := config.Normalized().WithDefaultWebDAVCredentials()
	if !normalized.IsConfigured() {
		if normalized.StorageType == StorageTypeBaiduPan {
			return errors.New("请先完成百度网盘授权登录")
		}
		if normalized.StorageType == StorageTypeWebDAV {
			return errors.New("WebDAV 地址、用户名和密码为必填项")
		}
		return errors.New("端点地址、访问密钥 ID 和访问密钥为必填项")
	}
	return saveProfileToDB(name, normalized)
}

// SaveProfileWithValidation persists a config and rejects incomplete submissions.
// Used by SaveProfile to keep the same first-run validation as the old TOML path.
