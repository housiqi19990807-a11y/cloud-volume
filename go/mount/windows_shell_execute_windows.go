//go:build windows

// ShellExecuteEx wrapper used to launch elevated installers (currently only
// WinFsp) and wait for their real exit code. PowerShell's Start-Process -PassThru
// cannot read the exit code of a process spawned in a different (elevated)
// session, so we shell down to ShellExecuteExW + WaitForSingleObject, which
// give us a process handle we can wait on directly.
package mount

import (
	"fmt"
	"strings"
	"syscall"
	"unsafe"

	"golang.org/x/sys/windows"
)

const (
	seeMaskNoCloseProcess = 0x00000040
	seeMaskFlagNoUi       = 0x00000400
	shellExecuteShowHide  = 0 // SW_HIDE
	waitStillActive       = 259
	errorCancelled        = 1223
	installTimeoutMS      = 10 * 60 * 1000 // 10 min for a ~2MB driver install incl. UAC
)

// shellExecuteInfo is the Win32 SHELLEXECUTEINFOW layout used by
// ShellExecuteExW. Defined locally because x/sys does not expose ShellExecuteEx.
type shellExecuteInfo struct {
	cbSize       uint32
	fMask        uint32
	hwnd         uintptr
	verb         *uint16
	file         *uint16
	parameters   *uint16
	directory    *uint16
	show         int32
	hInstApp     uintptr
	idList       uintptr
	class        *uint16
	hkeyClass    uintptr
	hotKey       uint32
	iconOrHandle uintptr
	process      uintptr
}

var (
	shellExecuteExWProc = syscall.NewLazyDLL("shell32.dll").NewProc("ShellExecuteExW")
	waitForSingleObject = syscall.NewLazyDLL("kernel32.dll").NewProc("WaitForSingleObject")
	getExitCodeProcess  = syscall.NewLazyDLL("kernel32.dll").NewProc("GetExitCodeProcess")
	closeHandleProc     = syscall.NewLazyDLL("kernel32.dll").NewProc("CloseHandle")
)

// runElevatedWait launches file with the "runas" verb, waits for the elevated
// process to exit, and returns its real exit code.
func runElevatedWait(file, parameters string) (uint32, error) {
	verb, err := windows.UTF16PtrFromString("runas")
	if err != nil {
		return 0, err
	}
	filePtr, err := windows.UTF16PtrFromString(file)
	if err != nil {
		return 0, err
	}
	var paramPtr *uint16
	if strings.TrimSpace(parameters) != "" {
		paramPtr, err = windows.UTF16PtrFromString(parameters)
		if err != nil {
			return 0, err
		}
	}

	info := shellExecuteInfo{
		cbSize:     uint32(unsafe.Sizeof(shellExecuteInfo{})),
		fMask:      seeMaskNoCloseProcess | seeMaskFlagNoUi,
		verb:       verb,
		file:       filePtr,
		parameters: paramPtr,
		show:       shellExecuteShowHide,
	}

	ret, _, callErr := shellExecuteExWProc.Call(uintptr(unsafe.Pointer(&info)))
	if ret == 0 {
		// ShellExecuteEx returns FALSE; callErr holds the real OS error.
		// ERROR_CANCELLED (1223) means the user dismissed the UAC prompt.
		if callErr == syscall.Errno(errorCancelled) {
			return 0, fmt.Errorf("用户取消了 WinFsp 安装的 UAC 确认")
		}
		return 0, fmt.Errorf("启动提权安装失败: %w", callErr)
	}
	if info.process == 0 {
		// No process handle (e.g. the verb was handled by an existing process).
		return 0, nil
	}
	defer closeHandleProc.Call(info.process)

	event, _, _ := waitForSingleObject.Call(
		info.process,
		uintptr(installTimeoutMS),
	)
	switch event {
	case 0: // WAIT_OBJECT_0: signalled (process exited)
	case 258: // WAIT_TIMEOUT
		return 0, fmt.Errorf("WinFsp 安装超时（%d 分钟）", installTimeoutMS/60000)
	default:
		return 0, fmt.Errorf("等待 WinFsp 安装进程失败 (event=%d)", event)
	}

	var exitCode uint32
	ret, _, _ = getExitCodeProcess.Call(info.process, uintptr(unsafe.Pointer(&exitCode)))
	if ret == 0 {
		return 0, fmt.Errorf("读取 WinFsp 安装进程退出码失败")
	}
	if exitCode == waitStillActive {
		return 0, fmt.Errorf("WinFsp 安装进程仍在运行")
	}
	return exitCode, nil
}
