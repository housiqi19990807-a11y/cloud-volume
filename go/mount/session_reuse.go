// Package mount keeps session reuse checks isolated so remount decisions stay explicit.
package mount

import (
	"reflect"
	"strings"

	storageconfig "remote-storage/go/config"
)

func mountSessionMatches(
	session *mountSession,
	cfg storageconfig.RemoteStorageConfig,
	bucket string,
	options MountOptions,
) bool {
	if session == nil {
		return false
	}
	normalized := cfg.Normalized()
	return session.bucket == normalizeBucketName(bucket) &&
		reflect.DeepEqual(session.config, normalized) &&
		session.requestedPath == normalizeMountPath(options.MountPath) &&
		session.readOnly == options.ReadOnly &&
		session.requestedDriveLetter == strings.ToUpper(strings.TrimSpace(options.DriveLetter)) &&
		session.autoSync == options.AutoSync &&
		session.uploadWorkers == options.UploadWorkers
}
