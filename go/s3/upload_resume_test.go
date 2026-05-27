// Upload resume tests pin multipart continuation for mount writeback retries.
package s3

import (
	"context"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strconv"
	"sync"
	"testing"

	storageconfig "remote-storage/go/config"
)

func TestUploadFileContextResumableSkipsCompletedPartsOnRetry(t *testing.T) {
	t.Parallel()

	const (
		bucket = "bucket"
		key    = "object.bin"
	)
	var (
		mu             sync.Mutex
		createCalls    int
		completeCalls  int
		abortCalls     int
		partUploadHits = map[int]int{}
	)
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/"+bucket+"/"+key {
			http.NotFound(w, r)
			return
		}
		query := r.URL.Query()
		switch {
		case r.Method == http.MethodPost && query.Has("uploads"):
			mu.Lock()
			createCalls++
			mu.Unlock()
			w.Header().Set("Content-Type", "application/xml")
			_, _ = w.Write([]byte(
				`<InitiateMultipartUploadResult><UploadId>upload-1</UploadId></InitiateMultipartUploadResult>`,
			))
		case r.Method == http.MethodPut && query.Get("uploadId") == "upload-1":
			partNumber, err := strconv.Atoi(query.Get("partNumber"))
			if err != nil {
				http.Error(w, "missing part number", http.StatusBadRequest)
				return
			}
			mu.Lock()
			partUploadHits[partNumber]++
			attempt := partUploadHits[partNumber]
			mu.Unlock()
			if partNumber == 2 && attempt <= 3 {
				http.Error(w, "retry this part", http.StatusInternalServerError)
				return
			}
			w.Header().Set("ETag", fmt.Sprintf(`"etag-%d"`, partNumber))
			w.WriteHeader(http.StatusOK)
		case r.Method == http.MethodPost && query.Get("uploadId") == "upload-1":
			mu.Lock()
			completeCalls++
			mu.Unlock()
			w.Header().Set("Content-Type", "application/xml")
			_, _ = w.Write([]byte(
				`<CompleteMultipartUploadResult><Location>ok</Location></CompleteMultipartUploadResult>`,
			))
		case r.Method == http.MethodDelete && query.Get("uploadId") == "upload-1":
			mu.Lock()
			abortCalls++
			mu.Unlock()
			w.WriteHeader(http.StatusNoContent)
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
	localPath := filepath.Join(t.TempDir(), "object.bin")
	payload := make([]byte, multipartUploadThreshold+2<<20)
	for index := range payload {
		payload[index] = byte(index % 251)
	}
	if err := os.WriteFile(localPath, payload, 0o644); err != nil {
		t.Fatalf("seed local file: %v", err)
	}

	err := UploadFileContextResumable(
		context.Background(),
		cfg,
		bucket,
		key,
		localPath,
		"",
	)
	if err == nil {
		t.Fatal("expected first multipart attempt to fail")
	}
	if _, statErr := os.Stat(uploadStatePath(localPath)); statErr != nil {
		t.Fatalf("expected resumable state after failed attempt, got %v", statErr)
	}

	if err := UploadFileContextResumable(
		context.Background(),
		cfg,
		bucket,
		key,
		localPath,
		"",
	); err != nil {
		t.Fatalf("UploadFileContextResumable retry: %v", err)
	}

	if _, statErr := os.Stat(uploadStatePath(localPath)); !os.IsNotExist(statErr) {
		t.Fatalf("expected resumable state removal after success, got %v", statErr)
	}
	mu.Lock()
	defer mu.Unlock()
	if createCalls != 1 {
		t.Fatalf("expected one multipart create call, got %d", createCalls)
	}
	if partUploadHits[1] < 1 {
		t.Fatalf("expected part 1 upload at least once, got %d", partUploadHits[1])
	}
	if partUploadHits[2] < 2 {
		t.Fatalf("expected part 2 retries across attempts, got %d", partUploadHits[2])
	}
	if completeCalls != 1 {
		t.Fatalf("expected one multipart completion, got %d", completeCalls)
	}
	if abortCalls != 0 {
		t.Fatalf("expected no multipart abort, got %d", abortCalls)
	}
}
