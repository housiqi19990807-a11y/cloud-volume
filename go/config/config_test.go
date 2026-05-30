// Config tests pin trash-directory normalization and reserved alias behavior.
package config

import "testing"

func TestTrashDirectoryAliases(t *testing.T) {
	t.Parallel()

	cases := []struct {
		name  string
		input string
		want  []string
	}{
		{name: "empty defaults to lowercase plus Finder alias", input: "", want: []string{".trash", ".Trash"}},
		{name: "lowercase keeps Finder alias", input: ".trash", want: []string{".trash", ".Trash"}},
		{name: "uppercase keeps app alias", input: ".Trash", want: []string{".Trash", ".trash"}},
		{name: "custom name stays single", input: ".recycle", want: []string{".recycle"}},
	}

	for _, tc := range cases {
		tc := tc
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			got := TrashDirectoryAliases(tc.input)
			if len(got) != len(tc.want) {
				t.Fatalf("len = %d, want %d (%v)", len(got), len(tc.want), got)
			}
			for index := range tc.want {
				if got[index] != tc.want[index] {
					t.Fatalf("aliases[%d] = %q, want %q (%v)", index, got[index], tc.want[index], got)
				}
			}
		})
	}
}

func TestNormalizeWindowsMountMode(t *testing.T) {
	t.Parallel()

	cases := []struct {
		name  string
		input string
		want  string
	}{
		{
			name:  "empty defaults to cached cloud files",
			input: "",
			want:  WindowsMountModeCloudFilesCached,
		},
		{
			name:  "direct cloud files stays enabled",
			input: WindowsMountModeCloudFilesDirect,
			want:  WindowsMountModeCloudFilesDirect,
		},
		{
			name:  "webdav stays enabled",
			input: WindowsMountModeWebDAV,
			want:  WindowsMountModeWebDAV,
		},
		{
			name:  "unknown falls back to cached cloud files",
			input: "unknown",
			want:  WindowsMountModeCloudFilesCached,
		},
	}

	for _, tc := range cases {
		tc := tc
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			if got := normalizeWindowsMountMode(tc.input); got != tc.want {
				t.Fatalf("normalizeWindowsMountMode(%q) = %q, want %q", tc.input, got, tc.want)
			}
		})
	}
}

func TestDefaultWindowsThisPcEntryEnabled(t *testing.T) {
	t.Parallel()

	if !DefaultConfig().WindowsThisPcEntryEnabled {
		t.Fatal("expected Windows This PC entry to be enabled by default")
	}
}
