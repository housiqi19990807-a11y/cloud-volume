//go:build windows

package mount

import (
	"strings"
	"testing"
)

func TestWindowsCloudFilesMountDirNameUsesFreshSuffix(t *testing.T) {
	first := windowsCloudFilesMountDirName("demo/bucket")
	second := windowsCloudFilesMountDirName("demo/bucket")

	if first == second {
		t.Fatalf("expected unique sync-root names, got %q", first)
	}
	if !strings.HasPrefix(first, "demo_bucket-") {
		t.Fatalf("expected sanitized bucket prefix, got %q", first)
	}
}
