// Sentinel errors and minimal net/error helpers, replacing the jtool/legacy
// error surface so the SDK has no external dependency.
package jwanfs

import (
	"context"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
)

// Sentinel errors.
var (
	ErrNoServer             = errors.New("no server")
	ErrNoAvailableUpstreams = errors.New("no available upstreams")
	ErrAccessDenied         = errors.New("InvalidAccessKeyId")
)

// ---- error wrapping (for fallback classification) -------------------------

// httpStatusError carries the HTTP status code from an FGW/raw HTTP failure.
type httpStatusError struct {
	status int
	body   string
}

func (e *httpStatusError) Error() string {
	return fmt.Sprintf("http status=%d body=%s", e.status, e.body)
}

func (e *httpStatusError) Unwrap() error { return nil }

// newHTTPStatusError wraps a non-2xx response into a httpStatusError.
func newHTTPStatusError(status int, body []byte) error {
	return &httpStatusError{status: status, body: string(body)}
}

// httpErrorStatus extracts an HTTP status code from an error chain, if any.
func httpErrorStatus(err error) int {
	var hse *httpStatusError
	if errors.As(err, &hse) {
		return hse.status
	}
	return 0
}

// ---- net error detection ---------------------------------------------------

// isNetError reports whether err is a transient network-layer failure.
// It checks net.Error, url.Error, and io.ErrUnexpectedEOF.
func isNetError(err error) bool {
	var netErr net.Error
	if errors.As(err, &netErr) {
		return true
	}
	// url.Error also satisfies net.Error via its Unwrap, but check explicitly
	// for robustness on older Go versions.
	type temporary interface{ Temporary() bool }
	var temp temporary
	if errors.As(err, &temp) {
		return true
	}
	if errors.Is(err, io.ErrUnexpectedEOF) {
		return true
	}
	return false
}

// errorsIs is an alias to context-check used by shouldFallback.
func errorsIs(err, target error) bool { return errors.Is(err, target) }

// statusError builds a plain error from a non-OK HTTP response body.
func statusError(resp *http.Response, body []byte) error {
	if resp.StatusCode == http.StatusForbidden {
		return ErrAccessDenied
	}
	return newHTTPStatusError(resp.StatusCode, body)
}

// ctxOrBackground returns ctx or context.Background() when ctx is nil.
func ctxOrBackground(ctx context.Context) context.Context {
	if ctx == nil {
		return context.Background()
	}
	return ctx
}

