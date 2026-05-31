// Upload resume tests pin multipart continuation for mount writeback retries.
package s3

import (
	"context"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strconv"
	"sync"
	"testing"
	"time"

	storageconfig "remote-storage/go/config"
)

func TestUploadFileContextResumableSkipsCompletedPartsOnRetry(t *testing.T) {
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
			// Drain the request body so Linux TCP stacks do not reset the
			// connection while the client is still streaming the multipart part.
			_, _ = io.Copy(io.Discard, r.Body)
			mu.Lock()
			partUploadHits[partNumber]++
			mu.Unlock()
			w.Header().Set("ETag", fmt.Sprintf(`"etag-%d"`, partNumber))
			w.WriteHeader(http.StatusOK)
		case r.Method == http.MethodPost && query.Get("uploadId") == "upload-1":
			_, _ = io.Copy(io.Discard, r.Body)
			mu.Lock()
			completeCalls++
			attempt := completeCalls
			mu.Unlock()
			if attempt == 1 {
				w.Header().Set("Content-Type", "application/xml")
				_, _ = w.Write([]byte(`<CompleteMultipartUploadResult>`))
				return
			}
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

	mu.Lock()
	partHitsAfterFirstAttempt := map[int]int{}
	for partNumber, hits := range partUploadHits {
		partHitsAfterFirstAttempt[partNumber] = hits
	}
	mu.Unlock()

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
	if partUploadHits[1] < 1 || partUploadHits[2] < 1 {
		t.Fatalf("expected both parts uploaded during first attempt, got part1=%d part2=%d", partUploadHits[1], partUploadHits[2])
	}
	if partUploadHits[1] != partHitsAfterFirstAttempt[1] || partUploadHits[2] != partHitsAfterFirstAttempt[2] {
		t.Fatalf(
			"expected completed parts to be skipped on retry, got first-attempt hits part1=%d part2=%d and final hits part1=%d part2=%d",
			partHitsAfterFirstAttempt[1],
			partHitsAfterFirstAttempt[2],
			partUploadHits[1],
			partUploadHits[2],
		)
	}
	if completeCalls != 2 {
		t.Fatalf("expected one failed completion and one successful completion, got %d", completeCalls)
	}
	if abortCalls != 0 {
		t.Fatalf("expected no multipart abort, got %d", abortCalls)
	}
}

func TestUploadTimeoutForBytesUsesRateFloorAndGrace(t *testing.T) {
	t.Parallel()

	if got, want := uploadTimeoutForBytes(0), partUploadMinTimeout; got != want {
		t.Fatalf("zero-size timeout = %v, want %v", got, want)
	}

	oneMiB := int64(1 << 20)
	if got, want := uploadTimeoutForBytes(oneMiB), partUploadMinTimeout; got != want {
		t.Fatalf("1MiB timeout = %v, want %v", got, want)
	}

	fourGiB := int64(4 << 30)
	want := time.Duration(fourGiB/minUploadRateBytesPerSec)*time.Second + partUploadGracePeriod
	if got := uploadTimeoutForBytes(fourGiB); got != want {
		t.Fatalf("4GiB timeout = %v, want %v", got, want)
	}
}
