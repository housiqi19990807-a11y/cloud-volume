// Report assembly keeps crash evidence bounded, local, and reviewable.
package main

import (
	"crypto/sha256"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"runtime"
	"sort"
	"strings"
	"time"
)

const diagnosticTailBytes int64 = 64 * 1024

type crashContext struct {
	Executable  string
	PID         int
	ExitCode    uint32
	LaunchError uint32
}

func writeCrashReport(context crashContext) (string, error) {
	home, err := os.UserHomeDir()
	if err != nil {
		return "", fmt.Errorf("resolve user home: %w", err)
	}
	reportDir := filepath.Join(home, ".cloud-volume", "runtime", "crashes")
	if err := os.MkdirAll(reportDir, 0o755); err != nil {
		return "", fmt.Errorf("create crash report directory: %w", err)
	}
	now := time.Now()
	reportPath := filepath.Join(reportDir, fmt.Sprintf(
		"crash-%s-%d.txt", now.Format("20060102-150405"), context.PID))
	content := buildCrashReport(context, now, home, os.TempDir())
	if err := os.WriteFile(reportPath, []byte(content), 0o600); err != nil {
		return "", fmt.Errorf("write crash report: %w", err)
	}
	return reportPath, nil
}

func buildCrashReport(
	context crashContext,
	now time.Time,
	home string,
	tempDir string,
) string {
	var report strings.Builder
	report.WriteString("Yunjuan Windows crash report\n")
	report.WriteString("================================\n")
	fmt.Fprintf(&report, "Generated: %s\n", now.Format(time.RFC3339))
	fmt.Fprintf(&report, "System: %s\n", platformSystemDescription())
	fmt.Fprintf(&report, "Reporter architecture: %s/%s\n", runtime.GOOS, runtime.GOARCH)
	fmt.Fprintf(&report, "Monitored PID: %d\n", context.PID)
	fmt.Fprintf(&report, "Executable: %s\n", context.Executable)
	if context.LaunchError != 0 {
		fmt.Fprintf(&report, "Launch error: %d (0x%08X)\n", context.LaunchError, context.LaunchError)
	} else {
		fmt.Fprintf(&report, "Exit code: %d (0x%08X, %s)\n",
			int32(context.ExitCode), context.ExitCode, describeExitCode(context.ExitCode))
	}

	report.WriteString("\nArtifact fingerprints\n")
	report.WriteString("---------------------\n")
	installDir := filepath.Dir(context.Executable)
	for _, relativePath := range []string{
		"cloud-volume.exe",
		"cloud-volume-app.exe",
		filepath.Join("data", "app.so"),
		"remote_storage_bridge.dll",
	} {
		report.WriteString(describeArtifact(filepath.Join(installDir, relativePath)))
	}

	bridgeLog := filepath.Join(home, ".cloud-volume", "runtime", "logs", "bridge.log")
	appendDiagnosticFile(&report, "Bridge log tail", bridgeLog)
	if updaterLog := latestUpdaterLog(tempDir); updaterLog != "" {
		appendDiagnosticFile(&report, "Latest updater log tail", updaterLog)
	}
	return report.String()
}

func describeArtifact(path string) string {
	info, err := os.Stat(path)
	if err != nil {
		return fmt.Sprintf("%s: unavailable (%v)\n", path, err)
	}
	file, err := os.Open(path)
	if err != nil {
		return fmt.Sprintf("%s: size=%d, hash unavailable (%v)\n", path, info.Size(), err)
	}
	hash := sha256.New()
	_, copyErr := io.Copy(hash, file)
	closeErr := file.Close()
	if copyErr != nil || closeErr != nil {
		return fmt.Sprintf("%s: size=%d, hash read failed (%v, %v)\n",
			path, info.Size(), copyErr, closeErr)
	}
	return fmt.Sprintf("%s: size=%d, modified=%s, sha256=%x\n",
		path, info.Size(), info.ModTime().Format(time.RFC3339), hash.Sum(nil))
}

func appendDiagnosticFile(report *strings.Builder, title string, path string) {
	report.WriteString("\n" + title + "\n")
	report.WriteString(strings.Repeat("-", len(title)) + "\n")
	fmt.Fprintf(report, "Source: %s\n", path)
	tail, err := tailFile(path, diagnosticTailBytes)
	if err != nil {
		fmt.Fprintf(report, "Unavailable: %v\n", err)
		return
	}
	report.Write(tail)
	if len(tail) > 0 && tail[len(tail)-1] != '\n' {
		report.WriteByte('\n')
	}
}

func tailFile(path string, limit int64) ([]byte, error) {
	file, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer file.Close()
	info, err := file.Stat()
	if err != nil {
		return nil, err
	}
	start := info.Size() - limit
	if start < 0 {
		start = 0
	}
	if _, err := file.Seek(start, io.SeekStart); err != nil {
		return nil, err
	}
	return io.ReadAll(io.LimitReader(file, limit))
}

func latestUpdaterLog(tempDir string) string {
	matches, _ := filepath.Glob(filepath.Join(tempDir, "cloud-volume-updater-*.log"))
	sort.Slice(matches, func(i, j int) bool {
		left, leftErr := os.Stat(matches[i])
		right, rightErr := os.Stat(matches[j])
		if leftErr != nil {
			return false
		}
		if rightErr != nil {
			return true
		}
		return left.ModTime().After(right.ModTime())
	})
	if len(matches) == 0 {
		return ""
	}
	return matches[0]
}

func describeExitCode(code uint32) string {
	switch code {
	case 0xC0000005:
		return "access violation"
	case 0xC000001D:
		return "illegal instruction"
	case 0xC0000135:
		return "required DLL not found"
	case 0xC0000142:
		return "DLL initialization failed"
	case 0xC0000409:
		return "stack buffer overrun or fail-fast"
	default:
		return "abnormal termination"
	}
}
