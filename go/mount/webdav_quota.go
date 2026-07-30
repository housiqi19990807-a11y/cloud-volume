// WebDAV quota projection exposes configured/provider capacity to mounted clients.
package mount

import (
	"context"
	"encoding/xml"
	"net/http"
	"strconv"
	"time"

	"golang.org/x/net/webdav"
)

const webDAVMountQuotaCacheTTL = 30 * time.Second

var (
	webDAVQuotaAvailableName = xml.Name{Space: "DAV:", Local: "quota-available-bytes"}
	webDAVQuotaUsedName      = xml.Name{Space: "DAV:", Local: "quota-used-bytes"}
)

func (a *bucketAccess) webDAVQuota(ctx context.Context) (total, used int64, known bool) {
	a.quotaMu.Lock()
	defer a.quotaMu.Unlock()

	if time.Since(a.quotaCachedAt) < webDAVMountQuotaCacheTTL {
		return a.quotaTotal, a.quotaUsed, a.quotaKnown
	}
	if a.quotaProvider != nil {
		if ctx == nil {
			ctx = context.Background()
		}
		quotaCtx := ctx
		cancel := func() {}
		if a.requestTimeout > 0 {
			quotaCtx, cancel = context.WithTimeout(ctx, a.requestTimeout)
		}
		quota, err := a.quotaProvider.BucketQuota(quotaCtx, a.bucket)
		cancel()
		if err == nil && quota.QuotaKnown {
			total = quota.QuotaBytes
			used = quota.UsedBytes
		}
	}
	if custom := a.config.BucketSettingsFor(a.bucket).CustomQuotaBytes; custom > 0 {
		total = custom
	}
	if total > 0 {
		if used < 0 {
			used = 0
		}
		if used > total {
			used = total
		}
		known = true
	}
	a.quotaCachedAt = time.Now()
	a.quotaTotal = total
	a.quotaUsed = used
	a.quotaKnown = known
	return total, used, known
}

func (f *readableWebDAVFile) DeadProps() (map[xml.Name]webdav.Property, error) {
	props := map[xml.Name]webdav.Property{}
	if f.path != "" || !f.info.IsDir() {
		return props, nil
	}
	total, used, known := f.access.webDAVQuota(f.ctx)
	if !known {
		return props, nil
	}
	props[webDAVQuotaAvailableName] = webDAVByteProperty(webDAVQuotaAvailableName, total-used)
	props[webDAVQuotaUsedName] = webDAVByteProperty(webDAVQuotaUsedName, used)
	return props, nil
}

func (f *readableWebDAVFile) Patch(patches []webdav.Proppatch) ([]webdav.Propstat, error) {
	props := make([]webdav.Property, 0)
	for _, patch := range patches {
		props = append(props, patch.Props...)
	}
	return []webdav.Propstat{{Props: props, Status: http.StatusForbidden}}, nil
}

func webDAVByteProperty(name xml.Name, value int64) webdav.Property {
	return webdav.Property{
		XMLName:  name,
		InnerXML: []byte(strconv.FormatInt(value, 10)),
	}
}
