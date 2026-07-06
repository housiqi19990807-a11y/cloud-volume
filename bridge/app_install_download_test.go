// Tests for the post-download size integrity check used by the in-app
// updater. Mirrors occasionally serve a truncated body (or an HTML error page
// with HTTP 200), so downloadInstaller must verify the saved payload matches
// the GitHub-reported asset size before handing it to hdiutil/unzip.

package main

import (
	"os"
	"path/filepath"
	"testing"
)

// A file whose on-disk size equals the expected size should pass verification.
func TestVerifyDownloadedSizeMatch(t *testing.T) {
	path := filepath.Join(t.TempDir(), "pkg.dmg")
	if err := os.WriteFile(path, []byte("12345"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := verifyDownloadedSize(path, 5); err != nil {
		t.Fatalf("want nil, got %v", err)
	}
}

// A truncated file should be rejected and removed so the next attempt starts
// from scratch instead of resuming a corrupt prefix.
func TestVerifyDownloadedSizeMismatchRemovesFile(t *testing.T) {
	path := filepath.Join(t.TempDir(), "pkg.dmg")
	if err := os.WriteFile(path, []byte("trunc"), 0o644); err != nil {
		t.Fatal(err)
	}
	err := verifyDownloadedSize(path, 999)
	if err == nil {
		t.Fatal("want error on size mismatch, got nil")
	}
	if _, statErr := os.Stat(path); !os.IsNotExist(statErr) {
		t.Fatalf("want file removed after mismatch, stat err = %v", statErr)
	}
}

// When no expected size is known we cannot verify, so the helper is a no-op.
func TestVerifyDownloadedSizeNoExpected(t *testing.T) {
	path := filepath.Join(t.TempDir(), "pkg.dmg")
	if err := os.WriteFile(path, []byte("anything"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := verifyDownloadedSize(path, 0); err != nil {
		t.Fatalf("want nil for expectedSize<=0, got %v", err)
	}
}

