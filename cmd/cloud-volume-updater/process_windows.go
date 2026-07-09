//go:build windows
// Windows-specific process and file-lock helpers for the standalone updater.
package main
import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"syscall"
	"time"
	"unsafe"
)

var (
	procGetTokenInformation = advapi32.NewProc("GetTokenInformation")
	procShellExecute        = shell32.NewProc("ShellExecuteW")
	advapi32                = syscall.NewLazyDLL("advapi32.dll")
	shell32                 = syscall.NewLazyDLL("shell32.dll")
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
// waitForNewApp polls until a fresh instance of the app exe is running, then
// returns its PID. We detect a "new" instance by scanning running processes
// for one whose PID differs from oldPID and whose image name matches the exe.
// Returns 0 if no new instance appeared within the timeout. This avoids the
// race where the updater exits immediately after Start() while the new app is
// still initializing (or fails to start at all).
func waitForNewApp(exePath string, oldPID int, timeout time.Duration) int {
	base := filepath.Base(exePath)
	deadline := time.Now().Add(timeout)
	for time.Now().Before(deadline) {
		for _, p := range findProcessesByName(base) {
			if p != oldPID {
				return p
			}
		}
		time.Sleep(300 * time.Millisecond)
	}
	return 0
}

// findProcessesByName returns PIDs of running processes whose image name equals
// name (case-insensitive). Uses tasklist to avoid pulling in snapshot APIs.
func findProcessesByName(name string) []int {
	out, err := exec.Command("tasklist", "/FI", "IMAGENAME eq "+name, "/FO", "CSV", "/NH").Output()
	if err != nil {
		return nil
	}
	var pids []int
	for _, line := range splitLines(string(out)) {
		if pid := parseCSVPid(line); pid > 0 {
			pids = append(pids, pid)
		}
	}
	return pids
}

// splitLines splits on CR and LF, dropping empty entries.
func splitLines(s string) []string {
	var out []string
	cur := 0
	for i := 0; i < len(s); i++ {
		if s[i] == '\n' || s[i] == '\r' {
			if cur < i {
				out = append(out, s[cur:i])
			}
			cur = i + 1
		}
	}
	if cur < len(s) {
		out = append(out, s[cur:])
	}
	return out
}

// parseCSVPid extracts the second quoted CSV field as an integer PID.
// tasklist CSV rows look like: "cloud-volume.exe","1234","Console","1","12,345 K"
func parseCSVPid(line string) int {
	first := indexByte(line, '"')
	if first < 0 {
		return 0
	}
	second := indexByte(line[first+1:], '"')
	if second < 0 {
		return 0
	}
	rest := line[first+1+second+1:]
	start := indexByte(rest, '"')
	if start < 0 {
		return 0
	}
	end := indexByte(rest[start+1:], '"')
	if end < 0 {
		return 0
	}
	num := rest[start+1 : start+1+end]
	n := 0
	for i := 0; i < len(num); i++ {
		c := num[i]
		if c < '0' || c > '9' {
			return 0
		}
		n = n*10 + int(c-'0')
	}
	return n
}

// indexByte returns the byte index of c in s, or -1.
func indexByte(s string, c byte) int {
	for i := 0; i < len(s); i++ {
		if s[i] == c {
			return i
		}
	}
	return -1
}

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

// isElevated returns true when the current process has an admin token.
func isElevated() bool {
	var token syscall.Token
	h, err := syscall.GetCurrentProcess()
	if err != nil {
		return false
	}
	defer syscall.CloseHandle(h)
	if err := syscall.OpenProcessToken(h, syscall.TOKEN_QUERY, &token); err != nil {
		return false
	}
	defer token.Close()
	var elevated uint32
	var returned uint32
	size := uint32(unsafe.Sizeof(elevated))
	ret, _, _ := procGetTokenInformation.Call(
		uintptr(token),
		20, // TokenElevation
		uintptr(unsafe.Pointer(&elevated)),
		uintptr(size),
		uintptr(unsafe.Pointer(&returned)),
	)
	return ret != 0 && elevated != 0
}

// relaunchElevated re-launches the updater with the same args via ShellExecuteW
// using the "runas" verb (triggers UAC). Returns true if re-launch started.
func relaunchElevated(zipPath, installDir string, oldPID int, exeName string) bool {
	self, err := os.Executable()
	if err != nil {
		return false
	}
	params := fmt.Sprintf(`-zip "%s" -install-dir "%s" -pid %d -exe-name "%s"`,
		zipPath, installDir, oldPID, exeName)
	op, _ := syscall.UTF16PtrFromString("runas")
	file, _ := syscall.UTF16PtrFromString(self)
	paramsW, _ := syscall.UTF16PtrFromString(params)
	ret, _, _ := procShellExecute.Call(
		0,
		uintptr(unsafe.Pointer(op)),
		uintptr(unsafe.Pointer(file)),
		uintptr(unsafe.Pointer(paramsW)),
		0,
		1, // SW_SHOWNORMAL
	)
	return int(ret) > 32
}