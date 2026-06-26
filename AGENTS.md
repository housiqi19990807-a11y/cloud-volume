# Repository Guidelines

## `lib` And `go` Structure Rules

- All hand-written code files under `lib`, `go`, `bridge`, and `macos/Runner` must stay under 500 lines.
- If a file approaches the limit, split it by feature or responsibility before adding more logic.
- Generated files are excluded from this rule:
  `.dart_tool`, `build`, `bin`, `macos/Flutter/ephemeral`.
- Every hand-written code file under `lib`, `go`, `bridge`, and `macos/Runner` must include at least one meaningful comment.
- Prefer file-level comments that explain the file responsibility, plus short section comments where logic is non-obvious.

## Flutter Frontend Organization

- Organize Flutter code by type first, then by feature:
  `lib/app`, `lib/pages`, `lib/widgets`, `lib/services`, `lib/state`, `lib/utils`, `lib/theme`, `lib/bridge`, `lib/models`.
- Keep entry files thin. They should wire modules together, not hold page logic inline.
- Large widget trees should be moved into page/widget modules instead of one oversized `build()` method.
- Keep bootstrap and configuration flows visually distinct from the eventual storage browser so first-run behavior stays obvious.

## Go Bridge Organization

- Split Go files by responsibility within a package, for example:
  `dispatch_config.go`, `config_store.go`, `config_paths.go`.
- Keep bridge exports grouped by feature instead of one large bridge file.
- Shared parsing, normalization, and transport helpers should live in dedicated helper files.
- Prefer a narrow C ABI plus JSON payloads for Flutter FFI when it avoids duplicating backend structs in Dart.

## Build Outputs

- Do not write compiled binaries or build artifacts to the repository root.
- Route local Go and Flutter build outputs to `bin/`, `build/`, or tool-managed build directories.
- For ad-hoc Go smoke validation from the repository root, do not run bare `go build .`.
- Use `go build -o bin/...` for manual bridge smoke tests, and remove temporary one-off outputs if they were created.  
  On Windows this means `go build -buildmode=c-shared -o bin/bridge/remote_storage_bridge.dll ./bridge` with `CGO_ENABLED=1` and a MinGW toolchain (e.g. MSYS2 UCRT64) available via `BRIDGE_CC`/`BRIDGE_CXX`.
- The macOS app must be started through the Go binding workflow, not plain Flutter alone.
- `make run` is the canonical local launch command. It first runs `make bridge`, which builds `./bridge` as `bin/bridge/libremote_storage_bridge.dylib`, then launches Flutter with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer flutter run -d macos`.
- When validating integrated app startup, prefer `make run` over a bare `flutter run -d macos` so the bridge binary and Xcode path are both set correctly.
- The Windows app must also be started through the Go binding workflow.  
  `scripts/run_windows.ps1` is the canonical Windows launch command. It resolves a Flutter binary and an MSYS2 MinGW toolchain, builds `./bridge` as `bin/bridge/remote_storage_bridge.dll`, then launches Flutter with `flutter run -d windows`.  
  `.\run_windows.ps1 -Build` builds the release bundle instead of running.  
  When validating integrated app startup on Windows, prefer `run_windows.ps1` over a bare `flutter run -d windows` so the bridge DLL and CGO toolchain are both set correctly.

## Git Workflow

- After completing the requested implementation and validation successfully, create a normal non-amended commit unless the user explicitly says not to commit.
- Do not include compiled binaries or other transient build artifacts in commits.
- Every time a new feature is added, update `README.md` in the same change set before committing.
- Maintain release note drafts in `CHANGELOG.md` under `## Unreleased` as work lands when the change is relevant to an upcoming release.

## Validation

- After each meaningful refactor batch, run the narrowest useful validation first.
- Before finishing, run `go test ./...` and `flutter analyze` unless the user explicitly asks for a different validation scope.
- Do not use screenshots as smoke-validation evidence.
- Do not run a local smoke test by default; after implementation, hand off app-level verification to the user unless they explicitly ask you to run it.


## Code Map (Cross-Session Knowledge)

> **Purpose:** This section captures the structure and responsibility of key features so new sessions do not have to re-explore the codebase. It must be kept up to date.
>
> **Maintenance rules (binding):**
>
> 1. **Feature work:** Every time a new feature is added or an existing feature's file set changes, update the relevant Code Map entry here in the same change set (before committing). List the files that participate in the feature, their responsibility, and the data flow between them.
> 2. **Exploration:** Any time the codebase is explored to answer a question, debug an issue, or understand a feature — even when no code change lands — record the discovered structure, file responsibilities, gotchas, and data flow into the relevant Code Map entry (or create a new one) before the turn ends. The goal is that the next session never has to re-read the same files to learn the same thing.
> 3. **Freshness:** Correct or remove entries that are no longer accurate. Do not leave this section stale — stale knowledge here is worse than no knowledge.

### Feature: File Sync (文件同步)

The sync feature lets users bind a local directory to a remote bucket prefix and keep them in sync (upload / download / two-way) on a configurable schedule, with conflict policies and exclude rules. The Go side runs a scheduler that computes diffs and executes operations; the Flutter side manages config and shows live status.

**Migration (2026-06-26):** Sync config management has been fully migrated from Settings to the File Sync Tasks page. The settings page no longer has a "文件同步" tab. The tasks page is now the **sole** entry point for creating, editing, deleting, toggling, and triggering sync profiles — this resolves the original UX friction where creating a task required navigating to Settings.

#### Flutter (Dart) files

- `lib/pages/file_sync_tasks_page.dart` — File Sync Tasks page. **The sole management hub for sync config.** Shows summary cards (enabled profiles, syncing, running/failed tasks), a "新建配置" button, profile rows with toggle/edit/delete/立即同步, and a list of `sync_*` transfer tasks. Listens to `TransferQueue` and `SyncProfileNotifier`. Takes `profiles` (List<ProfileInfo>) for the editor's account selector.
- `lib/pages/file_sync_tasks_page_actions.dart` — Part file containing the CRUD extension (`_FileSyncTasksActions`): `_addProfile`, `_editProfile`, `_saveProfile`, `_deleteProfile`, `_toggleEnabled`, `_triggerSync`. Extracted to keep the page under 500 lines.
- `lib/widgets/file_sync_profile_editor.dart` — Dialog for creating or editing a single `SyncProfile`. Fields: name, account, bucket, remote prefix, local dir (via `FilePicker`), direction, conflict policy, interval, quiet period, exclude rules, enabled toggle. Calls `onSave` callback on submit. Unchanged by the migration.
- `lib/models/sync_profile.dart` — Data models: `SyncDirection` (upload/download/twoway), `SyncConflictPolicy` (newest/localWins/remoteWins/skip), `SyncProfileStatus` (idle/syncing/error/paused), `SyncProfile` (mirrors `go/sync/profile.go`), `SyncProfileRuntime` (profile + live status/lastSyncAt/lastError/pendingOps). All have `fromJson` / `toJson` / `copyWith`.
- `lib/state/sync_profile_notifier.dart` — Singleton `SyncProfileNotifier` (ChangeNotifier). Polls Go runtime state every 3s. Exposes `profiles`, `saveProfile`, `deleteProfile`, `triggerProfile`. The tasks page is now the only UI listener.
- `lib/widgets/settings_file_sync_section.dart` — **DELETED** (2026-06-26). Its functionality moved to `file_sync_tasks_page.dart` + `file_sync_tasks_page_actions.dart`.

#### Go files

- `go/sync/profile.go` — `SyncProfile` struct, JSON tags, source of truth for the Dart model.
- `go/sync/store.go` — Persistence of sync profiles (load/save/list/delete).
- `go/sync/scheduler.go` — Periodic scheduler: triggers sync runs per profile based on `intervalSeconds` and `quietSeconds`.
- `go/sync/runner.go` — Orchestrates a single sync run end-to-end.
- `go/sync/diff.go` — Diffs local vs remote to compute the operation set.
- `go/sync/reconcile.go` — Conflict resolution using `SyncConflictPolicy`.
- `go/sync/executor.go` — Executes the planned operations (upload/download/delete/rename).
- `go/sync/rename_detect.go` — Detects renames/moves to avoid delete+upload churn.
- `go/sync/index.go` / `go/sync/helpers.go` — Indexing and shared utilities.

#### Data flow

1. User creates/edits a profile via `FileSyncProfileEditor`, opened from the tasks page (sole entry point).
2. `_FileSyncTasksActions._saveProfile` → `SyncProfileNotifier.saveProfile` → Go `saveSyncProfile` → `go/sync/store.go`.
3. `SyncProfileNotifier` polls `listSyncProfiles` every 3s → Go runtime state from `scheduler.go`/`runner.go`.
4. On interval or manual "立即同步" trigger → Go `runner.go` runs `diff.go` → `reconcile.go` → `executor.go`, enqueueing `sync_*` tasks into the shared `TransferQueue`.
5. `FileSyncTasksPage` displays both profile statuses (from `SyncProfileNotifier`) and live `sync_*` tasks (from `TransferQueue`).

### Feature: Transfer Queue (通用传输队列)

Shared upload/download queue backing both manual file operations and sync-generated tasks. Sync tasks are identified by `rawType` starting with `sync_`.

#### Key files

- `lib/state/transfer_queue.dart` — Core `TransferQueue` singleton.
- `lib/state/transfer_task.dart` — `TransferTask` model with `isSyncTask` getter and `rawType` (`sync_upload`, `sync_download`, `sync_delete`, `sync_rename`).
- `lib/state/transfer_queue_*.dart` — Split concerns: metrics, sync, local progress, foreground, storage, directory children.
- `lib/pages/transfers_page.dart` — Transfers page showing the full queue.

### Navigation structure

- `lib/pages/main_layout_page.dart` — Root layout with sidebar navigation. Routes include 文件同步 (`FileSyncTasksPage`), 文件管理 (`FileManagerPage`), 传输 (`TransfersPage`), 回收站 (`GlobalTrashPage`), 分享管理 (`ShareManagementPage`), and 设置 (`SettingsPage`).
- `lib/pages/settings_page.dart` — Settings page with sub-tabs (通用设置, Windows 设置, 关于). Sync management was **removed** from Settings (2026-06-26) and now lives entirely in the File Sync Tasks page.
