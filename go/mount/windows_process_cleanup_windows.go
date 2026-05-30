//go:build windows

// Windows process cleanup helpers terminate stale local debug runners that can
// keep bridge artifacts and writeback DB files locked after a failed session.
package mount

import (
	"bytes"
	"fmt"
	"os/exec"
	"path/filepath"
	"strings"
)

// CleanupStaleWindowsProcesses kills leftover remote_storage.exe processes that
// were launched from this repository's Windows runner output.
func CleanupStaleWindowsProcesses() (int, error) {
	exePath, err := exec.LookPath("powershell")
	if err != nil {
		return 0, fmt.Errorf("locate powershell: %w", err)
	}

	workspaceRoot, err := filepath.Abs(".")
	if err != nil {
		return 0, fmt.Errorf("resolve workspace root: %w", err)
	}
	targetPrefix := strings.ToLower(filepath.Clean(
		filepath.Join(workspaceRoot, "build", "windows", "x64", "runner"),
	))

	script := fmt.Sprintf(`
$targetPrefix = %q
$killed = 0
$processes = Get-CimInstance Win32_Process -Filter "Name = 'remote_storage.exe'"
foreach ($process in $processes) {
  $path = $process.ExecutablePath
  if (-not $path) { continue }
  $clean = [System.IO.Path]::GetFullPath($path).ToLowerInvariant()
  if (-not $clean.StartsWith($targetPrefix)) { continue }
  Stop-Process -Id $process.ProcessId -Force -ErrorAction Stop
  $killed++
}
Write-Output $killed
`, targetPrefix)

	cmd := exec.Command(exePath, "-NoProfile", "-Command", script)
	var stdout bytes.Buffer
	var stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr
	if err := cmd.Run(); err != nil {
		return 0, fmt.Errorf("cleanup stale windows processes: %w: %s", err, strings.TrimSpace(stderr.String()))
	}
	countText := strings.TrimSpace(stdout.String())
	if countText == "" {
		return 0, nil
	}
	var count int
	if _, err := fmt.Sscanf(countText, "%d", &count); err != nil {
		return 0, fmt.Errorf("parse cleanup stale windows processes count %q: %w", countText, err)
	}
	return count, nil
}
