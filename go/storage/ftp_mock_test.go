// FTP mock test server using ftpserverlib + afero in-memory filesystem.
// Provides an in-process real FTP server for backend tests.
package storage

import (
	"crypto/tls"
	"fmt"
	"os"
	"testing"
	"time"

	ftpserver "github.com/fclairamb/ftpserverlib"
	"github.com/spf13/afero"
)

// mockFTPServer wraps an ftpserverlib instance backed by an in-memory afero FS.
type mockFTPServer struct {
	server *ftpserver.FtpServer
	fs     afero.Fs
	addr   string
}

// newMockFTPServer starts a real FTP server on a random localhost port.
// The caller should call .Stop() when finished.
func newMockFTPServer(t *testing.T, username, password string) *mockFTPServer {
	t.Helper()
	fs := afero.NewMemMapFs()
	mainDriver := &mockFTPMainDriver{
		fs:       fs,
		username: username,
		password: password,
	}
	server := ftpserver.NewFtpServer(mainDriver)
	if err := server.Listen(); err != nil {
		t.Fatalf("start mock FTP server: %v", err)
	}
	go func() {
		_ = server.Serve()
	}()
	addr := server.Addr()
	return &mockFTPServer{
		server: server,
		fs:     fs,
		addr:   addr,
	}
}

// Stop shuts down the mock FTP server.
func (m *mockFTPServer) Stop() {
	_ = m.server.Stop()
}

// endpoint returns the host:port string for the FTP client.
func (m *mockFTPServer) endpoint() string {
	return m.addr
}

// fs returns the underlying afero FS for test seeding/assertions.
func (m *mockFTPServer) fileSystem() afero.Fs {
	return m.fs
}

// mockFTPMainDriver implements ftpserver.MainDriver using an in-memory afero FS.
type mockFTPMainDriver struct {
	fs       afero.Fs
	username string
	password string
}

func (d *mockFTPMainDriver) GetSettings() (*ftpserver.Settings, error) {
	return &ftpserver.Settings{
		ListenAddr: "127.0.0.1:0",
	}, nil
}

func (d *mockFTPMainDriver) ClientConnected(_ ftpserver.ClientContext) (string, error) {
	return "mock FTP ready", nil
}

func (d *mockFTPMainDriver) ClientDisconnected(_ ftpserver.ClientContext) {}

func (d *mockFTPMainDriver) AuthUser(_ ftpserver.ClientContext, user, pass string) (ftpserver.ClientDriver, error) {
	if user != d.username || pass != d.password {
		return nil, fmt.Errorf("authentication failed")
	}
	return &mockFTPClientDriver{fs: d.fs}, nil
}

func (d *mockFTPMainDriver) GetTLSConfig() (*tls.Config, error) {
	return nil, nil
}

// mockFTPClientDriver implements ftpserver.ClientDriver (afero.Fs) over the shared in-memory FS.
type mockFTPClientDriver struct {
	fs afero.Fs
}

// All afero.Fs methods delegate to the in-memory filesystem.
func (c *mockFTPClientDriver) Create(name string) (afero.File, error)         { return c.fs.Create(name) }
func (c *mockFTPClientDriver) Mkdir(name string, perm os.FileMode) error      { return c.fs.Mkdir(name, perm) }
func (c *mockFTPClientDriver) MkdirAll(path string, perm os.FileMode) error   { return c.fs.MkdirAll(path, perm) }
func (c *mockFTPClientDriver) Open(name string) (afero.File, error)           { return c.fs.Open(name) }
func (c *mockFTPClientDriver) OpenFile(name string, flag int, perm os.FileMode) (afero.File, error) {
	return c.fs.OpenFile(name, flag, perm)
}
func (c *mockFTPClientDriver) Remove(name string) error                       { return c.fs.Remove(name) }
func (c *mockFTPClientDriver) RemoveAll(path string) error                    { return c.fs.RemoveAll(path) }
func (c *mockFTPClientDriver) Rename(oldname, newname string) error           { return c.fs.Rename(oldname, newname) }
func (c *mockFTPClientDriver) Stat(name string) (os.FileInfo, error)          { return c.fs.Stat(name) }
func (c *mockFTPClientDriver) Name() string                                   { return "mockftp" }
func (c *mockFTPClientDriver) Chmod(name string, mode os.FileMode) error      { return c.fs.Chmod(name, mode) }
func (c *mockFTPClientDriver) Chown(name string, uid, gid int) error          { return c.fs.Chown(name, uid, gid) }
func (c *mockFTPClientDriver) Chtimes(name string, atime, mtime time.Time) error {
	return c.fs.Chtimes(name, atime, mtime)
}
