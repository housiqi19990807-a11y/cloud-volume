// WebDAV quota tests verify mounted clients receive RFC 4331 capacity values.
package mount

import (
	"context"
	"encoding/xml"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	storageconfig "remote-storage/go/config"
	storageops "remote-storage/go/storage"

	"golang.org/x/net/webdav"
)

type mountQuotaTestBackend struct {
	total int64
	used  int64
}

func (b mountQuotaTestBackend) BucketQuota(context.Context, string) (storageops.BucketInfo, error) {
	return storageops.BucketInfo{
		Name:       "test-bucket",
		QuotaBytes: b.total,
		UsedBytes:  b.used,
		QuotaKnown: true,
	}, nil
}

func TestWebDAVRootReportsProviderQuota(t *testing.T) {
	access := newTestBucketAccess(t)
	access.quotaProvider = mountQuotaTestBackend{total: 1000, used: 250}

	available, used := requestMountedWebDAVQuota(t, access)
	if available != "750" || used != "250" {
		t.Fatalf("quota available/used = %s/%s, want 750/250", available, used)
	}
}

func TestWebDAVRootCustomQuotaOverridesProviderTotal(t *testing.T) {
	access := newTestBucketAccess(t)
	access.config = storageconfig.RemoteStorageConfig{
		BucketSettings: map[string]storageconfig.BucketSettings{
			"test-bucket": {CustomQuotaBytes: 800},
		},
	}
	access.quotaProvider = mountQuotaTestBackend{total: 1000, used: 250}

	available, used := requestMountedWebDAVQuota(t, access)
	if available != "550" || used != "250" {
		t.Fatalf("custom quota available/used = %s/%s, want 550/250", available, used)
	}
}

func requestMountedWebDAVQuota(t *testing.T, access *bucketAccess) (string, string) {
	t.Helper()

	handler := &webdav.Handler{
		Prefix:     "/volume",
		FileSystem: &webDAVFS{access: access},
		LockSystem: webdav.NewMemLS(),
	}
	body := `<D:propfind xmlns:D="DAV:"><D:prop><D:quota-available-bytes/><D:quota-used-bytes/></D:prop></D:propfind>`
	request := httptest.NewRequest("PROPFIND", "/volume/", strings.NewReader(body))
	request.Header.Set("Depth", "0")
	response := httptest.NewRecorder()
	handler.ServeHTTP(response, request)
	if response.Code != http.StatusMultiStatus {
		t.Fatalf("PROPFIND status = %d body=%s", response.Code, response.Body.String())
	}
	return quotaValuesFromResponse(t, response.Body)
}

func quotaValuesFromResponse(t *testing.T, body io.Reader) (string, string) {
	t.Helper()

	var available, used string
	decoder := xml.NewDecoder(body)
	for {
		token, err := decoder.Token()
		if err == io.EOF {
			break
		}
		if err != nil {
			t.Fatalf("decode PROPFIND response: %v", err)
		}
		start, ok := token.(xml.StartElement)
		if !ok || start.Name.Space != "DAV:" {
			continue
		}
		switch start.Name.Local {
		case "quota-available-bytes":
			if err := decoder.DecodeElement(&available, &start); err != nil {
				t.Fatal(err)
			}
		case "quota-used-bytes":
			if err := decoder.DecodeElement(&used, &start); err != nil {
				t.Fatal(err)
			}
		}
	}
	if available == "" || used == "" {
		t.Fatalf("quota properties missing: available=%q used=%q", available, used)
	}
	return available, used
}
