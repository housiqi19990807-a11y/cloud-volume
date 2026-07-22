// WebDAV quota discovery reads the RFC 4331 properties from the mapped root.
package storage

import (
	"context"
	"encoding/xml"
	"fmt"
	"strconv"
	"strings"
	"time"
)

const (
	webDAVQuotaTimeout = 15 * time.Second
	maxQuotaBytes      = int64(^uint64(0) >> 1)
	webDAVQuotaBody    = `<?xml version="1.0" encoding="utf-8"?>
<D:propfind xmlns:D="DAV:">
  <D:prop>
    <D:quota-available-bytes/>
    <D:quota-used-bytes/>
  </D:prop>
</D:propfind>`
)

// quotaRoot returns the WebDAV path that should be probed for RFC 4331
// quota properties. When the account is scoped to a RootPrefix subdirectory,
// the probe must target that subdirectory rather than the endpoint root, so
// the server evaluates quota for the mounted tree instead of the virtual root.
func (b webDAVBackend) quotaRoot() string {
	root := strings.TrimSpace(b.cfg.RootPrefix)
	if root == "" {
		return ""
	}
	return cleanRemotePath(root)
}

func (b webDAVBackend) quota(ctx context.Context) (available int64, used int64, ok bool, err error) {
	if ctx == nil {
		ctx = context.Background()
	}
	ctx, cancel := context.WithTimeout(ctx, webDAVQuotaTimeout)
	defer cancel()
	req, err := b.request(ctx, "PROPFIND", b.quotaRoot(), strings.NewReader(webDAVQuotaBody))
	if err != nil {
		return 0, 0, false, err
	}
	req.Header.Set("Depth", "0")
	req.Header.Set("Content-Type", `application/xml; charset="utf-8"`)
	resp, err := b.client.Do(req)
	if err != nil {
		return 0, 0, false, err
	}
	defer resp.Body.Close()
	if resp.StatusCode >= 300 {
		return 0, 0, false, fmt.Errorf("webdav quota propfind: %s", resp.Status)
	}
	var multi webDAVMultistatus
	if err := xml.NewDecoder(resp.Body).Decode(&multi); err != nil {
		return 0, 0, false, err
	}

	// RFC 4331 allows the server to return quota-used-bytes and
	// quota-available-bytes in separate <propstat> elements, each with its own
	// 200/404 status. Accept whichever properties are present with 200 OK.
	var availableOK, usedOK bool
	for _, response := range multi.Responses {
		for _, propstat := range response.Propstat {
			if !strings.Contains(propstat.Status, " 200 ") {
				continue
			}
			if value := strings.TrimSpace(propstat.Prop.QuotaAvailableBytes); value != "" {
				available, availableOK = parseNonNegativeBytes(value)
			}
			if value := strings.TrimSpace(propstat.Prop.QuotaUsedBytes); value != "" {
				used, usedOK = parseNonNegativeBytes(value)
			}
		}
	}

	// Neither property was returned. Per RFC 4331 this means the server does not
	// expose quota information — return ok=false so the caller can skip capacity
	// display silently, rather than surfacing a hard error.
	if !availableOK && !usedOK {
		return 0, 0, false, nil
	}

	// If only one of the two is available, infer the other from the single value:
	//   - used known, available unknown  → treat as "unlimited free" (available = max)
	//   - available known, used unknown  → treat used as 0 (server reports free only)
	if !usedOK {
		used = 0
	}
	if !availableOK {
		available = maxQuotaBytes - used
	}

	if available < 0 {
		available = 0
	}
	return available, used, true, nil
}

func parseNonNegativeBytes(value string) (int64, bool) {
	parsed, err := strconv.ParseInt(strings.TrimSpace(value), 10, 64)
	return parsed, err == nil && parsed >= 0
}
