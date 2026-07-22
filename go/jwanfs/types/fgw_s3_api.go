// Package types carries the JWanFS FGW (file-gateway) business response/request
// structs migrated from jwanfs/pkg/types so the SDK can run without the legacy
// jtool/consts/size dependencies.
//
// Types are kept wire-compatible (same JSON tags) with the upstream gateway.
package types

// FGWS3API is the fgwapi query key value that selects an FGW route.
type FGWS3API = string

// FGW route identifiers used by the SDK when constructing fgwapi=? query URLs.
const (
	FGWS3APIFileInfo       FGWS3API = "file-info"
	FGWS3APIFileInfoDetail FGWS3API = "file-info-detail"
	FGWS3APIFileMd5        FGWS3API = "file-md5"
	FGWS3APIFileMove       FGWS3API = "file-move"
	FGWS3APIFileSearch     FGWS3API = "file-search"

	FGWS3APIResourceFile       FGWS3API = "resource-file"
	FGWS3APIResourceFileDetail FGWS3API = "resource-detail"

	FGWS3APIStaticFile FGWS3API = "static-file"

	FGWS3APIGetShareFile       FGWS3API = "share"
	FGWS3APIGetShareFileDetail FGWS3API = "share-detail"

	FGWS3APIExireToken FGWS3API = "expire-token"

	FGWS3APIBucketQuota FGWS3API = "bucket-quota"

	FGWS3APIAuthInfo FGWS3API = "auth-info"

	FGWS3APIGetExpire FGWS3API = "getExpire"

	FGWS3APIGatewayList FGWS3API = "gateway-list"
)

