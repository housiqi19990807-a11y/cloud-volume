// Baidu Pan backend tests pin the path rewriting rules used by list/upload/move flows.
package storage

import (
	"strings"
	"testing"

	storageconfig "remote-storage/go/config"
)

func TestBaiduPanCleanKey(t *testing.T) {
	t.Parallel()

	cases := map[string]string{
		"":             "",
		"/":            "",
		"docs":         "docs",
		"/docs//a.txt": "docs/a.txt",
		"docs/../a":    "a",
	}
	for input, want := range cases {
		if got := baiduPanCleanKey(input); got != want {
			t.Fatalf("clean key %q: got %q want %q", input, got, want)
		}
	}
}

func TestBaiduPanMoveTarget(t *testing.T) {
	t.Parallel()

	dir, name := baiduPanMoveTarget("folder/report.txt")
	if dir != "/folder" || name != "report.txt" {
		t.Fatalf("unexpected move target dir=%q name=%q", dir, name)
	}

	rootDir, rootName := baiduPanMoveTarget("top.txt")
	if rootDir != "/" || rootName != "top.txt" {
		t.Fatalf("unexpected root move target dir=%q name=%q", rootDir, rootName)
	}
}

func TestBaiduPanTempUploadPath(t *testing.T) {
	t.Parallel()

	got := baiduPanTempUploadPath("archive.zip", "folder/archive.zip")
	if !strings.HasPrefix(got, baiduPanUploadRoot+"/") {
		t.Fatalf("temp upload path should stay under upload root, got %q", got)
	}
	if !strings.HasSuffix(got, "-archive.zip") {
		t.Fatalf("temp upload path should preserve the filename suffix, got %q", got)
	}
}

func TestBaiduPanBucketLabel(t *testing.T) {
	t.Parallel()

	cfg := storageconfig.RemoteStorageConfig{
		StorageType:      storageconfig.StorageTypeBaiduPan,
		MappedBucketName: "我的百度网盘",
	}
	if got := baiduPanBucketLabel(cfg); got != "我的百度网盘" {
		t.Fatalf("bucket label: got %q", got)
	}
}
