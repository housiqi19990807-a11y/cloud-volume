// Bridge method for in-app update: download + install + relaunch.
//
// All platform-specific logic is handled here so Flutter only renders UI and
// polls progress through the existing TransferQueue polling loop.
//
// Supported platforms:
//   - macOS:  DMG (hdiutil attach → cp → detach → xattr) or ZIP (unzip)
//   - Windows: Inno Setup .exe installer (silent /SILENT /CLOSEAPPLICATIONS)
//   - Linux:   .AppImage (self-replace) or .tar.gz (extract to install dir)

package main

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"time"

	storageconfig "remote-storage/go/config"
	s3ops "remote-storage/go/s3"
)

type appInstallArgs struct {
	AssetURL      string `json:"assetUrl"`
	AssetName     string `json:"assetName"`
	InstallerType string `json:"installerType"`
	MirrorPrefix  string `json:"mirrorPrefix"`
	ProxyMode     string `json:"proxyMode"`
	ProxyType     string `json:"proxyType"`
	ProxyHost     string `json:"proxyHost"`
	ProxyPort     string `json:"proxyPort"`
	ProxyUsername string `json:"proxyUsername"`
	ProxyPassword string `json:"proxyPassword"`
}

type appInstallResult struct {
	TaskID string `json:"taskId"`
}

func installApp(args json.RawMessage) (any, error) {
	var input appInstallArgs
	if err := decodeArgs(args, &input); err != nil {
		return nil, err
	}
	if input.AssetURL == "" {
		return nil, fmt.Errorf("missing asset URL")
	}
	if input.AssetName == "" {
		return nil, fmt.Errorf("missing asset name")
	}

	taskID := fmt.Sprintf("app_update_%d", time.Now().UnixMilli())
	ctx, cancel := context.WithCancel(context.Background())

	// Register with transfer monitor so Flutter can poll progress.
	s3ops.QueueTransfer(taskID, "app_update", "", "", "", 0)

	go runAppUpdateInstall(ctx, cancel, taskID, input)

	return appInstallResult{TaskID: taskID}, nil
}

// runAppUpdateInstall runs the full download + install + relaunch sequence in a
// background goroutine. It updates the transfer monitor at each stage so Flutter
// can reflect progress. On success it calls os.Exit(0) after spawning the new
// binary. On failure it marks the task as failed and returns.
func runAppUpdateInstall(ctx context.Context, cancel context.CancelFunc, taskID string, input appInstallArgs) {
	defer cancel()

	s3ops.StartQueuedTransfer(taskID, "app_update", "", "", input.AssetName, 0, cancel)
	s3ops.SetTransferStatusDetail(taskID, "downloading")

	// Build the download URL with optional mirror prefix.
	downloadURL := input.AssetURL
	if input.MirrorPrefix != "" {
		prefix := strings.TrimRight(input.MirrorPrefix, "/")
		downloadURL = prefix + "/" + input.AssetURL
	}

	// Build proxy-aware HTTP client using the config package.
	proxyCfg := storageconfig.RemoteStorageConfig{
		ProxyMode:     input.ProxyMode,
		ProxyType:     input.ProxyType,
		ProxyHost:     input.ProxyHost,
		ProxyPort:     input.ProxyPort,
		ProxyUsername: input.ProxyUsername,
		ProxyPassword: input.ProxyPassword,
	}
	httpClient := storageconfig.ProxyHTTPClient(proxyCfg, 120)

	// Download to a temp directory.
	tmpDir := filepath.Join(os.TempDir(), "app_updates")
	if err := os.MkdirAll(tmpDir, 0755); err != nil {
		finishTransferError(taskID, fmt.Sprintf("创建临时目录失败：%v", err))
		return
	}
	dlPath := filepath.Join(tmpDir, input.AssetName)

	if err := streamDownload(ctx, httpClient, taskID, downloadURL, dlPath); err != nil {
		finishTransferError(taskID, fmt.Sprintf("下载失败：%v", err))
		return
	}

	s3ops.SetTransferStatusDetail(taskID, "installing")

	// Platform-specific install.
	switch runtime.GOOS {
	case "darwin":
		if err := installMacOS(taskID, dlPath, input.InstallerType); err != nil {
			finishTransferError(taskID, fmt.Sprintf("macOS 安装失败：%v", err))
			return
		}
	case "windows":
		if err := installWindows(taskID, dlPath, input.InstallerType); err != nil {
			finishTransferError(taskID, fmt.Sprintf("Windows 安装失败：%v", err))
			return
		}
	case "linux":
		if err := installLinux(taskID, dlPath, input.InstallerType); err != nil {
			finishTransferError(taskID, fmt.Sprintf("Linux 安装失败：%v", err))
			return
		}
	default:
		finishTransferError(taskID, fmt.Sprintf("不支持的平台：%s", runtime.GOOS))
		return
	}

	// Install succeeded - mark done and relaunch.
	s3ops.FinishQueuedTransfer(taskID, nil)
	// Short delay so Flutter polling can read the "done" status before we exit.
	time.Sleep(500 * time.Millisecond)

	// Relaunch and exit.
	relaunchApp()
	time.Sleep(800 * time.Millisecond)
	os.Exit(0)
}

func streamDownload(ctx context.Context, client *http.Client, taskID, url, destPath string) error {
	req, err := http.NewRequestWithContext(ctx, "GET", url, nil)
	if err != nil {
		return fmt.Errorf("创建请求失败：%w", err)
	}

	resp, err := client.Do(req)
	if err != nil {
		return fmt.Errorf("请求失败：%w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != 200 {
		return fmt.Errorf("HTTP %d", resp.StatusCode)
	}

	totalBytes := resp.ContentLength
	if totalBytes > 0 {
		s3ops.AddTransferTotal(taskID, totalBytes)
		s3ops.SetTransferCurrentFile(taskID, filepath.Base(destPath), totalBytes)
	}

	f, err := os.Create(destPath)
	if err != nil {
		return fmt.Errorf("创建文件失败：%w", err)
	}
	defer f.Close()

	buf := make([]byte, 32*1024)
	var received int64
	for {
		n, readErr := resp.Body.Read(buf)
		if n > 0 {
			if _, writeErr := f.Write(buf[:n]); writeErr != nil {
				return fmt.Errorf("写入文件失败：%w", writeErr)
			}
			received += int64(n)
			s3ops.AdvanceTransfer(taskID, int64(n))
		}
		if readErr == io.EOF {
			break
		}
		if readErr != nil {
			return fmt.Errorf("读取响应失败：%w", readErr)
		}
	}

	// Set final total now that we know it, so progress bar hits 100%.
	if totalBytes <= 0 && received > 0 {
		s3ops.AddTransferTotal(taskID, received)
	}

	if received == 0 {
		return fmt.Errorf("未收到任何数据")
	}
	return nil
}

// installMacOS handles DMG or ZIP installation on macOS.
func installMacOS(taskID, dlPath, installerType string) error {
	if _, err := os.Stat(dlPath); os.IsNotExist(err) {
		return fmt.Errorf("安装包不存在：%s", dlPath)
	}

	appName := "云卷.app"
	appsDir := "/Applications"
	targetApp := filepath.Join(appsDir, appName)

	switch installerType {
	case "dmg":
		return installMacOSDMG(dlPath, appName, appsDir, targetApp)
	default:
		return installMacOSZip(dlPath, appName, appsDir, targetApp)
	}
}

func installMacOSDMG(dlPath, appName, appsDir, targetApp string) error {
	// Mount the DMG. Use -plist for machine-readable output.
	out, err := exec.Command("hdiutil", "attach", "-nobrowse", "-noautoopen", "-plist", dlPath).CombinedOutput()
	if err != nil {
		return fmt.Errorf("挂载 DMG 失败：%s（%v）", strings.TrimSpace(string(out)), err)
	}

	// Parse the mount point from the plist output.
	mountPoint := parseMountPointFromPlist(string(out))
	if mountPoint == "" {
		// Fallback: scan /Volumes for the newly added volume.
		mountPoint, _ = findNewMountPoint()
	}
	if mountPoint == "" {
		exec.Command("hdiutil", "detach", dlPath, "-quiet").Run()
		return fmt.Errorf("无法确定 DMG 挂载点")
	}

	mountedApp := filepath.Join(mountPoint, appName)
	if _, err := os.Stat(mountedApp); os.IsNotExist(err) {
		exec.Command("hdiutil", "detach", mountPoint, "-quiet").Run()
		return fmt.Errorf("DMG 内未找到 %s", appName)
	}

	// Remove old app if it exists.
	if _, err := os.Stat(targetApp); err == nil {
		if err := os.RemoveAll(targetApp); err != nil {
			exec.Command("hdiutil", "detach", mountPoint, "-quiet").Run()
			return fmt.Errorf("删除旧应用失败：%w", err)
		}
	}

	// Copy new app.
	copyOut, copyErr := exec.Command("cp", "-R", mountedApp, appsDir).CombinedOutput()
	detachOut, detachErr := exec.Command("hdiutil", "detach", mountPoint, "-quiet").CombinedOutput()
	if detachErr != nil {
		log.Printf("[app_install] detach warning: %s", strings.TrimSpace(string(detachOut)))
	}
	if copyErr != nil {
		return fmt.Errorf("复制应用失败：%s（%v）", strings.TrimSpace(string(copyOut)), copyErr)
	}

	// Strip quarantine.
	exec.Command("xattr", "-cr", targetApp).Run()

	return nil
}

func installMacOSZip(dlPath, appName, appsDir, targetApp string) error {
	// Remove old app if it exists.
	if _, err := os.Stat(targetApp); err == nil {
		if err := os.RemoveAll(targetApp); err != nil {
			return fmt.Errorf("删除旧应用失败：%w", err)
		}
	}

	out, err := exec.Command("unzip", "-o", dlPath, "-d", appsDir).CombinedOutput()
	if err != nil {
		return fmt.Errorf("解压失败：%s（%v）", strings.TrimSpace(string(out)), err)
	}

	// Strip quarantine.
	exec.Command("xattr", "-cr", targetApp).Run()

	return nil
}

// parseMountPointFromPlist extracts the mount point from hdiutil -plist output.
// The plist contains a "mount-point" key under each system-entities entry.
func parseMountPointFromPlist(plist string) string {
	// The plist contains <key>mount-point</key> followed by a <string> value.
	// Whitespace/newlines vary, so scan in two steps instead of matching both tags.
	key := "<key>mount-point</key>"
	idx := strings.Index(plist, key)
	if idx < 0 {
		return ""
	}
	remaining := plist[idx+len(key):]
	startTag := "<string>"
	startIdx := strings.Index(remaining, startTag)
	if startIdx < 0 {
		return ""
	}
	start := startIdx + len(startTag)
	end := strings.Index(remaining[start:], "</string>")
	if end < 0 {
		return ""
	}
	return remaining[start : start+end]
}

// findNewMountPoint scans /Volumes to find a non-standard volume.
// Called as fallback when plist parsing fails.
func findNewMountPoint() (string, error) {
	knownVolumes := map[string]bool{
		"Macintosh HD": true,
		"Recovery":     true,
		"Update":       true,
		"Preboot":      true,
		"VM":           true,
	}

	entries, err := os.ReadDir("/Volumes")
	if err != nil {
		return "", fmt.Errorf("读取 /Volumes 失败：%w", err)
	}

	for _, entry := range entries {
		name := entry.Name()
		if !knownVolumes[name] && entry.IsDir() {
			return filepath.Join("/Volumes", name), nil
		}
	}

	return "", nil
}

// installWindows handles EXE or ZIP installation on Windows.
func installWindows(taskID, dlPath, installerType string) error {
	switch installerType {
	case "exe":
		cmd := exec.Command(dlPath, "/SILENT", "/CLOSEAPPLICATIONS", "/NORESTART", "/SP-", "/NOCANCEL")
		if err := cmd.Start(); err != nil {
			return fmt.Errorf("启动安装程序失败：%w", err)
		}
		time.Sleep(500 * time.Millisecond)
		return nil
	default:
		return fmt.Errorf("请使用 installer (.exe) 版本进行自动更新")
	}
}

// installLinux handles AppImage or tarball installation on Linux.
func installLinux(taskID, dlPath, installerType string) error {
	switch installerType {
	case "appimage":
		currentExe, err := os.Executable()
		if err != nil {
			return fmt.Errorf("获取当前可执行路径失败：%w", err)
		}
		targetPath := currentExe

		input, err := os.ReadFile(dlPath)
		if err != nil {
			return fmt.Errorf("读取安装包失败：%w", err)
		}
		if err := os.WriteFile(targetPath, input, 0755); err != nil {
			return fmt.Errorf("替换应用失败：%w", err)
		}
		return nil

	default:
		// tarball
		currentExe, err := os.Executable()
		if err != nil {
			return fmt.Errorf("获取当前可执行路径失败：%w", err)
		}
		installDir := filepath.Dir(currentExe)

		out, err := exec.Command("tar", "-xzf", dlPath, "--strip-components=1", "-C", installDir).CombinedOutput()
		if err != nil {
			return fmt.Errorf("解压失败：%s（%v）", strings.TrimSpace(string(out)), err)
		}
		return nil
	}
}

// relaunchApp starts the newly installed application.
func relaunchApp() {
	switch runtime.GOOS {
	case "darwin":
		exec.Command("open", "-n", "/Applications/云卷.app/Contents/MacOS/云卷").Start()
	case "windows":
		// The installer handles relaunch; just exit.
	case "linux":
		currentExe, err := os.Executable()
		if err == nil {
			exec.Command(currentExe).Start()
		}
	}
}

// finishTransferError marks the transfer task as failed with an error message.
func finishTransferError(taskID, msg string) {
	log.Printf("[app_install] %s: %s", taskID, msg)
	s3ops.FinishQueuedTransfer(taskID, fmt.Errorf("%s", msg))
}
