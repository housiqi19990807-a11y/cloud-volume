// WebDAV server lifecycle is kept separate from mount command execution.
package mount

import (
	"context"
	"fmt"
	"net"
	"net/http"
	"net/url"
	"strings"
	"time"

	"golang.org/x/net/webdav"
)

type webDAVServer struct {
	server   *http.Server
	listener net.Listener
}

func startWebDAVServer(
	access *bucketAccess,
	volumeName string,
) (*webDAVServer, string, int, error) {
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
	scope := "/" + strings.Trim(volumeName, "/")
	server := &http.Server{
		Handler:           webDAVLoggingHandler{next: newScopedWebDAVHandler(scope, handler)},
		ReadHeaderTimeout: 5 * time.Second,
	}
	instance := &webDAVServer{
		server:   server,
		listener: listener,
	}
	go func() {
		_ = server.Serve(listener)
	}()
	return instance, scopedServerURL(address.Port, scope), address.Port, nil
}

func (s *webDAVServer) stop() error {
	if s == nil || s.server == nil {
		return nil
	}
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	return s.server.Shutdown(ctx)
}

type scopedWebDAVHandler struct {
	scope string
	next  http.Handler
}

func newScopedWebDAVHandler(scope string, next http.Handler) http.Handler {
	return scopedWebDAVHandler{
		scope: strings.TrimRight(scope, "/"),
		next:  next,
	}
}

func (h scopedWebDAVHandler) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	if !strings.HasPrefix(r.URL.Path, h.scope) {
		http.NotFound(w, r)
		return
	}
	cloned := r.Clone(r.Context())
	cloned.URL = cloneURL(r.URL)
	cloned.URL.Path = trimScopedPath(r.URL.Path, h.scope)
	cloned.URL.RawPath = ""
	h.next.ServeHTTP(w, cloned)
}

func scopedServerURL(port int, scope string) string {
	return (&url.URL{
		Scheme: "http",
		Host:   fmt.Sprintf("127.0.0.1:%d", port),
		Path:   ensureDirSuffix(strings.Trim(scope, "/")),
	}).String()
}

func cloneURL(value *url.URL) *url.URL {
	if value == nil {
		return &url.URL{}
	}
	cloned := *value
	return &cloned
}

func trimScopedPath(pathValue, scope string) string {
	trimmed := strings.TrimPrefix(pathValue, scope)
	if trimmed == "" {
		return "/"
	}
	if !strings.HasPrefix(trimmed, "/") {
		return "/" + trimmed
	}
	return trimmed
}
