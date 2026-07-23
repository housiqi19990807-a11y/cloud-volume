// Package mount keeps optional mount request parameters separate from session state.
package mount

import (
	"path/filepath"
	"strings"
)

// MountOptions carries optional caller-specific mount behavior without
// changing the desktop bridge contract.
type MountOptions struct {
	MountPath     string `json:"mountPath"`
	ReadOnly      bool   `json:"readOnly"`
	DriveLetter   string `json:"driveLetter"`
	AutoSync      bool   `json:"autoSync"`
	UploadWorkers int    `json:"uploadWorkers"`
}

// UnmountOptions controls cleanup after a mount is safely disconnected.
// RemoveLocalCache applies only to managed Cloud Files sync roots; user-picked
// mount paths are deliberately never recursively removed by this option.
type UnmountOptions struct {
	RemoveLocalCache bool `json:"removeLocalCache"`
}

func normalizeMountPath(value string) string {
	trimmed := strings.TrimSpace(value)
	if trimmed == "" {
		return ""
	}
	return filepath.Clean(trimmed)
}
