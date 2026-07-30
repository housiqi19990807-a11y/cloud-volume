// WebDAV metadata handles serve PROPPATCH probes without mutating file content.
package mount

import (
	"context"
	"fmt"
	"io"
	"os"
)

// metadataWebDAVFile deliberately does not implement webdav.DeadPropsHolder.
// x/net/webdav therefore returns the same forbidden-property response as before,
// but opening and closing this handle never stages or queues object content.
type metadataWebDAVFile struct {
	info os.FileInfo
}

func newMetadataWebDAVFile(
	ctx context.Context,
	access *bucketAccess,
	virtualPath string,
) (*metadataWebDAVFile, error) {
	info, err := access.statPath(ctx, virtualPath)
	if err != nil {
		return nil, pathError("open metadata", virtualPath, err)
	}
	return &metadataWebDAVFile{info: fileInfoFromObject(info)}, nil
}

func (f *metadataWebDAVFile) Close() error {
	return nil
}

func (f *metadataWebDAVFile) Read([]byte) (int, error) {
	return 0, io.EOF
}

func (f *metadataWebDAVFile) Seek(int64, int) (int64, error) {
	return 0, fmt.Errorf("metadata-only WebDAV handle is not seekable")
}

func (f *metadataWebDAVFile) Readdir(int) ([]os.FileInfo, error) {
	return nil, fmt.Errorf("metadata-only WebDAV handle cannot list directories")
}

func (f *metadataWebDAVFile) Stat() (os.FileInfo, error) {
	return f.info, nil
}

func (f *metadataWebDAVFile) Write([]byte) (int, error) {
	return 0, fmt.Errorf("metadata-only WebDAV handle cannot write content")
}
