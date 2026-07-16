//go:build windows

// WinFsp backend tests cover pure helpers (suffix matching, drive detection)
// without needing the WinFsp driver installed. cgo/winfs-tagged backend
// behaviour is validated manually through the app on an installed host.
package mount

import "testing"

func TestHasWinFspMountSuffix(t *testing.T) {
	t.Parallel()

	cases := []struct {
		name string
		in   string
		want bool
	}{
		{name: "empty", in: "", want: false},
		{name: "plain bucket", in: "media", want: false},
		{name: "winfsp mount", in: "media-winfsp", want: true},
		{name: "prefix only", in: "-winfsp", want: false},
		{name: "nested name", in: "deep-bucket-winfsp", want: true},
	}

	for _, tc := range cases {
		tc := tc
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			if got := hasWinFspMountSuffix(tc.in); got != tc.want {
				t.Fatalf("hasWinFspMountSuffix(%q) = %v, want %v", tc.in, got, tc.want)
			}
		})
	}
}

func TestIsWindowsDriveMount(t *testing.T) {
	t.Parallel()

	cases := []struct {
		name string
		in   string
		want bool
	}{
		{name: "empty", in: "", want: false},
		{name: "path", in: `C:\Cloud Volume`, want: false},
		{name: "drive letter", in: "Z:", want: true},
		{name: "lowercase drive", in: "z:", want: true},
		{name: "drive with backslash", in: `Z:\`, want: false},
	}

	for _, tc := range cases {
		tc := tc
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			if got := isWindowsDriveMount(tc.in); got != tc.want {
				t.Fatalf("isWindowsDriveMount(%q) = %v, want %v", tc.in, got, tc.want)
			}
		})
	}
}

