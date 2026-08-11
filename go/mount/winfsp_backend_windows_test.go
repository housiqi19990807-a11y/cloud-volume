//go:build windows

// WinFsp backend tests cover pure helpers (suffix matching, drive detection)
// without needing the WinFsp driver installed. cgo/winfs-tagged backend
// behaviour is validated manually through the app on an installed host.
package mount

import (
	"testing"

	storageconfig "remote-storage/go/config"
)

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

func TestValidateWinFspDriveLetter(t *testing.T) {
	t.Parallel()

	cases := []struct {
		name    string
		drive   string
		wantErr bool
	}{
		{name: "available drive", drive: "Z:"},
		{name: "empty drive", drive: "", wantErr: true},
		{name: "directory path", drive: `C:\Cloud Volume`, wantErr: true},
		{name: "drive root path", drive: `Z:\`, wantErr: true},
	}

	for _, tc := range cases {
		tc := tc
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			if err := validateWinFspDriveLetter(tc.drive); (err != nil) != tc.wantErr {
				t.Fatalf("validateWinFspDriveLetter(%q) error = %v, wantErr %v", tc.drive, err, tc.wantErr)
			}
		})
	}
}

func TestWinFspVolumeLabelUsesBucketOverride(t *testing.T) {
	t.Parallel()

	cfg := storageconfig.RemoteStorageConfig{
		BucketSettings: map[string]storageconfig.BucketSettings{
			"archive": {WinFspVolumeLabel: "  Archive Drive  "},
		},
	}
	if got := winFspVolumeLabel(cfg, "archive"); got != "Archive Drive" {
		t.Fatalf("custom volume label = %q, want Archive Drive", got)
	}
	if got := winFspVolumeLabel(cfg, "photos"); got != "Cloud Volume photos" {
		t.Fatalf("fallback volume label = %q, want Cloud Volume photos", got)
	}
}
