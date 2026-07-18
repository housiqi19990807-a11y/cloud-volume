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

func (b webDAVBackend) quota(ctx context.Context) (int64, int64, error) {
	if ctx == nil {
		ctx = context.Background()
	}
	ctx, cancel := context.WithTimeout(ctx, webDAVQuotaTimeout)
	defer cancel()
	req, err := b.request(ctx, "PROPFIND", "", strings.NewReader(webDAVQuotaBody))
	if err != nil {
		return 0, 0, err
	}
	req.Header.Set("Depth", "0")
	req.Header.Set("Content-Type", `application/xml; charset="utf-8"`)
	resp, err := b.client.Do(req)
	if err != nil {
		return 0, 0, err
	}
	defer resp.Body.Close()
	if resp.StatusCode >= 300 {
		return 0, 0, fmt.Errorf("webdav quota propfind: %s", resp.Status)
	}
	var multi webDAVMultistatus
	if err := xml.NewDecoder(resp.Body).Decode(&multi); err != nil {
		return 0, 0, err
	}
	var available, used int64
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
	if availableOK && usedOK && available <= maxQuotaBytes-used {
		return available + used, used, nil
	}
	return 0, 0, fmt.Errorf("webdav server did not return quota properties")
}

func parseNonNegativeBytes(value string) (int64, bool) {
	parsed, err := strconv.ParseInt(strings.TrimSpace(value), 10, 64)
	return parsed, err == nil && parsed >= 0
}
