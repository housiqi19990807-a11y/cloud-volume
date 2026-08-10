//go:build windows

// Windows mount helpers run console utilities without flashing terminal windows.
package mount

import (
	"os/exec"
	"syscall"

	"golang.org/x/sys/windows"
)

func hiddenWindowsCommand(name string, args ...string) *exec.Cmd {
	cmd := exec.Command(name, args...)
	cmd.SysProcAttr = &syscall.SysProcAttr{
		HideWindow:    true,
		CreationFlags: windows.CREATE_NO_WINDOW,
	}
	return cmd
}
