//go:build windows

// WinFsp volume labels resolve the optional bucket override for Explorer.
package mount

import (
	"strings"

	storageconfig "remote-storage/go/config"
)

func winFspVolumeLabel(cfg storageconfig.RemoteStorageConfig, bucket string) string {
	if label := strings.TrimSpace(cfg.BucketSettingsFor(bucket).WinFspVolumeLabel); label != "" {
		return label
	}
	return "Cloud Volume " + bucket
}
