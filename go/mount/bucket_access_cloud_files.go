// Cloud Files reads use the remote-only bucket view so placeholders never mirror local drafts.
package mount

import (
	"context"
	"io"
	"os"

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

func (a *bucketAccess) readCachedRange(
	ctx context.Context,
	virtualPath string,
	offset,
	length int64,
) ([]byte, error) {
	if length <= 0 {
		return nil, nil
	}
	localPath, info, err := a.ensureLocalFile(ctx, virtualPath)
	if err != nil {
		return nil, err
	}
	file, err := os.Open(localPath)
	if err != nil {
		return nil, err
	}
	defer file.Close()

	if offset >= info.Size {
		return nil, nil
	}
	remaining := info.Size - offset
	if remaining < length {
		length = remaining
	}

	buffer := make([]byte, length)
	n, err := file.ReadAt(buffer, offset)
	switch {
	case err == nil:
		return buffer[:n], nil
	case err == io.EOF:
		return buffer[:n], nil
	default:
		return nil, err
	}
}
