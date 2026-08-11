// Bucket settings normalize per-bucket quota, access, and trash overrides.
package config

import (
	"path"
	"strings"
)

func normalizeTrashDirectoryName(value string) string {
	trimmed := strings.Trim(strings.TrimSpace(value), "/")
	if trimmed == "" {
		return ".trash"
	}
	cleaned := strings.TrimPrefix(path.Clean("/"+trimmed), "/")
	if cleaned == "" || cleaned == "." {
		return ".trash"
	}
	if !strings.Contains(cleaned, "/") && !strings.HasPrefix(cleaned, ".") {
		return "." + cleaned
	}
	return cleaned
}

func normalizeBucketSettings(settings map[string]BucketSettings) map[string]BucketSettings {
	result := map[string]BucketSettings{}
	for bucket, setting := range settings {
		cleanBucket := strings.TrimSpace(bucket)
		if cleanBucket == "" {
			continue
		}
		if strings.TrimSpace(setting.TrashDirectory) != "" {
			setting.TrashDirectory = normalizeTrashDirectoryName(setting.TrashDirectory)
		}
		if setting.CustomQuotaBytes < 0 {
			setting.CustomQuotaBytes = 0
		}
		setting.WinFspVolumeLabel = strings.TrimSpace(setting.WinFspVolumeLabel)
		result[cleanBucket] = setting
	}
	return result
}

// BucketSettingsFor resolves defaults and explicit overrides for one bucket.
func (c RemoteStorageConfig) BucketSettingsFor(bucket string) BucketSettings {
	normalized := c.Normalized()
	setting := BucketSettings{TrashDirectory: normalized.TrashDirectoryName}
	trashEnabled := normalized.StorageType == StorageTypeS3
	setting.TrashEnabled = &trashEnabled
	if override, ok := normalized.BucketSettings[strings.TrimSpace(bucket)]; ok {
		if override.TrashEnabled != nil {
			setting.TrashEnabled = override.TrashEnabled
		}
		if strings.TrimSpace(override.TrashDirectory) != "" {
			setting.TrashDirectory = normalizeTrashDirectoryName(override.TrashDirectory)
		}
		setting.ReadOnly = override.ReadOnly
		setting.CustomQuotaBytes = override.CustomQuotaBytes
		setting.WinFspVolumeLabel = override.WinFspVolumeLabel
	}
	return setting
}

func (c RemoteStorageConfig) WithBucketSettingsApplied(bucket string) RemoteStorageConfig {
	normalized := c.Normalized()
	normalized.TrashDirectoryName = normalized.BucketSettingsFor(bucket).TrashDirectory
	return normalized
}

func (s BucketSettings) IsTrashEnabled() bool {
	return s.TrashEnabled != nil && *s.TrashEnabled
}

// TrashDirectoryAliases returns reserved trash roots hidden from normal listings.
func TrashDirectoryAliases(value string) []string {
	primary := normalizeTrashDirectoryName(value)
	aliases := []string{primary}
	parent := path.Dir(primary)
	base := path.Base(primary)
	aliasBase := ""
	switch base {
	case ".trash":
		aliasBase = ".Trash"
	case ".Trash":
		aliasBase = ".trash"
	}
	if aliasBase != "" {
		alias := aliasBase
		if parent != "." && parent != "" {
			alias = path.Join(parent, aliasBase)
		}
		aliases = append(aliases, alias)
	}
	return aliases
}
