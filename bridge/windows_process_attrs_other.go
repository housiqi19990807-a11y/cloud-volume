//go:build !windows

// Non-Windows builds do not need special updater process attributes.

package main

import "syscall"

func windowsHiddenProcessAttrs() *syscall.SysProcAttr {
	return nil
}
