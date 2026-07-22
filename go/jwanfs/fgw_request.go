// FGW raw request transport: DoFGWAPIRaw, DoFGWAPI, doPublicFGWAPI.
//
// These build a signed SigV4 request against the fgwapi=? route, send it with
// failover across the upstream pool, and parse the FGWResp envelope.
package jwanfs

import (
	"bytes"
	"context"
	"fmt"
	"io"
	"net/http"

	"remote-storage/go/jwanfs/types"
)

// DoFGWAPIRaw sends a signed FGW request and returns the raw response body.
// bucket/path are forwarded as headers (the gateway reads them there).
func (c *Client) DoFGWAPIRaw(ctx context.Context, fgwapi string, method, bucket, path string, body []byte, query ...QueryValues) ([]byte, error) {
	return doWithFallback(c, func(server string) ([]byte, error) {
		c.debugf("FGWAPI: %s bucket=%s path=%s method=%s", fgwapi, bucket, path, method)

		urlValue, err := NewFGWAPI(server, fgwapi, mergeQueryValues(query...).AsURLValues())
		if err != nil {
			return nil, err
		}
		c.debugf("FullUrl: %s AccessKey: %s", urlValue.String(), c.ak)

		req, err := NewSignedRequestV4(ctx, method, urlValue.String(), body, c.ak, c.sk)
		if err != nil {
			return nil, err
		}
		if bucket != "" {
			req.Header.Set("bucket", bucket)
		}
		if path != "" {
			req.Header.Set("path", path)
		}

		resp, err := c.HTTPClient().Do(req)
		if err != nil {
			return nil, err
		}
		defer resp.Body.Close()

		data, err := io.ReadAll(resp.Body)
		if err != nil {
			return nil, err
		}
		c.debugf("RAW Resp: %s", string(data))
		if resp.StatusCode == http.StatusForbidden {
			return nil, ErrAccessDenied
		}
		if resp.StatusCode >= http.StatusBadRequest {
			return nil, fmt.Errorf("fgwapi status=%d body=%s", resp.StatusCode, string(data))
		}
		return data, nil
	})
}

// DoFGWAPI sends a signed FGW request and decodes the FGWResp[T] envelope.
// Returns the parsed response, the raw body, and an error.
func DoFGWAPI[T any](ctx context.Context, client *Client, fgwapi string, method, bucket, path string, body []byte, query ...QueryValues) (*types.FGWResp[T], []byte, error) {
	if client == nil {
		return nil, nil, fmt.Errorf("client is nil")
	}

	data, err := client.DoFGWAPIRaw(ctx, fgwapi, method, bucket, path, body, query...)
	if err != nil {
		return nil, data, err
	}

	var resp types.FGWResp[T]
	if err := readJSON(data, &resp); err != nil {
		return nil, data, err
	}
	if resp.Code != 200 {
		return &resp, data, fmt.Errorf("%v", resp.Msg)
	}
	return &resp, data, nil
}

// doPublicFGWAPI sends an unsigned FGW request (for public share/resource routes).
func doPublicFGWAPI[T any](ctx context.Context, client *Client, api string, method string, body []byte, query ...QueryValues) (*types.FGWResp[T], []byte, error) {
	data, err := doWithFallback(client, func(server string) ([]byte, error) {
		urlValue, buildErr := NewFGWAPI(server, api, mergeQueryValues(query...).AsURLValues())
		if buildErr != nil {
			return nil, buildErr
		}

		var reqBody io.Reader
		if len(body) > 0 {
			reqBody = bytes.NewReader(body)
		}
		req, reqErr := http.NewRequestWithContext(ctxOrBackground(ctx), method, urlValue.String(), reqBody)
		if reqErr != nil {
			return nil, reqErr
		}
		if len(body) > 0 {
			req.Header.Set("Content-Type", "application/json")
		}

		resp, callErr := client.HTTPClient().Do(req)
		if callErr != nil {
			return nil, callErr
		}
		defer resp.Body.Close()

		data, readErr := io.ReadAll(resp.Body)
		if readErr != nil {
			return nil, readErr
		}
		if resp.StatusCode >= http.StatusBadRequest {
			return nil, fmt.Errorf("fgwapi status=%d body=%s", resp.StatusCode, string(data))
		}
		return data, nil
	})
	if err != nil {
		return nil, data, err
	}

	var result types.FGWResp[T]
	if err := readJSON(data, &result); err != nil {
		return nil, data, err
	}
	if result.Code != 200 {
		return &result, data, fmt.Errorf("%v", result.Msg)
	}
	return &result, data, nil
}

