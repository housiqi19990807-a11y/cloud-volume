package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestBuildCrashReportIncludesExitAndArtifactFingerprints(t *testing.T) {
	root := t.TempDir()
	executable := filepath.Join(root, "cloud-volume-app.exe")
	if err := os.WriteFile(executable, []byte("runner"), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := os.MkdirAll(filepath.Join(root, "data"), 0o700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(root, "data", "app.so"), []byte("aot"), 0o600); err != nil {
		t.Fatal(err)
	}

	report := buildCrashReport(crashContext{
		Executable: executable,
		PID:        42,
		ExitCode:   0xC0000005,
	}, time.Date(2026, 7, 18, 9, 30, 0, 0, time.UTC), root, root)

	for _, expected := range []string{
		"0xC0000005, access violation",
		"Monitored PID: 42",
		"cloud-volume-app.exe: size=6",
		filepath.Join("data", "app.so") + ": size=3",
		"sha256=",
	} {
		if !strings.Contains(report, expected) {
			t.Fatalf("report missing %q:\n%s", expected, report)
		}
	}
}

func TestTailFileReturnsOnlyRequestedSuffix(t *testing.T) {
	path := filepath.Join(t.TempDir(), "test.log")
	if err := os.WriteFile(path, []byte("0123456789"), 0o600); err != nil {
		t.Fatal(err)
	}
	tail, err := tailFile(path, 4)
	if err != nil {
		t.Fatal(err)
	}
	if string(tail) != "6789" {
		t.Fatalf("tailFile() = %q, want %q", tail, "6789")
	}
}
