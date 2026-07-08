// Standalone updater EXE for Windows green-package (zip) updates.
//
// The main app downloads the update zip, then launches this updater with:
//
//	cloud-volume-updater.exe -zip <path> -install-dir <dir> -pid <oldPid> [-exe-name cloud-volume.exe]
//
// The updater shows a small progress window, waits for the old process to
// exit, extracts the zip into a staging directory, copies the payload over the
// install directory, then relaunches the app and exits.  It replaces the
// previous PowerShell-script approach which was fragile (hidden window, no
// visible feedback, silent failures on file-lock races).
package main

import (
	"archive/zip"
	"flag"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"time"
)

func main() {
	var (
		zipPath   = flag.String("zip", "", "path to the downloaded update zip")
		installDir = flag.String("install-dir", "", "directory containing cloud-volume.exe")
		oldPID     = flag.Int("pid", 0, "PID of the old process to wait for")
		exeName    = flag.String("exe-name", "cloud-volume.exe", "main executable filename")
	)
	flag.Parse()

	// Open the diagnostic log as early as possible so every step below is
	// captured. The path is %TEMP%\cloud-volume-updater-<pid>.log.
	initLogger()
	logf("cloud-volume-updater starting: zip=%s install-dir=%s pid=%d exe=%s",
		*zipPath, *installDir, *oldPID, *exeName)

	if *zipPath == "" || *installDir == "" {
		logf("ERROR: missing required arguments")
		fmt.Fprintln(os.Stderr, "usage: cloud-volume-updater -zip <path> -install-dir <dir> -pid <pid>")
		os.Exit(2)
	}
	if _, err := os.Stat(*zipPath); err != nil {
		logf("ERROR: update package missing: %v", err)
		fail("更新包不存在", err)
	}

	// Run the update with a Win32 progress window on Windows; on other
	// platforms just run headless (the updater is Windows-only in practice).
	if runtime.GOOS == "windows" {
		runWithWindow(*zipPath, *installDir, *oldPID, *exeName)
	} else {
		if err := performUpdate(*zipPath, *installDir, *oldPID, *exeName, func(string) {}); err != nil {
			fail("更新失败", err)
		}
	}
}

// performUpdate is the core update routine shared by the windowed and headless
// paths.  The status callback lets the UI layer show progress text.
func performUpdate(zipPath, installDir string, oldPID int, exeName string, setStatus func(string)) error {
	exePath := filepath.Join(installDir, exeName)

	// Wrap setStatus so every status change is also written to the log file.
	status := func(msg string) {
		logf("status: %s", msg)
		setStatus(msg)
	}

	// 1. Wait for the old process to exit so Windows releases file locks.
	if oldPID > 0 {
		status("正在等待应用退出...")
		waitForProcess(oldPID, 60*time.Second)
	}

	// 2. Poll until the main exe is writable (child/background procs may linger).
	status("正在准备更新...")
	deadline := time.Now().Add(60 * time.Second)
	for time.Now().Before(deadline) {
		if isFileWritable(exePath) {
			break
		}
		time.Sleep(time.Second)
	}
	if !isFileWritable(exePath) {
		logf("ERROR: %s still locked after 60s", exePath)
		return fmt.Errorf("%s 仍被占用，请手动关闭后重试", exeName)
	}

	// 3. Extract the zip to a staging directory.
	status("正在解压更新包...")
	staging, err := extractZip(zipPath)
	if err != nil {
		logf("ERROR: extract failed: %v", err)
		return fmt.Errorf("解压失败: %w", err)
	}
	defer os.RemoveAll(staging)
	logf("extracted to staging: %s", staging)

	// 4. Find the payload directory (zip root, or first child containing the exe).
	payload := staging
	if _, err := os.Stat(filepath.Join(payload, exeName)); os.IsNotExist(err) {
		logf("exe not at zip root, scanning subdirectories...")
		entries, _ := os.ReadDir(staging)
		for _, e := range entries {
			if e.IsDir() {
				if _, err := os.Stat(filepath.Join(staging, e.Name(), exeName)); err == nil {
					payload = filepath.Join(staging, e.Name())
					logf("found payload in subdirectory: %s", payload)
					break
				}
			}
		}
	}
	if _, err := os.Stat(filepath.Join(payload, exeName)); err != nil {
		logf("ERROR: %s not found in payload %s", exeName, payload)
		return fmt.Errorf("更新包中未找到 %s", exeName)
	}

	// 5. Copy each file from the payload over the install directory.
	status("正在替换文件...")
	if err := copyDir(payload, installDir); err != nil {
		logf("ERROR: copy failed: %v", err)
		return fmt.Errorf("替换文件失败: %w", err)
	}
	logf("files copied successfully")

	// 6. Relaunch the app.
	status("更新完成，正在启动...")
	cmd := exec.Command(exePath)
	cmd.Dir = installDir
	if err := cmd.Start(); err != nil {
		logf("ERROR: relaunch failed: %v", err)
		return fmt.Errorf("启动失败: %w", err)
	}
	logf("new app started, pid=%d", cmd.Process.Pid)

	// 7. Wait for the new app to actually appear before exiting, so we don't
	// race the relaunch. Poll for up to 30 seconds for a cloud-volume.exe
	// process whose PID differs from the old one.
	status("正在确认应用启动...")
	newPID := waitForNewApp(exePath, oldPID, 30*time.Second)
	if newPID > 0 {
		logf("confirmed new app running, pid=%d", newPID)
	} else {
		logf("WARNING: new app did not appear within 30s, exiting anyway")
	}
	// Give the new instance a moment to initialize its window before we vanish.
	time.Sleep(2 * time.Second)
	return nil
}

// extractZip decompresses the archive into a unique temp directory and returns
// its path.  The caller is responsible for cleaning it up.
func extractZip(zipPath string) (string, error) {
	staging, err := os.MkdirTemp("", "cloud-volume-update-*")
	if err != nil {
		return "", err
	}
	r, err := zip.OpenReader(zipPath)
	if err != nil {
		return staging, err
	}
	defer r.Close()
	for _, f := range r.File {
		dest := filepath.Join(staging, f.Name)
		if f.FileInfo().IsDir() {
			if err := os.MkdirAll(dest, 0755); err != nil {
				return staging, err
			}
			continue
		}
		if err := os.MkdirAll(filepath.Dir(dest), 0755); err != nil {
			return staging, err
		}
		out, err := os.OpenFile(dest, os.O_WRONLY|os.O_CREATE|os.O_TRUNC, 0644)
		if err != nil {
			return staging, err
		}
		rc, err := f.Open()
		if err != nil {
			out.Close()
			return staging, err
		}
		if _, err := io.Copy(out, rc); err != nil {
			rc.Close()
			out.Close()
			return staging, err
		}
		rc.Close()
		out.Close()
	}
	return staging, nil
}

// copyDir copies every file and subdirectory from src into dst, overwriting
// existing entries.  It skips the updater's own exe so it does not try to
// overwrite itself while running.
func copyDir(src, dst string) error {
	// Resolve the updater exe name so we can skip self-overwrite.
	selfName := filepath.Base(os.Args[0])
	return filepath.Walk(src, func(path string, info os.FileInfo, err error) error {
		if err != nil {
			return err
		}
		rel, err := filepath.Rel(src, path)
		if err != nil {
			return err
		}
		if rel == "." {
			return nil
		}
		// Never overwrite the running updater exe.
		if rel == selfName {
			return nil
		}
		target := filepath.Join(dst, rel)
		if info.IsDir() {
			return os.MkdirAll(target, info.Mode())
		}
		return copyFile(path, target, info.Mode())
	})
}

// copyFile copies a single file, handling Windows file-lock retries.
func copyFile(src, dst string, mode os.FileMode) error {
	// Retry a few times in case an antivirus or indexer briefly holds the file.
	var lastErr error
	for attempt := 0; attempt < 10; attempt++ {
		err := copyFileOnce(src, dst, mode)
		if err == nil {
			return nil
		}
		lastErr = err
		time.Sleep(500 * time.Millisecond)
	}
	return lastErr
}

func copyFileOnce(src, dst string, mode os.FileMode) error {
	in, err := os.Open(src)
	if err != nil {
		return err
	}
	defer in.Close()
	// Remove the destination first so we don't get "access denied" on a
	// read-only existing file (Windows refuses to overwrite read-only files).
	_ = os.Chmod(dst, 0644)
	out, err := os.OpenFile(dst, os.O_WRONLY|os.O_CREATE|os.O_TRUNC, mode)
	if err != nil {
		return err
	}
	if _, err := io.Copy(out, in); err != nil {
		out.Close()
		return err
	}
	return out.Close()
}

