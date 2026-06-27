// reconcile.go drives a single sync pass: scan the local tree, list the remote
// prefix, diff against the index, aggregate renames, and return the final op
// list. It depends only on the storage.Backend abstraction so all providers
// (S3, WebDAV, Baidu Pan) are supported uniformly.
package sync

import (
	"context"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"strings"
	"time"

	storageops "remote-storage/go/storage"
)

// Reconciler runs reconcile passes for a profile against a backend.
type Reconciler struct {
	profile    SyncProfile
	backend    storageops.Backend
	runtimeRoot string
}

// NewReconciler constructs a reconciler bound to one profile and backend.
func NewReconciler(profile SyncProfile, backend storageops.Backend, runtimeRoot string) *Reconciler {
	return &Reconciler{profile: profile, backend: backend, runtimeRoot: runtimeRoot}
}

// ReconcileResult is the outcome of a single pass, returned to the scheduler.
type ReconcileResult struct {
	Ops      []Op `json:"ops"`
	Skipped  int  `json:"skipped"`
	Updated  bool `json:"updated"` // true if any op ran (caller persists index)
}

// Run scans both sides, diffs, aggregates renames, and returns the op plan.
// It does not execute the ops; the scheduler dispatches them to the transfer
// queue and persists the index only after they succeed.
func (rc *Reconciler) Run(ctx context.Context) (*ReconcileResult, error) {
	local, err := rc.scanLocal(ctx)
	if err != nil {
		return nil, fmt.Errorf("scan local: %w", err)
	}
	remote, err := rc.scanRemote(ctx)
	if err != nil {
		return nil, fmt.Errorf("scan remote: %w", err)
	}
	idx, err := openIndex(rc.runtimeRoot, rc.profile.ID)
	if err != nil {
		return nil, fmt.Errorf("open index: %w", err)
	}
	defer idx.Close()

	indexKeys, lookup := rc.indexView(idx)
	rawOps := classifyAll(rc.profile, local, remote, indexKeys, lookup)
	ops := rc.aggregateRenames(rawOps, local, remote)

	skipped := 0
	emitted := make([]Op, 0, len(ops))
	for _, op := range ops {
		if op.Kind == OpSkip {
			skipped++
			continue
		}
		emitted = append(emitted, op)
	}
	return &ReconcileResult{Ops: emitted, Skipped: skipped}, nil
}

// aggregateRenames pairs adds with deletes by size, converting upload/download
// ops into rename ops where a size match exists. Unmatched deletes remain.
func (rc *Reconciler) aggregateRenames(rawOps []rawOp, local map[string]localSide, remote map[string]remoteSide) []Op {
	pairs := newRenamePairs()

	// First pass: collect all deletes with their metadata.
	for _, ro := range rawOps {
		if ro.op.Kind != OpDeleteLocal && ro.op.Kind != OpDeleteRemote {
			continue
		}
		size := ro.localSize
		mtime := ro.localMTime
		if size == 0 {
			size = ro.remoteSize
		}
		if mtime == 0 {
			mtime = ro.remoteMTime
		}
		pairs.recordDelete(ro.op.RelPath, size, mtime, local[ro.op.RelPath].present, remote[ro.op.RelPath].present)
	}

	// Second pass: match adds (upload/download) against collected deletes.
	out := make([]Op, 0, len(rawOps))
	for _, ro := range rawOps {
		switch ro.op.Kind {
		case OpUpload, OpDownload:
			addSize := ro.localSize
			if addSize == 0 {
				addSize = ro.remoteSize
			}
			if del, ok := pairs.matchAdd(ro.op.RelPath, addSize); ok && rc.profile.Direction == DirectionTwoWay {
				out = append(out, Op{
					Kind:       OpRename,
					RelPath:    ro.op.RelPath,
					OldRelPath: del,
					Reason:     "rename_detected",
					Size:       addSize,
				})
				continue
			}
			ro.op.Size = addSize
			out = append(out, ro.op)
		case OpDeleteLocal, OpDeleteRemote:
			// Only emit if not absorbed into a rename.
			if !pairs.matched[ro.op.RelPath] {
				out = append(out, ro.op)
			}
		default:
			out = append(out, ro.op)
		}
	}
	return out
}

// scanLocal walks the profile's local directory, returning a relative-path map.
func (rc *Reconciler) scanLocal(ctx context.Context) (map[string]localSide, error) {
	out := map[string]localSide{}
	root := rc.profile.LocalPath
	info, err := os.Stat(root)
	if err != nil {
		if os.IsNotExist(err) {
			return out, nil
		}
		return nil, err
	}
	if !info.IsDir() {
		return nil, fmt.Errorf("local sync path is not a directory: %s", root)
	}
	err = filepath.WalkDir(root, func(path string, d fs.DirEntry, walkErr error) error {
		if walkErr != nil {
			return walkErr
		}
		if ctx.Err() != nil {
			return ctx.Err()
		}
		rel, ok := rc.localRelative(path)
		if !ok {
			return nil
		}
		if d.IsDir() {
			return nil
		}
		if matchesExclude(rel, rc.profile.ExcludePatterns) {
			if d.IsDir() {
				return filepath.SkipDir
			}
			return nil
		}
		info, err := d.Info()
		if err != nil {
			return nil
		}
		out[rel] = localSide{
			size:    info.Size(),
			mtime:   info.ModTime().UnixNano(),
			present: true,
		}
		return nil
	})
	if err != nil {
		return nil, err
	}
	return out, nil
}

// localRelative converts an absolute local path to a slash-separated key.
func (rc *Reconciler) localRelative(absPath string) (string, bool) {
	root := filepath.Clean(rc.profile.LocalPath)
	rel, err := filepath.Rel(root, filepath.Clean(absPath))
	if err != nil || rel == "." {
		return "", false
	}
	// Prune excluded directories entirely via their relative path.
	if matchesExclude(rel, rc.profile.ExcludePatterns) {
		return "", false
	}
	return filepath.ToSlash(rel), true
}

// scanRemote lists all objects under the profile prefix, including nested paths.
func (rc *Reconciler) scanRemote(ctx context.Context) (map[string]remoteSide, error) {
	out := map[string]remoteSide{}
	items, err := rc.backend.ListObjectsRecursive(ctx, rc.profile.Bucket, rc.profile.RemotePrefix)
	if err != nil {
		return nil, err
	}
	for _, item := range items {
		if item.IsDir {
			continue
		}
		rel := rc.remoteRelative(item.Key)
		if rel == "" || matchesExclude(rel, rc.profile.ExcludePatterns) {
			continue
		}
		out[rel] = remoteSide{
			size:    item.Size,
			mtime:   parseRemoteMTime(item.LastModified),
			present: true,
		}
	}
	return out, nil
}

// remoteRelative strips the configured prefix from a remote key.
func (rc *Reconciler) remoteRelative(key string) string {
	prefix := rc.profile.RemotePrefix
	if prefix != "" && strings.HasPrefix(key, prefix) {
		key = strings.TrimPrefix(key, prefix)
	}
	key = strings.TrimPrefix(key, "/")
	return key
}

// localAbs reconstructs the absolute local path for a relative key.
func (rc *Reconciler) localAbs(rel string) string {
	return filepath.Join(rc.profile.LocalPath, filepath.FromSlash(rel))
}

// remoteKey joins the profile prefix with a relative key.
func (rc *Reconciler) remoteKey(rel string) string {
	return rc.profile.relativeKey(rel)
}

// parseRemoteMTime parses the local-time layout used by ObjectInfo.LastModified.
// The remote listing formats timestamps as "2006-01-02 15:04:05" in local time;
// failures yield zero, treated as "unknown mtime" by the diff layer.
func parseRemoteMTime(value string) int64 {
	if value == "" {
		return 0
	}
	t, err := time.ParseInLocation("2006-01-02 15:04:05", value, time.Local)
	if err != nil {
		return 0
	}
	return t.UnixNano()
}

// indexView returns the complete set of indexed relative paths plus a lazy
// lookup. Keys are collected up front so diff can build the union; individual
// entries are fetched per-key to avoid loading every value into memory.
func (rc *Reconciler) indexView(idx *Index) ([]string, indexLookup) {
	var keys []string
	_ = idx.EachEntry(func(rel string, _ IndexEntry) bool {
		keys = append(keys, rel)
		return true
	})
	lookup := func(rel string) (IndexEntry, bool) {
		return idx.GetEntry(rel)
	}
	return keys, lookup
}
