//go:build windows

// WinFsp installer helpers write the embedded MSI to a temp file and launch
// msiexec with elevation so the user can enable the virtual file system engine
// without leaving the app. The install is best-effort: callers surface any
// error so the settings UI / mount dialog can fall back to Cloud Files.
package mount

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"syscall"
)

// InstallWindowsWinFsp extracts the embedded MSI (or reuses the side-by-side
// copy shipped by the Inno Setup installer) and runs a silent elevated install.
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

	// Prefer a silent elevated msiexec so the user only sees the UAC prompt.
	// /qn = quiet, no UI; /norestart keeps the app running after install.
	if err := runElevated("msiexec.exe", "/i", msiPath, "/qn", "/norestart"); err != nil {
		return fmt.Errorf("install WinFsp: %w", err)
	}
	if !WindowsWinFspAvailable() {
		return fmt.Errorf("WinFsp install finished but the driver DLL is still not visible; reboot may be required")
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

// runElevated launches a process with the "runas" verb so the user sees a UAC
// elevation prompt. It waits for the process to exit and surfaces a non-zero
// exit code as an error.
func runElevated(file string, args ...string) error {
	// Build a single command line; ShellExecuteW with "runas" does not take an
	// argv array, so we quote arguments that contain spaces.
	quoted := make([]string, 0, len(args))
	for _, arg := range args {
		if strings.ContainsAny(arg, " \t\"") {
			quoted = append(quoted, `"`+strings.ReplaceAll(arg, `"`, `\"`)+`"`)
			continue
		}
		quoted = append(quoted, arg)
	}
	params := strings.Join(quoted, " ")

	// Use PowerShell Start-Process -Verb RunAs -Wait so we get a reliable exit
	// code from the elevated msiexec process.
	ps := fmt.Sprintf(
		"Start-Process -FilePath %s -ArgumentList %s -Verb RunAs -Wait -PassThru | ForEach-Object { exit $_.ExitCode }",
		powershellQuote(file),
		powershellQuote(params),
	)
	cmd := exec.Command("powershell.exe", "-NoProfile", "-NonInteractive", "-Command", ps)
	// Hide the PowerShell window; the UAC prompt itself still appears.
	cmd.SysProcAttr = &syscall.SysProcAttr{HideWindow: true}
	output, err := cmd.CombinedOutput()
	if err != nil {
		// If elevation was cancelled the exit code is typically 1223 /
		// ERROR_CANCELLED; surface the combined output for diagnosis.
		return fmt.Errorf("%w: %s", err, strings.TrimSpace(string(output)))
	}
	return nil
}

func powershellQuote(value string) string {
	return `'` + strings.ReplaceAll(value, `'`, `''`) + `'`
}
