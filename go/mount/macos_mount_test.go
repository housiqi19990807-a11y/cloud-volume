//go:build darwin

// macOS mount tests pin unmount fallback order for busy WebDAV volumes.
package mount

import "testing"

func TestUnmountCommands(t *testing.T) {
	t.Parallel()

	commands := unmountCommands("/Volumes/云卷-demo")
	if len(commands) != 3 {
		t.Fatalf("expected 3 unmount commands, got %d", len(commands))
	}
	if commands[0].name != "/sbin/umount" {
		t.Fatalf("expected first unmount command to be /sbin/umount, got %q", commands[0].name)
	}
	if commands[1].name != "/usr/sbin/diskutil" || commands[1].args[0] != "unmount" {
		t.Fatalf("expected second command to be diskutil unmount, got %+v", commands[1])
	}
	if commands[2].name != "/usr/sbin/diskutil" || commands[2].args[1] != "force" {
		t.Fatalf("expected third command to be diskutil unmount force, got %+v", commands[2])
	}
}

func TestFindMountedWebDAVPathRecoversEncodedVolumeName(t *testing.T) {
	t.Parallel()

	got := findMountedWebDAVPath(
		"http://127.0.0.1:60250/%E4%BA%91%E5%8D%B7-%E6%B5%8B%E8%AF%95/",
		"",
		[]string{"/Volumes/云卷-测试"},
	)
	if got != "/Volumes/云卷-测试" {
		t.Fatalf("recovered path = %q", got)
	}
}

func TestFindMountedWebDAVPathRecoversRequestedPath(t *testing.T) {
	t.Parallel()

	got := findMountedWebDAVPath(
		"http://127.0.0.1:60250/volume/",
		"/tmp/cloud-volume",
		[]string{"/tmp/cloud-volume"},
	)
	if got != "/tmp/cloud-volume" {
		t.Fatalf("recovered requested path = %q", got)
	}
}
