//go:build windows
// Windows-specific process and file-lock helpers for the standalone updater.
package main
import (
	"os"
	"syscall"
	"time"
)
// waitForProcess blocks until the process with the given PID exits or the
// timeout elapses.  On Windows we open a handle with SYNCHRONIZE and wait.
func waitForProcess(pid int, timeout time.Duration) {
	h, err := syscall.OpenProcess(syscall.SYNCHRONIZE, false, uint32(pid))
	if err != nil {
		return // process already gone or inaccessible
	}
	defer syscall.CloseHandle(h)
	syscall.WaitForSingleObject(h, uint32(timeout/time.Millisecond))
}
// isFileWritable returns true when the file can be opened for exclusive write
// access, meaning no other process holds a lock on it.
func isFileWritable(path string) bool {
	if _, err := os.Stat(path); os.IsNotExist(err) {
		return true // nothing to unlock
	}
	h, err := syscall.CreateFile(
		syscall.StringToUTF16Ptr(path),
		syscall.GENERIC_WRITE,
		0, // exclusive — no other share
		nil,
		syscall.OPEN_EXISTING,
		syscall.FILE_ATTRIBUTE_NORMAL,
		0)
	if err != nil {
		return false
	}
	syscall.CloseHandle(h)
	return true
}
