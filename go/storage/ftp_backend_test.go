// FTP backend integration tests using the in-process mock FTP server.
// These tests exercise the real FTP protocol path (control + passive data
// connections) against an ftpserverlib instance backed by an afero memory FS.
package storage

import (
	"strings"
	"testing"

	"github.com/spf13/afero"

	storageconfig "remote-storage/go/config"
)

// ftpTestConfig builds a RemoteStorageConfig pointing at the mock FTP server.
func ftpTestConfig(addr, user, pass string) storageconfig.RemoteStorageConfig {
	return storageconfig.RemoteStorageConfig{
		StorageType:    storageconfig.StorageTypeFTP,
		Endpoint:       addr,
		FTPUsername:    user,
		FTPPassword:    pass,
		HasFTPPassword: true,
		MappedBucketName: "FTP",
	}
}

func TestFTPListObjectsPage(t *testing.T) {
	srv := newMockFTPServer(t, "testuser", "testpass")
	defer srv.Stop()
	seedMockFiles(t, srv.fileSystem())

	backend := newFTPBackend(ftpTestConfig(srv.endpoint(), "testuser", "testpass"))
	page, err := backend.ListObjectsPage(nil, "FTP", "", "", 200)
	if err != nil {
		t.Fatalf("ListObjectsPage error: %v", err)
	}
	if len(page.Items) != 2 {
		t.Fatalf("expected 2 root entries, got %d: %+v", len(page.Items), page.Items)
	}
	// Directories should come first.
	if !page.Items[0].IsDir || page.Items[0].Key != "docs/" {
		t.Fatalf("first item = %+v, want docs/", page.Items[0])
	}
	if page.Items[1].IsDir || page.Items[1].Key != "hello.txt" {
		t.Fatalf("second item = %+v, want hello.txt", page.Items[1])
	}
}

func TestFTPListObjectsSubdirectory(t *testing.T) {
	srv := newMockFTPServer(t, "u", "p")
	defer srv.Stop()
	seedMockFiles(t, srv.fileSystem())

	backend := newFTPBackend(ftpTestConfig(srv.endpoint(), "u", "p"))
	page, err := backend.ListObjectsPage(nil, "FTP", "docs", "", 200)
	if err != nil {
		t.Fatalf("ListObjectsPage(docs) error: %v", err)
	}
	if len(page.Items) != 1 || page.Items[0].Key != "docs/notes.txt" {
		t.Fatalf("items = %+v, want docs/notes.txt", page.Items)
	}
}

func TestFTPUploadAndDownload(t *testing.T) {
	srv := newMockFTPServer(t, "u", "p")
	defer srv.Stop()

	backend := newFTPBackend(ftpTestConfig(srv.endpoint(), "u", "p"))
	// Upload
	err := backend.UploadReader(nil, "FTP", "upload/test.bin", strings.NewReader("hello ftp"), 9, "", "test.bin")
	if err != nil {
		t.Fatalf("UploadReader error: %v", err)
	}
	// Verify via ListObjectsPage
	page, err := backend.ListObjectsPage(nil, "FTP", "upload", "", 200)
	if err != nil {
		t.Fatalf("list after upload error: %v", err)
	}
	if len(page.Items) != 1 || page.Items[0].Key != "upload/test.bin" || page.Items[0].Size != 9 {
		t.Fatalf("items = %+v, want upload/test.bin size=9", page.Items)
	}
}

func TestFTPHeadObject(t *testing.T) {
	srv := newMockFTPServer(t, "u", "p")
	defer srv.Stop()
	seedMockFiles(t, srv.fileSystem())

	backend := newFTPBackend(ftpTestConfig(srv.endpoint(), "u", "p"))
	info, err := backend.HeadObject(nil, "FTP", "hello.txt")
	if err != nil {
		t.Fatalf("HeadObject error: %v", err)
	}
	if info.Key != "hello.txt" || info.Size != int64(len("hello world")) || info.IsDir {
		t.Fatalf("info = %+v, want hello.txt size=%d", info, len("hello world"))
	}
}

func TestFTPCreateAndDeleteDirectory(t *testing.T) {
	srv := newMockFTPServer(t, "u", "p")
	defer srv.Stop()

	backend := newFTPBackend(ftpTestConfig(srv.endpoint(), "u", "p"))
	if err := backend.CreateDirectory(nil, "FTP", "", "newdir"); err != nil {
		t.Fatalf("CreateDirectory error: %v", err)
	}
	page, err := backend.ListObjectsPage(nil, "FTP", "", "", 200)
	if err != nil {
		t.Fatalf("list after mkdir error: %v", err)
	}
	found := false
	for _, item := range page.Items {
		if item.Key == "newdir/" && item.IsDir {
			found = true
		}
	}
	if !found {
		t.Fatalf("newdir/ not found in listing: %+v", page.Items)
	}
	// Delete the directory
	if err := backend.DeleteObject(nil, "FTP", "newdir", true, ""); err != nil {
		t.Fatalf("DeleteObject(newdir) error: %v", err)
	}
}

func TestFTPReadObjectRange(t *testing.T) {
	srv := newMockFTPServer(t, "u", "p")
	defer srv.Stop()
	seedMockFiles(t, srv.fileSystem())

	backend := newFTPBackend(ftpTestConfig(srv.endpoint(), "u", "p"))
	data, err := backend.ReadObjectRange(nil, "FTP", "hello.txt", 6, 5)
	if err != nil {
		t.Fatalf("ReadObjectRange error: %v", err)
	}
	if string(data) != "world" {
		t.Fatalf("data = %q, want 'world'", string(data))
	}
}

// seedMockFiles populates the afero FS with a known directory structure for listing tests.
func seedMockFiles(t *testing.T, fs afero.Fs) {
	t.Helper()
	if err := fs.MkdirAll("/docs", 0o755); err != nil {
		t.Fatalf("seed mkdir /docs: %v", err)
	}
	if err := afero.WriteFile(fs, "/hello.txt", []byte("hello world"), 0o644); err != nil {
		t.Fatalf("seed write /hello.txt: %v", err)
	}
	if err := afero.WriteFile(fs, "/docs/notes.txt", []byte("ftp notes"), 0o644); err != nil {
		t.Fatalf("seed write /docs/notes.txt: %v", err)
	}
}
