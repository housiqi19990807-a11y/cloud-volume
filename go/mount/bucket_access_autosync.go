// Bucket access autosync helpers bridge Linux sequential write detection to resumable multipart uploads.
package mount

import (
	"context"
	"os"

	s3ops "remote-storage/go/s3"
)

func (a *bucketAccess) uploadPartialPrefix(
	ctx context.Context,
	virtualPath,
	localPath string,
	info os.FileInfo,
	readySize int64,
) error {
	if a == nil || readySize <= 0 {
		return nil
	}
	return s3ops.UploadFilePrefixContextResumable(
		ctx,
		a.config,
		a.bucket,
		a.remoteKey(virtualPath),
		localPath,
		info,
		readySize,
		a.uploadWorkers,
	)
}
