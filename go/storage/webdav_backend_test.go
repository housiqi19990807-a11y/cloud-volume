// WebDAV backend tests keep HTTP request construction safe for bridge callers.
package storage

import (
	"fmt"
	"net/http"
	"net/http/httptest"
	"testing"

	storageconfig "remote-storage/go/config"
)

func TestWebDAVListObjectsPageAcceptsNilContext(t *testing.T) {
	var requested bool
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		requested = true
		if r.Method != "PROPFIND" {
			t.Fatalf("method = %q, want PROPFIND", r.Method)
		}
		if r.Header.Get("Depth") != "1" {
			t.Fatalf("Depth = %q, want 1", r.Header.Get("Depth"))
		}
		username, password, ok := r.BasicAuth()
		if !ok || username != "web-user" || password != "web-pass" {
			t.Fatalf("unexpected basic auth username=%q password=%q ok=%v", username, password, ok)
		}
		w.Header().Set("Content-Type", `application/xml; charset="utf-8"`)
		_, _ = fmt.Fprint(w, `<?xml version="1.0" encoding="utf-8"?>
<D:multistatus xmlns:D="DAV:">
  <D:response>
    <D:href>/dav/</D:href>
    <D:propstat><D:prop><D:resourcetype><D:collection/></D:resourcetype></D:prop></D:propstat>
  </D:response>
  <D:response>
    <D:href>/dav/photo.jpg</D:href>
    <D:propstat><D:prop><D:getcontentlength>42</D:getcontentlength></D:prop></D:propstat>
  </D:response>
</D:multistatus>`)
	}))
	defer server.Close()

	backend := NewWebDAVBackend(storageconfig.RemoteStorageConfig{
		StorageType:       storageconfig.StorageTypeWebDAV,
		Endpoint:          server.URL + "/dav/",
		WebDAVUsername:    "web-user",
		WebDAVPassword:    "web-pass",
		HasWebDAVPassword: true,
	})
	page, err := backend.ListObjectsPage(nil, "WebDAV", "", "", 200)
	if err != nil {
		t.Fatalf("ListObjectsPage returned error: %v", err)
	}
	if !requested {
		t.Fatal("expected WebDAV server to receive PROPFIND")
	}
	if len(page.Items) != 1 || page.Items[0].Key != "photo.jpg" {
		t.Fatalf("items = %#v, want one photo.jpg entry", page.Items)
	}
}

func TestWebDAVHeadObjectKeepsDepthZeroTarget(t *testing.T) {
	var requestedPath string
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		requestedPath = r.URL.Path
		if r.Method != "PROPFIND" {
			t.Fatalf("method = %q, want PROPFIND", r.Method)
		}
		if r.Header.Get("Depth") != "0" {
			t.Fatalf("Depth = %q, want 0", r.Header.Get("Depth"))
		}
		w.Header().Set("Content-Type", `application/xml; charset="utf-8"`)
		_, _ = fmt.Fprint(w, `<?xml version="1.0" encoding="utf-8"?>
<D:multistatus xmlns:D="DAV:">
  <D:response>
    <D:href>/dav/20134-image/photo.jpg</D:href>
    <D:propstat><D:prop><D:getcontentlength>42</D:getcontentlength></D:prop></D:propstat>
  </D:response>
</D:multistatus>`)
	}))
	defer server.Close()

	backend := NewWebDAVBackend(storageconfig.RemoteStorageConfig{
		StorageType:       storageconfig.StorageTypeWebDAV,
		Endpoint:          server.URL + "/dav/",
		WebDAVUsername:    "web-user",
		WebDAVPassword:    "web-pass",
		HasWebDAVPassword: true,
	})
	info, err := backend.HeadObject(nil, "WebDAV", "20134-image/photo.jpg")
	if err != nil {
		t.Fatalf("HeadObject returned error: %v", err)
	}
	if requestedPath != "/dav/20134-image/photo.jpg" {
		t.Fatalf("requested path = %q, want /dav/20134-image/photo.jpg", requestedPath)
	}
	if info.Key != "20134-image/photo.jpg" || info.Size != 42 || info.IsDir {
		t.Fatalf("info = %#v, want file object with size 42", info)
	}
}

func TestWebDAVListBucketsUsesMappedBucketName(t *testing.T) {
	backend := NewWebDAVBackend(storageconfig.RemoteStorageConfig{
		StorageType:       storageconfig.StorageTypeWebDAV,
		Endpoint:          "https://example.invalid/dav/",
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
}
