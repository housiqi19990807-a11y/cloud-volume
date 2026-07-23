// Configuration backup settings and portable account snapshots live in the config DB.
package config

import (
	"encoding/json"
	"fmt"
	"sort"
	"strings"
	"time"

	bolt "go.etcd.io/bbolt"
)

var configBackupSettingsKey = []byte("config_backup_settings")

// ConfigBackupTarget identifies the remote location that receives snapshots.
// ProfileName is preferred; Standalone is intentionally not added to profiles.
type ConfigBackupTarget struct {
	ProfileName string               `json:"profileName"`
	Standalone  *RemoteStorageConfig `json:"standalone,omitempty"`
	Bucket      string               `json:"bucket"`
	Prefix      string               `json:"prefix"`
}

type ConfigBackupSettings struct {
	Enabled bool               `json:"enabled"`
	Target  ConfigBackupTarget `json:"target"`
}

// ConfigBackupArchive contains user-facing account configuration, not caches.
type ConfigBackupArchive struct {
	Version       int                            `json:"version"`
	CreatedAt     time.Time                      `json:"createdAt"`
	Profiles      map[string]RemoteStorageConfig `json:"profiles"`
	ActiveProfile string                         `json:"activeProfile"`
	GlobalProxy   ProxySettings                  `json:"globalProxy"`
	ProfileOrder  []string                       `json:"profileOrder"`
	BucketOrder   []string                       `json:"bucketOrder"`
}

func LoadConfigBackupSettings() (ConfigBackupSettings, error) {
	db, err := openConfigDB()
	if err != nil {
		return ConfigBackupSettings{}, err
	}
	defer db.Close()
	var settings ConfigBackupSettings
	err = db.View(func(tx *bolt.Tx) error {
		data := tx.Bucket(metaBucketKey).Get(configBackupSettingsKey)
		if len(data) == 0 {
			return nil
		}
		return json.Unmarshal(data, &settings)
	})
	return settings, err
}

func SaveConfigBackupSettings(settings ConfigBackupSettings) error {
	settings.Target.ProfileName = sanitizeProfileName(settings.Target.ProfileName)
	settings.Target.Bucket = strings.TrimSpace(settings.Target.Bucket)
	settings.Target.Prefix = strings.Trim(strings.TrimSpace(settings.Target.Prefix), "/")
	if settings.Enabled && settings.Target.Bucket == "" {
		return fmt.Errorf("请选择配置备份的存储桶")
	}
	if settings.Target.ProfileName == "" {
		if settings.Target.Standalone != nil {
			normalized := settings.Target.Standalone.Normalized().WithDefaultWebDAVCredentials()
			if normalized.IsConfigured() {
				settings.Target.Standalone = &normalized
			} else {
				settings.Target.Standalone = nil
			}
		}
		if settings.Enabled && (settings.Target.Standalone == nil || !settings.Target.Standalone.IsConfigured()) {
			return fmt.Errorf("请配置用于备份的独立存储连接")
		}
	}
	payload, err := json.Marshal(settings)
	if err != nil {
		return fmt.Errorf("encode config backup settings: %w", err)
	}
	db, err := openConfigDB()
	if err != nil {
		return err
	}
	defer db.Close()
	return db.Update(func(tx *bolt.Tx) error {
		return tx.Bucket(metaBucketKey).Put(configBackupSettingsKey, payload)
	})
}

// ExportConfigBackup captures only restorable user configuration.
func ExportConfigBackup() (ConfigBackupArchive, error) {
	db, err := openConfigDB()
	if err != nil {
		return ConfigBackupArchive{}, err
	}
	defer db.Close()
	archive := ConfigBackupArchive{Version: 1, CreatedAt: time.Now().UTC(), Profiles: map[string]RemoteStorageConfig{}}
	err = db.View(func(tx *bolt.Tx) error {
		profiles := tx.Bucket(profilesBucketKey)
		if err := profiles.ForEach(func(key, value []byte) error {
			var cfg RemoteStorageConfig
			if err := json.Unmarshal(value, &cfg); err != nil {
				return fmt.Errorf("decode profile %q: %w", key, err)
			}
			archive.Profiles[string(key)] = cfg
			return nil
		}); err != nil {
			return err
		}
		meta := tx.Bucket(metaBucketKey)
		archive.ActiveProfile = string(meta.Get(activeProfileKey))
		archive.ProfileOrder = loadProfileOrder(tx)
		archive.BucketOrder = loadBucketOrder(tx)
		if data := meta.Get(globalProxyKey); len(data) > 0 {
			if err := json.Unmarshal(data, &archive.GlobalProxy); err != nil {
				return fmt.Errorf("decode global proxy: %w", err)
			}
		}
		return nil
	})
	return archive, err
}

// RestoreConfigBackup replaces account/proxy/order state but preserves the
// backup destination itself, so the user can restore again after a bad import.
func RestoreConfigBackup(archive ConfigBackupArchive) error {
	if archive.Version != 1 || len(archive.Profiles) == 0 {
		return fmt.Errorf("不支持或为空的配置备份")
	}
	names := make([]string, 0, len(archive.Profiles))
	profilesByName := make(map[string]RemoteStorageConfig, len(archive.Profiles))
	for name, cfg := range archive.Profiles {
		clean := sanitizeProfileName(name)
		if clean == "" {
			return fmt.Errorf("配置备份包含无效账号名")
		}
		if _, exists := profilesByName[clean]; exists {
			return fmt.Errorf("配置备份包含重复账号名")
		}
		names = append(names, clean)
		profilesByName[clean] = cfg
	}
	sort.Strings(names)
	db, err := openConfigDB()
	if err != nil {
		return err
	}
	defer db.Close()
	return db.Update(func(tx *bolt.Tx) error {
		if err := tx.DeleteBucket(profilesBucketKey); err != nil && err != bolt.ErrBucketNotFound {
			return err
		}
		profiles, err := tx.CreateBucket(profilesBucketKey)
		if err != nil {
			return err
		}
		for _, name := range names {
			data, err := json.Marshal(profilesByName[name].Normalized().WithDefaultWebDAVCredentials())
			if err != nil {
				return err
			}
			if err := profiles.Put([]byte(name), data); err != nil {
				return err
			}
		}
		meta := tx.Bucket(metaBucketKey)
		if err := meta.Put(activeProfileKey, []byte(sanitizeProfileName(archive.ActiveProfile))); err != nil {
			return err
		}
		proxy, err := json.Marshal(archive.GlobalProxy)
		if err != nil {
			return err
		}
		if err := meta.Put(globalProxyKey, proxy); err != nil {
			return err
		}
		if err := putOrderJSON(tx, profileOrderKey, archive.ProfileOrder); err != nil {
			return err
		}
		return putOrderJSON(tx, bucketOrderKey, archive.BucketOrder)
	})
}
