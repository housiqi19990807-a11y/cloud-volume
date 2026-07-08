//go:build windows

// Win32 progress dialog for the standalone updater.  Uses a simple modal
// MessageBox to tell the user an update is in progress while the actual
// file replacement runs on a background goroutine.  This avoids the complexity
// of hand-rolling a full window procedure and drawing pipeline while still
// giving visible feedback.
package main

import (
	"fmt"
	"os"
	"syscall"
	"unsafe"
)

var (
	user32         = syscall.NewLazyDLL("user32.dll")
	procMessageBox = user32.NewProc("MessageBoxW")
	procPostMessage = user32.NewProc("PostMessageW")
	procFindWindow = user32.NewProc("FindWindowW")
)

const (
	MB_OK           = 0x00000000
	MB_ICONINFORMATION = 0x00000040
	MB_TOPMOST      = 0x00040000
	MB_SETFOREGROUND = 0x00010000
	WM_CLOSE        = 0x0010
)

// runWithWindow shows a progress message box, runs the update on a goroutine,
// then closes the box and exits.
func runWithWindow(zipPath, installDir string, oldPID int, exeName string) {
	// Start the update in the background.
	done := make(chan error, 1)
	go func() {
		err := performUpdate(zipPath, installDir, oldPID, exeName, func(string) {})
		done <- err
	}()

	// Show a topmost modal box so the user knows the update is running.
	// The MessageBox blocks until the update goroutine closes it via WM_CLOSE.
	go func() {
		err := <-done
		// Find and close the message box window.
		className, _ := syscall.UTF16PtrFromString("#32770") // dialog class
		hwnd, _, _ := procFindWindow.Call(
			uintptr(unsafe.Pointer(className)),
			0)
		if hwnd != 0 {
			procPostMessage.Call(hwnd, WM_CLOSE, 0, 0)
		}
		// If the update failed, show the error in a second box.
		if err != nil {
			title, _ := syscall.UTF16PtrFromString("更新失败")
			msg, _ := syscall.UTF16PtrFromString(fmt.Sprintf("更新失败：%v", err))
			procMessageBox.Call(0,
				uintptr(unsafe.Pointer(msg)),
				uintptr(unsafe.Pointer(title)),
				MB_OK|MB_ICONINFORMATION|MB_TOPMOST|MB_SETFOREGROUND)
		}
		os.Exit(0)
	}()

	// This call blocks until the goroutine posts WM_CLOSE.
	title, _ := syscall.UTF16PtrFromString("云卷更新")
	msg, _ := syscall.UTF16PtrFromString("正在更新云卷，请稍候...\n\n更新完成后将自动重新启动。")
	procMessageBox.Call(0,
		uintptr(unsafe.Pointer(msg)),
		uintptr(unsafe.Pointer(title)),
		MB_OK|MB_ICONINFORMATION|MB_TOPMOST|MB_SETFOREGROUND)
}

