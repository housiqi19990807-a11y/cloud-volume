//go:build windows

// Windows mount actions use the shell open verb instead of explorer.exe exit codes.
package mount

import (
	"fmt"
	"unsafe"

	"golang.org/x/sys/windows"
)

var shellExecuteWProc = windows.NewLazySystemDLL("shell32.dll").NewProc("ShellExecuteW")

func openMountPath(mountPath string) error {
	action, err := windows.UTF16PtrFromString("open")
	if err != nil {
		return fmt.Errorf("open mount path action: %w", err)
	}
	target, err := windows.UTF16PtrFromString(mountPath)
	if err != nil {
		return fmt.Errorf("open mount path target: %w", err)
	}

	result, _, callErr := shellExecuteWProc.Call(
		0,
		uintptr(unsafe.Pointer(action)),
		uintptr(unsafe.Pointer(target)),
		0,
		0,
		1,
	)
	if shellExecuteSucceeded(result) {
		return nil
	}
	// ShellExecuteW returns the failure cause in `result` (<= 32). The errno
	// from syscall is always non-nil even on success, so only surface it when
	// it carries a real OS error; otherwise fall back to the result code,
	// which is what callers actually need to diagnose the failure.
	if callErr != nil && callErr != windows.ERROR_SUCCESS {
		return fmt.Errorf("open mount path: %w (result=%d)", callErr, result)
	}
	return fmt.Errorf("open mount path: shell execute returned %d", result)
}

func shellExecuteSucceeded(result uintptr) bool {
	return result > 32
}
