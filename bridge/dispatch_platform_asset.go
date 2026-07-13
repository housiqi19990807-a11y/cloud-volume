// Platform-specific release asset matching for in-app updates.
//
// Asset names are the single source of truth for which GitHub release file to
// download and how to install it. They mirror the artifacts produced by
// scripts/build_desktop_packages.sh so the naming convention stays in sync.
//
// Matching uses exact full filenames, not loose suffixes, so CLI packages
// (e.g. yunjuan-cli-full-windows-amd64.zip) are never confused with desktop
// packages (e.g. yunjuan-windows-amd64.zip) — both end with "-windows-amd64.zip".
package main

import (
	"encoding/json"
	"fmt"
	"runtime"
	"strings"
)

// artifactPrefix mirrors ARTIFACT_PREFIX in build_desktop_packages.sh.
const artifactPrefix = "yunjuan"

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
	Asset         releaseAsset `json:"asset"`
	Platform      string       `json:"platform"`
	InstallerType string       `json:"installerType"`
}

// matchPlatformAssetInput is the JSON payload from the frontend.
type matchPlatformAssetInput struct {
	Assets              []releaseAsset `json:"assets"`
	RuntimeArchitecture string         `json:"runtimeArchitecture"`
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
		result = matchWindows(input.Assets, arch)
	case "linux":
		result = matchLinux(input.Assets)
	}
	if result == nil {
		return nil, fmt.Errorf("no matching asset for %s/%s", runtime.GOOS, arch)
	}
	return result, nil
}

// matchMacOS matches exact filenames: yunjuan-macos-<arch>.dmg or .zip.
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
	// Ordered priority: preferred-arch dmg/zip, universal, fallback-arch.
	type candidate struct {
		filename      string
		installerType string
	}
	var cands []candidate
	if preferred != "" {
		cands = append(cands,
			candidate{artifactPrefix + "-macos-" + preferred + ".dmg", "dmg"},
			candidate{artifactPrefix + "-macos-" + preferred + ".zip", "zip"},
		)
	}
	cands = append(cands,
		candidate{artifactPrefix + "-macos-universal.dmg", "dmg"},
		candidate{artifactPrefix + "-macos-universal.zip", "zip"},
	)
	if fallback != "" {
		cands = append(cands,
			candidate{artifactPrefix + "-macos-" + fallback + ".dmg", "dmg"},
			candidate{artifactPrefix + "-macos-" + fallback + ".zip", "zip"},
		)
	}
	if preferred == "" && fallback == "" {
		cands = append(cands,
			candidate{artifactPrefix + "-macos-arm64.dmg", "dmg"},
			candidate{artifactPrefix + "-macos-arm64.zip", "zip"},
			candidate{artifactPrefix + "-macos-amd64.dmg", "dmg"},
			candidate{artifactPrefix + "-macos-amd64.zip", "zip"},
		)
	}
	for _, c := range cands {
		if a := findAssetByName(assets, c.filename); a != nil {
			return &platformAssetResult{Asset: *a, Platform: "macOS", InstallerType: c.installerType}
		}
	}
	return nil
}

// matchWindows prefers the native package and lets ARM64 fall back to amd64,
// which Windows 11 on ARM can execute, while releases transition to dual arch.
func matchWindows(assets []releaseAsset, arch string) *platformAssetResult {
	architectures := []string{"amd64"}
	if arch == "arm64" {
		architectures = []string{"arm64", "amd64"}
	}
	for _, candidateArch := range architectures {
		if a := findAssetByName(assets, artifactPrefix+"-windows-"+candidateArch+".zip"); a != nil {
			return &platformAssetResult{Asset: *a, Platform: "Windows", InstallerType: "zip"}
		}
		if a := findAssetByName(assets, artifactPrefix+"-windows-"+candidateArch+"-installer.exe"); a != nil {
			return &platformAssetResult{Asset: *a, Platform: "Windows", InstallerType: "exe"}
		}
	}
	return nil
}

// matchLinux matches exact filenames: yunjuan-linux-amd64.AppImage, then .tar.gz.
func matchLinux(assets []releaseAsset) *platformAssetResult {
	if a := findAssetByName(assets, artifactPrefix+"-linux-amd64.AppImage"); a != nil {
		return &platformAssetResult{Asset: *a, Platform: "Linux", InstallerType: "appimage"}
	}
	if a := findAssetByName(assets, artifactPrefix+"-linux-amd64.tar.gz"); a != nil {
		return &platformAssetResult{Asset: *a, Platform: "Linux", InstallerType: "tarball"}
	}
	return nil
}

// findAssetByName returns the first asset whose name matches exactly
// (case-insensitive). Full-name matching prevents CLI packages from matching
// desktop packages, since yunjuan-cli-full-windows-amd64.zip != yunjuan-windows-amd64.zip.
func findAssetByName(assets []releaseAsset, name string) *releaseAsset {
	n := strings.ToLower(name)
	for i := range assets {
		if strings.ToLower(assets[i].Name) == n {
			return &assets[i]
		}
	}
	return nil
}
