//go:build windows && cgo

// Cloud Files health probes verify the sync root is still writable before the UI trusts it.
package mount

import (
	"context"
	"fmt"
	"os/exec"
	"path/filepath"
	"strings"
	"time"
)

const (
	windowsCloudFilesHealthProbeDir  = ".cloud-volume"
	windowsCloudFilesHealthProbeFile = "write-probe.txt"
	windowsCloudFilesHealthTimeout   = 6 * time.Second
	windowsCloudFilesHealthCacheTTL  = 5 * time.Second
)

func windowsCloudFilesWriteProbe(rootPath string) error {
	probeDir := filepath.Join(rootPath, windowsCloudFilesHealthProbeDir)
	probeFile := filepath.Join(probeDir, windowsCloudFilesHealthProbeFile)
	ctx, cancel := context.WithTimeout(
		context.Background(),
		windowsCloudFilesHealthTimeout,
	)
	defer cancel()

	script := fmt.Sprintf(
		"$dir = %s; $file = %s; "+
			"New-Item -ItemType Directory -Force -Path $dir | Out-Null; "+
			"[System.IO.File]::WriteAllText($file, 'probe'); "+
			"Remove-Item -LiteralPath $file -Force -ErrorAction SilentlyContinue; "+
			"Remove-Item -LiteralPath $dir -Force -ErrorAction SilentlyContinue",
		windowsPowerShellString(probeDir),
		windowsPowerShellString(probeFile),
	)
	cmd := exec.CommandContext(
		ctx,
		"powershell.exe",
		"-NoProfile",
		"-NonInteractive",
		"-Command",
		script,
	)
	output, err := cmd.CombinedOutput()
	if ctx.Err() == context.DeadlineExceeded {
		return fmt.Errorf("write probe timed out after %s", windowsCloudFilesHealthTimeout)
	}
	if err != nil {
		trimmed := strings.TrimSpace(string(output))
		if trimmed == "" {
			return fmt.Errorf("write probe failed: %w", err)
		}
		return fmt.Errorf("write probe failed: %w: %s", err, trimmed)
	}
	return nil
}

func windowsPowerShellString(value string) string {
	return "'" + strings.ReplaceAll(value, "'", "''") + "'"
}
