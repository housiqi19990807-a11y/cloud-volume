// WebDAV request logging focuses on trash-related Finder operations and failures.
package mount

import (
	"log"
	"net/http"
	"path"
	"strings"
)

type webDAVLoggingHandler struct {
	next http.Handler
}

func (h webDAVLoggingHandler) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	recorder := &statusRecorder{ResponseWriter: w, status: http.StatusOK}
	h.next.ServeHTTP(recorder, r)
	if shouldLogWebDAVRequest(r, recorder.status) {
		log.Printf(
			"[mount/webdav] method=%s path=%q destination=%q depth=%q overwrite=%q status=%d",
			r.Method,
			r.URL.Path,
			r.Header.Get("Destination"),
			r.Header.Get("Depth"),
			r.Header.Get("Overwrite"),
			recorder.status,
		)
	}
}

type statusRecorder struct {
	http.ResponseWriter
	status int
}

func (r *statusRecorder) WriteHeader(statusCode int) {
	r.status = statusCode
	r.ResponseWriter.WriteHeader(statusCode)
}

func shouldLogWebDAVRequest(r *http.Request, status int) bool {
	if isExpectedProbeMiss(r, status) {
		return false
	}
	if status >= http.StatusBadRequest {
		return true
	}
	if isTrashLikePath(r.URL.Path) || isTrashLikePath(r.Header.Get("Destination")) {
		return true
	}
	switch r.Method {
	case http.MethodDelete, "MOVE":
		return true
	default:
		return false
	}
}

func isExpectedProbeMiss(r *http.Request, status int) bool {
	if r.Method != "PROPFIND" || status != http.StatusNotFound {
		return false
	}
	name := path.Base(strings.TrimSpace(r.URL.Path))
	if strings.HasPrefix(name, "._") {
		return true
	}
	switch name {
	case ".hidden",
		".metadata_direct_scope_only",
		".metadata_never_index",
		".metadata_never_index_unless_rootfs",
		".ql_disablecache",
		".ql_disablethumbnails",
		".Spotlight-V100":
		return true
	default:
		return false
	}
}

func isTrashLikePath(value string) bool {
	trimmed := strings.TrimSpace(value)
	if trimmed == "" {
		return false
	}
	return strings.Contains(trimmed, "/.Trash") ||
		strings.HasPrefix(trimmed, ".Trash") ||
		strings.Contains(trimmed, "/.Trashes") ||
		strings.HasPrefix(trimmed, ".Trashes")
}
