// WebDAV quota tests verify mounted clients receive RFC 4331 capacity values.
package mount

import (
	"context"
	"encoding/xml"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"
	"time"

	storageconfig "remote-storage/go/config"
	storageops "remote-storage/go/storage"

	"golang.org/x/net/webdav"
)

type mountQuotaTestBackend struct {
	total   int64
	used    int64
	started chan struct{}
	release chan struct{}
	once    sync.Once
}

func (b *mountQuotaTestBackend) BucketQuota(context.Context, string) (storageops.BucketInfo, error) {
	b.once.Do(func() { close(b.started) })
	<-b.release
	return storageops.BucketInfo{
		Name:       "test-bucket",
		QuotaBytes: b.total,
		UsedBytes:  b.used,
		QuotaKnown: true,
	}, nil
}

func TestWebDAVRootReportsProviderQuota(t *testing.T) {
	access := newTestBucketAccess(t)
	provider := mountQuotaTestBackend{
		total:   1000,
		used:    250,
		started: make(chan struct{}),
		release: make(chan struct{}),
	}
	access.quotaProvider = &provider

	startedAt := time.Now()
	available, used := requestMountedWebDAVQuota(t, access)
	if elapsed := time.Since(startedAt); elapsed > 500*time.Millisecond {
		t.Fatalf("initial quota PROPFIND blocked for %v", elapsed)
	}
	if available != "" || used != "" {
		t.Fatalf("quota before provider response = %s/%s, want unsupported", available, used)
	}
	<-provider.started
	close(provider.release)
	waitForMountedWebDAVQuota(t, access, "750", "250")
}

func TestWebDAVRootCustomQuotaOverridesProviderTotal(t *testing.T) {
	access := newTestBucketAccess(t)
	access.config = storageconfig.RemoteStorageConfig{
		BucketSettings: map[string]storageconfig.BucketSettings{
			"test-bucket": {CustomQuotaBytes: 800},
		},
	}
	provider := mountQuotaTestBackend{
		total:   1000,
		used:    250,
		started: make(chan struct{}),
		release: make(chan struct{}),
	}
	access.quotaProvider = &provider

	available, used := requestMountedWebDAVQuota(t, access)
	if available != "800" || used != "0" {
		t.Fatalf("initial custom quota available/used = %s/%s, want 800/0", available, used)
	}
	<-provider.started
	close(provider.release)
	waitForMountedWebDAVQuota(t, access, "550", "250")
}

func waitForMountedWebDAVQuota(t *testing.T, access *bucketAccess, wantAvailable, wantUsed string) {
	t.Helper()

	deadline := time.Now().Add(2 * time.Second)
	for time.Now().Before(deadline) {
		available, used := requestMountedWebDAVQuota(t, access)
		if available == wantAvailable && used == wantUsed {
			return
		}
		time.Sleep(10 * time.Millisecond)
	}
	available, used := requestMountedWebDAVQuota(t, access)
	t.Fatalf("quota available/used = %s/%s, want %s/%s", available, used, wantAvailable, wantUsed)
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
	return available, used
}
