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
- `lib/widgets/file_sync_profile_editor.dart` — Editor widget for creating or editing a single `SyncProfile`. **2-step wizard:** Step 1 同步两端 (optional name, local dir via `FilePicker`, remote dir via `RemoteDirectoryPickerDialog`), Step 2 同步策略 (direction, conflict policy, interval, quiet period, exclude rules, enabled toggle). Receives `api` + `List<FileManagerBucketEntry> buckets`. **`asDialog`:** `true` (default) wraps step content in `ShadDialog` for Web / in-app fallback; `false` returns bare `_buildContent` only — **never nest ShadDialog inside the detached sub-window**. Sub-window layout uses `_buildSubWindowLayout`: fixed step indicator + scrollable step body + pinned nav buttons (avoids RenderFlex overflow on step 2). On save success: `onSaved` then `Navigator.pop` only when `asDialog` is true.

**Sub-window architecture (2026-06-27):** The sync config editor now opens as a **detached OS sub-window** instead of a cramped ShadDialog. Follows the same `desktop_multi_window` pattern as `FilePreviewWindowApp`:
- `lib/models/sync_editor_window_args.dart` — Args model with `profileNames` (account names to load buckets from) and optional `initialProfileJson` (for edit mode). Serialized to JSON for crossing the multi-window boundary.
- `lib/app/sync_editor_window_app.dart` — Sub-window root is **`ShadApp` + `buildAppTheme`** (required — bare `MaterialApp` causes `ShadTheme.of()` crash). Body: bootstraps its own `RemoteStorageApi` bridge, loads buckets from account profiles, `Scaffold` + custom title bar + `FileSyncProfileEditor(asDialog: false)`. On save, `SyncProfileNotifier.saveProfile` then `windowManager.close()` via `onSaved`.
- `lib/services/sync_editor_window_service.dart` (+ `_io.dart` / `_web.dart`) — Conditional service: desktop uses `WindowController.create()`, web falls back to returning `false` so callers use in-app dialog.
- `lib/app/app_entry_io.dart` — Dispatch: checks `SyncEditorWindowArgs.matches(arguments)` and launches `SyncEditorWindowApp`.
- `lib/services/desktop_modal_overlay_controller.dart` / `lib/widgets/desktop_modal_scrim.dart` — Parent engine shows grey `AbsorbPointer` scrim (ref-count) while modal sub-windows are open; `acquireParentModalOverlay` on open, `modal_overlay_release` method on close.
- `lib/services/desktop_sub_window_modal.dart` — Shared acquire/release + `windowManager.setMovable(false)` in `app_entry_io` for sync editor and remote picker windows (no title-bar drag).
- `lib/services/desktop_overlay.dart` — **`showDesktopOverlayOrDialog`**: desktop tries detached sub-window via `openSubWindow`; Web uses `showShadDialog` via `showDialog`. Use this for large flows (sync editor, remote directory picker) instead of calling `showShadDialog` directly from pages.
- `lib/services/desktop_window_method_host.dart` — Main engine (and sync-editor sub-window) registers `WindowMethodChannel` handler for `remote_directory_picker_result` so picker sub-windows can return JSON to the **creator** window (`creatorWindowId` in args).
- `lib/models/remote_directory_picker_window_args.dart` / `lib/app/remote_directory_picker_window_app.dart` / `lib/services/remote_directory_picker_window_service.dart` — Remote directory picker as 720×560 sub-window; `RemoteDirectoryPickerDialog(asDialog: false)` inside. `showRemoteDirectoryPicker` routes through `showDesktopOverlayOrDialog`.
- `lib/widgets/remote_directory_picker_dialog. **`showRemoteDirectoryPicker`** uses `showDesktopOverlayOrDialog` (sub-window on desktop). Widget supports `asDialog`, `onConfirm`, `onCancel` for sub-window mode.dart` — File-manager-style remote directory picker dialog. **`showRemoteDirectoryPicker`** uses `showDesktopOverlayOrDialog` (sub-window on desktop). Widget supports `asDialog`, `onConfirm`, `onCancel` for sub-window mode. Shows bucket list at top level, then directory browsing (breadcrumbs, navigate into dirs, create directory). "选择当前目录" returns a `RemoteDirectoryResult(bucket, prefix, profileName, config)`. Uses `listObjects` and `createDirectory` from `RemoteStorageGateway`.
- `lib/widgets/remote_directory_picker_actions.dart` — Part file with `_loadObjects` and `_createDirectory` methods for the picker.
- `lib/widgets/file_sync_profile_editor_steps.dart` — Part file with top-level functions `stepPickEndpoints`, `stepSyncStrategy` and bucket tile/list helpers. Receives `_FileSyncProfileEditorState self` to access fields/controllers and calls `self.markDirty(...)` for setState.
- `lib/models/sync_profile.dart` — Data models: `SyncDirection` (upload/download/twoway), `SyncConflictPolicy` (newest/localWins/remoteWins/skip), `SyncProfileStatus` (idle/syncing/error/paused), `SyncProfile` (mirrors `go/sync/profile.go`), `SyncProfileRuntime` (profile + live status/lastSyncAt/lastError/pendingOps). All have `fromJson` / `toJson` / `copyWith`.
- `lib/state/sync_profile_notifier.dart` — Singleton `SyncProfileNotifier` (ChangeNotifier). Polls Go runtime state every 3s. Exposes `profiles`, `saveProfile`, `deleteProfile`, `triggerProfile`. The tasks page is now the only UI listener.
- `lib/widgets/settings_file_sync_section.dart` — **DELETED** (2026-06-26). Its functionality moved to `file_sync_tasks_page.dart` + `file_sync_tasks_page_actions.dart`.

#### Delete detection and sync (exploration)

Each reconcile pass compares **three views** per relative path: local scan (`localSide`), remote list under prefix (`remoteSide`), and **persisted index** (`IndexEntry` in bbolt — last synced local/remote size+mtime). Keys are the union of all three sets (`go/sync/diff.go` `classify`).

**“Deletion” is inferred when one side is missing now but the index says that side used to exist:**

| Now | Index hint | Direction | Op |
|-----|------------|-----------|-----|
| local missing, remote has file | `idx.LocalSize` or `idx.LocalMTime` ≠ 0 | **twoway** | `delete_remote` (propagate local delete to bucket) |
| same | same | **upload only** | skip |
| same | same | **download only** | `download` (`local_deleted_redownload` — treat as local loss, restore from remote) |
| local has file, remote missing | `idx.RemoteSize` or `idx.RemoteMTime` ≠ 0 | **twoway** | `delete_local` |
| same | same | **download only** | `download` (`remote_deleted_reupload` naming in code is upload path for upload-only — see `diff.go` case `l.present && !r.present`) |
| same | same | **upload only** | `upload` (`remote_deleted_reupload`) |

If a path is absent on both sides but still in index → `skip` (`stale_index`). Brand-new file on one side only (index never had the other side) → normal `upload` / `download`, not delete.

**Rename vs delete:** After classify, `reconcile.aggregateRenames` pairs a pending delete with an add of **equal size** (twoway only) → `OpRename` instead of delete+upload (`go/sync/rename_detect.go`).

**Execution:** `OpDeleteRemote` → `backend.DeleteObject`; `OpDeleteLocal` → `os.Remove`. Queue kind `sync_delete`. On success, index entry for that rel path is **removed** (`executor.updateIndex`). Deletes involving local paths can be deferred by **quiet period** only for upload/rename/delete_local hot-file check in `runner.isHot` — remote-only delete ops are not gated by quiet period.

**Not real-time FS watch:** Periodic reconcile (`intervalSeconds`) + manual trigger; not inotify-style instant delete sync.

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

1. User creates/edits a profile from **文件同步** page only (`_addProfile` / `_editProfile`): desktop → `SyncEditorWindowService.openEditor` → sub-window; Web or unsupported → `showShadDialog` + `FileSyncProfileEditor(asDialog: true)`.
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

### Feature: macOS Window Lifecycle & Positioning

Controls how the main window is sized, centered, shown/hidden, and terminated on macOS.

#### Key files

- `macos/Runner/MainFlutterWindow.swift` — Main window class (`NSWindow` subclass). Owns `MenuBarController` (tray). In `awakeFromNib` it sets transparent titlebar, full-size content view, min size, then calls `applyDefaultWindowLayout()` on the next run loop tick. `applyDefaultWindowLayout` resolves a size via `resolvedInitialWindowSize()` (scales to fit smaller screens) then centers via `centeredWindowFrame(for:)` using `self.screen ?? NSScreen.main`. Overrides `close()` to intercept with a confirm dialog (退出 / 隐藏到托盘 / 取消) unless `allowsDirectClose` is set. `terminateWithoutConfirmation` bypasses the dialog.
- `macos/Runner/AppDelegate.swift` — `FlutterAppDelegate`. `applicationShouldTerminateAfterLastWindowClosed` returns `false` (keeps app alive when window hidden). `applicationShouldHandleReopen` calls `showYunjuanMainWindow()` (dock click reopens window). `applicationWillTerminate` calls bridge `cleanup_mounts` via dlopen to unmount buckets on exit.
- Top-level free functions: `yunjuanMainWindow()` finds the main `MainFlutterWindow`; `showYunjuanMainWindow()` / `hideYunjuanMainWindow()` show/hide via `orderOut` / `makeKeyAndOrderFront` + `NSApp.activate`.

#### Startup screen behavior

The window centers on `self.screen ?? NSScreen.main`. `NSScreen.main` is whatever macOS considers the primary display (the one with the menu bar in System Settings → Displays). If the app launches on the "wrong" screen, the fix is in macOS display settings, not in app code.

#### Constants

- Default size: 1160 x 740; minimum: 920 x 620; compact fallback: 840 x 560.
- Size resolution scales to 72% width / 66% height of the visible frame if the defaults don't fit.

### Navigation structure

- `lib/pages/main_layout_page.dart` — Root layout with sidebar navigation. Routes include 文件同步 (`FileSyncTasksPage`), 文件管理 (`FileManagerPage`), 传输 (`TransfersPage`), 回收站 (`GlobalTrashPage`), 分享管理 (`ShareManagementPage`), and 设置 (`SettingsPage`).
- `lib/pages/settings_page.dart` — Settings page with sub-tabs (通用设置, Windows 设置, 关于). Sync management was **removed** from Settings (2026-06-26) and now lives entirely in the File Sync Tasks page.
