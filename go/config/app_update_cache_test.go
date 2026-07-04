package config

import (
	"os"
	"path/filepath"
	"testing"
)

func TestUsableCachedInstallerMatchesSize(t *testing.T) {
	root := t.TempDir()
	path := filepath.Join(root, "pkg.dmg")
	if err := os.WriteFile(path, []byte("12345"), 0o644); err != nil {
		t.Fatal(err)
	}
	ok, err := UsableCachedInstaller(path, 5)
	if err != nil || !ok {
		t.Fatalf("want usable size=5, got ok=%v err=%v", ok, err)
	}
	ok, err = UsableCachedInstaller(path, 4)
	if err != nil || ok {
		t.Fatalf("want not usable on size mismatch, got ok=%v err=%v", ok, err)
	}
}
