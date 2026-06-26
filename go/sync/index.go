// Index tracks the last-known state of each path on both local and remote
// sides so reconcile can diff against it instead of treating every run as a
// full mirror. It is the lightweight alternative to embedding a git repo.
//
// Only size + mtime are tracked because ETag availability differs across
// backends (S3 multipart ETags are unreliable, Baidu Pan has no ETag at all),
// so a uniform signature keeps behavior consistent across providers.
package sync

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"time"
)

// IndexEntry records the last synchronized attributes for a single relative path.
type IndexEntry struct {
	LocalSize    int64 `json:"localSize,omitempty"`
	LocalMTime   int64 `json:"localMTime,omitempty"`  // unix nano
	RemoteSize   int64 `json:"remoteSize,omitempty"`
	RemoteMTime  int64 `json:"remoteMTime,omitempty"` // unix nano
	LastSyncedAt int64 `json:"lastSyncedAt,omitempty"`
}

// Index is the persisted map keyed by slash-separated relative path.
type Index struct {
	Entries map[string]IndexEntry `json:"entries"`
}

// newIndex returns an empty index ready for population.
func newIndex() *Index {
	return &Index{Entries: map[string]IndexEntry{}}
}

// indexDir returns the per-profile index directory under the runtime root.
func indexDir(runtimeRoot, profileID string) string {
	return filepath.Join(runtimeRoot, "sync", profileID)
}

// indexPath returns the JSON index file for a profile.
func indexPath(runtimeRoot, profileID string) string {
	return filepath.Join(indexDir(runtimeRoot, profileID), "index.json")
}

// loadIndex reads the persisted index, returning an empty one when absent.
func loadIndex(runtimeRoot, profileID string) (*Index, error) {
	data, err := os.ReadFile(indexPath(runtimeRoot, profileID))
	if os.IsNotExist(err) {
		return newIndex(), nil
	}
	if err != nil {
		return nil, fmt.Errorf("read sync index: %w", err)
	}
	var idx Index
	if err := json.Unmarshal(data, &idx); err != nil {
		return nil, fmt.Errorf("parse sync index: %w", err)
	}
	if idx.Entries == nil {
		idx.Entries = map[string]IndexEntry{}
	}
	return &idx, nil
}

// save persists the index to disk under the profile's runtime directory.
func (idx *Index) save(runtimeRoot, profileID string) error {
	dir := indexDir(runtimeRoot, profileID)
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return fmt.Errorf("create sync index dir: %w", err)
	}
	body, err := json.MarshalIndent(idx, "", "  ")
	if err != nil {
		return fmt.Errorf("encode sync index: %w", err)
	}
	return os.WriteFile(indexPath(runtimeRoot, profileID), body, 0o600)
}

// sortedKeys returns relative paths in stable order for deterministic iteration.
func (idx *Index) sortedKeys() []string {
	keys := make([]string, 0, len(idx.Entries))
	for k := range idx.Entries {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	return keys
}

// nowNano is a testable indirection for the current time.
var nowNano = func() int64 { return time.Now().UnixNano() }
