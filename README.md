# remote-storage

`remote-storage` is a Flutter desktop app for managing S3-compatible remote storage across macOS, Linux, and Windows.
The end-user product branding is `云卷`.

## Bootstrap flow

- On startup, the app loads `~/.remote-storage/config.toml` through the Go FFI bridge.
- If the configuration is missing or incomplete, the app opens the initialization page (left-right split layout).
- Saving the form writes the config file and switches the app to a placeholder connected state.
- Theme accent color is persisted via `shared_preferences` and defaults to tech-blue.

## Local development

```bash
flutter pub get
go mod tidy
make run
```

`make run` is the canonical startup flow on the current host desktop platform.
On macOS it preserves the required bridge-first startup and launches Flutter
with the required `DEVELOPER_DIR` binding.

Platform-specific targets:

- macOS: `make bridge-macos`, `make run-macos`, `make build-macos`
- Linux: `make bridge-linux`, `make run-linux`, `make build-linux`
- Windows: `make bridge-windows`, `make build-windows`

Linux and Windows desktop shells are now checked into the repository alongside
the existing macOS host app so the project can be built natively on all three
desktop platforms.

## Tagged releases

Pushing a tag such as `v0.0.1` now triggers a GitHub Actions release workflow
that:

- builds 7 native desktop release lanes:
  macOS `amd64`, macOS `arm64`, macOS `universal`, Windows `amd64`,
  Windows `arm64`, Linux `amd64`, and Linux `arm64`
- builds the Go FFI bridge in the native library format for each platform
- bundles that bridge into the packaged desktop output
- publishes these assets to the matching GitHub Release:
  macOS `zip + dmg`, Windows `zip + installer.exe`, and Linux `AppImage`

## Configuration fields

The initial setup page persists these S3-compatible settings:

- `endpoint` — S3-compatible endpoint URL
- `region` — storage region
- `bucket` — target bucket name
- `access_key_id` — access key
- `secret_access_key` — secret key
- `root_prefix` — optional key prefix
- `use_path_style` — use path-style URLs (recommended for most compatible stores)

## UI design

- macOS transparent titlebar with Flutter content extending behind traffic lights.
- Left-right split config page: dark brand panel on the left, form on the right.
- User-switchable accent color (5 presets: tech-blue, violet, green, orange, rose).
- Custom SVG app branding now ships as `云卷` and is reused across the sidebar and macOS Dock icon.
- macOS now exposes a menu bar status icon that can reopen the main `云卷` window after it is closed.
- Choosing `退出云卷` from the macOS tray now exits the app immediately.
- The macOS tray now uses a dedicated logo-only template icon asset, and the default main window opens at a smaller size.
- On macOS launch, the main window now resets to the default centered size instead of restoring the previous session's dimensions.
- Finder-inspired file manager using the Local-cloudPan SVG file-type icon set.
- Sidebar navigation, transfer status, and bucket entries now use Fluent System Icons for a more app-like system UI style.
- Breadcrumbs and the file action bar now share a single header row, with long paths collapsed in the middle to `...` while still supporting direct breadcrumb jumps, in-place folder creation, and `..` entries in non-root directories.
- Switching between sidebar pages now preserves recent page state instead of recreating the file manager view.
- Sidebar footer shows a live upload/download status entry with animated activity, aggregate speeds, an active-task badge, and a hover task list.
- WhiteSur SVG resources are also vendored as an optional backup icon library.
- Internal folder grids stay borderless and use larger document-style icons.
- New folder creation uses a MinIO-compatible placeholder upload path so S3-compatible endpoints can create directories reliably.
- Settings now allow configuring a default download directory; the save dialog falls back to the system Downloads folder when none is set.
- Settings now also allow switching between single-click open and Finder-style double-click open; in double-click mode, clicking a row selects it for multi-select while clicking the file or folder name still opens it directly.
- File and folder items now expose a desktop-style right-click menu for rename and delete actions in both list and grid views.
- In double-click mode, selected items can be batch-downloaded or batch-deleted directly from the file action bar.
- In double-click mode, multi-selection uses explicit checkmarks: a checkbox on the left in list view and a checkbox at the top-right in grid view.
- In list view, the table header now includes a select-all checkbox that can select or clear all visible items in the current directory.
- Upload now supports multi-file selection, and in-flight upload/download tasks can be canceled from both the transfers page and the sidebar hover list.
- Breadcrumbs now stay fully expanded when space allows, and only collapse the oldest left-side path segments into `...` when the header becomes tight.
- Settings now default to hiding files and directories whose names start with `.`, with a switch to reveal them when needed.
- Clicking a file now opens it directly: before opening, the app first sends a `HEAD` request to compare the remote file size and last-modified time with the local SQLite-tracked cache record; mismatches invalidate the cache and trigger a fresh download before opening, while the right-click menu still exposes an explicit download action for choosing a save path.
- List mode now uses a fixed table header with aligned Name, Size, and Modified columns so metadata sits on the right instead of leaving a large empty area.
- The current bucket can now be mounted on macOS as a Finder-visible system volume through an anonymous local WebDAV server plus the system mount flow, with quick actions for mount, unmount, and opening the mounted directory directly from the file manager action bar.
- The bucket list now also exposes per-bucket mount actions directly, so buckets can be mounted, opened, or unmounted before entering the bucket view.
- The bucket browser now supports a right-click menu in both list and grid modes for opening, mounting, unmounting, and opening mounted buckets; list mode still keeps the fixed header row plus visible mount actions, while grid mode stays visually clean with only the bucket icon and name on each tile.
- Mounted-volume reads and writes are now bridged into the existing transfer queue: first reads trigger tracked background downloads into a reusable local cache, while writes land in a local staging area first and then upload asynchronously as cancelable transfer jobs.
- Mounted-volume writes now use a delayed writeback model: Finder/WebDAV edits first settle into a local cache plus local metadata overlay, then upload after a 1-minute quiet period, while rename/move/delete operations update that local mount view first and carry pending writebacks along.
- Delayed mounted uploads now appear in the in-app task queue immediately as `等待同步` items, and users can cancel them or manually trigger `立即同步` before the quiet period expires.
- Object copy and move operations now also feed the same transfer pipeline from the Go backend hook layer, so explicit bucket-level copy/move actions and mount-triggered remote moves show up in transfer management with progress and cancel support instead of bypassing the task system.
- The transfer queue now keeps a low-frequency background sync even while the UI is otherwise idle, so WebDAV-triggered copy, paste, read, and upload activity shows up in the transfers page without requiring a Flutter-initiated task first.
- The macOS mount layer now adds short-lived metadata caching, next-level directory prefetch, request timeouts, and duplicate-request coalescing to keep Finder/WebDAV probing from exploding remote round-trips on slower storage backends.
- The mount cache now also keeps a local metadata overlay for staged files, locally created directories, tombstoned deletes, and pending renames, so Finder lists stay consistent during delayed upload windows instead of snapping back to stale remote metadata.
- The macOS bucket mount now lets the system mount the anonymous local WebDAV endpoint as a real `/Volumes/...` WebDAV volume, which matches Finder's normal network-volume semantics more closely than the older Desktop directory mount.
- The macOS mount overlay still keeps local-only system dot paths such as `.TemporaryItems` and `.fseventsd` writable so Finder and Archive Utility can create temporary content without pushing those macOS-private files back to S3.
- The mount layer now supports full-path file and directory moves instead of only same-directory renames, which keeps macOS Archive Utility and similar extract/copy flows working when they create temporary writable folders and then move results into place.
- On macOS app termination, the host now proactively unmounts any active bucket mount before exit so Finder does not keep a stale desktop mount entry that hangs on later access.
- In list mode, the bucket browser now also uses a fixed header row so bucket names, types, and mount actions align with the same structured table feel as the object browser.
- Deletes now use an app-level recycle bin per bucket instead of Finder trash on the mounted WebDAV volume, so files and directories are soft-deleted into a hidden bucket directory such as `.trash`; for compatibility, the mount layer also treats both `.trash` and Finder-style `.Trash` as reserved trash roots.
- Mounted deletes now also handle MinIO-style directory placeholder objects, macOS `._*` sidecar metadata files, and just-written file timing races, so real Finder or shell recursive deletes can remove freshly created directories without leaving phantom entries behind.
- The bucket list now exposes a recycle-bin entry per bucket through the visible action area in list mode and the right-click menu in both list and grid modes, which keeps recycle-bin browsing scoped to the current bucket instead of a global page.
- Settings now expose the recycle-bin directory name and retention days, and the mounted WebDAV view hides that configured recycle-bin directory from Finder so the special trash area stays app-managed.
- Full Chinese interface.
- Built with `shadcn_ui`.
