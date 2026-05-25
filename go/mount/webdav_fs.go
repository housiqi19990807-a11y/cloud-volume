// WebDAV filesystem maps Finder/WebDAV operations onto one S3 bucket view.
package mount

import (
	"context"
	"io/fs"
	"os"
	"path"
	"strings"
	"time"

	"golang.org/x/net/webdav"
)

type webDAVFS struct {
	access *bucketAccess
}

func (f *webDAVFS) Mkdir(ctx context.Context, name string, _ os.FileMode) error {
	return f.access.createDirectory(ctx, normalizeWebDAVName(name))
}

func (f *webDAVFS) OpenFile(
	ctx context.Context,
	name string,
	flag int,
	perm os.FileMode,
) (webdav.File, error) {
	clean := normalizeWebDAVName(name)
	switch {
	case flag&os.O_CREATE != 0 || flag&os.O_WRONLY != 0 || flag&os.O_RDWR != 0 || flag&os.O_TRUNC != 0:
		return newWritableWebDAVFile(ctx, f.access, clean, perm, flag)
	default:
		return newReadableWebDAVFile(ctx, f.access, clean)
	}
}

func (f *webDAVFS) RemoveAll(ctx context.Context, name string) error {
	clean := normalizeWebDAVName(name)
	info, err := f.Stat(ctx, clean)
	if err != nil {
		return err
	}
	return f.access.deletePath(ctx, clean, info.IsDir())
}

func (f *webDAVFS) Rename(ctx context.Context, oldName, newName string) error {
	oldClean := normalizeWebDAVName(oldName)
	newClean := normalizeWebDAVName(newName)
	info, err := f.Stat(ctx, oldClean)
	if err != nil {
		return err
	}
	return f.access.renamePath(ctx, oldClean, newClean, info.IsDir())
}

func (f *webDAVFS) Stat(ctx context.Context, name string) (os.FileInfo, error) {
	clean := normalizeWebDAVName(name)
	if clean == "" {
		return virtualFileInfo{
			name:    "/",
			size:    0,
			mode:    fs.ModeDir | 0o755,
			modTime: time.Now(),
			isDir:   true,
		}, nil
	}
	info, err := f.access.statPath(ctx, clean)
	if err != nil {
		return nil, err
	}
	return fileInfoFromObject(info), nil
}

func normalizeWebDAVName(name string) string {
	clean := path.Clean("/" + strings.TrimSpace(name))
	return strings.Trim(clean, "/")
}
