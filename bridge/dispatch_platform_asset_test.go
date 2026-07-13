// Tests architecture-sensitive desktop release asset selection.
package main

import "testing"

func TestMatchWindowsPrefersNativeARM64Asset(t *testing.T) {
	assets := []releaseAsset{
		{Name: "yunjuan-windows-amd64.zip"},
		{Name: "yunjuan-windows-arm64-installer.exe"},
	}
	got := matchWindows(assets, "arm64")
	if got == nil || got.Asset.Name != "yunjuan-windows-arm64-installer.exe" || got.InstallerType != "exe" {
		t.Fatalf("matchWindows() = %#v, want native ARM64 installer", got)
	}
}

func TestMatchWindowsARM64FallsBackToAMD64(t *testing.T) {
	assets := []releaseAsset{{Name: "yunjuan-windows-amd64.zip"}}
	got := matchWindows(assets, "arm64")
	if got == nil || got.Asset.Name != "yunjuan-windows-amd64.zip" || got.InstallerType != "zip" {
		t.Fatalf("matchWindows() = %#v, want amd64 zip fallback", got)
	}
}

func TestMatchWindowsAMD64DoesNotSelectARM64(t *testing.T) {
	assets := []releaseAsset{{Name: "yunjuan-windows-arm64.zip"}}
	if got := matchWindows(assets, "amd64"); got != nil {
		t.Fatalf("matchWindows() = %#v, want no incompatible ARM64 fallback", got)
	}
}
