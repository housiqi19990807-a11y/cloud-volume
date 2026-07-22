// Resource file detail types used by the FGW resource-detail route.
package types

// ResourceFileInfo is a single file entry inside resource/search/share lists.
type ResourceFileInfo struct {
	Name        string `json:"Name" dc:"文件名称"`
	FileSize    int64  `json:"FileSize" dc:"文件大小"`
	Type        string `json:"Type" dc:"文件类型"`
	Mtime       int64  `json:"Mtime" dc:"文件最后修改时间"`
	Path        string `json:"Path" dc:"全路径"`
	DownloadUrl string `json:"DownloadUrl,omitempty" dc:"下载地址"`
	S3Url       string `json:"S3Url,omitempty" dc:"下载地址"`
	ThumbsUrl   string `json:"ThumbsUrl,omitempty" dc:"预览图地址"`
}

// IsDir reports whether the entry is a directory.
func (r *ResourceFileInfo) IsDir() bool {
	return r.Type == "dir"
}

// GetResourceDetailReq is the query for resource-detail.
type GetResourceDetailReq struct {
	CurPage     int         `query:"Page"`
	PageSize    int         `query:"PageSize"`
	Name        string      `query:"Name"`
	SortName    string      `query:"SortName"`
	SortOrder   string      `query:"SortOrder"`
	Path        string      `query:"Path"`
	Search      string      `query:"Search"`
	Type        SearchType  `query:"Type"`
	SearchField string      `query:"SearchField"`
	ID          string      `query:"ShareUrl"`
}

// GetResourceDetailRes wraps a resource with its file list.
type GetResourceDetailRes struct {
	FileInfo []ResourceFileInfo `json:"FileInfo"`
}

// S3GetResourceFile builds the query for resource-file downloads.
type S3GetResourceFile struct {
	ShareUrl string `query:"ShareUrl"`
	Mode     string `query:"mode"`
	File     string `query:"file"`
}

