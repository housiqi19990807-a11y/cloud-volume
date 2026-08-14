# Windows Mount Mutation and Cross-Client Sync Reliability Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Windows Cloud Files directory renames, cross-directory moves, and cross-client refreshes converge to one correct remote and local state, including recovery after an app restart.

**Architecture:** Preserve concurrent uploads and extend the existing upload-aware rename lane instead of adding a second competing queue. Add a rebase-and-fence operation to `dirSyncQueue`, persist rename records together with upload generations, and reconcile every retry from observed source/destination state. Retain the bounded set of directories observed by Cloud Files and poll idle entries every two minutes rather than expiring them.

**Tech Stack:** Go mount queues, append-only JSONL runtime records, storage backend interfaces, Windows Cloud Files callbacks, Go unit tests, and Flutter/Windows release validation.

---

## Scope And File Map

- Directory ordering: `go/mount/dir_sync_queue.go`, `go/mount/bucket_access_writes.go`, `go/mount/writeback_rename_queue.go`, and focused tests in `go/mount/dir_sync_queue_test.go`.
- Restart-safe moves: new `go/mount/mutation_record.go`, `go/mount/mutation_store.go`, and `go/mount/mutation_store_test.go`; changes to `go/mount/bucket_access.go`, `go/mount/bucket_access_writes.go`, `go/mount/writeback_store.go`, `go/mount/writeback_rename_queue.go`, `go/mount/writeback_rename_queue_test.go`, and `go/mount/types.go`.
- Remote visibility: `go/mount/remote_poller.go` and `go/mount/remote_poller_test.go`. Change `go/mount/cloud_files_hydrator_windows.go` only if a regression test proves its existing `OnFetchPlaceholders` activity hook is insufficient.
- Release knowledge: `README.md`, `CHANGELOG.md`, and the Windows mount Code Map in `AGENTS.md`.

Do not change provider APIs for the partial-move recovery path. `storage.Backend` already exposes `MoveObject`, `CopyObject`, and `DeleteObjectHard`; the mount coordinator can select the safe operation from remote state and thereby bypass the JWanFS fast move only during an ambiguous retry. All changed hand-written files must remain below 500 lines and contain a meaningful responsibility comment.

## Task 1: Fence Directory Creates Before A Rename

**Files:**
- Modify: `go/mount/dir_sync_queue.go`
- Modify: `go/mount/bucket_access_writes.go`
- Modify: `go/mount/writeback_rename_queue.go`
- Create: `go/mount/dir_sync_queue_test.go`
- Test: `go/mount/writeback_rename_queue_test.go`

- [ ] **Step 1: Write the failing directory-race tests.**

Use a fake backend that records `create:<path>` and `rename:<old>:<new>` events. Add these tests:

```go
func TestDirectoryCreateIsRebasedBeforeRename(t *testing.T)
func TestNestedDirectoryCreatesRebaseAsOneTree(t *testing.T)
func TestRunningDirectoryCreateFinishesBeforeRename(t *testing.T)
```

The first test enqueues `New Folder`, immediately renames it to `Reports`, and asserts that the terminal remote state contains only `Reports`. The nested test covers `New Folder/sub` and checks every queued descendant is rebased. The running test blocks `CreateDirectory("New Folder")` with a channel and asserts that the remote rename cannot start until the channel is released.

- [ ] **Step 2: Confirm the RED state with an exact test selector.**

```powershell
go test ./go/mount -run 'Test(DirectoryCreateIsRebasedBeforeRename|NestedDirectoryCreatesRebaseAsOneTree|RunningDirectoryCreateFinishesBeforeRename)$' -count=1 -v
```

Expected: at least one test fails because `dirSyncQueue` and the writeback rename lane currently have no shared ordering boundary.

- [ ] **Step 3: Make directory queue entries rebaseable and waitable.**

Replace `chan string` work with stable entry objects. Keep two directory workers, but track queued and running entries under the queue mutex:

```go
type dirSyncEntry struct {
    path     string
    running  bool
    canceled bool
    done     chan struct{}
}

type dirSyncBarrier struct {
    entries []*dirSyncEntry
}

func (q *dirSyncQueue) rebaseAndFence(oldPath, newPath string, isDir bool) *dirSyncBarrier
func (q *dirSyncQueue) wait(ctx context.Context, barrier *dirSyncBarrier) error
```

`rebaseAndFence` must run while holding `q.mu`. Re-key every queued old-prefix entry to the new prefix; if that collides with an existing target entry, cancel the duplicate token and include the surviving entry in the barrier. Never rewrite an entry whose provider call is already running. Include matching running old-prefix entries and rebased target entries in the returned barrier. Workers re-read `entry.path` under the mutex before calling `createRemoteDirectory`, skip canceled entries, and close `done` exactly once.

- [ ] **Step 4: Attach the directory fence to the existing upload barrier.**

In `bucketAccess.enqueueRenamePath`, call `a.dirSync.rebaseAndFence(oldClean, newClean, isDir)` before enqueueing the rename. Add the returned barrier to `queuedWritebackRename`. In `executeQueuedRename`, preserve this order:

```text
capture the upload generation and rebase pending local file sources
wait for uploads at or below that generation
wait for directory creates captured by the directory fence
reconcile the remote rename
release later uploads
```

The Cloud Files callback remains non-blocking: it only enqueues the work. A directory create already running under the old name finishes first and is then moved; a queued create is rebased to the new name and the rename reconciler treats source-missing/destination-present as complete.

- [ ] **Step 5: Run focused and existing ordering regressions.**

```powershell
go test ./go/mount -run 'Test(DirectoryCreateIsRebasedBeforeRename|NestedDirectoryCreatesRebaseAsOneTree|RunningDirectoryCreateFinishesBeforeRename|QueuedRenameOrdersUploadsAcrossDirectoryBarrier|MarkRenameSourceLeavesRenamedChildrenWritable)$' -count=1 -v
```

Expected: all selected tests pass; no final event/state contains both `New Folder` and `Reports`.

- [ ] **Step 6: Commit the independently testable ordering fix.**

```powershell
git add go/mount/dir_sync_queue.go go/mount/dir_sync_queue_test.go go/mount/bucket_access_writes.go go/mount/writeback_rename_queue.go go/mount/writeback_rename_queue_test.go
git commit -m "fix(windows): order directory creates with renames"
```

## Task 2: Persist And Idempotently Recover Remote Moves

**Files:**
- Create: `go/mount/mutation_record.go`
- Create: `go/mount/mutation_store.go`
- Create: `go/mount/mutation_store_test.go`
- Modify: `go/mount/bucket_access.go`
- Modify: `go/mount/bucket_access_writes.go`
- Modify: `go/mount/writeback_store.go`
- Modify: `go/mount/writeback_rename_queue.go`
- Modify: `go/mount/writeback_rename_queue_test.go`
- Modify: `go/mount/types.go`

- [ ] **Step 1: Define serializable rename state and failing recovery tests.**

Use an explicit schema rather than serializing the current `run func() error` closure:

```go
const mutationRecordVersion = 1

type mutationRecord struct {
    Version           int    `json:"version"`
    ID                string `json:"id"`
    TaskID            string `json:"taskId"`
    Kind              string `json:"kind"` // "rename"
    OldVirtualPath    string `json:"oldVirtualPath"`
    NewVirtualPath    string `json:"newVirtualPath"`
    OldLocalPath      string `json:"oldLocalPath"`
    NewLocalPath      string `json:"newLocalPath"`
    IsDirectory       bool   `json:"isDirectory"`
    UploadGeneration  uint64 `json:"uploadGeneration"`
    RetryCount        int    `json:"retryCount"`
    NextAttemptUnixNs int64  `json:"nextAttemptUnixNs"`
    LastError         string `json:"lastError,omitempty"`
    UpdatedAtUnixNs   int64  `json:"updatedAtUnixNs"`
}
```

Add:

```go
func TestRenameMutationRestoresAfterRestart(t *testing.T)
func TestMoveWithBothSourceAndDestinationConverges(t *testing.T)
func TestCompletedMoveIsNotRepeatedAfterRestore(t *testing.T)
func TestRenameFailureAppearsInMountStatus(t *testing.T)
func TestMutationStoreIgnoresOnlyATruncatedFinalLine(t *testing.T)
```

The fake backend must support independent source/destination existence, injected copy/delete failures, and call counters. The restart test closes the first queue with a pending record, constructs a second queue from the same `sessionRoot`, and observes completion.

- [ ] **Step 2: Confirm the persistence tests fail before implementation.**

```powershell
go test ./go/mount -run 'Test(RenameMutationRestoresAfterRestart|MoveWithBothSourceAndDestinationConverges|CompletedMoveIsNotRepeatedAfterRestore|RenameFailureAppearsInMountStatus|MutationStoreIgnoresOnlyATruncatedFinalLine)$' -count=1 -v
```

Expected: tests fail because rename closures are memory-only and `writebackRecord` does not preserve generation.

- [ ] **Step 3: Implement a crash-tolerant append-only mutation store.**

Store logs under `filepath.Join(access.sessionRoot, "mutations")` as `queue-<pid>.jsonl`. Each line is a versioned `upsert` or `complete` event for one mutation ID. On every append, flush and call `File.Sync()` before reporting success. Recovery scans all `queue-*.jsonl` files, applies events in file/line order, accepts a malformed line only when it is the final unterminated line of a file, and returns an error for malformed interior data or unsupported versions.

After recovery, compact live records into a new uniquely named JSONL file, sync it, then remove stale process logs. Do not rename over an existing file on Windows. A `complete` tombstone is written only after the remote postcondition is verified; a crash after provider success but before the tombstone is safe because the next run re-observes source/destination state.

- [ ] **Step 4: Persist upload generations and reconstruct barriers before dispatch.**

Add `Generation uint64` to `writebackRecord`, populate it in `upsert`, and restore it in `toPendingWriteback`. During `acquireWritebackQueue`, restore uploads and mutation records before starting either dispatcher. Rebuild rename barriers and local source rebases sorted by `UploadGeneration`, then set the next queue generation to one greater than the maximum restored upload or mutation generation.

This preserves the invariant across restart: uploads captured before a move finish before it, while uploads created after the move remain blocked until it reaches a verified terminal state. Old writeback JSON without `generation` naturally restores at generation zero.

- [ ] **Step 5: Replace closure retries with a remote-state reconciler.**

Add a probe that distinguishes absence from provider failure:

```go
func (a *bucketAccess) probeRemotePath(ctx context.Context, virtualPath string, isDir bool) (bool, error)
func (a *bucketAccess) reconcileRemoteMove(ctx context.Context, record mutationRecord) error
```

For files, treat only `errors.Is(err, os.ErrNotExist)` as absent. For directories, check the marker and then list one item under the prefix; propagate network/authentication errors. Execute this state table:

| Source | Destination | Action |
|---|---|---|
| absent | present | Mark complete without another provider mutation |
| present | absent | Call `MoveObject`, then probe both paths |
| present | present | Call `CopyObject` to overwrite/merge the destination, call `DeleteObjectHard` for the captured source, then probe both paths |
| absent | absent | Retain the record and retry with a state-conflict error |

Store one stable `TaskID` in the mutation record and reuse it for every attempt. On error, increment `RetryCount`, calculate `NextAttemptUnixNs` with `nextWritebackRetryDelay`, persist the new state, and leave the upload barrier closed. On verified success, update/invalidate the bucket cache, forget old peer content, broadcast the rename once, append the completion event, and release the barrier.

- [ ] **Step 6: Surface durable failures without relying on an in-memory callback.**

Track the most recent live mutation error under the writeback queue mutex and expose it with `mutationLastError() string`. In `mountSession.status()`, prefer that error over an empty `session.lastError`; clear it only after the corresponding mutation succeeds or is superseded by a later failure. Queue submission errors in the Cloud Files callback continue to set `session.lastError` immediately.

On shutdown, stop accepting new mutations, persist in-memory retry state, release waiters, and leave incomplete records for the next mount. Never delete a record merely because shutdown or a timeout occurred.

- [ ] **Step 7: Run recovery, writeback-store, and move regressions.**

```powershell
go test ./go/mount -run 'Test(RenameMutation|MoveWithBothSourceAndDestination|CompletedMove|RenameFailure|MutationStore|QueuedRename|Writeback.*Restore)' -count=1 -v
go test ./go/s3 -run 'Test.*Move.*' -count=1
```

Expected: a failed move survives queue reconstruction; source-present/destination-present converges by explicit copy plus hard delete; source-absent/destination-present performs no second move.

- [ ] **Step 8: Commit restart recovery separately.**

```powershell
git add go/mount/mutation_record.go go/mount/mutation_store.go go/mount/mutation_store_test.go go/mount/bucket_access.go go/mount/bucket_access_writes.go go/mount/writeback_store.go go/mount/writeback_rename_queue.go go/mount/writeback_rename_queue_test.go go/mount/types.go
git commit -m "fix(mount): recover interrupted remote moves"
```

## Task 3: Retain Observed Directories For Bounded Idle Polling

**Files:**
- Modify: `go/mount/remote_poller.go`
- Modify: `go/mount/remote_poller_test.go`
- Modify only if required by a failing Windows-specific test: `go/mount/cloud_files_hydrator_windows.go`

- [ ] **Step 1: Replace the expiry expectation with retention tests.**

Rename `TestDirectoryActivityBacksOffAndExpires` to `TestDirectoryActivityBacksOffWithoutExpiring` and change its five-minute-old entry expectation from deleted to retained. Add:

```go
func TestRemotePollerRefreshesAnIdleObservedDirectory(t *testing.T)
func TestDirectoryActivityStillHonorsTheTwelveDirectoryCap(t *testing.T)
```

The idle refresh test seeds a remote item, records `docs` older than `remotePollWarmWindow`, calls `pollOnce`, and asserts `externalDirectoryRefresh` receives the item. The cap test records 13 paths with increasing timestamps and expects only the newest 12.

- [ ] **Step 2: Confirm the RED state.**

```powershell
go test ./go/mount -run 'Test(DirectoryActivityBacksOffWithoutExpiring|RemotePollerRefreshesAnIdleObservedDirectory|DirectoryActivityStillHonorsTheTwelveDirectoryCap)$' -count=1 -v
```

Expected: the old entry is removed by `recent`, so retention and idle refresh fail.

- [ ] **Step 3: Remove time-based eviction while preserving bounded cadence.**

`directoryActivityTracker.recent` returns all retained entries sorted and never deletes based on age. `nextDelay` uses the most recently observed entry:

```text
age <= 45 seconds             -> configured active delay
45 seconds < age <= 3 minutes -> 30 seconds
age > 3 minutes or no entries -> 2 minutes
```

Keep the 12-directory oldest-entry eviction in `noteAt`, keep `SupportsMountRemotePolling()` unchanged so SFTP remains opted out, and add a comment stating that the tracker is a bounded observed-directory set rather than a three-minute cache.

- [ ] **Step 4: Run polling and projection regressions.**

```powershell
go test ./go/mount -run 'Test(RemotePoller|DirectoryActivity|CloudFiles|FetchPlaceholder)' -count=1 -v
```

Expected: idle observed paths refresh every two minutes, the cap remains 12, and provider-created placeholder updates do not feed back into local writeback.

- [ ] **Step 5: Commit the visibility fix.**

```powershell
git add go/mount/remote_poller.go go/mount/remote_poller_test.go go/mount/cloud_files_hydrator_windows.go
git commit -m "fix(windows): retain idle directory refreshes"
```

Stage `cloud_files_hydrator_windows.go` only if it actually changed.

## Task 4: Documentation, Full Validation, And Release Handoff

**Files:**
- Modify: `CHANGELOG.md` under `## Unreleased`
- Modify: `README.md` Windows troubleshooting section
- Modify: `AGENTS.md` Windows mount Code Map
- Build only: `scripts/run_windows.ps1`, `scripts/build_windows_installer.ps1`

- [ ] **Step 1: Record the recovery contract and operational boundary.**

Add an Unreleased entry covering ordered directory renames, restart-safe remote moves, and bounded idle refresh. In `README.md`, state that historical duplicate files/folders cannot be removed automatically because intent is unknowable; users must compare source and destination before deleting an old remote key. State that Debug logging must be enabled before reproducing and that the useful events are `rename-queued`, `rename-retry`, `rename-finished`, `dir-sync`, and `poll`.

Replace the diagnosis paragraph in the `AGENTS.md` Windows mount Code Map with the implemented files, data flow, persistence location, state table, and regression test names. Preserve the evidence that installers built before 2026-08-11 do not contain the earlier upload barrier fix.

- [ ] **Step 2: Check file limits and run the complete validation gates.**

```powershell
Get-ChildItem go/mount/*.go | ForEach-Object { if ((Get-Content $_.FullName).Count -ge 500) { $_.FullName } }
go test ./...
flutter analyze
git diff --check
```

Expected: no changed hand-written file reaches 500 lines; Go exits 0; Flutter has no new diagnostics caused by this change; whitespace checks pass. If `TestWindowsSyncWatcherCloseReturnsDuringHarvest` hits its known parallel timing failure, rerun exactly that test alone and report both results without weakening its timeout.

- [ ] **Step 3: Build a fresh Windows bundle and installer through the canonical workflow.**

```powershell
.\scripts\run_windows.ps1 -Build
.\scripts\build_windows_installer.ps1
```

Verify the architecture-matched release directory contains `cloud-volume.exe`, `cloud-volume-app.exe`, `cloud-volume-crash-reporter.exe`, `cloud-volume-updater.exe`, and `remote_storage_bridge.dll`. Verify the product version names the new commit and is newer than the local 2026-08-10 `v1.2.4-36-ge1732651-dirty` installer. Do not stage `dist/`, `bin/`, or `build/`.

- [ ] **Step 4: Hand the app-level verification matrix to the user.**

1. Create `New Folder`, immediately rename it, restart Windows, and confirm exactly one remote directory remains.
2. Move an existing file across directories, interrupt the network during the remote mutation, restart the app, and confirm the source disappears while the destination remains.
3. Open a Windows directory, leave it idle beyond three minutes, create a file on Linux, and confirm the Windows placeholder appears without remounting (allow the two-minute idle poll interval).
4. If any case fails, enable Debug logging before reproduction and collect only the mutation, directory-sync, and polling lines listed above.

- [ ] **Step 5: Commit documentation after the implementation gates pass.**

```powershell
git add CHANGELOG.md README.md AGENTS.md
git commit -m "docs: document Windows mutation recovery"
```

Keep the user's existing changes in `scripts/build_windows_installer.ps1`, `scripts/setup_windows_dev.ps1`, and untracked `dist/` out of all commits.

## Rollback And Safety Rules

- Keep the three runtime changes in separate commits so directory ordering, move recovery, and polling retention can be reverted independently.
- Never auto-delete historical duplicates. Only the observed source-absent/destination-present state may complete a restored move without another provider mutation.
- Never interpret an authentication, timeout, or listing error as “path absent.” Such errors retain the record and retry.
- Keep polling bounded to 12 observed directories and the two-minute idle interval. Do not restore silent three-minute expiry.

## Plan Self-Review

- Coverage: Task 1 fixes duplicate old/new folder markers; Task 2 fixes partial moves and restart loss; Task 3 fixes Linux-to-Windows visibility after idle; Task 4 covers docs, full gates, packaging, and user verification.
- Placeholder scan: clean; every code-changing step names its files, behavior, test, and expected result.
- Type consistency: Task 2 persists the same `UploadGeneration` used by the existing writeback barrier and reconstructs executable operations from data rather than closures.
- Scope: no Flutter UI redesign, automatic historical cleanup, provider API expansion, or unrelated watcher refactor is included.
