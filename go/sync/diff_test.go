package sync

import (
	"testing"
)

func TestClassifyNewLocalUpload(t *testing.T) {
	profile := SyncProfile{Direction: DirectionUpload, ConflictPolicy: ConflictNewest}
	local := map[string]localSide{"a.txt": {size: 10, mtime: 100, present: true}}
	remote := map[string]remoteSide{}
	idx := newIndex()

	ops := classifyAll(profile, local, remote, idx)
	if len(ops) != 1 || ops[0].op.Kind != OpUpload {
		t.Fatalf("expected single upload, got %+v", ops)
	}
}

func TestClassifyNewRemoteDownload(t *testing.T) {
	profile := SyncProfile{Direction: DirectionDownload, ConflictPolicy: ConflictNewest}
	local := map[string]localSide{}
	remote := map[string]remoteSide{"b.txt": {size: 20, mtime: 200, present: true}}
	idx := newIndex()

	ops := classifyAll(profile, local, remote, idx)
	if len(ops) != 1 || ops[0].op.Kind != OpDownload {
		t.Fatalf("expected single download, got %+v", ops)
	}
}

func TestClassifyTwoWayDeleteRemote(t *testing.T) {
	profile := SyncProfile{Direction: DirectionTwoWay, ConflictPolicy: ConflictNewest}
	local := map[string]localSide{}
	remote := map[string]remoteSide{"c.txt": {size: 5, mtime: 50, present: true}}
	idx := &Index{Entries: map[string]IndexEntry{
		"c.txt": {LocalSize: 5, LocalMTime: 40, RemoteSize: 5, RemoteMTime: 50},
	}}

	ops := classifyAll(profile, local, remote, idx)
	if len(ops) != 1 || ops[0].op.Kind != OpDeleteRemote {
		t.Fatalf("expected delete_remote, got %+v", ops)
	}
}

func TestClassifyBothUnchangedSkip(t *testing.T) {
	profile := SyncProfile{Direction: DirectionTwoWay}
	local := map[string]localSide{"x.txt": {size: 7, mtime: 77, present: true}}
	remote := map[string]remoteSide{"x.txt": {size: 7, mtime: 77, present: true}}
	idx := &Index{Entries: map[string]IndexEntry{
		"x.txt": {LocalSize: 7, LocalMTime: 77, RemoteSize: 7, RemoteMTime: 77},
	}}

	ops := classifyAll(profile, local, remote, idx)
	if len(ops) != 1 || ops[0].op.Kind != OpSkip {
		t.Fatalf("expected skip, got %+v", ops)
	}
}

func TestClassifyConflictNewestLocalWins(t *testing.T) {
	profile := SyncProfile{Direction: DirectionTwoWay, ConflictPolicy: ConflictNewest}
	local := map[string]localSide{"f.txt": {size: 9, mtime: 900, present: true}}
	remote := map[string]remoteSide{"f.txt": {size: 9, mtime: 800, present: true}}
	idx := &Index{Entries: map[string]IndexEntry{
		"f.txt": {LocalSize: 9, LocalMTime: 500, RemoteSize: 9, RemoteMTime: 500},
	}}

	ops := classifyAll(profile, local, remote, idx)
	if len(ops) != 1 || ops[0].op.Kind != OpUpload {
		t.Fatalf("expected upload (newest=local), got %+v", ops)
	}
}

func TestRenameDetectionSizeMatch(t *testing.T) {
	profile := SyncProfile{Direction: DirectionTwoWay}
	backend := newFakeBackend()
	rc := NewReconciler(profile, backend, t.TempDir())

	// "old.txt" deleted locally, "new.txt" added locally, same size.
	rawOps := []rawOp{
		{op: Op{Kind: OpDeleteLocal, RelPath: "old.txt"}, localSize: 100, localMTime: 1000},
		{op: Op{Kind: OpUpload, RelPath: "new.txt"}, localSize: 100, localMTime: 2000, remoteSize: 0},
	}
	local := map[string]localSide{"new.txt": {size: 100, present: true}}
	remote := map[string]remoteSide{}

	ops := rc.aggregateRenames(rawOps, local, remote)
	var hasRename bool
	for _, op := range ops {
		if op.Kind == OpRename {
			hasRename = true
			if op.OldRelPath != "old.txt" || op.RelPath != "new.txt" {
				t.Fatalf("rename has wrong paths: %+v", op)
			}
		}
	}
	if !hasRename {
		t.Fatalf("expected a rename op, got %+v", ops)
	}
}
