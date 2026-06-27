// diff.go computes the operation plan for one reconcile pass by comparing the
// local snapshot, remote snapshot, and the persisted index entry for each path.
// Rename detection runs separately in reconcile.go where full size metadata is
// available, so this file only classifies add/change/delete/conflict per key.
package sync

import "sort"

// localSide is the scanned view of a local file under the sync root.
type localSide struct {
	size    int64
	mtime   int64 // unix nano
	present bool
	isDir   bool
}

// remoteSide is the listed view of a remote object under the sync prefix.
type remoteSide struct {
	size    int64
	mtime   int64 // unix nano
	present bool
	isDir   bool
}

// OpKind enumerates the primitive operations reconcile can emit.
type OpKind string

const (
	OpUpload          OpKind = "upload"
	OpDownload        OpKind = "download"
	OpEnsureLocalDir   OpKind = "ensure_local_dir"
	OpDeleteLocal      OpKind = "delete_local"
	OpDeleteRemote     OpKind = "delete_remote"
	OpRename           OpKind = "rename"
	OpSkip             OpKind = "skip"
)

// Op is a single planned file operation feeding into the transfer queue.
type Op struct {
	Kind      OpKind `json:"kind"`
	RelPath   string `json:"relPath"`
	OldRelPath string `json:"oldRelPath,omitempty"`
	Reason    string `json:"reason,omitempty"`
	// Size is populated by reconcile for rename matching and transfer sizing.
	Size int64 `json:"size,omitempty"`
}

// rawOp carries the classified op plus the snapshot metadata needed for rename
// pairing and delete-side determination in the reconcile layer.
type rawOp struct {
	op          Op
	localSize   int64
	localMTime  int64
	remoteSize  int64
	remoteMTime int64
}

// indexLookup returns the stored IndexEntry for a relative path.
type indexLookup func(rel string) (IndexEntry, bool)

// classifyAll walks the union of local/remote/index and returns one rawOp per
// key. The index side is supplied as a lazy lookup plus its key set so bbolt
// entries are fetched per-key instead of loaded into a map upfront.
func classifyAll(
	profile SyncProfile,
	local map[string]localSide,
	remote map[string]remoteSide,
	indexKeys []string,
	lookup indexLookup,
) []rawOp {
	keys := unionKeys(local, remote, indexKeys)
	out := make([]rawOp, 0, len(keys))
	for _, rel := range keys {
		l := local[rel]
		r := remote[rel]
		idx, _ := lookup(rel)
		out = append(out, rawOp{
			op:          classify(profile, rel, l, r, idx),
			localSize:   l.size,
			localMTime:  l.mtime,
			remoteSize:  r.size,
			remoteMTime: r.mtime,
		})
	}
	return out
}

// classify decides the op for a single key.
func classify(
	profile SyncProfile,
	rel string,
	l localSide,
	r remoteSide,
	idx IndexEntry,
) Op {
	if !l.present {
		if dir, ok := localDirSide(profile, rel); ok {
			l = dir
		}
	}
	locChanged := l.present && !l.isDir && (l.size != idx.LocalSize || l.mtime != idx.LocalMTime)
	remChanged := r.present && !r.isDir && (r.size != idx.RemoteSize || r.mtime != idx.RemoteMTime)

	if r.present && r.isDir && !l.present {
		if indexTrackedRemoteDir(idx) && profile.Direction == DirectionTwoWay {
			return Op{Kind: OpDeleteLocal, RelPath: rel, Reason: "remote_dir_removed"}
		}
		if indexTrackedRemoteDir(idx) {
			return Op{Kind: OpSkip, RelPath: rel, Reason: "stale_dir_index"}
		}
		if profile.Direction == DirectionUpload {
			return Op{Kind: OpSkip, RelPath: rel, Reason: "upload_only"}
		}
		return Op{Kind: OpEnsureLocalDir, RelPath: rel, Reason: "new_remote_dir"}
	}

	switch {
	case l.present && r.present:
		if r.isDir || l.isDir {
			return Op{Kind: OpSkip, RelPath: rel, Reason: "directory_marker"}
		}
		if !locChanged && !remChanged {
			return Op{Kind: OpSkip, RelPath: rel}
		}
		if locChanged && remChanged {
			return resolveConflict(profile, rel, l, r, idx)
		}
		if locChanged {
			if profile.Direction == DirectionDownload {
				return Op{Kind: OpSkip, RelPath: rel, Reason: "download_only"}
			}
			return Op{Kind: OpUpload, RelPath: rel}
		}
		if profile.Direction == DirectionUpload {
			return Op{Kind: OpSkip, RelPath: rel, Reason: "upload_only"}
		}
		return Op{Kind: OpDownload, RelPath: rel}

	case l.present && !r.present:
		if idx.RemoteSize != 0 || idx.RemoteMTime != 0 {
			switch profile.Direction {
			case DirectionUpload:
				return Op{Kind: OpUpload, RelPath: rel, Reason: "remote_deleted_reupload"}
			case DirectionTwoWay:
				return Op{Kind: OpDeleteLocal, RelPath: rel}
			default:
				return Op{Kind: OpSkip, RelPath: rel}
			}
		}
		if profile.Direction == DirectionDownload {
			return Op{Kind: OpSkip, RelPath: rel}
		}
		return Op{Kind: OpUpload, RelPath: rel, Reason: "new_local"}

	case !l.present && r.present:
		if r.isDir {
			return Op{Kind: OpSkip, RelPath: rel, Reason: "remote_dir_unhandled"}
		}
		if idx.LocalSize != 0 || idx.LocalMTime != 0 {
			switch profile.Direction {
			case DirectionDownload:
				return Op{Kind: OpDownload, RelPath: rel, Reason: "local_deleted_redownload"}
			case DirectionTwoWay:
				return Op{Kind: OpDeleteRemote, RelPath: rel}
			default:
				return Op{Kind: OpSkip, RelPath: rel}
			}
		}
		if profile.Direction == DirectionUpload {
			return Op{Kind: OpSkip, RelPath: rel}
		}
		return Op{Kind: OpDownload, RelPath: rel, Reason: "new_remote"}

	default:
		if indexTrackedRemoteDir(idx) && !r.present {
			return Op{Kind: OpSkip, RelPath: rel, Reason: "stale_dir_index"}
		}
		return Op{Kind: OpSkip, RelPath: rel, Reason: "stale_index"}
	}
}

// indexTrackedRemoteDir is true when the index remembers a synced directory marker (not a file).
func indexTrackedRemoteDir(idx IndexEntry) bool {
	return idx.LocalSize == 0 && idx.RemoteSize == 0 && idx.LocalMTime != 0
}

// resolveConflict applies the profile's conflict policy when both sides changed.
func resolveConflict(profile SyncProfile, rel string, l localSide, r remoteSide, idx IndexEntry) Op {
	switch profile.ConflictPolicy {
	case ConflictLocalWins:
		if profile.Direction == DirectionDownload {
			return Op{Kind: OpSkip, RelPath: rel}
		}
		return Op{Kind: OpUpload, RelPath: rel, Reason: "conflict_local_wins"}
	case ConflictRemoteWins:
		if profile.Direction == DirectionUpload {
			return Op{Kind: OpSkip, RelPath: rel}
		}
		return Op{Kind: OpDownload, RelPath: rel, Reason: "conflict_remote_wins"}
	case ConflictSkip:
		return Op{Kind: OpSkip, RelPath: rel}
	default:
		if l.mtime >= r.mtime {
			if profile.Direction == DirectionDownload {
				return Op{Kind: OpSkip, RelPath: rel}
			}
			return Op{Kind: OpUpload, RelPath: rel, Reason: "conflict_newest_local"}
		}
		if profile.Direction == DirectionUpload {
			return Op{Kind: OpSkip, RelPath: rel}
		}
		return Op{Kind: OpDownload, RelPath: rel, Reason: "conflict_newest_remote"}
	}
}

// unionKeys returns the sorted union of all key sets.
func unionKeys(local map[string]localSide, remote map[string]remoteSide, indexKeys []string) []string {
	set := map[string]struct{}{}
	for k := range local {
		set[k] = struct{}{}
	}
	for k := range remote {
		set[k] = struct{}{}
	}
	for _, k := range indexKeys {
		set[k] = struct{}{}
	}
	out := make([]string, 0, len(set))
	for k := range set {
		out = append(out, k)
	}
	sort.Strings(out)
	return out
}
