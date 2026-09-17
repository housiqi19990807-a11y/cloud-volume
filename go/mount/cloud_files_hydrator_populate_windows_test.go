//go:build windows && cgo

package mount

import (
	"errors"
	"path/filepath"
	"testing"
)

// TestPopulateChildDirectoriesSeedsEveryDirectoryLevel pins the eager
// recursive projection that keeps headless mounts usable: without it,
// tree/deep stays invisible unless a shell happens to enumerate tree.
func TestPopulateChildDirectoriesSeedsEveryDirectoryLevel(t *testing.T) {
	visited := map[string]int{}
	hydrator := &cloudFilesHydrator{}
	items := map[string][]cloudPlaceholderInfo{
		`C:\root`: {
			{RelativePath: "tree", IsDirectory: true},
			{RelativePath: "seed.txt", FileSize: 4},
		},
		`C:\root\tree`: {
			{RelativePath: "deep", IsDirectory: true},
		},
		`C:\root\tree\deep`: {
			{RelativePath: "b.txt", FileSize: 6},
		},
	}
	var populate func(string) error
	populate = func(localPath string) error {
		cleanPath := filepath.Clean(localPath)
		visited[cleanPath]++
		return hydrator.populateChildDirectories(cleanPath, items[cleanPath], populate)
	}

	err := populate(`C:\root`)
	if err != nil {
		t.Fatalf("PopulatePlaceholders returned error: %v", err)
	}
	want := map[string]int{
		`C:\root`:           1,
		`C:\root\tree`:      1,
		`C:\root\tree\deep`: 1,
	}
	for path, count := range want {
		if visited[path] != count {
			t.Fatalf("populate visited %q %d times, want %d", path, visited[path], count)
		}
	}
}

// TestPopulateChildDirectoriesStopsOnError ensures a failed child listing is
// surfaced to the mount caller instead of leaving a silently partial tree.
func TestPopulateChildDirectoriesStopsOnError(t *testing.T) {
	visited := map[string]int{}
	hydrator := &cloudFilesHydrator{}
	items := map[string][]cloudPlaceholderInfo{
		`C:\root`: {
			{RelativePath: "broken", IsDirectory: true},
			{RelativePath: "ok", IsDirectory: true},
		},
		`C:\root\broken`: nil,
	}
	var populate func(string) error
	populate = func(localPath string) error {
		cleanPath := filepath.Clean(localPath)
		visited[cleanPath]++
		if cleanPath == `C:\root\broken` {
			return errors.New("remote listing failed")
		}
		return hydrator.populateChildDirectories(cleanPath, items[cleanPath], populate)
	}

	err := populate(`C:\root`)
	if err == nil {
		t.Fatal("PopulatePlaceholders must fail when a child directory cannot be listed")
	}
	if filepath.Clean(err.Error()) == "" {
		t.Fatal("PopulatePlaceholders error must carry context")
	}
	if visited[`C:\root\ok`] != 0 {
		t.Fatal("population must stop at the first failing child directory")
	}
}
