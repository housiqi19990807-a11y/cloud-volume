# remote-storage

`remote-storage` is a Flutter macOS desktop app for managing S3-compatible remote storage.

## Bootstrap flow

- On startup, the app loads `~/.remote-storage/config.toml` through the Go FFI bridge.
- If the configuration is missing or incomplete, the app opens the initialization page (left-right split layout).
- Saving the form writes the config file and switches the app to a placeholder connected state.
- Theme accent color is persisted via `shared_preferences` and defaults to tech-blue.

## Local development

```bash
flutter pub get
go mod tidy
flutter run -d macos
```

The Go bridge is built on demand to `bin/bridge/` the first time Flutter connects to it.

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
- Full Chinese interface.
- Built with `shadcn_ui`.
