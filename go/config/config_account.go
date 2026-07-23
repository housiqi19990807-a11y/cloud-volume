// Account-facing configuration helpers preserve stored credentials and labels.
package config

// WithResolvedCacheDirectory fills the platform default cache path for UI/runtime use.
func (c RemoteStorageConfig) WithResolvedCacheDirectory() (RemoteStorageConfig, error) {
	normalized := c.Normalized()
	cacheDir, err := ResolveCacheDir(normalized)
	if err != nil {
		return RemoteStorageConfig{}, err
	}
	normalized.ResolvedCacheDirectory = cacheDir
	return normalized, nil
}

// IsConfigured defines the minimum first-run fields required to leave setup mode.
// Bucket and root prefix are optional — only endpoint + auth keys are required.
func (c RemoteStorageConfig) IsConfigured() bool {
	normalized := c.Normalized()
	if normalized.Endpoint == "" {
		return false
	}
	if normalized.StorageType == StorageTypeBaiduPan {
		return normalized.AccessKeyID != "" &&
			(normalized.SecretAccessKey != "" || normalized.HasSecretAccessKey)
	}
	if normalized.StorageType == StorageTypeWebDAV {
		return normalized.WebDAVUsername != "" &&
			(normalized.WebDAVPassword != "" || normalized.HasWebDAVPassword)
	}
	if normalized.StorageType == StorageTypeFTP || normalized.StorageType == StorageTypeSFTP {
		// Anonymous login: username is optional, password is optional.
		if normalized.FTPAnonymous {
			return true
		}
		return normalized.FTPUsername != "" &&
			(normalized.FTPPassword != "" || normalized.HasFTPPassword)
	}
	return normalized.AccessKeyID != "" &&
		(normalized.SecretAccessKey != "" || normalized.HasSecretAccessKey)
}

// HasWebDAVCredentials reports whether web login credentials are complete.
func (c RemoteStorageConfig) HasWebDAVCredentials() bool {
	normalized := c.Normalized()
	return normalized.WebDAVUsername != "" &&
		(normalized.WebDAVPassword != "" || normalized.HasWebDAVPassword)
}

// MergeStoredSecrets keeps existing secrets when the client intentionally omits them.
func (c RemoteStorageConfig) MergeStoredSecrets(existing RemoteStorageConfig) RemoteStorageConfig {
	normalized := c.Normalized()
	current := existing.Normalized()
	if normalized.SecretAccessKey == "" && normalized.HasSecretAccessKey && current.SecretAccessKey != "" {
		normalized.SecretAccessKey = current.SecretAccessKey
	}
	if normalized.WebDAVPassword == "" && normalized.HasWebDAVPassword && current.WebDAVPassword != "" {
		normalized.WebDAVPassword = current.WebDAVPassword
	}
	if normalized.FTPPassword == "" && normalized.HasFTPPassword && current.FTPPassword != "" {
		normalized.FTPPassword = current.FTPPassword
	}
	normalized.HasSecretAccessKey = normalized.SecretAccessKey != "" || normalized.HasSecretAccessKey
	normalized.HasWebDAVPassword = normalized.WebDAVPassword != "" || normalized.HasWebDAVPassword
	normalized.HasFTPPassword = normalized.FTPPassword != "" || normalized.HasFTPPassword
	return normalized
}

// WithDefaultWebDAVCredentials falls back to AK/SK when web credentials are omitted.
func (c RemoteStorageConfig) WithDefaultWebDAVCredentials() RemoteStorageConfig {
	normalized := c.Normalized()
	if normalized.StorageType == StorageTypeWebDAV || normalized.StorageType == StorageTypeFTP ||
		normalized.StorageType == StorageTypeSFTP || normalized.StorageType == StorageTypeBaiduPan {
		return normalized
	}
	if normalized.WebDAVUsername == "" {
		normalized.WebDAVUsername = normalized.AccessKeyID
	}
	if normalized.WebDAVPassword == "" && normalized.SecretAccessKey != "" {
		normalized.WebDAVPassword = normalized.SecretAccessKey
	}
	normalized.HasWebDAVPassword = normalized.WebDAVPassword != "" || normalized.HasWebDAVPassword
	return normalized
}

// AccountLabel returns the user-facing account name for management views.
func (c RemoteStorageConfig) AccountLabel(fallback string) string {
	normalized := c.Normalized()
	if normalized.DisplayName != "" {
		return normalized.DisplayName
	}
	if normalized.StorageType == StorageTypeBaiduPan {
		if fallback != "" {
			return fallback
		}
		return "百度网盘"
	}
	if normalized.StorageType == StorageTypeFTP || normalized.StorageType == StorageTypeSFTP {
		if normalized.FTPUsername != "" {
			return normalized.FTPUsername
		}
		return "FTP"
	}
	if normalized.AccessKeyID != "" {
		return normalized.AccessKeyID
	}
	if normalized.WebDAVUsername != "" {
		return normalized.WebDAVUsername
	}
	if fallback != "" {
		return fallback
	}
	return "未命名账号"
}

// MappedBucketLabel returns the virtual bucket name used by single-root backends.
func (c RemoteStorageConfig) MappedBucketLabel() string {
	return c.Normalized().MappedBucketName
}

// PublicSanitized clears secrets while preserving whether stored secrets exist.
func (c RemoteStorageConfig) PublicSanitized() RemoteStorageConfig {
	normalized := c.Normalized()
	normalized.SecretAccessKey = ""
	normalized.WebDAVPassword = ""
	normalized.FTPPassword = ""
	normalized.HasFTPPassword = normalized.HasFTPPassword && normalized.FTPPassword == ""
	return normalized
}
