// executor.go performs a single planned op (upload/download/delete/rename)
// against the backend, registers it in the shared transfer monitor, and
// updates the profile's index on success so the next reconcile sees it settled.
package sync

import (
	"context"
	"fmt"
	"log"
	"os"
	"path/filepath"

	s3ops "remote-storage/go/s3"
	storageops "remote-storage/go/storage"
)

// opExecutor binds a profile + backend and can execute one Op at a time.
type opExecutor struct {
	profile    SyncProfile
	backend    storageops.Backend
	runtimeRoot string
}

func newOpExecutor(profile SyncProfile, backend storageops.Backend, runtimeRoot string) *opExecutor {
	return &opExecutor{profile: profile, backend: backend, runtimeRoot: runtimeRoot}
}

// run executes the op synchronously, reporting progress through the monitor.
func (e *opExecutor) run(ctx context.Context, taskID string, op Op) {
	kind := transferKindFor(op)
	bucket := e.profile.Bucket
	key := e.profile.relativeKey(op.RelPath)
	localPath := localAbsPath(e.profile, op.RelPath)

	s3ops.QueueTransfer(taskID, kind, bucket, key, localPath, op.Size)
	ctx, cancel := context.WithCancel(ctx)
	s3ops.StartQueuedTransfer(taskID, kind, bucket, key, localPath, op.Size, cancel)

	err := e.executeOp(ctx, op, key, localPath)
	s3ops.FinishQueuedTransfer(taskID, err)
	if err != nil {
		log.Printf("[sync/exec] %s op %s failed: %v", e.profile.Name, op.Kind, err)
		return
	}
	e.updateIndex(op, key, localPath)
}

// executeOp performs the actual backend call for the op kind.
func (e *opExecutor) executeOp(ctx context.Context, op Op, key, localPath string) error {
	switch op.Kind {
	case OpUpload:
		if err := os.MkdirAll(filepath.Dir(localPath), 0o755); err != nil {
			return fmt.Errorf("ensure local dir: %w", err)
		}
		return e.backend.UploadFile(ctx, e.profile.Bucket, key, localPath, "")
	case OpDownload:
		if err := os.MkdirAll(filepath.Dir(localPath), 0o755); err != nil {
			return fmt.Errorf("ensure local dir: %w", err)
		}
		return e.backend.DownloadFile(ctx, e.profile.Bucket, key, localPath, "")
	case OpDeleteRemote:
		return e.backend.DeleteObject(ctx, e.profile.Bucket, key, false, "")
	case OpDeleteLocal:
		if err := os.Remove(localPath); err != nil && !os.IsNotExist(err) {
			return err
		}
		return nil
	case OpRename:
		oldKey := e.profile.relativeKey(op.OldRelPath)
		return e.backend.MoveObject(ctx, e.profile.Bucket, oldKey, key, false, "")
	default:
		return nil
	}
}

// updateIndex records the new settled state for the op's path after success.
func (e *opExecutor) updateIndex(op Op, key, localPath string) {
	idx, err := loadIndex(e.runtimeRoot, e.profile.ID)
	if err != nil {
		log.Printf("[sync/exec] load index for update: %v", err)
		return
	}
	now := nowNano()
	switch op.Kind {
	case OpUpload, OpRename:
		if info, statErr := os.Stat(localPath); statErr == nil {
			entry := idx.Entries[op.RelPath]
			entry.LocalSize = info.Size()
			entry.LocalMTime = info.ModTime().UnixNano()
			entry.RemoteSize = info.Size()
			entry.RemoteMTime = entry.LocalMTime
			entry.LastSyncedAt = now
			idx.Entries[op.RelPath] = entry
		}
		// For rename, clear the old path from the index.
		if op.Kind == OpRename && op.OldRelPath != "" {
			delete(idx.Entries, op.OldRelPath)
		}
	case OpDownload:
		if info, statErr := os.Stat(localPath); statErr == nil {
			entry := idx.Entries[op.RelPath]
			entry.LocalSize = info.Size()
			entry.LocalMTime = info.ModTime().UnixNano()
			entry.RemoteSize = info.Size()
			entry.RemoteMTime = entry.LocalMTime
			entry.LastSyncedAt = now
			idx.Entries[op.RelPath] = entry
		}
	case OpDeleteRemote, OpDeleteLocal:
		delete(idx.Entries, op.RelPath)
	}
	if err := idx.save(e.runtimeRoot, e.profile.ID); err != nil {
		log.Printf("[sync/exec] save index: %v", err)
	}
}

// transferKindFor maps an OpKind to the transfer monitor's kind string.
func transferKindFor(op Op) string {
	switch op.Kind {
	case OpUpload:
		return "sync_upload"
	case OpDownload:
		return "sync_download"
	case OpDeleteRemote, OpDeleteLocal:
		return "sync_delete"
	case OpRename:
		return "sync_rename"
	default:
		return "sync"
	}
}
