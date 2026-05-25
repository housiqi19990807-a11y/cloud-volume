// WebDAV server lifecycle is kept separate from mount command execution.
package mount

import (
	"context"
	"fmt"
	"net"
	"net/http"
	"time"

	"golang.org/x/net/webdav"
)

type webDAVServer struct {
	server   *http.Server
	listener net.Listener
}

func startWebDAVServer(access *bucketAccess) (*webDAVServer, string, int, error) {
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		return nil, "", 0, fmt.Errorf("listen local webdav server: %w", err)
	}
	address := listener.Addr().(*net.TCPAddr)
	fs := &webDAVFS{access: access}
	handler := &webdav.Handler{
		FileSystem: fs,
		LockSystem: webdav.NewMemLS(),
	}
	server := &http.Server{
		Handler:           webDAVLoggingHandler{next: handler},
		ReadHeaderTimeout: 5 * time.Second,
	}
	instance := &webDAVServer{
		server:   server,
		listener: listener,
	}
	go func() {
		_ = server.Serve(listener)
	}()
	return instance, fmt.Sprintf("http://127.0.0.1:%d/", address.Port), address.Port, nil
}

func (s *webDAVServer) stop() error {
	if s == nil || s.server == nil {
		return nil
	}
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	return s.server.Shutdown(ctx)
}
