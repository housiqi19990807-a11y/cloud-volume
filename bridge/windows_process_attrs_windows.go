//go:build windows

// Windows process attributes keep helper updater scripts out of the foreground.

package main

import "syscall"

func windowsHiddenProcessAttrs() *syscall.SysProcAttr {
	return &syscall.SysProcAttr{HideWindow: true}
}
