// FGW file search request/response types.
package types

// S3FileSearchReq queries the file-search route.
type S3FileSearchReq struct {
	Keyword  string    `query:"Keyword"`
	Ext      string    `query:"Ext"`
	Page     int64     `query:"Page" default:"1"`
	PageSize int64     `query:"PageSize" default:"50"`
	Sort     SortOrder `query:"Sort"`
	SortBy   SortBy    `query:"SortBy"`
}

// S3FileSearchRes is the file-search result.
type S3FileSearchRes struct {
	FileInfo []ResourceFileInfo `json:"FileInfo"`
	Total    int64              `json:"Total"`
}

