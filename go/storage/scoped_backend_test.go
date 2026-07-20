// Scoped backend tests cover virtual path joining used by all providers.
package storage

import "testing"

func TestScopeKey(t *testing.T) {
	tests := []struct {
		root, key, want string
	}{
		{"archive/2026", "", "archive/2026/"},
		{"archive/2026", "photos/", "archive/2026/photos"},
		{"", "photos", "photos"},
	}
	for _, tt := range tests {
		if got := scopeKey(tt.root, tt.key); got != tt.want {
			t.Errorf("scopeKey(%q, %q) = %q, want %q", tt.root, tt.key, got, tt.want)
		}
	}
}

func TestUnscopedKey(t *testing.T) {
	b := scopedBackend{root: "archive/2026"}
	if got := b.unscopedKey("archive/2026/photos/a.txt"); got != "photos/a.txt" {
		t.Fatalf("unscoped key = %q", got)
	}
}
