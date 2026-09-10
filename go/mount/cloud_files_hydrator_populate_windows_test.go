//go:build windows && cgo

package mount

import (
	"errors"
	"path/filepath"
	"testing"
)

// recordingHydrator is a minimal cloudFilesHydrator double: it records which
// directories the eager recursive projection visited, so tests can pin both
// full-tree seeding and fail-fast behavior without a live CFAPI connection.
type recordingHydrator struct {
	cloudFilesHydrator
	visits      map[string]int
	items       map[string][]cloudPlaceholderInfo
	failingPath string
}

func (h *recordingHydrator) listDirectoryPlaceholders(
	localPath string,
) ([]cloudPlaceholderInfo, error) {
	cleanPath := filepath.Clean(localPath)
	h.visits[cleanPath]++
	if cleanPath == h.failingPath {
		return nil, errors.New("remote listing failed")
	}
	return h.items[cleanPath], nil
}

// projectPlaceholders is stubbed because eager projection only decides what
// to seed here; placeholder creation itself is covered by provider tests.
func (h *recordingHydrator) projectPlaceholders(
	string,
	[]cloudPlaceholderInfo,
) error {
	return nil
}

// TestPopulateChildDirectoriesSeedsEveryDirectoryLevel pins the eager
// recursive projection that keeps headless mounts usable: without it,
// tree/deep stays invisible unless a shell happens to enumerate tree.
func TestPopulateChildDirectoriesSeedsEveryDirectoryLevel(t *testing.T) {
	visited := map[string]int{}
	hydrator := &recordingHydrator{
		cloudFilesHydrator: cloudFilesHydrator{
			placeholderInflight:  map[string]*cloudFilesPlaceholderFetch{},
			placeholderFetched:   map[string]cloudFilesPlaceholderCache{},
			projectedDirectories: map[string]map[string]cloudPlaceholderInfo{},
		},
		visits: visited,
		items: map[string][]cloudPlaceholderInfo{
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
		},
	}

	err := hydrator.PopulatePlaceholders(`C:\root`)
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
	hydrator := &recordingHydrator{
		cloudFilesHydrator: cloudFilesHydrator{
			placeholderInflight:  map[string]*cloudFilesPlaceholderFetch{},
			placeholderFetched:   map[string]cloudFilesPlaceholderCache{},
			projectedDirectories: map[string]map[string]cloudPlaceholderInfo{},
		},
		visits: visited,
		items: map[string][]cloudPlaceholderInfo{
			`C:\root`: {
				{RelativePath: "broken", IsDirectory: true},
				{RelativePath: "ok", IsDirectory: true},
			},
			`C:\root\broken`: nil,
		},
		failingPath: `C:\root\broken`,
	}

	err := hydrator.PopulatePlaceholders(`C:\root`)
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
