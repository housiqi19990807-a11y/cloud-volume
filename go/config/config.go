package config

import "strings"

// RemoteStorageConfig stores the S3-compatible connection values persisted to TOML.
type RemoteStorageConfig struct {
	Endpoint                 string `json:"endpoint" toml:"endpoint"`
	Region                   string `json:"region" toml:"region"`
	Bucket                   string `json:"bucket" toml:"bucket"`
	AccessKeyID              string `json:"accessKeyId" toml:"access_key_id"`
	SecretAccessKey          string `json:"secretAccessKey" toml:"secret_access_key"`
	RootPrefix               string `json:"rootPrefix" toml:"root_prefix"`
	DefaultDownloadDirectory string `json:"defaultDownloadDirectory" toml:"default_download_directory"`
	UsePathStyle             bool   `json:"usePathStyle" toml:"use_path_style"`
}

// BootstrapState is the typed payload returned to Flutter during startup.
type BootstrapState struct {
	ConfigPath string              `json:"configPath"`
	Configured bool                `json:"configured"`
	Config     RemoteStorageConfig `json:"config"`
	Profiles   []ProfileInfo       `json:"profiles"`
}

// DefaultConfig seeds new users with path-style access enabled for broader compatibility.
func DefaultConfig() RemoteStorageConfig {
	return RemoteStorageConfig{
		UsePathStyle: true,
	}
}

// Normalized trims user input and keeps prefix formatting stable across reads and writes.
func (c RemoteStorageConfig) Normalized() RemoteStorageConfig {
	return RemoteStorageConfig{
		Endpoint:                 strings.TrimSpace(c.Endpoint),
		Region:                   strings.TrimSpace(c.Region),
		Bucket:                   strings.TrimSpace(c.Bucket),
		AccessKeyID:              strings.TrimSpace(c.AccessKeyID),
		SecretAccessKey:          strings.TrimSpace(c.SecretAccessKey),
		RootPrefix:               strings.Trim(strings.TrimSpace(c.RootPrefix), "/"),
		DefaultDownloadDirectory: strings.TrimSpace(c.DefaultDownloadDirectory),
		UsePathStyle:             c.UsePathStyle,
	}
}

// IsConfigured defines the minimum first-run fields required to leave setup mode.
// Bucket and root prefix are optional — only endpoint + auth keys are required.
func (c RemoteStorageConfig) IsConfigured() bool {
	normalized := c.Normalized()
	return normalized.Endpoint != "" &&
		normalized.AccessKeyID != "" &&
		normalized.SecretAccessKey != ""
}
