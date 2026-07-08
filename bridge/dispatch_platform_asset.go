// Platform-specific release asset matching for in-app updates.
//
// Asset name suffixes are the single source of truth for which GitHub release
// file to download and how to install it. They mirror the artifacts produced
// by scripts/build_desktop_packages.sh so the naming convention stays in sync.
//
// Matching uses exact filename suffixes, not loose substrings, so CLI packages
// (e.g. yunjuan-cli-full-windows-amd64.zip) are never confused with desktop
// packages (e.g. yunjuan-windows-amd64.zip).
package main
import (
	"encoding/json"
	"fmt"
	"runtime"
	"strings"
)
// releaseAsset mirrors the GitHub release asset fields the frontend needs.
type releaseAsset struct {
	Name        string `json:"name"`
	DownloadURL string `json:"downloadUrl"`
	Size        int64  `json:"size"`
	ContentType string `json:"contentType"`
	Digest      string `json:"digest"`
}
// platformAssetResult is returned to the frontend: the matched asset plus the
// installer type the Go installer switch expects ("zip", "dmg", "exe", ...).
type platformAssetResult struct {
	Asset        releaseAsset `json:"asset"`
	Platform     string       `json:"platform"`
	InstallerType string      `json:"installerType"`
}
// matchPlatformAssetInput is the JSON payload from the frontend.
type matchPlatformAssetInput struct {
	Assets            []releaseAsset `json:"assets"`
	RuntimeArchitecture string        `json:"runtimeArchitecture"`
}
// matchPlatformAsset picks the correct release asset for this host. The
// frontend passes the full asset list from the GitHub API and gets back the
// one asset to download plus its installer type.
func matchPlatformAsset(args json.RawMessage) (any, error) {
	var input matchPlatformAssetInput
	if err := decodeArgs(args, &input); err != nil {
		return nil, err
	}
	if len(input.Assets) == 0 {
		return nil, fmt.Errorf("no assets provided")
	}
	arch := input.RuntimeArchitecture
	if arch == "" {
		arch = runtime.GOARCH
	}
	var result *platformAssetResult
	switch runtime.GOOS {
	case "darwin":
		result = matchMacOS(input.Assets, arch)
	case "windows":
		result = matchWindows(input.Assets)
	case "linux":
		result = matchLinux(input.Assets)
	}
	if result == nil {
		return nil, fmt.Errorf("no matching asset for %s/%s", runtime.GOOS, arch)
	}
	return result, nil
}
// matchMacOS matches yunjuan-macos-<arch>.dmg or .zip.
func matchMacOS(assets []releaseAsset, arch string) *platformAssetResult {
	preferred := arch
	if preferred != "arm64" && preferred != "amd64" {
		preferred = ""
	}
	fallback := ""
	if preferred == "arm64" {
		fallback = "amd64"
	} else if preferred == "amd64" {
		fallback = "arm64"
	}
	// Ordered priority list: preferred-arch dmg/zip, universal, fallback-arch.
	type candidate struct {
		suffix        string
		installerType string
	}
	var cands []candidate
	if preferred != "" {
		cands = append(cands,
			candidate{"-macos-" + preferred + ".dmg", "dmg"},
			candidate{"-macos-" + preferred + ".zip", "zip"},
		)
	}
	cands = append(cands,
		candidate{"-macos-universal.dmg", "dmg"},
		candidate{"-macos-universal.zip", "zip"},
	)
	if fallback != "" {
		cands = append(cands,
			candidate{"-macos-" + fallback + ".dmg", "dmg"},
			candidate{"-macos-" + fallback + ".zip", "zip"},
		)
	}
	if preferred == "" && fallback == "" {
		cands = append(cands,
			candidate{"-macos-arm64.dmg", "dmg"},
			candidate{"-macos-arm64.zip", "zip"},
			candidate{"-macos-amd64.dmg", "dmg"},
			candidate{"-macos-amd64.zip", "zip"},
		)
	}
	for _, c := range cands {
		if a := findAssetBySuffix(assets, c.suffix); a != nil {
			return &platformAssetResult{Asset: *a, Platform: "macOS", InstallerType: c.installerType}
		}
	}
	return nil
}
// matchWindows matches yunjuan-windows-amd64.zip, then installer.exe.
func matchWindows(assets []releaseAsset) *platformAssetResult {
	if a := findAssetBySuffix(assets, "-windows-amd64.zip"); a != nil {
		return &platformAssetResult{Asset: *a, Platform: "Windows", InstallerType: "zip"}
	}
	if a := findAssetBySuffix(assets, "-windows-amd64-installer.exe"); a != nil {
		return &platformAssetResult{Asset: *a, Platform: "Windows", InstallerType: "exe"}
	}
	return nil
}
// matchLinux matches yunjuan-linux-amd64.AppImage, then .tar.gz.
func matchLinux(assets []releaseAsset) *platformAssetResult {
	if a := findAssetBySuffix(assets, "-linux-amd64.appimage"); a != nil {
		return &platformAssetResult{Asset: *a, Platform: "Linux", InstallerType: "appimage"}
	}
	if a := findAssetBySuffix(assets, "-linux-amd64.tar.gz"); a != nil {
		return &platformAssetResult{Asset: *a, Platform: "Linux", InstallerType: "tarball"}
	}
	return nil
}
// findAssetBySuffix returns the first asset whose name ends with suffix
// (case-insensitive). Exact suffix match avoids CLI/desktop confusion.
func findAssetBySuffix(assets []releaseAsset, suffix string) *releaseAsset {
	s := strings.ToLower(suffix)
	for i := range assets {
		if strings.HasSuffix(strings.ToLower(assets[i].Name), s) {
			return &assets[i]
		}
	}
	return nil
}
