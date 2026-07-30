// WebDAV upload tracking tests pin mount-writeback task completion.
package storage

import (
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"

	s3ops "remote-storage/go/s3"
)

func TestWebDAVUploadFileFinishesQueuedTransfer(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.Method {
		case "PROPFIND":
			writeWebDAVAccessResponse(w, `<D:privilege><D:write/></D:privilege>`)
		case http.MethodPut:
			data, err := io.ReadAll(r.Body)
			if err != nil {
				t.Fatalf("read PUT body: %v", err)
			}
			if string(data) != "tracked upload" {
				t.Fatalf("PUT body = %q", data)
			}
			w.WriteHeader(http.StatusCreated)
		default:
			t.Fatalf("method = %q, want PROPFIND or PUT", r.Method)
		}
	}))
	defer server.Close()

	localPath := filepath.Join(t.TempDir(), "tracked.txt")
	if err := os.WriteFile(localPath, []byte("tracked upload"), 0o644); err != nil {
		t.Fatalf("write upload source: %v", err)
	}
	taskID := "webdav-upload-file-finishes-queued-transfer"
	s3ops.QueueTransfer(taskID, "upload", "WebDAV", "tracked.txt", localPath, 14)
	t.Cleanup(func() { s3ops.ForgetTransfer(taskID) })

	backend := newTestWebDAVBackend(server.URL)
	if err := backend.UploadFile(nil, "WebDAV", "tracked.txt", localPath, taskID); err != nil {
		t.Fatalf("UploadFile error: %v", err)
	}
	assertCompletedUploadSnapshot(t, taskID, 14)
}
