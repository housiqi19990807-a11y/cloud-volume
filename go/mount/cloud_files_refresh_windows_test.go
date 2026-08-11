//go:build windows && cgo

// Cloud Files refresh tests pin the metadata comparison used to avoid needless dehydration.
package mount

import (
	"testing"
	"time"
)

func TestCloudFilesPlaceholderMatchesRemoteMetadata(t *testing.T) {
	base := cloudPlaceholderInfo{
		RelativePath: "report.txt",
		FileSize:     64,
		FileID:       "docs/report.txt",
		ModTime:      time.Date(2026, 8, 7, 10, 0, 0, 0, time.UTC),
	}
	if !cloudFilesPlaceholderMatches(base, base) {
		t.Fatal("identical placeholder metadata should not refresh")
	}
	changed := base
	changed.ModTime = changed.ModTime.Add(time.Second)
	if cloudFilesPlaceholderMatches(base, changed) {
		t.Fatal("changed remote metadata should refresh the placeholder")
	}
	changed = base
	changed.FileID = "docs/report.txt\x1fnew-etag"
	if cloudFilesPlaceholderMatches(base, changed) {
		t.Fatal("changed ETag should refresh a same-size placeholder")
	}
}
