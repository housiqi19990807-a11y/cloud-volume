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

func (a *bucketAccess) webDAVQuota(_ context.Context) (total, used int64, known bool) {
	a.quotaMu.Lock()
	if time.Since(a.quotaCachedAt) < webDAVMountQuotaCacheTTL {
		total, used, known = a.quotaTotal, a.quotaUsed, a.quotaKnown
		a.quotaMu.Unlock()
		return total, used, known
	}

	total, used, known = a.quotaTotal, a.quotaUsed, a.quotaKnown
	if custom := a.config.BucketSettingsFor(a.bucket).CustomQuotaBytes; custom > 0 {
		total, known = custom, true
		used = clampMountQuotaUsed(total, used)
	}
	if a.quotaProvider == nil {
		a.quotaCachedAt = time.Now()
		a.quotaTotal, a.quotaUsed, a.quotaKnown = total, used, known
		a.quotaMu.Unlock()
		return total, used, known
	}
	if !a.quotaLoading {
		a.quotaLoading = true
		go a.refreshWebDAVQuota()
	}
	a.quotaMu.Unlock()
	return total, used, known
}

func (a *bucketAccess) seedWebDAVQuota(total, used int64, known bool) {
	a.seedWebDAVQuotaState(total, used, known, true)
}

// seedStaleWebDAVQuota makes the last known capacity available to the first
// PROPFIND while leaving it immediately eligible for an async refresh.
func (a *bucketAccess) seedStaleWebDAVQuota(total, used int64, known bool) {
	a.seedWebDAVQuotaState(total, used, known, false)
}

func (a *bucketAccess) seedWebDAVQuotaState(total, used int64, known, fresh bool) {
	if !known || total <= 0 {
		return
	}
	if custom := a.config.BucketSettingsFor(a.bucket).CustomQuotaBytes; custom > 0 {
		total = custom
	}
	a.quotaMu.Lock()
	if fresh {
		a.quotaCachedAt = time.Now()
	} else {
		a.quotaCachedAt = time.Time{}
	}
	a.quotaTotal = total
	a.quotaUsed = clampMountQuotaUsed(total, used)
	a.quotaKnown = true
	a.quotaMu.Unlock()
}

func (a *bucketAccess) refreshWebDAVQuota() {
	ctx := context.Background()
	cancel := func() {}
	if a.requestTimeout > 0 {
		ctx, cancel = context.WithTimeout(ctx, a.requestTimeout)
	}
	quota, err := a.quotaProvider.BucketQuota(ctx, a.bucket)
	cancel()

	a.quotaMu.Lock()
	defer a.quotaMu.Unlock()
	// Keep the last usable capacity through a transient refresh failure. A
	// failed provider probe must not turn an already mounted volume back into
	// 0/0 until the next successful refresh.
	total, used, known := a.quotaTotal, a.quotaUsed, a.quotaKnown
	if err == nil && quota.QuotaKnown && quota.QuotaBytes > 0 {
		total, used, known = quota.QuotaBytes, quota.UsedBytes, true
	}
	if custom := a.config.BucketSettingsFor(a.bucket).CustomQuotaBytes; custom > 0 {
		total, known = custom, true
	}
	used = clampMountQuotaUsed(total, used)
	a.quotaCachedAt = time.Now()
	a.quotaTotal, a.quotaUsed, a.quotaKnown = total, used, known
	a.quotaLoading = false
}

func clampMountQuotaUsed(total, used int64) int64 {
	if used < 0 {
		return 0
	}
	if used > total {
		return total
	}
	return used
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
