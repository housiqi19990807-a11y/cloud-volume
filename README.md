# remote-storage

`remote-storage` is a Flutter macOS desktop app for managing S3-compatible remote storage.
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

`make run` is the canonical startup flow. It rebuilds the Go bridge into
`bin/bridge/` and then launches the macOS Flutter app with the required
`DEVELOPER_DIR` binding.

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
- File and folder items now expose a desktop-style right-click menu for rename and delete actions in both list and grid views.
- Full Chinese interface.
- Built with `shadcn_ui`.
