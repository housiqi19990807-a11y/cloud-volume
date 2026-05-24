# remote-storage

`remote-storage` is a Flutter desktop app backed by a Go bridge for managing S3-compatible remote storage.

## Current bootstrap flow

- On startup, the app loads `~/.remote-storage/config.toml` through the Go FFI bridge.
- If the configuration is missing or incomplete, the app opens the initialization page.
- Saving the form writes the config file and switches the app to a placeholder connected state.

## Local development

```bash
flutter pub get
go mod tidy
flutter run -d macos
```

The Go bridge is built on demand to `bin/bridge/` the first time Flutter connects to it.

## Configuration fields

The initial setup page persists these S3-compatible settings:

- `endpoint`
- `region`
- `bucket`
- `access_key_id`
- `secret_access_key`
- `root_prefix`
- `use_path_style`

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
