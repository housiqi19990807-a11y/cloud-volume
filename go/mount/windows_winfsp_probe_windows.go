//go:build windows

// WinFsp presence probe shared by the mount backend selector and the Flutter
// settings UI. It mirrors cgofuse's own DLL discovery (winfsp-x64.dll /
// winfsp-a64.dll, then the HKLM\Software\WinFsp InstallDir fallback) so the
// answer matches what an actual WinFsp mount would see at runtime.
package mount

import (
	"path/filepath"
	"runtime"
	"strings"
	"syscall"
	"unsafe"
)

// WindowsWinFspAvailable reports whether the WinFsp driver DLL that cgofuse
// loads can be found on this machine. It is safe to call from any goroutine
// and never panics: a missing WinFsp install simply reports false.
func WindowsWinFspAvailable() bool {
	dllName := winFspDllName(runtime.GOARCH)
	if dllName == "" {
		return false
	}
	if dll, err := syscall.LoadDLL(dllName); err == nil {
		_ = dll.Release()
		return true
	}
	installDir, ok := winFspInstallDir()
	if !ok {
		return false
	}
	dll, err := syscall.LoadDLL(filepath.Join(installDir, "bin", dllName))
	if err != nil {
		return false
	}
	_ = dll.Release()
	return true
}

func winFspDllName(arch string) string {
	switch arch {
	case "arm64":
		return "winfsp-a64.dll"
	case "amd64":
		return "winfsp-x64.dll"
	case "386":
		return "winfsp-x86.dll"
	default:
		return ""
	}
}

func winFspInstallDir() (string, bool) {
	kname, _ := syscall.UTF16PtrFromString("Software\\WinFsp")
	var regkey syscall.Handle
	err := syscall.RegOpenKeyEx(
		syscall.HKEY_LOCAL_MACHINE,
		kname,
		0,
		syscall.KEY_READ|syscall.KEY_WOW64_32KEY,
		&regkey,
	)
	if err != nil {
		return "", false
	}
	defer syscall.RegCloseKey(regkey)

	var pathbuf [syscall.MAX_PATH]uint16
	var regtype, size uint32
	vname, _ := syscall.UTF16PtrFromString("InstallDir")
	size = uint32(len(pathbuf) * 2)
	err = syscall.RegQueryValueEx(
		regkey,
		vname,
		nil,
		&regtype,
		(*byte)(unsafe.Pointer(&pathbuf)),
		&size,
	)
	if err != nil || regtype != syscall.REG_SZ {
		return "", false
	}
	if size >= 2 && pathbuf[size/2-1] == 0 {
		size -= 2
	}
	return syscall.UTF16ToString(pathbuf[:size/2]), true
}

// hasWinFspMountSuffix identifies managed WinFsp mount directories under the
// Cloud Volume root during cleanup. Kept here (non-cgo, non-tag) so tests and
// the cleanup helpers can call it even when the WinFsp engine itself is built
// out.
func hasWinFspMountSuffix(name string) bool {
	return len(name) > len("-winfsp") && name[len(name)-len("-winfsp"):] == "-winfsp"
}

// isWindowsDriveMount reports whether a mount path is a bare "X:" drive letter,
// which WinFsp can mount onto directly without a backing directory.
func isWindowsDriveMount(path string) bool {
	trimmed := strings.TrimSpace(path)
	return len(trimmed) == 2 && trimmed[1] == ':'
}
