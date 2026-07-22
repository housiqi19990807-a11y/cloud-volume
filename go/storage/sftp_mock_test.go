// SFTP mock test server using golang.org/x/crypto/ssh + pkg/sftp request server.
// Provides an in-process real SSH/SFTP server for backend tests.
package storage

import (
	"bytes"
	"crypto/rand"
	"crypto/rsa"
	"crypto/x509"
	"encoding/pem"
	"errors"
	"io"
	"net"
	"os"
	"path"
	"sync"
	"testing"
	"time"

	"github.com/pkg/sftp"
	"golang.org/x/crypto/ssh"
)

// mockSFTPServer runs a real SSH server with SFTP subsystem on a random port.
// It uses a shared in-memory virtual filesystem so files persist across
// connections, which is essential because the SFTP backend opens a new
// connection per operation.
type mockSFTPServer struct {
	listener net.Listener
	config   *ssh.ServerConfig
	stopCh   chan struct{}
	root     *sharedSFTPRoot
}

// newMockSFTPServer starts a real SSH/SFTP server. Credentials are checked
// via password auth. The server runs on 127.0.0.1:0.
func newMockSFTPServer(t *testing.T, username, password string) *mockSFTPServer {
	t.Helper()
	config := &ssh.ServerConfig{
		PasswordCallback: func(c ssh.ConnMetadata, pass []byte) (*ssh.Permissions, error) {
			if c.User() == username && string(pass) == password {
				return nil, nil
			}
			return nil, errSFTPAuth
		},
	}
	hostKey := generateTestHostKey(t)
	config.AddHostKey(hostKey)
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatalf("listen for mock SFTP: %v", err)
	}
	srv := &mockSFTPServer{
		listener: listener,
		config:   config,
		stopCh:   make(chan struct{}),
		root:     newSharedSFTPRoot(),
	}
	go srv.serve()
	return srv
}

// errSFTPAuth is a sentinel auth error for the mock SFTP server.
var errSFTPAuth = &mockSFTPAuthError{}

type mockSFTPAuthError struct{}

func (e *mockSFTPAuthError) Error() string { return "mock sftp auth failed" }

// serve accepts connections and hands the SFTP subsystem to sftp.RequestServer.
func (s *mockSFTPServer) serve() {
	for {
		conn, err := s.listener.Accept()
		if err != nil {
			select {
			case <-s.stopCh:
				return
			default:
			}
			continue
		}
		go s.handleConn(conn)
	}
}

// handleConn processes one SSH connection.
func (s *mockSFTPServer) handleConn(conn net.Conn) {
	defer conn.Close()
	sshConn, chans, reqs, err := ssh.NewServerConn(conn, s.config)
	if err != nil {
		return
	}
	defer sshConn.Close()
	go ssh.DiscardRequests(reqs)
	for newChannel := range chans {
		if newChannel.ChannelType() != "session" {
			_ = newChannel.Reject(ssh.UnknownChannelType, "unknown channel")
			continue
		}
		channel, reqs, err := newChannel.Accept()
		if err != nil {
			continue
		}
		go s.handleSessionRequests(channel, reqs)
	}
}

// handleSessionRequests processes subsystem requests within an SSH session channel.
// Each SFTP session uses the server's shared in-memory root so files created
// by one connection are visible to subsequent connections.
func (s *mockSFTPServer) handleSessionRequests(channel ssh.Channel, in <-chan *ssh.Request) {
	defer channel.Close()
	for req := range in {
		if req.Type == "subsystem" && len(req.Payload) >= 4 && string(req.Payload[4:]) == "sftp" {
			_ = req.Reply(true, nil)
			handlers := sftp.Handlers{
				FileGet:  s.root,
				FilePut:  s.root,
				FileCmd:  s.root,
				FileList: s.root,
			}
			server := sftp.NewRequestServer(channel, handlers)
			_ = server.Serve()
			_ = server.Close()
			return
		}
		_ = req.Reply(false, nil)
	}
}

// Stop shuts down the mock SFTP server.
func (s *mockSFTPServer) Stop() {
	close(s.stopCh)
	_ = s.listener.Close()
}

// endpoint returns the host:port string for the SFTP client.
func (s *mockSFTPServer) endpoint() string {
	return s.listener.Addr().String()
}

// generateTestHostKey creates an RSA key for the SSH test server.
func generateTestHostKey(t *testing.T) ssh.Signer {
	t.Helper()
	key, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		t.Fatalf("generate RSA key: %v", err)
	}
	keyBytes := x509.MarshalPKCS1PrivateKey(key)
	keyPem := pem.EncodeToMemory(&pem.Block{Type: "RSA PRIVATE KEY", Bytes: keyBytes})
	signer, err := ssh.ParsePrivateKey(keyPem)
	if err != nil {
		t.Fatalf("parse RSA key: %v", err)
	}
	return signer
}

// sharedSFTPRoot is a thread-safe in-memory virtual filesystem for the mock
// SFTP server. It implements all four sftp handler interfaces so that files
// persist across separate SFTP connections (the backend opens one per op).
type sharedSFTPRoot struct {
	mu    sync.Mutex
	files map[string]*sharedSFTPFile
}

// sharedSFTPFile represents one file or directory in the mock FS.
type sharedSFTPFile struct {
	name    string
	content []byte
	modtime time.Time
	isdir   bool
}

// newSharedSFTPRoot creates a shared in-memory SFTP root with an empty root directory.
func newSharedSFTPRoot() *sharedSFTPRoot {
	return &sharedSFTPRoot{
		files: map[string]*sharedSFTPFile{
			"/": {name: "/", modtime: time.Now(), isdir: true},
		},
	}
}

// Fileread opens a file for reading.
func (r *sharedSFTPRoot) Fileread(rr *sftp.Request) (io.ReaderAt, error) {
	r.mu.Lock()
	defer r.mu.Unlock()
	file, ok := r.files[rr.Filepath]
	if !ok || file.isdir {
		return nil, os.ErrNotExist
	}
	return bytes.NewReader(file.content), nil
}

// Filewrite opens a file for writing.
func (r *sharedSFTPRoot) Filewrite(rr *sftp.Request) (io.WriterAt, error) {
	if !rr.Pflags().Write {
		return nil, os.ErrInvalid
	}
	r.mu.Lock()
	defer r.mu.Unlock()
	file, ok := r.files[rr.Filepath]
	if !ok {
		if !rr.Pflags().Creat {
			return nil, os.ErrNotExist
		}
		file = &sharedSFTPFile{name: rr.Filepath, modtime: time.Now()}
		r.files[rr.Filepath] = file
	}
	if file.isdir {
		return nil, os.ErrInvalid
	}
	if rr.Pflags().Trunc {
		file.content = nil
	}
	return &sharedSFTPWriter{file: file}, nil
}

// sharedSFTPWriter implements io.WriterAt, growing the file content as needed.
type sharedSFTPWriter struct {
	file *sharedSFTPFile
	mu   sync.Mutex
}

func (w *sharedSFTPWriter) WriteAt(p []byte, off int64) (int, error) {
	w.mu.Lock()
	defer w.mu.Unlock()
	end := off + int64(len(p))
	if end > int64(len(w.file.content)) {
		newContent := make([]byte, end)
		copy(newContent, w.file.content)
		w.file.content = newContent
	}
	copy(w.file.content[off:], p)
	w.file.modtime = time.Now()
	return len(p), nil
}

// Filecmd handles Mkdir, Rmdir, Remove, Rename, Setstat etc.
func (r *sharedSFTPRoot) Filecmd(rr *sftp.Request) error {
	r.mu.Lock()
	defer r.mu.Unlock()
	switch rr.Method {
	case "Mkdir":
		r.files[rr.Filepath] = &sharedSFTPFile{name: rr.Filepath, modtime: time.Now(), isdir: true}
	case "Remove":
		delete(r.files, rr.Filepath)
	case "Rmdir":
		for name := range r.files {
			if path.Dir(name) == rr.Filepath {
				return errors.New("directory not empty")
			}
		}
		delete(r.files, rr.Filepath)
	case "Rename":
		file, ok := r.files[rr.Filepath]
		if !ok {
			return os.ErrNotExist
		}
		delete(r.files, rr.Filepath)
		file.name = rr.Target
		r.files[rr.Target] = file
	case "Setstat":
		// No-op for the mock.
	}
	return nil
}

// Filelist handles List and Stat.
func (r *sharedSFTPRoot) Filelist(rr *sftp.Request) (sftp.ListerAt, error) {
	r.mu.Lock()
	defer r.mu.Unlock()
	switch rr.Method {
	case "List":
		dir, ok := r.files[rr.Filepath]
		if !ok || !dir.isdir {
			return nil, os.ErrNotExist
		}
		var entries []os.FileInfo
		for name, file := range r.files {
			if name == rr.Filepath {
				continue
			}
			if path.Dir(name) == dir.name {
				entries = append(entries, sharedSFTPFileInfo{name: path.Base(name), file: file})
			}
		}
		return listerAt(entries), nil
	case "Stat":
		file, ok := r.files[rr.Filepath]
		if !ok {
			return nil, os.ErrNotExist
		}
		return listerAt([]os.FileInfo{sharedSFTPFileInfo{name: path.Base(file.name), file: file}}), nil
	}
	return nil, errors.New("unsupported method")
}

// sharedSFTPFileInfo implements os.FileInfo for the mock files.
type sharedSFTPFileInfo struct {
	name string
	file *sharedSFTPFile
}

func (i sharedSFTPFileInfo) Name() string { return i.name }
func (i sharedSFTPFileInfo) Size() int64  { return int64(len(i.file.content)) }
func (i sharedSFTPFileInfo) Mode() os.FileMode {
	if i.file.isdir {
		return 0o755 | os.ModeDir
	}
	return 0o644
}
func (i sharedSFTPFileInfo) ModTime() time.Time { return i.file.modtime }
func (i sharedSFTPFileInfo) IsDir() bool        { return i.file.isdir }
func (i sharedSFTPFileInfo) Sys() any           { return nil }

// listerAt converts a slice of FileInfo to sftp.ListerAt.
type listerAt []os.FileInfo

func (l listerAt) ListAt(buf []os.FileInfo, offset int64) (int, error) {
	if offset >= int64(len(l)) {
		return 0, io.EOF
	}
	n := copy(buf, l[offset:])
	if offset+int64(n) >= int64(len(l)) {
		return n, io.EOF
	}
	return n, nil
}
