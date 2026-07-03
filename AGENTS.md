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

### Hover-aware clickable rows (binding rule)

Any clickable row, tile, or sidebar item that needs a hover visual response **must be a dedicated `StatefulWidget`** that owns a `bool _hovered` field. The field is toggled by `MouseRegion(onEnter/onExit)` to `setState`, and drives background color, text color, and cursor via an `AnimatedContainer`. This is the only reliable way to get hover to rebuild the widget subtree.

**Never** build hover items as inline `MouseRegion` + `Container` inside an `extension on State` or a plain builder — the extension/builder has no mutable field to store `_hovered`, so the `onEnter`/`onExit` callbacks have nowhere to write, hover never rebuilds, and you get a dead or stuck hover state. This bug has re-occurred multiple times (settings sidebar rail, file list tiles).

Canonical implementations to copy:
- `lib/pages/main_layout_page.dart` `_SidebarNavItem` / `_SidebarNavItemState` — sidebar nav items.
- `lib/widgets/file_list_tile.dart` — file-manager rows (`dimmed` disables hover).
- `lib/widgets/transfer_task_widgets.dart` — transfer queue rows.
- `lib/pages/settings_page_layout.dart` `_SettingsGroupTile` — settings left rail entries.

The idle cursor should be `SystemMouseCursors.basic` (basic arrow), switching to `SystemMouseCursors.click` only on hover, so it does not get stuck on a pointing hand inherited from an ancestor.

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

- `lib/pages/file_sync_tasks_page.dart` — File Sync Tasks page. **The sole management hub for sync config.** Summary cards + profile rows; full `sync_*` queue lives on **Transfers**; each profile card shows latest pending/running task via `file_sync_profile_active_task.dart`.
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
- `lib/widgets/remote_directory_picker_dialog.dart` — File-manager-style remote directory picker. **`showRemoteDirectoryPicker`** uses `showDesktopOverlayOrDialog` (sub-window on desktop). Widget supports `asDialog`, `onConfirm`, `onCancel` for sub-window mode. Shows bucket list at top level, then directory browsing (breadcrumbs, navigate into dirs, create directory). "选择当前目录" returns a `RemoteDirectoryResult(bucket, prefix, profileName, config)`. Uses `listObjects` and `createDirectory` from `RemoteStorageGateway`.
- `lib/widgets/remote_directory_picker_list.dart` — Part file: directory list + **file rows for display only**. Directories and `..` are selectable; **files are not** (`dimmed: true` on `FileListTile`). Toggle **显示隐藏文件** filters dot-prefixed names. File icons use **grayscale `ColorFilter.matrix`** (not `srcATop` tint) so multi-color SVGs (e.g. zip) grey correctly; title/size use muted text via `FileListTile.dimmed`.
- `lib/widgets/file_list_tile.dart` — Shared list row; **`dimmed`** disables hover/press, uses arrow (not hand) cursor, and paints title/size in muted foreground for non-selectable rows.
- `lib/widgets/remote_directory_picker_actions.dart` — Part file with `_loadObjects` and `_createDirectory` methods for the picker.
- `lib/widgets/file_sync_profile_editor_steps.dart` — Part file with top-level functions `stepPickEndpoints`, `stepSyncStrategy` and bucket tile/list helpers. Receives `_FileSyncProfileEditorState self` to access fields/controllers and calls `self.markDirty(...)` for setState.
- `lib/models/sync_profile.dart` — Data models: `SyncDirection` (upload/download/twoway), `SyncConflictPolicy` (newest/localWins/remoteWins/skip), `SyncProfileStatus` (idle/syncing/error/paused), `SyncProfile` (mirrors `go/sync/profile.go`), `SyncProfileRuntime` (profile + live status/lastSyncAt/lastError/pendingOps). All have `fromJson` / `toJson` / `copyWith`.
- `lib/state/sync_profile_notifier.dart` — Singleton `SyncProfileNotifier` (ChangeNotifier). Polls Go runtime state every 3s. Exposes `profiles`, `saveProfile`, `deleteProfile`, `triggerProfile`. The tasks page is now the only UI listener.
- `lib/widgets/settings_file_sync_section.dart` — **DELETED** (2026-06-26). Its functionality moved to `file_sync_tasks_page.dart` + `file_sync_tasks_page_actions.dart`.

#### Delete detection and sync (exploration)

**Remote scan depth (2026-06-27):** `go/sync/reconcile.go` `scanRemote` must list **all nested files** under `RemotePrefix`, not only the immediate listing page. File-manager `ListObjectsPage` uses delimiter/depth-1 for UI browsing; sync uses `storage.Backend.ListObjectsRecursive` (S3: paginator without delimiter; WebDAV: PROPFIND depth infinity; Baidu: BFS over directories). If sync only saw top-level files, empty local + remote tree with subfolders would produce **zero downloads** even under two-way sync.
**Local directory keys:** `scanLocal` only walks files, so `classify` calls `localDirSide` to detect existing folders. Without this, `ensure_local_dir` index entries made the next pass think the remote dir vanished and emitted `delete_local` on the folder path.
**Empty remote folders:** Sync also emits `OpEnsureLocalDir` (`sync_mkdir`) when the remote side has a directory marker (S3 `key/` placeholder, WebDAV/Baidu `IsDir`) and local is missing it. File-only reconcile never created folders when a remote dir had no files inside.

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

### Feature: Account Management (账号管理)

Lists configured storage accounts and lets users add, edit, or remove them. On desktop, the add/edit form now opens as a **detached OS sub-window** instead of an in-page `ShadDialog`, matching the file-sync editor pattern. On Web, or when the sub-window cannot be created, it falls back to the original `ShadDialog`.

**Sub-window architecture (2026-07-02):** The add/edit form uses the same `desktop_multi_window` plumbing as the sync editor and remote directory picker:
- `lib/models/account_editor_window_args.dart` — Args model with `initialConfigJson` (edit mode), `profileName`, `editing`, and `creatorFrame*`. JSON is the only data that crosses the multi-window boundary.
- `lib/app/account_editor_window_app.dart` — Sub-window root is `ShadApp` + `buildAppTheme`. Body: bootstraps its own `RemoteStorageGateway`, custom title bar, and `CloudStorageAccountDialog(asDialog: false)`. On save it calls `api.saveProfile`, shows a toast, sends `account_editor_saved` to the creator window, and closes itself.
- `lib/services/account_editor_window_service.dart` (+ `_io.dart` / `_web.dart`) — Conditional service: desktop uses `WindowController.create()` and registers a `VoidCallback` with `DesktopWindowMethodHost`; Web returns `false` so callers fall back to `showShadDialog`.
- `lib/app/app_entry_io.dart` — Dispatch: checks `AccountEditorWindowArgs.matches(arguments)` and launches `AccountEditorWindowApp`. Window size is configured as `520×640` (minimum `480×560`).
- `lib/services/desktop_window_method_host.dart` — Main engine multiplexes `account_editor_saved` to the registered callback so the parent window can refresh its account list after the sub-window saves.
- `lib/services/desktop_sub_window_modal.dart` — `account_editor` is included in `_isModalSubWindowArguments` so the modal overlay and always-on-top behavior apply consistently.
- `lib/services/desktop_overlay.dart` — `AccountEditorWindowService.isSupported` is included in the `showDesktopOverlayOrDialog` helper check.
- `lib/widgets/cloud_storage_account_dialog.dart` — The dialog widget is now dual-mode: `asDialog: true` wraps the form in a `ShadDialog` (Web / fallback); `asDialog: false` returns bare content for the detached sub-window. Its `onSave` callback now receives a `RemoteStorageConfig` built from the form, and it accepts optional `onSaved` / `onCancel` callbacks for the sub-window path.
- `lib/models/cloud_storage_account_draft.dart` — Plain form draft model, moved out of the dialog to avoid import cycles with the config builder.
- `lib/utils/account_config_builder.dart` — Builds a `RemoteStorageConfig` from the draft, preserving existing secrets when the user leaves password fields blank in edit mode.
- `lib/utils/account_profile_name.dart` — Shared profile-key generator used by both the in-page dialog path and the detached sub-window path.
- `lib/pages/cloud_storage_page.dart` — Entry point. `_showAddAccountDialog` / `_showEditAccountDialog` first try `AccountEditorWindowService.openEditor`; on `false` they fall back to `showShadDialog`. Edit mode loads the existing config with `api.loadProfile` before passing it to the sub-window or dialog.

#### Data flow
1. User clicks "新增账号" or row "编辑" in `CloudStoragePage`.
2. `AccountEditorWindowService.openEditor` acquires the parent modal overlay, registers `widget.onRefresh` as the `account_editor_saved` callback, and spawns the sub-window.
3. The sub-window bootstraps its own bridge, renders `CloudStorageAccountDialog(asDialog: false)`.
4. User fills the form and submits; the dialog builds a `RemoteStorageConfig` via `buildAccountConfig` and calls the sub-window `_onSave`.
5. `_onSave` generates the profile key (or reuses the existing one) and calls `api.saveProfile`.
6. On success, the dialog invokes `onSaved`, which sends `account_editor_saved` to the creator window, then closes the sub-window.
7. The main engine receives `account_editor_saved`, calls the registered callback (`widget.onRefresh`), and the account list refreshes.
8. If the sub-window path is unsupported, the flow falls back to `showShadDialog` with `CloudStorageAccountDialog(asDialog: true)`, saving directly in the page callback.

### Feature: Transfer Queue (通用传输队列)

Shared upload/download queue backing both manual file operations and sync-generated tasks. Sync tasks are identified by `rawType` starting with `sync_`.

#### Key files

- `lib/state/transfer_queue.dart` — Core `TransferQueue` singleton.
- `lib/state/transfer_task.dart` — `TransferTask` model with `isSyncTask` getter and `rawType` (`sync_upload`, `sync_download`, `sync_delete`, `sync_rename`).
- `lib/state/transfer_queue_*.dart` — Split concerns: metrics, sync, local progress, foreground, storage, directory children.
- `lib/pages/transfers_page.dart` — Transfers page showing the full queue.

### Feature: File Preview & Upload Cache Seeding (文件预览与上传缓存衔接)

点击/双击文件打开走的是 `FileAccessService._ensureCachedObjectRequest`：`headObject` 拿远端 size/mtime → `FileCacheStore.findUsableCachePath` 查 SQLite 缓存表 → 命中则直接用缓存文件，未命中则建 `download` 任务拉到 `<cacheDir>/files/<bucket>/<key>` 并写缓存记录。缓存命中的硬约束：记录的 `localPath` 必须 `_isInsideRoot` 缓存目录内，且 size/mtime 与远端匹配（`_matchesRemoteObject`）。

**问题（2026-06-30 修复）：** 上传走传输队列，成功后只 `markTaskDone` + 刷新列表，从不动缓存表。所以"刚上传完的文件双击还要重下"——上传与预览是两套独立记账。

**修复：** 上传成功后调 `FileAccessService.seedCacheFromUpload`（io 实现 / web 空操作）：`headObject` 拿远端元数据 → 把本地源（`localSourcePath` 或 `bytes`）copy/写入缓存目录 → `upsertCacheRecord`。以远端 size/mtime 为准（不能用本地 stat，否则比对失败）。整个 seed 包 try/catch 吞异常：只是缓存优化，绝不阻断"上传已成功"。`unawaited` 后台执行，不阻塞列表回显。

#### Key files
- `lib/services/file_access_service_io.dart` — `seedCacheFromUpload`（桌面实现）、`_ensureCachedObjectRequest`（预览/打开缓存命中逻辑）。
- `lib/services/file_access_service_web.dart` — `seedCacheFromUpload` 空操作（浏览器无本地缓存目录）。
- `lib/pages/file_manager_page_actions.dart` — `_runUploadTask`（本地路径上传，传 `localSourcePath`）、`_runBrowserUploadTask`（bytes 上传，传 `bytes`）成功分支调 seed。
- `lib/services/file_cache_store.dart` — SQLite 缓存表：`findUsableCachePath` / `cachePathFor` / `upsertCacheRecord`；`_matchesRemoteObject` 要求 size+mtime 都匹配。
- `lib/pages/file_manager_page_preview.dart` — 双击预览入口 `_showObjectPreview`。

### Feature: Local File Paste / Drag Upload (本地粘贴/拖拽上传)

桌面端文件管理页接收本地文件输入（访达复制后 Cmd+V 粘贴、拖拽到列表）。**粘贴走 method channel（见下）**；拖拽走 `super_drag_and_drop` 的 `DropRegion`。二者共用 `DesktopFileTransferService` 把 file:// URI 解析成本地路径，再交给 `_uploadLocalPaths` 入队上传。

**根因与修复（2026-07-01）：** Flutter macOS 引擎的 `FlutterViewController.performKeyEquivalent` 在 `firstResponder == _flutterView` 时调 `[_flutterView keyDown:event]`。但 `FlutterView` 是普通 `NSView`，没有 override `keyDown:`——默认实现走 `interpretKeyEvents:`，把 Cmd+V 交给 TSM 输入上下文（日志表现为 `NSSoftLinking - _TSMMenuKeyTransWithModifiersBeginWithEvent`），TSM 静默吞掉 `paste:`/`copy:` selector，事件**永远到不了**引擎 keyboardManager 或 Flutter `Shortcuts`。

**解决方案：** 不再依赖 Flutter `Shortcuts` 处理 Cmd+V/C。改为在 `MainFlutterWindow.performKeyEquivalent`（NSWindow 层）截获 Cmd+V/C，`return true` 阻止 AppKit 菜单和 TSM 处理，通过 `cloud_volume/clipboard_shortcut` method channel 直接通知 Dart 侧。`FileTransferClipboardRegion` 里的 `Shortcuts`/`_PasteFilesIntent` 仍保留（理论上对非 macOS 或未来 engine 修复有用），但 macOS 上实际由 channel 驱动。

#### Key files

- `macos/Runner/ClipboardShortcutPlugin.swift` — `ClipboardShortcutPlugin`（FlutterPlugin，注册 method channel `cloud_volume/clipboard_shortcut`）+ `ClipboardShortcutCoordinator`（单例，持有 plugin 实例供 window 调用）。
- `macos/Runner/MainFlutterWindow.swift` — `performKeyEquivalent` override：截获 Cmd+V → `ClipboardShortcutCoordinator.shared.handlePaste()`、Cmd+C → `handleCopy()`，其余交 `super`。在 `awakeFromNib` 注册 plugin。
- `lib/services/clipboard_shortcut_channel.dart` — `ClipboardShortcutChannel` 单例：`start(onPaste, onCopy)` 设置 `MethodChannel` handler；`isSupported` 仅 macOS 非 Web。
- `lib/widgets/file_transfer_clipboard_region.dart` — `Shortcuts`+`Actions`+`DropRegion` 包装层（拖拽实际生效；粘贴的 `Shortcuts` 在 macOS 上被 channel 旁路）。
- `lib/services/desktop_file_transfer_service_io.dart` — `localFilePathsFromClipboard`（读 `SystemClipboard` 的 `Formats.fileUri`）、`localFilePathsFromDrop`、`writeLocalFilesToClipboard`、`localUploadEntries`。
- `lib/pages/file_manager_page_transfer_inputs.dart` — `_uploadLocalPaths`（入口，含 `_ensureCurrentDirectoryWritable` 兜底校验）、`_copySelectedObjectsToClipboard`、`_handleNativePaste` / `_handleNativeCopy`（channel 回调入口）。
- `lib/pages/file_manager_page_access.dart` — `_currentDirectoryWritable` / `_ensureCurrentDirectoryWritable` / `_refreshDirectoryAccess`（WebDAV 目录 PROPFIND 可写性检查）。

#### Data flow

1. 访达复制文件 → 系统 pasteboard 含 `public.file-url`。
2. macOS Cmd+V → `MainFlutterWindow.performKeyEquivalent` 截获 → `ClipboardShortcutCoordinator.handlePaste()` → method channel `paste`。
3. Dart `ClipboardShortcutChannel` → `_handleNativePaste` → `DesktopFileTransferService.localFilePathsFromClipboard` 解析路径 → `_uploadLocalPaths` → `_ensureCurrentDirectoryWritable` → `TransferQueue.startTask` 入队上传。

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
- `lib/pages/settings_page.dart` — Settings page. Groups (通用设置, Windows 设置, 关于) use a **left vertical sidebar rail** (not top tabs). Sync management was **removed** from Settings (2026-06-26) and now lives entirely in the File Sync Tasks page.

### Feature: Settings Page Layout (设置页布局)

The settings page uses a **two-column anchor layout**: a left vertical anchor rail with section headers (通用 / Windows / 关于), and a right scrollable page that shows all settings cards in one continuous column. Clicking a left rail item scrolls the right page to that card; scrolling the right page updates the active highlight in the left rail.

#### Key files
- `lib/pages/settings_page.dart` — `SettingsPage` + `_SettingsPageState`. `_SettingsTab` enum identifies one card/anchor per config block. State owns `_contentScrollController`, `_sectionKeys`, and `_activeTab`. `build()` renders a `Row`: left `SizedBox(width: 180)` with title + `_buildGroupRail(theme)`; right `Expanded` + `SingleChildScrollView(controller: _contentScrollController)` with `_buildAllContent`.
- `lib/pages/settings_page_layout.dart` — part file. `_SettingsLayout` extension: `_railGroups()` builds `_SettingsRailGroup` list with section headers + anchors; `_buildGroupRail` renders headers + `_SettingsGroupTile` rows; `_tabLabel` maps enum to Chinese label; `_buildAllContent` renders every visible card as one page using `KeyedSubtree` + `_sectionKeys`; `_scrollToAnchor` uses `Scrollable.ensureVisible`; `_syncActiveAnchorFromScroll` updates `_activeTab` by finding the keyed section nearest the viewport top. `_SettingsGroupTile` is the hover-aware StatefulWidget tile (must be StatefulWidget — see Hover rule above).
- `lib/pages/settings_page_sections.dart` — part file. `_SettingsSections` extension with per-anchor card builders (`_buildUpdateSection`, `_buildProxySection`, `_buildAppearanceSection`, `_buildDownloadSection`, `_buildCacheSection`, `_buildVisibilitySection`, `_buildSyncSection`, `_buildTrashSection`, `_buildWebdavSection`, `_buildResetAccountSection`, `_buildConfigManageSection`, `_buildWindowsEntrySection`, `_buildWindowsWritebackSection`, `_buildWindowsMountSection`, `_buildAboutSection`). Each returns `[_buildCard(...)]`.
- `lib/pages/settings_page_actions.dart` — part file with `_SettingsPageActions` extension: all config save/refresh/cleanup actions.

#### Data flow
1. `_SettingsPageState.build()` wires the right-side `SingleChildScrollView` to `_contentScrollController` and calls `_buildAllContent(theme, config)`.
2. `_railGroups()` returns 通用 (download anchor only when supported; WebDAV 凭据 anchor only on Web), Windows (if `isWindowsPlatform`), 关于 groups.
3. `_buildAllContent` loops through those same visible anchors, wrapping each section card with the matching `_sectionKeys[tab]`.
4. Tapping `_SettingsGroupTile` calls `_scrollToAnchor(tab)`, sets `_activeTab`, then `Scrollable.ensureVisible` scrolls the right page to the keyed card.
5. Manual right-side scrolling triggers `_syncActiveAnchorFromScroll`, which updates the left rail highlight to the section nearest the top of the viewport.
6. Left rail scrolls independently when the anchor list is taller than the viewport.

### Feature: Flutter → Go app logging

- `bridge/dispatch_log.go` — `write_flutter_log` bridge method; lines go to stderr + `BridgeLogPath()` via `log.Printf` with `[app/<tag>]` prefix.
- `lib/utils/app_log.dart` — `AppLog.info/warning/error`; bound in `AppBootstrapPage` after API bootstrap.
- `RemoteStorageGateway.writeAppLog` — desktop FFI; web no-op.

### Feature: In-App Auto Update (应用内自动更新)

Detects new GitHub releases and, on desktop, downloads + installs the correct platform package in-app — no manual uninstall or command-line steps needed.

**Mirror rule (2026-07-02 fix):** The GitHub Releases **API** call (`checkLatestRelease`) is **always direct** to `api.github.com` — public download mirrors like `gh-proxy.com` reject api.github.com URLs with HTTP 403. The configured mirror prefix (`UpdateNetworkConfig.wrapUrl`) is now applied **only** to the asset **download** URL in `downloadAndInstallAsset`.
**Architecture matching (2026-07-02 fix):** `matchPlatformAsset` previously hardcoded universal-first on macOS, so an arm64 app would download the larger universal DMG. It now prefers the **running build architecture**: the Go bridge exposes `get_build_info` returning `buildArch` (injected at compile time via `-ldflags -X main.buildArch=...` in Makefile / `build_desktop_packages.sh`); Flutter reads it via `widget.api.getBuildInfo()` and passes it to `matchPlatformAsset`. If the bridge is unavailable (web, old dev build), it falls back to `runtimeCpuArchitecture` (parsed from `Platform.version`). Universal is tried only after the arch-specific package, and as a fallback when the specific arch asset is absent.
**Download progress (2026-07-02 fix):** When the server does not report `Content-Length` and the asset metadata has no size, the progress bar previously stayed stuck at 0%. `_installProgress` is now initialized to `-1` (indeterminate); the `LinearProgressIndicator` uses `null` value (continuous animation) and the status text shows downloaded bytes via `_formatBytes`.
**Temp download path (2026-07-03 fix):** Historical Dart-side temp-dir issue; install path is now Go `bridge/dispatch_app_install.go` (`os.TempDir()/app_updates`, `MkdirAll` before download).

**Bundled dylib load order (2026-07-03 fix):** macOS bundles may contain two copies of `libremote_storage_bridge.dylib` — `Contents/Frameworks/` (from `make build-macos`) and a stale `Contents/MacOS/` copy from older dev runs. `_findBundledLibraryPath` previously preferred `MacOS/` first, so Flutter FFI loaded the old dylib without `install_app` → `unsupported bridge method "install_app"`. Fix: probe `Frameworks/` before `MacOS/`; `Makefile` `build-macos` runs `rm -f` on `Contents/MacOS/$(dylib)` before `cp` to Frameworks.

#### Key files

- `lib/bridge/remote_storage_bridge.dart` — FFI loader: `connect()` / `openAtPath()`; `_findBundledLibraryPath()` macOS order Frameworks → MacOS.
- `lib/services/app_update_service.dart` — `AppUpdateService.checkLatestRelease`: fetches GitHub Releases API **directly** (never wrapped by mirror), parses `tag_name` + `assets` array into `AppUpdateCheckResult` with `List<ReleaseAsset>`. Also has `compareVersionLabels` for semver comparison.
- `lib/services/platform_asset_matcher.dart` — `matchPlatformAsset(assets, {runtimeArchitecture})`: picks the correct asset. macOS order: arch-specific DMG/zip → universal DMG/zip → other-arch DMG/zip; Windows prefers `installer.exe` → `.zip`; Linux prefers `.AppImage` → `.tar.gz`.
- `lib/services/app_installer.dart` — Conditional export: IO → `app_installer_io.dart`, Web → `app_installer_stub.dart`. Exports `kSupportsInAppInstall` and `downloadAndInstallAsset`.
- `lib/services/app_installer_io.dart` — Desktop: delegates to `api.installApp()` → bridge `install_app`; progress via `TransferQueue` only (no Dart `Process.run` / download).
- `bridge/dispatch_app_install.go` — Go `install_app`: download (mirror/proxy), platform install (DMG/ZIP/exe/AppImage/tar), relaunch, `os.Exit(0)`; progress via `s3ops` transfer monitor.
- `lib/services/app_installer_stub.dart` / `app_installer_web.dart` — Web stub: returns error string (no local filesystem access).
- `lib/widgets/settings_update_section.dart` — Update UI in 设置 → 通用设置 → 应用更新. Calls `widget.api.getBuildInfo()` at init to load `_buildArch`, passes it to `matchPlatformAsset`. Shows version status, “检测更新”, “一键更新” (when matched asset exists), “取消更新” while an `app_update` task is active, indeterminate-or-percentage progress bar, and “GitHub 下载” fallback.
- `lib/widgets/settings_update_mirror_field.dart` — GitHub download mirror input (extracted from `settings_update_section.dart` to keep it under 500 lines). Persisted via `UpdateNetworkConfig`; affects only `downloadAndInstallAsset` download URLs.
- `bridge/build_info.go` — `buildArch` package var (set by ldflags) + `getBuildInfo()` returns `{buildArch, runtimeOS, runtimeArch}`. Falls back to `runtime.GOARCH` when `buildArch` is empty (local dev builds).
- `bridge/dispatch.go` — Routes `get_build_info` → `getBuildInfo()`.
- `lib/platform/platform_info_io.dart` / `_stub.dart` / `_web.dart` — `runtimeCpuArchitecture` heuristic (parses `Platform.version`), used as Dart-side fallback.

#### Data flow

1. User clicks “检测更新” → `AppUpdateService.checkLatestRelease` → GitHub API **direct** (no mirror).
2. If `updateAvailable` and `matchPlatformAsset(assets, runtimeArchitecture: _buildArch)` finds a matching asset → “一键更新” button appears.
3. User clicks “一键更新” → `lib/services/app_installer_io.dart` `downloadAndInstallAsset` → `api.installApp(...)` → bridge `install_app` → `bridge/dispatch_app_install.go` spawns background goroutine, returns `taskId`.
4. Go goroutine streams download (URL wrapped by mirror if configured) to `os.TempDir()/app_updates/`, reporting progress through `s3ops` transfer monitor; Flutter `_SettingsUpdateSectionState._onTransferQueueChanged` renders the progress bar.
5. On download complete, goroutine performs platform install: macOS mounts DMG (`hdiutil attach -plist`) and replaces `/Applications/云卷.app`, Windows runs `.exe` `/SILENT`, Linux replaces AppImage / extracts tarball.
6. If the user clicks “取消更新” before completion, `SettingsUpdateSection._cancelInstall` calls `TransferQueue.cancelTask(taskId)` (or `api.cancelTransfer(taskId)` before the task has been polled), which reaches bridge `cancel_transfer`; Go `CancelTransfer` invokes the stored context cancel and aborts the HTTP download.
7. `relaunchApp()` starts the new binary, then `os.Exit(0)`.

### Feature: Global Proxy & Network Configuration (全局代理设置)

Three proxy modes: system (read `HTTP_PROXY`/`HTTPS_PROXY` env vars, default), direct (no proxy), custom (user-specified URL). Affects all outbound traffic.

#### Key files

- `go/config/config.go` — `ProxyMode` / `ProxyURL` fields on `RemoteStorageConfig`; `normalizeProxyMode` validates to system/direct/custom.
- `go/config/proxy.go` — `ProxyTransport(mode, customURL)` returns an `http.RoundTripper` respecting the mode. `ProxyHTTPClient` wraps it with a timeout.
- `go/s3/client.go` — AWS S3 client uses `ProxyTransport` as its `http.Client.Transport`.
- `go/s3/minio_directory.go` — MinIO client gets `options.Transport` from `ProxyTransport`.
- `go/storage/webdav_backend.go` — WebDAV `http.Client` created via `ProxyHTTPClient`.
- `go/storage/baidu_pan_sdk.go` / `baidu_pan_retry_http.go` — Baidu Pan SDK client replaced via `ApplyBaiduPanProxy` on config save.
- `lib/services/proxy_http_client.dart` — Conditional export: IO → `proxy_http_client_io.dart` (dart:io `HttpClient` with proxy), Web → stub (browser handles proxy).
- `lib/services/update_settings.dart` — GitHub mirror config (separate from proxy): persisted in SharedPreferences, wraps github.com URLs with a mirror prefix.
- `lib/widgets/settings_proxy_section.dart` — Settings UI: proxy mode chips + custom URL input + GitHub mirror input with quick-pick buttons.
- `bridge/dispatch_config.go` — `saveConfig` applies `ApplyBaiduPanProxy` before saving. Also holds `updateProxySettings`, profile CRUD, and cache maintenance handlers (split from `dispatch.go`).

#### Data flow

1. User configures proxy in 设置 → 通用设置 → 网络代理.
2. `SettingsProxySection._save` → `_saveProxySettings` → `widget.api.saveConfig(config.copyWith(proxyMode, proxyUrl))` → Go `saveConfig` → `ApplyBaiduPanProxy` + `SaveProfile`.
3. On next S3/WebDAV/MinIO client creation, `ProxyTransport(cfg.ProxyMode, cfg.ProxyURL)` is applied.
4. Dart http calls (GitHub API, download) use `createProxyHttpClient(ProxyConfig(mode, customUrl))`.
5. GitHub mirror wraps **download** URLs only (via `UpdateNetworkConfig.wrapUrl` in `app_installer_io.dart`); the Release API call bypasses the mirror entirely.
