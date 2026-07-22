// FGW business API methods: FileInfo, FileMD5, MoveObject, BucketQuota,
// FileSearch, temp tokens, share/resource URLs, AuthInfo, GetExpire.
//
// Migrated from jwanfs/pkg/sdk/s3/fgw.go and sign.go (DoFGWAPI/DoFGWAPIRaw).
// The minio/aws-specific methods are intentionally omitted; this file covers
// the FGW-route surface only.
package jwanfs

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"

	"remote-storage/go/jwanfs/types"
)

// FileMD5Result wraps the file-md5 FGW response.
type FileMD5Result struct {
	MD5 string `json:"MD5"`
}

// FileInfo calls the file-info FGW route (detail=false).
func (c *Client) FileInfo(ctx context.Context, bucket, path string) (*types.FileInfoDetailRes, error) {
	return c.FileInfoDetail(ctx, bucket, path, false)
}

// FileInfoDetail calls file-info or file-info-detail depending on the flag.
// When detail is requested and the file has a Size but no chunks, it reports
// an error (consistent with the legacy SDK behavior).
func (c *Client) FileInfoDetail(ctx context.Context, bucket, path string, detail bool) (*types.FileInfoDetailRes, error) {
	api := types.FGWS3APIFileInfo
	if detail {
		api = types.FGWS3APIFileInfoDetail
	}

	path = normalizeFGWPath(path)
	resp, _, err := DoFGWAPI[types.FileInfoDetailRes](ctx, c, api, http.MethodGet, bucket, path, nil)
	if resp == nil {
		return nil, err
	}
	if err == nil && detail && resp.Data != nil && resp.Data.Size != 0 {
		if resp.Data.ChunkList == nil || resp.Data.ChunkList.ChunkCount == 0 {
			err = fmt.Errorf("文件分块不存在")
		}
	}
	return resp.Data, err
}

// GetFileMD5 fetches the MD5 of a file via the file-md5 route.
func (c *Client) GetFileMD5(ctx context.Context, bucket, path string) (string, error) {
	q := makeQueryValues()
	q.Add("path", bucket+normalizeFGWPath(path))

	resp, _, err := DoFGWAPI[FileMD5Result](ctx, c, types.FGWS3APIFileMd5, http.MethodGet, bucket, path, nil, q)
	if resp == nil || resp.Data == nil {
		return "", err
	}
	return resp.Data.MD5, err
}

// MoveObject moves/renames an object within a bucket via the file-move route.
func (c *Client) MoveObject(ctx context.Context, bucket, from, to string) error {
	q := makeQueryValues()
	q.Add("from", from)
	q.Add("to", to)
	_, _, err := DoFGWAPI[map[string]any](ctx, c, types.FGWS3APIFileMove, http.MethodPut, bucket, "", nil, q)
	return err
}

// RenameObject is an alias for MoveObject.
func (c *Client) RenameObject(ctx context.Context, bucket, from, to string) error {
	return c.MoveObject(ctx, bucket, from, to)
}

// BucketQuota fetches the quota for a bucket via the bucket-quota route.
func (c *Client) BucketQuota(ctx context.Context, bucket string) (*types.GetBucketQuotaRes, error) {
	resp, _, err := DoFGWAPI[types.GetBucketQuotaRes](ctx, c, types.FGWS3APIBucketQuota, http.MethodGet, bucket, "", nil)
	if resp == nil {
		return nil, err
	}
	return resp.Data, err
}

// FileSearch searches for files within a bucket.
func (c *Client) FileSearch(ctx context.Context, bucket string, req types.S3FileSearchReq) (*types.S3FileSearchRes, error) {
	resp, _, err := DoFGWAPI[types.S3FileSearchRes](ctx, c, types.FGWS3APIFileSearch, http.MethodGet, bucket, "", nil, structToQueryValues(req))
	if resp == nil {
		return nil, err
	}
	return resp.Data, err
}

// CreateTempToken creates a temporary AKSK via the expire-token route.
func (c *Client) CreateTempToken(ctx context.Context, req types.UserTempTokenReq) (*types.UserTempTokenAKSKRes, error) {
	return c.doTempToken(ctx, http.MethodPost, req)
}

// UpdateTempToken updates a temporary AKSK via the expire-token route.
func (c *Client) UpdateTempToken(ctx context.Context, req types.UserTempTokenReq) (*types.UserTempTokenAKSKRes, error) {
	return c.doTempToken(ctx, http.MethodPut, req)
}

// ShareDetail fetches share-file detail via the public share-detail route.
func (c *Client) ShareDetail(ctx context.Context, req types.S3ShareFileDetailReq) (*types.S3ShareFileDetailRes, error) {
	resp, _, err := doPublicFGWAPI[types.S3ShareFileDetailRes](ctx, c, types.FGWS3APIGetShareFileDetail, http.MethodGet, nil, structToQueryValues(req))
	if resp == nil {
		return nil, err
	}
	return resp.Data, err
}

// AuthInfo fetches the current AKSK authorization info via auth-info.
// This doubles as the JWanFS-gateway detection probe.
func (c *Client) AuthInfo(ctx context.Context) (*types.S3AuthInfoRes, error) {
	resp, _, err := DoFGWAPI[types.S3AuthInfoRes](ctx, c, types.FGWS3APIAuthInfo, http.MethodGet, "", "", nil)
	if resp == nil {
		return nil, err
	}
	return resp.Data, err
}

// GetExpire queries the current AKSK expiration time (unix seconds; -1 = never).
//
// The gateway registers getExpire as a root route matching the "getExpire"
// query key (not fgwapi), so this method builds the request directly rather
// than going through DoFGWAPI.
func (c *Client) GetExpire(ctx context.Context) (int64, error) {
	data, err := doWithFallback(c, func(server string) ([]byte, error) {
		baseURL := server
		if !strings.HasPrefix(baseURL, "http://") && !strings.HasPrefix(baseURL, "https://") {
			baseURL = "http://" + baseURL
		}
		baseURL = strings.TrimSuffix(baseURL, "/") + "/?getExpire="
		req, err := NewSignedRequestV4(ctx, http.MethodGet, baseURL, nil, c.ak, c.sk)
		if err != nil {
			return nil, err
		}
		resp, err := c.HTTPClient().Do(req)
		if err != nil {
			return nil, err
		}
		defer resp.Body.Close()
		body, err := io.ReadAll(resp.Body)
		if err != nil {
			return nil, err
		}
		if resp.StatusCode == http.StatusForbidden {
			return nil, ErrAccessDenied
		}
		if resp.StatusCode >= http.StatusBadRequest {
			return nil, fmt.Errorf("getExpire status=%d body=%s", resp.StatusCode, string(body))
		}
		return body, nil
	})
	if err != nil {
		return 0, err
	}

	var res akSkExpire
	if err := readJSON(data, &res); err != nil {
		return 0, err
	}
	return res.Expire, nil
}

// akSkExpire mirrors the getExpire response shape.
type akSkExpire struct {
	Expire int64 `json:"expiration"`
}

// ShareFileURL builds a signed share-file download URL.
func (c *Client) ShareFileURL(req types.S3GetShareFile) (string, error) {
	u, err := c.NewFGWAPI(types.FGWS3APIGetShareFile, structToQueryValues(req).AsURLValues())
	if err != nil {
		return "", err
	}
	return u.String(), nil
}

// ResourceDetail fetches resource file detail via the public resource-detail route.
func (c *Client) ResourceDetail(ctx context.Context, req types.GetResourceDetailReq) (*types.GetResourceDetailRes, error) {
	resp, _, err := doPublicFGWAPI[types.GetResourceDetailRes](ctx, c, types.FGWS3APIResourceFileDetail, http.MethodGet, nil, structToQueryValues(req))
	if resp == nil {
		return nil, err
	}
	return resp.Data, err
}

// ResourceFileURL builds a resource-file download URL.
func (c *Client) ResourceFileURL(req types.S3GetResourceFile) (string, error) {
	u, err := c.NewFGWAPI(types.FGWS3APIResourceFile, structToQueryValues(req).AsURLValues())
	if err != nil {
		return "", err
	}
	return u.String(), nil
}

// StaticFileURL builds a static-file URL from arbitrary query values.
func (c *Client) StaticFileURL(query QueryValues) (string, error) {
	u, err := c.NewFGWAPI(types.FGWS3APIStaticFile, query.AsURLValues())
	if err != nil {
		return "", err
	}
	return u.String(), nil
}

func (c *Client) doTempToken(ctx context.Context, method string, req types.UserTempTokenReq) (*types.UserTempTokenAKSKRes, error) {
	body, err := json.Marshal(req)
	if err != nil {
		return nil, err
	}
	resp, _, err := DoFGWAPI[types.UserTempTokenAKSKRes](ctx, c, types.FGWS3APIExireToken, method, "", "", body)
	if resp == nil {
		return nil, err
	}
	return resp.Data, err
}
