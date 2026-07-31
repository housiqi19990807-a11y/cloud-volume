//go:build darwin

// macOS mount tests pin path recovery, Finder coalescing, and safe unmount lifecycle.
package mount

import (
	"errors"
	"io"
	"net"
	"net/http"
	"testing"
	"time"

	"path/filepath"
)

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

func TestMountOpenGateCoalescesBusyFinderOpen(t *testing.T) {
	t.Parallel()

	gate := newMountOpenGate()
	const mountPath = "/Volumes/云卷-demo"
	if !gate.tryStart(mountPath) {
		t.Fatal("first Finder open was not admitted")
	}
	if gate.tryStart(mountPath) {
		t.Fatal("duplicate Finder open was not coalesced")
	}
	gate.finish(mountPath)
	if !gate.tryStart(mountPath) {
		t.Fatal("Finder open remained stuck after command completion")
	}
}

func TestStopKeepsWebDAVAliveWhenUnmountFails(t *testing.T) {
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	server := &http.Server{Handler: http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		_, _ = io.WriteString(w, "alive")
	})}
	go func() { _ = server.Serve(listener) }()
	webDAV := &webDAVServer{server: server, listener: listener}
	t.Cleanup(func() { _ = webDAV.stop() })

	oldProbe := probeWebDAVMountActive
	oldUnmount := executeUnmountWebDAV
	probeWebDAVMountActive = func(string) (bool, error) { return true, nil }
	executeUnmountWebDAV = func(string) error { return errors.New("busy") }
	t.Cleanup(func() {
		probeWebDAVMountActive = oldProbe
		executeUnmountWebDAV = oldUnmount
	})

	session := &mountSession{
		bucket:      "test-bucket",
		mounted:     true,
		stopping:    true,
		mountTarget: "/Volumes/云卷-test",
		server:      webDAV,
	}
	if err := session.stop(); err == nil {
		t.Fatal("stop unexpectedly succeeded")
	}
	if !session.mounted || session.stopping || session.server == nil {
		t.Fatal("failed unmount discarded the live mount server")
	}
	response, err := http.Get("http://" + listener.Addr().String())
	if err != nil {
		t.Fatalf("WebDAV server stopped after failed unmount: %v", err)
	}
	_ = response.Body.Close()
}
func TestOpenMountPathReturnsBeforeFinderStatfs(t *testing.T) {
	t.Parallel()

	dir := t.TempDir()
	startedAt := time.Now()
	if err := openMountPath(dir); err != nil {
		t.Fatalf("openMountPath: %v", err)
	}
	if elapsed := time.Since(startedAt); elapsed > time.Second {
		t.Fatalf("openMountPath blocked for %v; should return immediately", elapsed)
	}
	// The gate must eventually release so a subsequent open is not coalesced.
	clean := filepath.Clean(dir)
	deadline := time.Now().Add(macosOpenLaunchTimeout + 2*time.Second)
	for time.Now().Before(deadline) {
		if macOSMountOpenGate.tryStart(clean) {
			macOSMountOpenGate.finish(clean)
			return
		}
		time.Sleep(50 * time.Millisecond)
	}
	t.Fatal("open gate was never released after Finder open dispatched")
}
