// FGW share-file request/response types.
package types

// S3GetShareFile builds the query for share-file downloads.
type S3GetShareFile struct {
	ShareUrl string `query:"ShareUrl"`
	Mode     string `query:"mode"`
	File     string `query:"file"`
	Password string `query:"pwd"`
	Style    string `query:"style"`
}

// S3ShareFileDetailReq queries share-file detail listings.
type S3ShareFileDetailReq struct {
	ShareUrl string `query:"ShareUrl"`
	Path     string `query:"path"`
	Password string `query:"pwd"`
}

// S3ShareFileDetailRes is the share-file detail listing.
type S3ShareFileDetailRes struct {
	FileInfo []ResourceFileInfo `json:"FileInfo"`
	Total    int64              `json:"Total"`
}

