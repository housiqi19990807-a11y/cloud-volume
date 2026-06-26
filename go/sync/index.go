// Index tracks the last-known state of each path on both local and remote
// sides so reconcile can diff against it. Backed by bbolt so reads and writes
// are per-key O(1) and memory stays flat regardless of file count, instead of
// loading the entire index into a Go map like the earlier JSON approach.
//
// Each profile owns one bbolt DB file at runtime/sync/<profileID>/index.db.
// Entry values are JSON-encoded IndexEntry records (tens of bytes each); the
// path key is the slash-separated relative path.
package sync

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"time"

	bolt "go.etcd.io/bbolt"
)

// IndexEntry records the last synchronized attributes for a single relative path.
type IndexEntry struct {
	LocalSize    int64 `json:"localSize,omitempty"`
	LocalMTime   int64 `json:"localMTime,omitempty"`
	RemoteSize   int64 `json:"remoteSize,omitempty"`
	RemoteMTime  int64 `json:"remoteMTime,omitempty"`
	LastSyncedAt int64 `json:"lastSyncedAt,omitempty"`
}

// bbolt buckets keep entry data and metadata separated.
var (
	entriesBucket = []byte("entries")
	metaBucket    = []byte("meta")
	lastSyncKey   = []byte("lastSyncAt")
)

// Index wraps an open bbolt DB for one sync profile.
type Index struct {
	db *bolt.DB
}

// indexDBPath returns the per-profile bbolt file path under the runtime root.
func indexDBPath(runtimeRoot, profileID string) string {
	return filepath.Join(runtimeRoot, "sync", profileID, "index.db")
}

// openIndex opens (or creates) the bbolt DB for a profile. The caller must
// Close it when finished, typically at the end of a reconcile pass.
func openIndex(runtimeRoot, profileID string) (*Index, error) {
	path := indexDBPath(runtimeRoot, profileID)
	if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
		return nil, fmt.Errorf("create sync index dir: %w", err)
	}
	db, err := bolt.Open(path, 0o600, &bolt.Options{Timeout: 5 * time.Second})
	if err != nil {
		return nil, fmt.Errorf("open sync index db: %w", err)
	}
	err = db.Update(func(tx *bolt.Tx) error {
		if _, err := tx.CreateBucketIfNotExists(entriesBucket); err != nil {
			return fmt.Errorf("create entries bucket: %w", err)
		}
		if _, err := tx.CreateBucketIfNotExists(metaBucket); err != nil {
			return fmt.Errorf("create meta bucket: %w", err)
		}
		return nil
	})
	if err != nil {
		db.Close()
		return nil, err
	}
	return &Index{db: db}, nil
}

// Close releases the underlying bbolt DB handle.
func (idx *Index) Close() error {
	if idx == nil || idx.db == nil {
		return nil
	}
	return idx.db.Close()
}

// GetEntry reads a single index entry by relative path. Returns a zero value
// and ok=false when the key is absent.
func (idx *Index) GetEntry(rel string) (IndexEntry, bool) {
	var entry IndexEntry
	var found bool
	_ = idx.db.View(func(tx *bolt.Tx) error {
		b := tx.Bucket(entriesBucket)
		raw := b.Get([]byte(rel))
		if raw == nil {
			return nil
		}
		found = true
		return json.Unmarshal(raw, &entry)
	})
	return entry, found
}

// PutEntry writes or replaces a single index entry.
func (idx *Index) PutEntry(rel string, entry IndexEntry) error {
	return idx.db.Update(func(tx *bolt.Tx) error {
		b := tx.Bucket(entriesBucket)
		body, err := json.Marshal(entry)
		if err != nil {
			return fmt.Errorf("encode index entry: %w", err)
		}
		return b.Put([]byte(rel), body)
	})
}

// DeleteEntry removes a single index entry.
func (idx *Index) DeleteEntry(rel string) error {
	return idx.db.Update(func(tx *bolt.Tx) error {
		return tx.Bucket(entriesBucket).Delete([]byte(rel))
	})
}

// EachEntry iterates over all stored entries, keyed by relative path. The
// callback may return false to stop iteration early. Used by diff to build the
// union key set lazily without loading everything into a map at once.
func (idx *Index) EachEntry(fn func(rel string, entry IndexEntry) bool) error {
	return idx.db.View(func(tx *bolt.Tx) error {
		b := tx.Bucket(entriesBucket)
		c := b.Cursor()
		for k, v := c.First(); k != nil; k, v = c.Next() {
			var entry IndexEntry
			if err := json.Unmarshal(v, &entry); err != nil {
				continue
			}
			if !fn(string(k), entry) {
				return nil
			}
		}
		return nil
	})
}

// CountEntries returns the number of indexed paths.
func (idx *Index) CountEntries() int {
	var n int
	_ = idx.db.View(func(tx *bolt.Tx) error {
		n = tx.Bucket(entriesBucket).Stats().KeyN
		return nil
	})
	return n
}

// SetLastSync records the completion timestamp of the latest reconcile pass.
func (idx *Index) SetLastSync(ts int64) error {
	return idx.db.Update(func(tx *bolt.Tx) error {
		return tx.Bucket(metaBucket).Put(lastSyncKey, []byte(fmt.Sprintf("%d", ts)))
	})
}

// LastSync returns the most recent reconcile completion timestamp, or zero.
func (idx *Index) LastSync() int64 {
	var raw []byte
	_ = idx.db.View(func(tx *bolt.Tx) error {
		raw = tx.Bucket(metaBucket).Get(lastSyncKey)
		return nil
	})
	if len(raw) == 0 {
		return 0
	}
	var n int64
	_, _ = fmt.Sscanf(string(raw), "%d", &n)
	return n
}

// nowNano is a testable indirection for the current time.
var nowNano = func() int64 { return time.Now().UnixNano() }
