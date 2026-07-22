// Path normalization helpers for FGW routes.
package jwanfs

import "strings"

// normalizeFGWPath trims a trailing "/" and returns "/" for empty paths so the
// gateway always receives a non-empty path header.
func normalizeFGWPath(path string) string {
	path = strings.TrimSuffix(path, "/")
	if path == "" {
		return "/"
	}
	return path
}

