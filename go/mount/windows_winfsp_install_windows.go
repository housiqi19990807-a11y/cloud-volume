//go:build windows

// WinFsp installer helpers write the embedded MSI to a temp file and launch
// msiexec with elevation so the user can enable the virtual file system engine
// without leaving the app. The install is best-effort: callers surface any
// error so the settings UI / mount dialog can fall back to Cloud Files.
package mount

import (
	"fmt"
	"os"
	"path/filepath"
)

// InstallWindowsWinFsp extracts the embedded MSI (or reuses the side-by-side
// copy shipped by the Inno Setup installer) and runs an elevated install.
// When WinFsp is already present the call is a no-op. On success the caller
// should re-probe with WindowsWinFspAvailable.
func InstallWindowsWinFsp() error {
	if WindowsWinFspAvailable() {
		return nil
	}

	msiPath, cleanup, err := prepareWinFspMSI()
	if err != nil {
		return err
	}
	if cleanup != nil {
		defer cleanup()
	}

	// /passive shows a progress bar but needs no user input; /norestart keeps
	// the app running. ALLUSERS=1 forces a per-machine install which is what
	// the WinFsp MSI expects (it is authored as Privileged/elevated).
	exitCode, runErr := runElevatedWait(
		"msiexec.exe",
		"/i \""+msiPath+"\" /passive /norestart ALLUSERS=1",
	)
	if runErr != nil {
		return fmt.Errorf("install WinFsp: %w", runErr)
	}
	switch exitCode {
	case 0, 3010: // success, or success-with-reboot-required
		// fall through to availability probe
	default:
		return fmt.Errorf("WinFsp 安装程序退出码 %d（请查看 UAC / MSI 对话框了解详情）", exitCode)
	}

	if !WindowsWinFspAvailable() {
		return fmt.Errorf("WinFsp 安装上报成功，但驱动 DLL 仍不可见；可能需要重启系统")
	}
	return nil
}

// prepareWinFspMSI returns a path to an MSI that msiexec can install. Prefer
// the side-by-side copy under {app}/winfsp (shipped by the installer), then
// fall back to the embedded payload written into a temp file.
func prepareWinFspMSI() (string, func(), error) {
	if sideBySide := sideBySideWinFspMSI(); sideBySide != "" {
		return sideBySide, nil, nil
	}

	payload := EmbeddedWinFspMSI()
	if len(payload) == 0 {
		return "", nil, fmt.Errorf("embedded WinFsp installer is missing")
	}
	tempDir, err := os.MkdirTemp("", "cloud-volume-winfsp-*")
	if err != nil {
		return "", nil, fmt.Errorf("create temp dir for WinFsp install: %w", err)
	}
	msiPath := filepath.Join(tempDir, "winfsp.msi")
	if err := os.WriteFile(msiPath, payload, 0o644); err != nil {
		_ = os.RemoveAll(tempDir)
		return "", nil, fmt.Errorf("write WinFsp MSI: %w", err)
	}
	return msiPath, func() { _ = os.RemoveAll(tempDir) }, nil
}

func sideBySideWinFspMSI() string {
	exePath, err := os.Executable()
	if err != nil {
		return ""
	}
	candidate := filepath.Join(filepath.Dir(exePath), "winfsp", "winfsp.msi")
	if info, err := os.Stat(candidate); err == nil && !info.IsDir() {
		return candidate
	}
	return ""
}
