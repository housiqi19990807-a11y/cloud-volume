// WebDAV quota tests cover immediate bucket discovery and second-stage capacity lookup.
package storage

import (
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	storageconfig "remote-storage/go/config"
)

func TestWebDAVListBucketsUsesMappedBucketName(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != "PROPFIND" || r.Header.Get("Depth") != "0" {
			t.Fatalf("quota request method=%q depth=%q", r.Method, r.Header.Get("Depth"))
		}
		body, err := io.ReadAll(r.Body)
		if err != nil {
			t.Fatalf("read quota request: %v", err)
		}
		if !strings.Contains(string(body), "quota-available-bytes") ||
			!strings.Contains(string(body), "quota-used-bytes") {
			t.Fatalf("quota request body = %q", body)
		}
		w.Header().Set("Content-Type", `application/xml; charset="utf-8"`)
		_, _ = fmt.Fprint(w, `<?xml version="1.0" encoding="utf-8"?>
<D:multistatus xmlns:D="DAV:"><D:response><D:propstat>
<D:prop><D:quota-available-bytes>750</D:quota-available-bytes></D:prop>
<D:status>HTTP/1.1 200 OK</D:status>
</D:propstat><D:propstat>
<D:prop><D:quota-used-bytes>250</D:quota-used-bytes></D:prop>
<D:status>HTTP/1.1 200 OK</D:status>
</D:propstat></D:response></D:multistatus>`)
	}))
	defer server.Close()

	backend := NewWebDAVBackend(storageconfig.RemoteStorageConfig{
		StorageType:       storageconfig.StorageTypeWebDAV,
		Endpoint:          server.URL + "/dav/",
		DisplayName:       "Account Fallback",
		MappedBucketName:  "Second DAV",
		WebDAVUsername:    "web-user",
		WebDAVPassword:    "web-pass",
		HasWebDAVPassword: true,
	})
	buckets, err := backend.ListBuckets(nil)
	if err != nil {
		t.Fatalf("ListBuckets returned error: %v", err)
	}
	if len(buckets) != 1 || buckets[0].Name != "Second DAV" {
		t.Fatalf("buckets = %#v, want mapped bucket name", buckets)
	}
	if buckets[0].QuotaBytes != 0 || buckets[0].QuotaKnown {
		t.Fatalf("bucket quota = %#v, want initial unknown quota", buckets[0])
	}
	quota, err := backend.(BucketQuotaProvider).BucketQuota(nil, "Second DAV")
	if err != nil {
		t.Fatalf("BucketQuota returned error: %v", err)
	}
	if quota.QuotaBytes != 1000 || quota.UsedBytes != 250 || !quota.QuotaKnown {
		t.Fatalf("quota = %#v, want total=1000 used=250", quota)
	}
}

func TestWebDAVListBucketsKeepsBucketWhenQuotaUnsupported(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", `application/xml; charset="utf-8"`)
		_, _ = fmt.Fprint(w, `<?xml version="1.0" encoding="utf-8"?>
<D:multistatus xmlns:D="DAV:"><D:response><D:propstat>
<D:prop><D:quota-available-bytes/><D:quota-used-bytes/></D:prop>
<D:status>HTTP/1.1 404 Not Found</D:status>
</D:propstat></D:response></D:multistatus>`)
	}))
	defer server.Close()

	backend := NewWebDAVBackend(storageconfig.RemoteStorageConfig{
		StorageType:      storageconfig.StorageTypeWebDAV,
		Endpoint:         server.URL + "/dav/",
		MappedBucketName: "No Quota DAV",
	})
	buckets, err := backend.ListBuckets(nil)
	if err != nil {
		t.Fatalf("ListBuckets returned error: %v", err)
	}
	if len(buckets) != 1 || buckets[0].Name != "No Quota DAV" || buckets[0].QuotaBytes != 0 {
		t.Fatalf("buckets = %#v, want bucket without quota", buckets)
	}
	if _, err := backend.(BucketQuotaProvider).BucketQuota(nil, "No Quota DAV"); err == nil {
		t.Fatal("BucketQuota returned nil error for unsupported quota")
	}
}
