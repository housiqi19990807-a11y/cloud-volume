// rename_detect.go identifies move operations by matching a deleted file on one
// side with an added file of the same size, avoiding a wasteful delete+upload
// pair. Matching is done with full snapshot data in reconcile, not from the
// size-less Op list, so this file only provides the tracking container.
package sync

import "sort"

// renameWindow is the maximum mtime gap (in nanoseconds) to treat a matched
// add+delete pair as the same file moved rather than two independent events.
const renameWindow int64 = 5_000_000_000

// pendingDeletion records a deferred delete with enough metadata for pairing.
type pendingDeletion struct {
	rel           string
	size          int64
	mtime         int64
	localPresent  bool
	remotePresent bool
	matched       bool
}

// renamePairs holds matched (addedRel, deletedRel) tuples produced by reconcile.
type renamePairs struct {
	pairs    map[string]string // addedRel -> deletedRel
	matched  map[string]bool   // deletedRel -> consumed
	deletes  []pendingDeletion
}

func newRenamePairs() *renamePairs {
	return &renamePairs{
		pairs:   map[string]string{},
		matched: map[string]bool{},
	}
}

// recordDelete stores a deletion candidate awaiting pairing.
func (rp *renamePairs) recordDelete(rel string, size, mtime int64, local, remote bool) {
	rp.deletes = append(rp.deletes, pendingDeletion{
		rel:           rel,
		size:          size,
		mtime:         mtime,
		localPresent:  local,
		remotePresent: remote,
	})
}

// matchAdd tries to pair an added file (by size) with an unmatched deletion,
// returning the deleted rel path when a match exists. Only exact size matches
// are accepted so multipart-sensitive ETags and size-less backends stay safe.
func (rp *renamePairs) matchAdd(addedRel string, addedSize int64) (string, bool) {
	if addedSize == 0 {
		return "", false
	}
	for i := range rp.deletes {
		del := &rp.deletes[i]
		if del.matched || del.size != addedSize {
			continue
		}
		if del.rel == addedRel {
			continue
		}
		del.matched = true
		rp.matched[del.rel] = true
		rp.pairs[addedRel] = del.rel
		return del.rel, true
	}
	return "", false
}

// pairFor returns the deleted source path for a given added path, if any.
func (rp *renamePairs) pairFor(addedRel string) (string, bool) {
	del, ok := rp.pairs[addedRel]
	return del, ok
}

// unmatchedDeletes returns deletion keys not absorbed into renames, sorted.
func (rp *renamePairs) unmatchedDeletes() []string {
	out := make([]string, 0, len(rp.deletes))
	for _, del := range rp.deletes {
		if !del.matched {
			out = append(out, del.rel)
		}
	}
	sort.Strings(out)
	return out
}
