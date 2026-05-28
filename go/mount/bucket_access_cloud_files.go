// Cloud Files reads use the remote-only bucket view so placeholders never mirror local drafts.
package mount

import (
	"context"

	s3ops "remote-storage/go/s3"
)

func (a *bucketAccess) listRemoteDirectory(
	ctx context.Context,
	virtualPrefix string,
) ([]s3ops.ObjectInfo, error) {
	return a.fetchDirectory(ctx, virtualPrefix)
}

func (a *bucketAccess) statRemotePath(
	ctx context.Context,
	virtualPath string,
) (s3ops.ObjectInfo, error) {
	return a.fetchStat(ctx, virtualPath)
}

func (a *bucketAccess) readRemoteRange(
	ctx context.Context,
	virtualPath string,
	offset,
	length int64,
) ([]byte, error) {
	timeoutCtx, cancel := a.withTransferTimeout(ctx)
	defer cancel()
	return s3ops.ReadObjectRangeContext(
		timeoutCtx,
		a.config,
		a.bucket,
		a.remoteKey(virtualPath),
		offset,
		length,
	)
}
