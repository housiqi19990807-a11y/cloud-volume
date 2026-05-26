// Resume download tests verify range-based continuation against an S3-compatible endpoint.
package s3

import (
	"context"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"sync"
	"testing"

	storageconfig "remote-storage/go/config"
)

func TestDownloadFileContextResumesFromPartialFile(t *testing.T) {
	t.Parallel()

	const body = "hello world"
	var (
		mu         sync.Mutex
		rangeValue string
	)
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/bucket/object.txt" {
			http.NotFound(w, r)
			return
		}
		switch r.Method {
		case http.MethodHead:
			w.Header().Set("Content-Length", fmt.Sprintf("%d", len(body)))
			w.Header().Set("Last-Modified", "Tue, 26 May 2026 22:00:00 GMT")
			w.WriteHeader(http.StatusOK)
		case http.MethodGet:
			mu.Lock()
			rangeValue = r.Header.Get("Range")
			mu.Unlock()
			if rangeValue == "bytes=5-" {
				w.Header().Set("Content-Length", "6")
				w.Header().Set("Content-Range", "bytes 5-10/11")
				w.WriteHeader(http.StatusPartialContent)
				_, _ = w.Write([]byte(body[5:]))
				return
			}
			w.Header().Set("Content-Length", fmt.Sprintf("%d", len(body)))
			w.WriteHeader(http.StatusOK)
			_, _ = w.Write([]byte(body))
		default:
			http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		}
	}))
	defer server.Close()

	cfg := storageconfig.RemoteStorageConfig{
		Endpoint:        server.URL,
		Region:          "us-east-1",
		AccessKeyID:     "test",
		SecretAccessKey: "test",
		UsePathStyle:    true,
	}
	localPath := filepath.Join(t.TempDir(), "object.txt")
	if err := os.WriteFile(localPath, []byte("hello"), 0o644); err != nil {
		t.Fatalf("seed partial file: %v", err)
	}

	if err := DownloadFileContext(context.Background(), cfg, "bucket", "object.txt", localPath, ""); err != nil {
		t.Fatalf("DownloadFileContext: %v", err)
	}

	data, err := os.ReadFile(localPath)
	if err != nil {
		t.Fatalf("ReadFile: %v", err)
	}
	if string(data) != body {
		t.Fatalf("unexpected downloaded content %q", string(data))
	}
	mu.Lock()
	defer mu.Unlock()
	if rangeValue != "bytes=5-" {
		t.Fatalf("expected ranged resume request, got %q", rangeValue)
	}
}
