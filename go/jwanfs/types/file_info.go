// File info detail types returned by the FGW file-info / file-info-detail routes.
package types

import "io/fs"

// FileInfoDetailRes mirrors the gateway response for file-info(-detail).
// Size uses int64 directly (the legacy size.B alias was int64-backed).
type FileInfoDetailRes struct {
	Path         string     `json:"Path" dc:"文件路径"`
	Name         string     `json:"Name" dc:"文件名"`
	Size         int64      `json:"Size" dc:"文件大小"`
	Type         string     `json:"Type" dc:"文件类型"`
	Ctime        int64      `json:"Ctime" dc:"文件创建时间"`
	Mtime        int64      `json:"Mtime" dc:"文件最后修改时间"`
	ETag         string     `json:"ETag" dc:"文件校验ETag"`
	UID          uint32     `json:"UID" dc:"文件UID"`
	GID          uint32     `json:"GID" dc:"文件GID"`
	FileMode     uint32     `json:"FileMode" dc:"文件权限"`
	DataPosition []string   `json:"DataPosition" dc:"文件存储路径"`
	ChunkList    *ChunkList `json:"ChunkList,omitempty" dc:"分块列表"`
}

// Mode returns the filesystem mode, marking directories when Type == "dir".
func (f *FileInfoDetailRes) Mode() fs.FileMode {
	if f.IsDir() {
		return fs.FileMode(f.FileMode) | fs.ModeDir
	}
	return fs.FileMode(f.FileMode)
}

// IsDir reports whether the entry is a directory.
func (f *FileInfoDetailRes) IsDir() bool {
	return f.Type == "dir"
}

// ChunkList describes the chunks of a file (only in detail responses).
type ChunkList struct {
	ChunkCount int          `json:"Total" dc:"分块数量"`
	Chunks     []*ChunkInfo `json:"Chunks" dc:"分块数量"`
}

// ChunkInfo describes a single file chunk.
type ChunkInfo struct {
	ChunkID     string   `json:"ChunkID" dc:"分块ID"`
	ChunkSize   int64    `json:"ChunkSize" dc:"分块大小 单位KB"`
	InternalURL []string `json:"InternalURL" dc:"内部存储卷地址"`
	ETag        string   `json:"ETag" dc:"分块校验ETag"`
}

