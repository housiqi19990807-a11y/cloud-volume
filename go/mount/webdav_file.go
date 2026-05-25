// WebDAV file handles implement read, directory listing, and staged-write upload.
package mount

import (
	"context"
	"fmt"
	"io"
	"io/fs"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"

	s3ops "remote-storage/go/s3"
)

type readableWebDAVFile struct {
	ctx      context.Context
	access   *bucketAccess
	path     string
	file     *os.File
	dirInfos []os.FileInfo
	dirPos   int
	info     os.FileInfo
}

type writableWebDAVFile struct {
	ctx        context.Context
	access     *bucketAccess
	virtualKey string
	tempPath   string
	file       *os.File
	info       os.FileInfo
	closed     bool
}

type virtualFileInfo struct {
	name    string
	size    int64
	mode    fs.FileMode
	modTime time.Time
	isDir   bool
}

func newReadableWebDAVFile(
	ctx context.Context,
	access *bucketAccess,
	virtualPath string,
) (*readableWebDAVFile, error) {
	if virtualPath == "" {
		return newDirectoryHandle(access, ""), nil
	}
	info, err := access.statPath(ctx, virtualPath)
	if err != nil {
		return nil, pathError("open", virtualPath, err)
	}
	if info.IsDir {
		return newDirectoryHandle(access, virtualPath), nil
	}

	localPath, _, err := access.ensureLocalFile(ctx, virtualPath)
	if err != nil {
		return nil, pathError("open", virtualPath, err)
	}
	file, err := os.Open(localPath)
	if err != nil {
		return nil, pathError("open", virtualPath, err)
	}
	return &readableWebDAVFile{
		ctx:    ctx,
		access: access,
		path:   virtualPath,
		file:   file,
		info:   fileInfoFromObject(info),
	}, nil
}

func newWritableWebDAVFile(
	ctx context.Context,
	access *bucketAccess,
	virtualPath string,
	perm os.FileMode,
	flag int,
) (*writableWebDAVFile, error) {
	tempPath := access.stagePathFor(virtualPath)
	if err := os.MkdirAll(filepath.Dir(tempPath), 0o755); err != nil {
		return nil, err
	}
	if err := seedWritableTempFile(ctx, access, virtualPath, tempPath, flag); err != nil {
		return nil, err
	}
	openFlag := os.O_CREATE
	if flag&os.O_RDWR != 0 {
		openFlag |= os.O_RDWR
	} else {
		openFlag |= os.O_WRONLY
	}
	if flag&os.O_TRUNC != 0 {
		openFlag |= os.O_TRUNC
	}
	if flag&os.O_APPEND != 0 {
		openFlag |= os.O_APPEND
	}
	if perm.Perm() == 0 {
		perm = 0o644
	}
	file, err := os.OpenFile(tempPath, openFlag, perm.Perm())
	if err != nil {
		return nil, err
	}
	info := virtualFileInfo{
		name:    baseName(virtualPath),
		size:    0,
		mode:    0o644,
		modTime: time.Now(),
		isDir:   false,
	}
	return &writableWebDAVFile{
		ctx:        ctx,
		access:     access,
		virtualKey: virtualPath,
		tempPath:   tempPath,
		file:       file,
		info:       info,
	}, nil
}

func seedWritableTempFile(
	ctx context.Context,
	access *bucketAccess,
	virtualPath,
	tempPath string,
	flag int,
) error {
	_ = os.Remove(tempPath)
	if flag&os.O_TRUNC != 0 {
		return nil
	}

	localPath, _, err := access.ensureLocalFile(ctx, virtualPath)
	if err == nil {
		return copyFile(tempPath, localPath)
	}
	if flag&os.O_CREATE != 0 {
		return nil
	}
	return err
}

func newDirectoryHandle(access *bucketAccess, virtualPath string) *readableWebDAVFile {
	return &readableWebDAVFile{
		ctx:    context.Background(),
		access: access,
		path:   virtualPath,
		info: virtualFileInfo{
			name:    baseName(virtualPath),
			size:    0,
			mode:    fs.ModeDir | 0o755,
			modTime: time.Now(),
			isDir:   true,
		},
		dirInfos: nil,
	}
}

func (f *readableWebDAVFile) Close() error {
	if f.file != nil {
		return f.file.Close()
	}
	return nil
}

func (f *readableWebDAVFile) Read(p []byte) (int, error) {
	if f.file == nil {
		return 0, io.EOF
	}
	return f.file.Read(p)
}

func (f *readableWebDAVFile) Seek(offset int64, whence int) (int64, error) {
	if f.file == nil {
		return 0, nil
	}
	return f.file.Seek(offset, whence)
}

func (f *readableWebDAVFile) Readdir(count int) ([]os.FileInfo, error) {
	if !f.info.IsDir() {
		return nil, fmt.Errorf("not a directory")
	}
	if f.dirInfos == nil {
		items, err := f.listDir()
		if err != nil {
			return nil, err
		}
		f.dirInfos = items
	}
	if f.dirPos >= len(f.dirInfos) && count > 0 {
		return nil, io.EOF
	}
	if count <= 0 {
		return f.dirInfos, nil
	}
	end := f.dirPos + count
	if end > len(f.dirInfos) {
		end = len(f.dirInfos)
	}
	out := f.dirInfos[f.dirPos:end]
	f.dirPos = end
	return out, nil
}

func (f *readableWebDAVFile) Stat() (os.FileInfo, error) {
	return f.info, nil
}

func (f *readableWebDAVFile) Write([]byte) (int, error) {
	return 0, fmt.Errorf("read-only file handle")
}

func (f *readableWebDAVFile) listDir() ([]os.FileInfo, error) {
	items, err := f.access.listDirectory(f.ctx, f.path)
	if err != nil {
		return nil, pathError("readdir", f.path, err)
	}
	infos := make([]os.FileInfo, 0, len(items))
	for _, item := range items {
		infos = append(infos, fileInfoFromObject(item))
	}
	sort.Slice(infos, func(i, j int) bool {
		if infos[i].IsDir() != infos[j].IsDir() {
			return infos[i].IsDir()
		}
		return infos[i].Name() < infos[j].Name()
	})
	return infos, nil
}

func (f *writableWebDAVFile) Close() error {
	if f.closed {
		return nil
	}
	f.closed = true
	if err := f.file.Close(); err != nil {
		return err
	}
	cachePath := f.access.cachePathFor(f.virtualKey)
	_ = os.MkdirAll(filepath.Dir(cachePath), 0o755)
	_ = os.Remove(cachePath)
	if err := os.Rename(f.tempPath, cachePath); err != nil {
		return err
	}
	f.access.registerLocalWrite(f.virtualKey, cachePath, fileSize(cachePath))
	f.access.scheduleUpload(f.virtualKey, cachePath)
	return nil
}

func (f *writableWebDAVFile) Read([]byte) (int, error) {
	return 0, io.EOF
}

func (f *writableWebDAVFile) Seek(offset int64, whence int) (int64, error) {
	return f.file.Seek(offset, whence)
}

func (f *writableWebDAVFile) Readdir(int) ([]os.FileInfo, error) {
	return nil, fmt.Errorf("not a directory")
}

func (f *writableWebDAVFile) Stat() (os.FileInfo, error) {
	stat, err := f.file.Stat()
	if err == nil {
		return stat, nil
	}
	return f.info, nil
}

func (f *writableWebDAVFile) Write(p []byte) (int, error) {
	return f.file.Write(p)
}

func fileInfoFromObject(info s3ops.ObjectInfo) os.FileInfo {
	name := info.Key
	if info.IsDir {
		name = baseName(strings.TrimSuffix(info.Key, "/"))
	} else {
		name = baseName(info.Key)
	}
	modTime := time.Now()
	if parsed, err := time.Parse("2006-01-02 15:04:05", info.LastModified); err == nil {
		modTime = parsed
	}
	mode := fs.FileMode(0o644)
	if info.IsDir {
		mode = fs.ModeDir | 0o755
	}
	return virtualFileInfo{
		name:    name,
		size:    info.Size,
		mode:    mode,
		modTime: modTime,
		isDir:   info.IsDir,
	}
}

func (i virtualFileInfo) Name() string       { return i.name }
func (i virtualFileInfo) Size() int64        { return i.size }
func (i virtualFileInfo) Mode() fs.FileMode  { return i.mode }
func (i virtualFileInfo) ModTime() time.Time { return i.modTime }
func (i virtualFileInfo) IsDir() bool        { return i.isDir }
func (i virtualFileInfo) Sys() any           { return nil }

func pathError(op, virtualPath string, err error) error {
	if err == nil {
		return nil
	}
	if _, ok := err.(*os.PathError); ok {
		return err
	}
	pathValue := "/" + cleanVirtualPath(virtualPath)
	if pathValue == "/" {
		pathValue = "."
	}
	return &os.PathError{Op: op, Path: pathValue, Err: err}
}
