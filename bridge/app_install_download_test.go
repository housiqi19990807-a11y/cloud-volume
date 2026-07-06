// Tests for the post-download size integrity check used by the in-app
// updater. Mirrors occasionally serve a truncated body (or an HTML error page
// with HTTP 200), so downloadInstaller must verify the saved payload matches
// the GitHub-reported asset size before handing it to hdiutil/unzip.

package main

import (
	"crypto/sha256"
	"encoding/hex"
	"fmt"
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

// A file whose SHA-256 matches the GitHub digest should pass.
func TestVerifyDownloadedDigestMatch(t *testing.T) {
	content := []byte("hello installer")
	sum := sha256.Sum256(content)
	digest := "sha256:" + hex.EncodeToString(sum[:])

	path := filepath.Join(t.TempDir(), "pkg.dmg")
	if err := os.WriteFile(path, content, 0o644); err != nil {
		t.Fatal(err)
	}
	if err := verifyDownloadedDigest(path, digest); err != nil {
		t.Fatalf("want nil, got %v", err)
	}
}

// A file whose content differs from the expected digest should be removed.
func TestVerifyDownloadedDigestMismatchRemovesFile(t *testing.T) {
	// Use the digest of a different payload so the check fails.
	other := []byte("honest download")
	sum := sha256.Sum256(other)
	digest := "sha256:" + hex.EncodeToString(sum[:])

	path := filepath.Join(t.TempDir(), "pkg.dmg")
	if err := os.WriteFile(path, []byte("corrupt mirror body"), 0o644); err != nil {
		t.Fatal(err)
	}
	err := verifyDownloadedDigest(path, digest)
	if err == nil {
		t.Fatal("want error on digest mismatch, got nil")
	}
	if _, statErr := os.Stat(path); !os.IsNotExist(statErr) {
		t.Fatalf("want file removed after mismatch, stat err = %v", statErr)
	}
}

// An empty or malformed digest is ignored (we cannot verify, so we don't block).
func TestVerifyDownloadedDigestMalformed(t *testing.T) {
	cases := []string{"", "md5:deadbeef", "sha256:not-hex"}
	for i, digest := range cases {
		path := filepath.Join(t.TempDir(), "pkg.dmg")
		if err := os.WriteFile(path, []byte("placeholder"), 0o644); err != nil {
			t.Fatalf("case %d: %v", i, err)
		}
		if err := verifyDownloadedDigest(path, digest); err != nil {
			t.Fatalf("case %d (%q): want nil, got %v", i, digest, err)
		}
	}
}

func TestIsRetryableFetchError(t *testing.T) {
	retryable := []string{
		"读取响应失败：stream error: stream ID 1; INTERNAL_ERROR; received from peer",
		"请求失败：connection reset by peer",
		"读取响应失败：unexpected EOF",
	}
	for _, msg := range retryable {
		if !isRetryableFetchError(fmt.Errorf("%s", msg)) {
			t.Fatalf("want retryable: %q", msg)
		}
	}
	nonRetryable := []string{
		"HTTP 403",
		"写入文件失败：no space left on device",
		"打开文件失败：permission denied",
	}
	for _, msg := range nonRetryable {
		if isRetryableFetchError(fmt.Errorf("%s", msg)) {
			t.Fatalf("want non-retryable: %q", msg)
		}
	}
}
