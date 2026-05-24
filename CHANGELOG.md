# Changelog

## Unreleased

- Bootstrap a Flutter desktop shell with a Go FFI bridge and first-run remote storage configuration flow.
- Transparent macOS titlebar with content extending behind traffic lights.
- Left-right split config page: dark brand panel + form.
- User-switchable accent color with 5 presets, persisted across restarts.
- File manager now uses the Local-cloudPan SVG icon set for list and grid views.
- Buckets and sidebar navigation now use matching custom SVGs instead of reusing folder icons.
- macOS file picking now includes the required `file_picker` user-selected file entitlements.
- Grid mode is denser, with tighter spacing and more compact Finder-style tiles.
- Sidebar page switches now preserve in-memory page state through an `IndexedStack`.
- Sidebar footer now shows live transfer activity, aggregate speeds, and a hover task list for recent uploads/downloads.
- Sidebar footer now adds a task-count badge while uploads or downloads are pending.
- File manager now keeps breadcrumbs and actions in one header row, collapses long middle path segments into `...`, and still supports in-place folder creation plus `..` parent entries in non-root directories.
- WhiteSur SVG assets are vendored in-repo as an optional secondary icon library.
- Sidebar, bucket, and transfer entry icons now use Fluent System Icons for a more native app-style navigation set.
- New folder creation now uses a MinIO-compatible zero-byte directory placeholder flow for better S3-compatible endpoint support.
- Full Chinese interface.
