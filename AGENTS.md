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

Any clickable row, tile, card, or sidebar item that needs a hover visual response **must be a dedicated `StatefulWidget`** that owns a `bool _hovered` field. The field is toggled by `MouseRegion(onEnter/onExit)` to `setState`, and drives background color (and only when intentional, text/icon color) via an `AnimatedContainer`. This is the only reliable way to get hover to rebuild the widget subtree.

**Never** build hover items as inline `MouseRegion` + `Container` inside an `extension on State` or a plain builder — the extension/builder has no mutable field to store `_hovered`, so the `onEnter`/`onExit` callbacks have nowhere to write, hover never rebuilds, and you get a dead or stuck hover state. This bug has re-occurred multiple times (settings sidebar rail, file list tiles).

#### Hover visual style (binding — read every time you touch hover UI)

Hover is a **subtle state change**, not a different component skin. This is a hard product rule: if the pointer slides across a list of cards/buttons and they look like different designs while hovered, the hover is wrong.

**Allowed on hover (only):**
- Background wash via `ListInteractionColors.fromTheme` (`hover` = neutral `mutedForeground @ ~0.08`)
- Optionally a slightly stronger wash when already **selected**

**Forbidden on hover (unless the item is selected/disabled as its permanent state):**
- Changing **icon color** (muted → primary, gray → red, etc.)
- Changing **border color** or **border width**
- Changing **font weight / text color**
- Swapping in a different fill system (`colorScheme.secondary` blue, pink destructive fill, etc.)
- Showing/hiding trailing chrome (checkmarks) that reflows layout

**Checklist before shipping any hover control:**
1. Idle vs hover screenshot should differ mainly by a light background, not by “new theme”.
2. Icon/border/text at idle == icon/border/text at hover (same Color/width/weight).
3. Prefer `ListInteractionColors.rowBackground(selected:, hovered:, pressed:)` — do **not** invent per-feature hover palettes.
4. Use a dedicated `StatefulWidget` + `_hovered` + `MouseRegion` + `GestureDetector(behavior: opaque)` + `AnimatedContainer`.
5. Layout must not jump (fixed border width; reserve checkmark width; no 1→1.5 border).
6. Title-bar / chrome buttons (including modal close): **no Material ink splash**; hover = neutral wash only; **do not** turn the X red/pink on hover.

**Bad examples (regressions — do not reintroduce):**
- Protocol cards: hover → primary border + `secondary` fill + primary icon (`StorageProtocolCard`, fixed 2026-07-11).
- Modal shell close: hover → pink fill + red X (`DesktopModalShell`, fixed 2026-07-11). Correct = fixed muted X + neutral wash only.

Canonical implementations to copy:
- `lib/theme/list_interaction_colors.dart` — shared hover/selected washes.
- `lib/pages/main_layout_page.dart` `_SidebarNavItem` — sidebar nav items.
- `lib/widgets/file_list_tile.dart` — file-manager rows (`dimmed` disables hover).
- `lib/widgets/transfer_task_widgets.dart` — transfer queue rows.
- `lib/pages/settings_page_layout.dart` `_SettingsGroupTile` — settings left rail entries.
- `lib/widgets/cloud_storage_account_dialog_steps.dart` `StorageProtocolCard` — selectable cards (neutral hover; primary chrome only when selected).
- `lib/widgets/desktop_modal_shell.dart` `_ModalShellCloseButton` — modal title-bar close (no splash; neutral hover only).

Cursor: dense list rows use idle `SystemMouseCursors.basic` and `click` only while hovered (or a constant `click` cursor for always-interactive cards if it never sticks). Never leave a pointing hand stuck after unhover/unmount.

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
> **Explore rule (binding):** After any codebase exploration (including Explore-agent work), write the reusable findings into the relevant Code Map entry before ending the turn. Do not leave discoveries only in the conversation. This applies even when no implementation is made.
>
> **Maintenance rules (binding):**
>
> 1. **Feature work:** Every time a new feature is added or an existing feature's file set changes, update the relevant Code Map entry here in the same change set (before committing). List the files that participate in the feature, their responsibility, and the data flow between them.
> 2. **Exploration:** Any time the codebase is explored to answer a question, debug an issue, or understand a feature — even when no code change lands — record the discovered structure, file responsibilities, gotchas, and data flow into the relevant Code Map entry (or create a new one) before the turn ends. The goal is that the next session never has to re-read the same files to learn the same thing.
> 3. **Freshness:** Correct or remove entries that are no longer accurate. Do not leave this section stale — stale knowledge here is worse than no knowledge.

### Feature: Windows Local Development Workflow

Windows development now has two scripts: one for new-machine dependency bootstrap, and one for project run/build after dependencies exist.

#### Key files

- `scripts/setup_windows_dev.bat` - Double-click launcher for dependency bootstrap. It changes to the repo root, calls `scripts/setup_windows_dev.ps1` with `powershell -NoProfile -ExecutionPolicy Bypass`, forwards any command-line arguments, reports success/failure, and pauses at the end for double-click users. Set `CLOUD_VOLUME_NO_PAUSE=1` when invoking it from automation to avoid the final pause.
- `scripts/setup_windows_dev.ps1` - New-machine bootstrap script. Uses `winget` to install/verify Git, Go, Visual Studio 2022 Build Tools, and MSYS2; direct installers remain as fallbacks. It also installs the native MSVC Rust toolchain through official `rustup-init`, adds `$HOME\.cargo\bin` to user `PATH`, and ensures the matching Rust target exists. Architecture detection honors `PROCESSOR_ARCHITEW6432` so an emulated PowerShell still sees the native OS. x64 installs UCRT64 `mingw-w64-ucrt-x86_64-gcc`; ARM64 installs CLANGARM64 `mingw-w64-clang-aarch64-clang` and the Visual Studio `Microsoft.VisualStudio.Component.VC.Tools.ARM64` component (modifying an existing Build Tools installation when needed). The Go MSI fallback also uses the native `amd64`/`arm64` artifact. It sets `FLUTTER_ROOT`, architecture-matched `BRIDGE_CC`/`BRIDGE_CXX`, user `PATH`, and default `GOPROXY=https://goproxy.cn,direct` while preserving custom proxies. It treats unavailable Developer Mode as a warning, probes China Flutter mirrors before falling back to official sources, and checks native exit codes. Optional flags: `-FlutterRoot`, `-MsysRoot`, `-SkipWingetInstall`, `-SkipFlutterClone`, `-SkipMsysPackages`, `-SkipDoctor`, and `-ValidateProject`.
- `scripts/run_windows.ps1` - Canonical Windows local run/build helper. It detects native x64/ARM64 architecture, resolves Flutter, Go, and Rustup, selects UCRT64 GCC/G++ for x64 or CLANGARM64 Clang/Clang++ for ARM64, and validates each compiler's `-dumpmachine` output before enabling cgo. On ARM64, Rustup is required so CargoKit-backed plugins such as `super_native_extensions` build locally instead of downloading GitHub Release artifacts; CargoKit verbose logging exposes the underlying failure rather than only MSB8066. Stale `BRIDGE_CC` values for the wrong architecture are skipped; an explicitly passed incompatible compiler fails immediately with a focused error. It sets `GOOS=windows`, native `GOARCH`, `CGO_ENABLED`, `CC`/`CXX`, builds the bridge, and runs/builds Flutter. Release output uses `build/windows/x64/...` or `build/windows/arm64/...` dynamically and verifies `cloud-volume.exe`, `cloud-volume-app.exe`, the crash reporter, and updater before returning success. Developer Mode absence is warning-only. Build mode embeds `APP_VERSION_LABEL`; run mode defaults it to `dev`.
- `scripts/run_windows_debug.bat` - Double-click launcher for debug runs. It changes to the repo root and calls `scripts/run_windows.ps1` without `-Build`, so the bridge DLL is built first and then `flutter run -d windows` starts the app. Forwards extra command-line arguments and pauses unless `CLOUD_VOLUME_NO_PAUSE=1`.
- `scripts/build_windows.bat` - Double-click release-build launcher. It calls `scripts/run_windows.ps1 -Build`, detects x64 versus ARM64 (including an emulated shell), and opens the matching `build/windows/<x64|arm64>/runner/Release/` directory.
- `scripts/build_windows_installer.ps1` - Builds `yunjuan-windows-<x64|arm64>-installer.exe` from the architecture-matched Flutter release bundle via Inno Setup 6. It passes `x64compatible` or `arm64` to both Inno architecture directives and uses `git describe` unless `-Version` is provided.
- `scripts/build_windows_installer.bat` - Double-click launcher for `build_windows_installer.ps1`; it builds/packages the release and pauses on completion for interactive users.
- `README.md` - Windows development documentation covers bootstrap, architecture-specific toolchains, run/build launchers, Developer Mode behavior, and Go/Flutter mirrors.
- `AGENTS.md` Build Outputs section - Reinforces that Windows validation should prefer `scripts/run_windows.ps1` over bare `flutter run -d windows` so the bridge DLL and CGO toolchain are configured correctly.

#### Gotchas

- ARM64 cgo must use the CLANGARM64 compiler selected by the scripts. If `gcc_arm64.S` ever reports unknown `stp`/`ldp`/`blr` instructions again, inspect the printed compiler target: it must contain `aarch64`/`arm64`, not `x86_64`. User overrides passed with `-BridgeCc`/`-BridgeCxx` are intentionally rejected when their `-dumpmachine` target does not match the native architecture.
- Visual Studio readiness for Flutter Windows is more than a workload ID: ARM64 hosts need `Microsoft.VisualStudio.Component.VC.Tools.ARM64` and `MSBuild\\Microsoft\\VC\\*\\Platforms\\ARM64`. `setup_windows_dev.ps1` now verifies that platform folder and waits for VS setup modify to finish; `run_windows.ps1` fails early with the exact install command when it is missing.
- Cloud Files cgo sources under `go/mount/cloud_files_*_windows.go` must not hardcode `-D_AMD64_`. On ARM64 that forces x64 `windows.h` intrinsics (`+D`, `=@ccc`) and redefines `CONTEXT`. Use architecture-specific `#cgo amd64 CFLAGS` / `#cgo arm64 CFLAGS` instead.
- `Resolve-Executable` must not treat bare command names as filesystem paths. This repository has a top-level `go/` package directory, so resolving `go` via `Test-Path` would return that directory and later `& $go build` fails with “cannot recognize C:\\...\\cloud-volume\\go”. Bare names now go through `Get-Command` / explicit leaf candidates only.
- On some Windows ARM hosts, PowerShell's call operator (`& clang.exe -dumpmachine`) can return empty output even when the compiler works. `run_windows.ps1` therefore probes compilers through `System.Diagnostics.ProcessStartInfo`, prefers known `C:\\msys64\\clangarm64\\bin\\clang(.exe|++.exe)` paths over a stale user `BRIDGE_CC` pointing at UCRT64 gcc, and rewrites the user `BRIDGE_CC`/`BRIDGE_CXX` values after a successful match.
- `super_native_extensions` uses CargoKit. Without Rustup, CargoKit first downloads signed `aarch64-pc-windows-msvc` binaries from GitHub Releases; on this ARM64 host Dart's HTTP client timed out even while PowerShell could reach the same URL, and MSBuild surfaced only MSB8066. The setup script now installs Rustup, and the run script adds `$HOME\.cargo\bin` before Flutter starts, which makes CargoKit choose its built-in local-build path.
- `scripts/run_windows.ps1` fails fast with clear errors if Flutter or `gcc`/`g++` is missing; it does not download or install them.
- `scripts/setup_windows_dev.ps1` prefers `winget` but can install VS Build Tools and MSYS2 without it. Git and Go still require either `winget` or preinstallation before the script reaches later steps.
- Direct downloads use retrying `Invoke-WebRequest`, then `curl.exe -L --ssl-no-revoke`; the latter handles Windows machines whose certificate revocation check fails because the revocation server is offline.
- VS Build Tools installer exit code `3010` means installation succeeded but a reboot is requested; the script accepts it and continues.
- Flutter first bootstrap can leave `bin/cache/dart-sdk` incomplete with no `dart.exe`; the script detects that state and downloads `dart-sdk-windows-x64.zip` for the current engine version from `FLUTTER_STORAGE_BASE_URL` before invoking `flutter.bat`.
- If Flutter was cloned/installed from an elevated process, Git may reject it with `detected dubious ownership` because the directory is owned by `BUILTIN/Administrators`; both setup and run scripts add the resolved Flutter root (for example `C:/Users/3000y/dev/flutter`) to the current user's global Git `safe.directory` before invoking Flutter.
- Flutter Windows plugins may require symlink support. Both setup and run scripts check `HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock\AllowDevelopmentWithoutDevLicense`; when running as administrator they try to set it to `1`, otherwise they show the Developer Mode path as a warning without blocking setup/build preflight.
- `scripts/setup_windows_dev.ps1` does not run a full app build by default; pass `-ValidateProject` to call `scripts/run_windows.ps1 -Build` after dependency setup.
- After setup writes user environment variables and `PATH`, open a new PowerShell window before using `scripts/run_windows.ps1` interactively.

### Feature: Windows Crash Watchdog / Startup Reports

Windows release bundles separate the public launcher from the Flutter process so failures before the first window exists are still observable.

#### Key files

- `windows/runner/crash_launcher.cpp` - Implements the public `cloud-volume.exe`. It resolves the sibling `cloud-volume-app.exe`, forwards the original command line, starts it with `CreateProcessW`, waits for its process handle, and launches the report helper after a non-zero exit or `CreateProcessW` failure. If the report helper itself is unavailable, it shows a minimal native error with the Windows error/exit code.
- `windows/CMakeLists.txt` / `windows/runner/CMakeLists.txt` / `windows/runner/Runner.rc` - The Flutter target is named `cloud-volume-app`; a small native `cloud_volume_launcher` target keeps the on-disk name `cloud-volume.exe`; the Go `cloud-volume-crash-reporter.exe` is built with `CGO_ENABLED=0` and installed beside both. The launcher target compiles as UTF-8 because its last-resort native error contains Chinese text, and statically links the MSVC runtime so missing `MSVCP140`/`VCRUNTIME140` cannot prevent the watchdog itself from starting.
- `cmd/cloud-volume-crash-reporter/main.go` / `report.go` / `notify_windows.go` - Parses launch/exit diagnostics, writes `~/.cloud-volume/runtime/crashes/crash-<timestamp>-<pid>.txt`, and offers to reveal it in Explorer. Reports include the Windows build, runtime architecture, signed/hex exit code, SHA-256/size/mtime for the launcher, Flutter app, `data/app.so`, and bridge, plus 64 KiB tails from `bridge.log` and the newest `%TEMP%\cloud-volume-updater-*.log`. The prompt warns that local paths may be present.
- `cmd/cloud-volume-crash-reporter/report_test.go` - Covers exit-code/artifact report content and bounded log-tail reads.
- `bridge/app_launcher_path.go` / `bridge/dispatch_app_install.go` - Windows ZIP updates pass the public launcher to `cloud-volume-updater.exe`, even though `os.Executable()` inside Flutter resolves to `cloud-volume-app.exe`.
- `go/mount/windows_process_cleanup_windows.go` / `lib/pages/settings_page_actions.dart` - Development cleanup now terminates both launcher and app processes and describes them generically in the UI.
- `scripts/run_windows.ps1` / `scripts/build_desktop_packages.sh` / `scripts/build_windows_installer.ps1` - Release packaging verifies that launcher, app, crash reporter, and updater are all present before producing an artifact.

#### Data flow

1. Installer shortcuts, post-install launch, ZIP users, and the updater start `cloud-volume.exe`.
2. The launcher starts `cloud-volume-app.exe` and remains hidden while waiting on its process handle. Flutter-created modal/preview sub-windows continue to spawn `cloud-volume-app.exe` directly and are not wrapped in extra watchdogs.
3. Exit code `0` is normal, including confirmed close and the bridge's intentional update-time `os.Exit(0)`; the launcher exits silently.
4. A non-zero exit or app creation failure starts the report helper. The helper fingerprints the installed runtime, appends bounded diagnostic tails, writes the report with user-only permissions, and prompts the user to inspect/submit it.
5. For a green-ZIP update, the updater waits for the Flutter PID. Once Flutter exits with `0`, the launcher also exits; the updater polls `cloud-volume.exe` until writable, replaces the whole bundle, and starts the new launcher.

#### Gotchas

- Do not point shortcuts or updater relaunch at `cloud-volume-app.exe`; doing so bypasses pre-window crash capture.
- Do not report exit code `0` as a crash. The in-app updater intentionally terminates the Flutter process with `os.Exit(0)` after handing work to the external updater.
- `cloud-volume.exe` remains running while the app is healthy, so updates must wait for both processes before overwriting the launcher image. Passing the launcher as updater `-exe-name` provides that writability gate.
- The launcher can diagnose a missing app, loader failure, Flutter engine failure, or later native crash. It cannot diagnose corruption that prevents the launcher itself from loading; its imports therefore stay limited to Windows system libraries and it has no Flutter/Go runtime dependency.
- Reports may contain local paths from logs. Keep the user review warning and the 64 KiB tail limit when extending diagnostics; do not collect credentials or full configuration files.

### Feature: Desktop Window Close / Tray Exit

The custom desktop chrome routes close actions through Flutter so Windows can offer "hide to tray" versus "exit" without losing OS-level close gestures.

#### Key files

- `lib/widgets/desktop_window_controls.dart` - App-owned minimize/maximize/close controls. The close button and native close requests call `_confirmClose`; confirmed exit first awaits `AppExitCleanup.cleanupMounts()`, then calls `WindowControls.exitApp()` rather than `WindowControls.close()`.
- `lib/services/app_exit_cleanup.dart` - Stores the bootstrapped desktop gateway and coalesces exit-time `cleanupMounts` calls. Cleanup has a 30-second timeout and failures are swallowed so an unavailable stale mount cannot leave an invisible process running forever.
- `go/mount/manager.go` / `bridge/dispatch_mount.go` - `ActiveMountCount` and `get_active_mount_count` expose the number of live in-process mount sessions for the close warning without probing every bucket.
- `lib/services/window_controls.dart` - Method-channel facade for desktop window actions. `close()` means "request close" and may be intercepted by Windows tray logic; `exitApp()` means the user already confirmed and the native host must bypass tray interception.
- `windows/runner/flutter_window.cpp` / `windows/runner/flutter_window.h` - Windows host channel implementation. Every `WM_CLOSE` is sent back to Flutter as `requestClose`; tray Exit sends `requestExit` to Flutter so mounts are cleaned first; the subsequent `exitApp` calls `ExitApplication()` and destroys the window directly.
- `windows/runner/win32_window.cpp` / `windows/runner/win32_window.h` - Base Win32 window lifecycle. `Close()` posts `WM_CLOSE`, while `Destroy()` performs the real teardown and posts quit when `quit_on_close_` is set.
- `linux/runner/my_application.cc` - Linux channel implementation. It has no tray interception; `exitApp` is equivalent to `close`, and `shouldConfirmClose` returns `false`.

#### Gotchas

- Do not use `WindowControls.close()` for a confirmed app exit on Windows. It posts `WM_CLOSE`, which is intentionally intercepted when the tray icon is active and will reopen the confirmation flow instead of quitting.
- Use `WindowControls.close()` only for unconfirmed close requests such as the app-owned close button pre-confirmation path, Alt+F4, or taskbar close handling.
- Use `WindowControls.exitApp()` for explicit "Exit" choices after confirmation, including tray menu exit actions on the native side.

### Feature: Windows Custom Chrome / Window Corners

The Windows host removes the native title bar and uses app-owned chrome, while still asking DWM for native rounded corners where the OS supports it.

#### Key files

- `windows/runner/win32_window.cpp` - Creates the main host with the Flutter-default `WS_OVERLAPPEDWINDOW` style, resizes the hosted Flutter child in `WM_SIZE`, and requests native rounded corners in `UpdateTheme`. It does not override non-client calculation, hit-testing, or standard minimize/maximize/drag commands; the registered `window_manager` plugin owns those behaviors.
- `windows/runner/flutter_window.cpp` - Hosts the Flutter view and owns project-specific tray/close/exit behavior. Its custom method channel no longer exposes minimize, maximize, drag, or maximized-state methods, and it leaves initial visibility to Dart so the frame is hidden before the first visible window frame.
- `lib/app/app_entry_io.dart` - Initializes `window_manager`, applies `TitleBarStyle.hidden` to the main Windows window before `runApp`, then shows/focuses the window after Flutter's first frame.
- `lib/widgets/desktop_window_controls.dart` / `lib/services/window_controls.dart` - Draw the app-owned controls. On Windows, normal minimize/maximize/drag/state operations route through `window_manager`, and `WindowListener` events keep the maximize icon synchronized; Linux retains the custom method channel.

#### Gotchas

- Native DWM rounded corners are a Windows 11-era shell feature. On Windows 10 / Windows Server 2022 build 20348, the `DWMWA_WINDOW_CORNER_PREFERENCE` call is ignored even though it compiles, so the main window stays square.
- Even on Windows 11, fully custom borderless windows can be less reliable than standard framed windows for OS-drawn corners. The current code requests rounded corners but does not implement a manual `SetWindowRgn` or transparent-window mask fallback.
- Keep one owner for Windows non-client behavior. `window_manager` already handles hidden-titlebar `WM_NCCALCSIZE`, maximum-size constraints, frame refresh, and native animated system commands. Duplicating those cases in `Win32Window::MessageHandler` causes ordering conflicts because plugin delegates run before the runner handler.
- Do not replace the main host style with `WS_POPUP` or reintroduce runner `ForceRedraw()` calls around maximize. Those attempts either lose the standard taskbar work area or merely recolor the unpainted transition instead of letting the plugin/DWM path retain the rendered surface.
- The window class must keep a real `hbrBackground` brush (`CreateSolidBrush(RGB(0xF8,0xFA,0xFF))`, matching the light app surface). With `hbrBackground = 0` the area exposed during maximize/restore flashes black until Flutter presents the resized frame. A layered/transparent window is not viable: the hosted Direct3D Flutter child cannot composite through it, so the surface-matching opaque brush is the reliable fix. If a dark theme ships, this brush color must follow the theme.
- An earlier diagnostic machine reported Windows Server 2022 build 20348, where missing rounded corners were expected. The 2026-07-17 static diagnosis ran on Windows 11 Pro build 26100 and identified the relevant code path independently of that older shell limitation.

### Feature: Windows Mount Presentation / Drive Letters

Windows has two distinct mount presentations. The selected `windows_mount_mode` decides whether a bucket receives a real mapped drive letter or remains a Cloud Files sync-root directory.

#### Key files

- `go/mount/backend_windows.go` - Selects `cloud_files_cached`, `cloud_files_direct`, or `webdav`; an empty/unknown setting normalizes to `cloud_files_cached`.
- `go/mount/backend_windows_webdav.go` / `go/mount/webdav_mount_windows.go` - WebDAV starts the local server, scans unused drive letters from `Z:` down through `D:`, and invokes `net use <drive> <url> /persistent:no`.
- `go/mount/backend_windows_cloud_files_cgo.go` / `go/mount/windows_cloud_files_paths.go` - Cloud Files registers the stable sync root at `~/Cloud Volume/<bucket>` and returns that directory as `mountPath`. When requested, startup assigns a drive letter after the provider health check; stop removes it before disconnecting the provider.
- `go/mount/windows_drive_mapping_windows.go` / `go/mount/windows_drive_mapping_other.go` - Shared Windows drive-letter discovery, requested-letter validation, and `subst` lifecycle, plus the portable bridge stub. It lists free letters from `Z:` down through `D:`, verifies the chosen letter again at mount time, verifies the mapping after creation, compares the current target before removal, and cleans managed mappings whose targets are direct children of the Cloud Files root.
- `go/mount/windows_shell_namespace_windows.go` - When `windows_this_pc_entry_enabled` is true, Cloud Files can register a per-user Explorer namespace shortcut under “This PC”. This is a folder entry targeting the sync root, not an `X:`-style drive.
- `bridge/dispatch_mount.go` / `lib/services/remote_storage_api_desktop_storage.dart` / `lib/services/remote_storage_gateway.dart` - `list_available_drive_letters` exposes the Windows list through the optional `AvailableDriveLetterQuery` capability, so Web and test gateways do not need a meaningless Windows method.
- `lib/widgets/mount_bucket_dialog.dart` / `lib/pages/file_manager_page_mount.dart` - Read/write behavior is a `ShadSwitch`. Windows Cloud Files adds a `ShadSelect` for “分配盘符” versus “路径挂载”, defaults to drive mode when free letters exist, and provides a second `ShadSelect` for the exact letter. WebDAV and non-Windows mounts stay path-only.
- `lib/services/remote_storage_gateway.dart` / `lib/models/bucket_mount_status.dart` / `go/mount/options.go` / `go/mount/types.go` - Carry the requested `driveLetter` into the session and return the actual `driveLetter` to Flutter. Opening a mounted bucket prefers that drive when present while the provider continues using the real sync-root path internally.
- `lib/widgets/windows_settings_sections.dart` / `lib/models/remote_storage_config.dart` - Settings exposes both Cloud Files variants and the legacy pure-WebDAV mapped-drive fallback. New/default configs select `cloud_files_cached` and disable the optional “This PC” namespace entry.

#### Gotchas

- Do not describe the Cloud Files “This PC” namespace item as a drive letter. `Win32_LogicalDisk` / `net use` will not contain it, and paths remain under the user profile.
- Cloud Files drive letters are `subst` convenience mappings, not separate volumes. Keep `session.mountPath` as the CFAPI registration/hydration root and `session.driveLetter` as presentation only; never translate provider callback paths through the drive letter.
- The drive-letter `ShadSelect` sets `ensureSelectedVisible: false`. The package default calls `Scrollable.ensureVisible` for the selected option and can scroll the surrounding app modal to its final row when the popover opens.
- Removal must query the current `subst` target and refuse to delete a drive whose target differs from the session path. Per-bucket stale cleanup runs before deleting the sync root, and full cleanup only removes mappings targeting direct children of `~/Cloud Volume`.
- The current WebDAV allocator does not let users request a specific letter; it always chooses the highest free letter in `Z:` to `D:` order.

### Feature: File Sync (文件同步)

The sync feature lets users bind a local directory to a remote bucket prefix and keep them in sync (upload / download / two-way) on a configurable schedule, with conflict policies and exclude rules. The Go side runs a scheduler that computes diffs and executes operations; the Flutter side manages config and shows live status.

**Migration (2026-06-26):** Sync config management has been fully migrated from Settings to the File Sync Tasks page. The settings page no longer has a "文件同步" tab. The tasks page is now the **sole** entry point for creating, editing, deleting, toggling, and triggering sync profiles — this resolves the original UX friction where creating a task required navigating to Settings.

#### Flutter (Dart) files

- `lib/pages/file_sync_tasks_page.dart` — File Sync Tasks page. **The sole management hub for sync config.** Summary cards + profile rows; full `sync_*` queue lives on **Transfers**; each profile card shows latest pending/running task via `file_sync_profile_active_task.dart`.
- `lib/pages/file_sync_tasks_page_actions.dart` — Part file containing the CRUD extension (`_FileSyncTasksActions`): `_addProfile`, `_editProfile`, `_saveProfile`, `_deleteProfile`, `_toggleEnabled`, `_triggerSync`. Extracted to keep the page under 500 lines.
- `lib/widgets/file_sync_profile_editor.dart` — Editor widget for creating or editing a single `SyncProfile`. **2-step wizard:** Step 1 同步两端 (optional name, local dir via `FilePicker`, remote dir via `RemoteDirectoryPickerDialog`), Step 2 同步策略 (direction, conflict policy, interval, quiet period, exclude rules, enabled toggle). Receives `api` + `List<FileManagerBucketEntry> buckets`. **`asDialog`:** `true` (default) wraps step content in `ShadDialog` for the **default in-app modal** path; `false` returns bare `_buildContent` only for the **debug-only** OS sub-window — **never nest ShadDialog inside the detached sub-window**. Sub-window layout uses `_buildSubWindowLayout`: fixed step indicator + scrollable step body + pinned nav buttons (avoids RenderFlex overflow on step 2). On save success: `onSaved` then `Navigator.pop` only when `asDialog` is true.

**Modal presentation policy (2026-07-11):** Default for sync / account / remote-directory editors is the **in-app app modal** (`showAppModal` + `asDialog: true`). OS sub-windows stay in the tree for development only (`preferModalSubWindows` = `kDebugMode && USE_MODAL_SUB_WINDOWS`). See **Feature: App Modal (统一拟态框)** and **Feature: Desktop Modal Sub-Window Shell**.

**Debug sub-window stack (retained, not default):**
- `lib/models/sync_editor_window_args.dart` — Args model with `profileNames` and optional `initialProfileJson`.
- `lib/app/sync_editor_window_app.dart` — Built on shared **`DesktopModalSubWindowApp`** (`scrollable: false`). Bootstrap loads bridge + bucket list; content is `FileSyncProfileEditor(asDialog: false)`.
- `lib/services/sync_editor_window_service.dart` (+ `_io.dart` / `_web.dart`) — Desktop `isSupported` follows `preferModalSubWindows`; when false, `openEditor` returns `false` and pages open `showAppModal` + `FileSyncProfileEditor(asDialog: true)`.
- `lib/app/app_entry_io.dart` — Still dispatches debug-spawned sub-windows: `SyncEditorWindowArgs.matches` → `configureDesktopModalSubWindow` + `SyncEditorWindowApp`.
- `lib/services/desktop_modal_overlay_controller.dart` / `lib/widgets/desktop_modal_scrim.dart` — Parent scrim only on the debug sub-window path.
- `lib/services/desktop_sub_window_modal.dart` — Shared acquire/release, chrome, center, resize helpers for debug sub-windows.
- `lib/services/desktop_overlay.dart` — **`showDesktopOverlayOrDialog`**: opens sub-window only when `preferModalSubWindows && service.isSupported`; else in-app dialog. **Current sole caller:** `showRemoteDirectoryPicker`.
- `lib/services/desktop_window_method_host.dart` — Method multiplex for debug sub-window results/overlay/bounds.
- `lib/models/remote_directory_picker_window_args.dart` / `lib/app/remote_directory_picker_window_app.dart` / `lib/services/remote_directory_picker_window_service.dart` — Debug remote-directory OS window (720×560); default path is in-app modal.
- `lib/widgets/remote_directory_picker_dialog.dart` — File-manager-style remote directory picker. **`showRemoteDirectoryPicker`** uses `showDesktopOverlayOrDialog` (in-app modal by default). Widget supports `asDialog`, `onConfirm`, `onCancel`. Returns `RemoteDirectoryResult(bucket, prefix, profileName, config)`.
- `lib/widgets/remote_directory_picker_list.dart` — Part file: directory list + **file rows for display only**. Directories and `..` are selectable; **files are not** (`dimmed: true` on `FileListTile`). Toggle **显示隐藏文件** filters dot-prefixed names. File icons use **grayscale `ColorFilter.matrix`** (not `srcATop` tint) so multi-color SVGs (e.g. zip) grey correctly; title/size use muted text via `FileListTile.dimmed`.
- `lib/widgets/file_list_tile.dart` — Shared list row; **`dimmed`** disables hover/press, uses arrow (not hand) cursor, and paints title/size in muted foreground for non-selectable rows.

**Hover/cursor fix (2026-07-07):** `FileListTile` must keep `SystemMouseCursors.basic` while idle and switch to `SystemMouseCursors.click` only when its own `_hovered` field is true. A regression had `cursor: click` for every non-dimmed row, so file-manager rows could leave the cursor looking like a stuck hand during preview/open interactions. `deleting` rows now also count as non-interactive for hover/press/cursor and title tap handling.
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

1. User creates/edits a profile from **文件同步** page only (`_addProfile` / `_editProfile`): default → `showAppModal` + `FileSyncProfileEditor(asDialog: true)`; debug sub-window only when `SyncEditorWindowService.openEditor` is supported (`preferModalSubWindows`).
2. `_FileSyncTasksActions._saveProfile` → `SyncProfileNotifier.saveProfile` → Go `saveSyncProfile` → `go/sync/store.go`.
3. `SyncProfileNotifier` polls `listSyncProfiles` every 3s → Go runtime state from `scheduler.go`/`runner.go`.
4. On interval or manual "立即同步" trigger → Go `runner.go` runs `diff.go` → `reconcile.go` → `executor.go`, enqueueing `sync_*` tasks into the shared `TransferQueue`.
5. `FileSyncTasksPage` displays both profile statuses (from `SyncProfileNotifier`) and live `sync_*` tasks (from `TransferQueue`).

### Feature: First-run Config Setup (首次启动配置)

First-run / incomplete-config onboarding before the main shell. Content extends under the desktop title-bar chrome (no page-level top padding).

**Layout by step (current, 2026-07-14):**
- **Step 0「选择协议」:** split-panel — left brand (`ConfigLeftPanel`), right type chooser (`ConfigStorageTypeStep`).
- **Step 1「连接信息」:** full-screen form — left brand is **hidden** so the form can use the full window width; `ConfigRightFormPanel(fullWidth: true)`. On wide windows, S3 / WebDAV fields use a two-column layout to avoid single-column scrolling; Baidu OAuth stays single-column because the auth block is already wide.
- **Step transition:** Next / Back animate the left brand with `TweenAnimationBuilder` + `ClipRect/Align(widthFactor)` (slide-collapse) and fade the right pane with a non-stacking `AnimatedSwitcher` (~240ms). No intermediate spinner page — that was dropped because double rebuild + spinner animation felt janky.

#### Key files

- `lib/pages/config_setup_page.dart` — Wizard host. Step 0 choose type → step 1 account form. Owns controllers and default gateway constants. Conditionally mounts left brand only on step 0; passes `fullWidth: true` on step 1.
- `lib/widgets/config_storage_type_step.dart` — Step 0 type cards (S3 / WebDAV / 百度网盘) + Next.
- `lib/widgets/config_right_form.dart` — Step 1 connection form shell + Back / Save / advanced dialog. `fullWidth` widens the form (max ~720) and enables two-column field layout when viewport ≥ 700. Back uses `ShadButton.ghost`.
- `lib/widgets/config_right_form_fields.dart` — Part file: single-column / two-column field builders for the connection form.
- `lib/widgets/config_left_panel.dart` — Brand / tagline / accent picker (step 0 only on first-run).
- `lib/pages/app_bootstrap_page.dart` — Routes here when `!state.configured` or “重新配置认证信息”.
- `lib/pages/login_page.dart` — Web login still uses left brand + form split (independent of first-run step layout).

#### Default gateways (IHEP)

| Protocol | Default endpoint |
|----------|------------------|
| S3 | `https://fgws3-ocloud.ihep.ac.cn` |
| WebDAV | `https://webdav-ocloud.ihep.ac.cn` |
| 百度网盘 | `https://pan.baidu.com` (OAuth, not user-edited) |

Presets apply when the field is empty or still a known preset; user-typed custom URLs are not overwritten when switching protocol cards.

#### Gotchas

- Do **not** add Scaffold body top padding to clear `DesktopWindowControls` — that creates a full-width white band above both panels. Baidu step-1 Back was already usable with the original padding; avoid layout hacks here unless a real hit-test bug is reproduced.
- Step 1 intentionally drops the left brand so the long connection form does not need as much vertical scrolling; step 0 keeps the brand for first-run marketing / accent picker.
- Account-management modal wizard (`CloudStorageAccountDialog`) is a separate path and does not prefill IHEP defaults; only first-run setup does.
- Save still goes through `api.saveConfig` (legacy first-run profile `"default"`).

### Feature: Account Management (账号管理)

Lists configured storage accounts and lets users add, edit, or remove them. **Default:** add/edit opens as an **in-app app modal** (`showAppModal` + `CloudStorageAccountDialog(asDialog: true)`). **Debug only:** with `preferModalSubWindows`, desktop can still spawn the detached OS sub-window.

**Two-step wizard (current, 2026-07-11):** New accounts use a 2-step guided flow:
- **Step 0「选择协议」:** Large selectable cards for S3 / WebDAV / 百度网盘. Selecting a card updates `_storageType` without navigating.
- **Step 1「连接信息」:** Name field + protocol-specific connection fields + `AccountProxySection`.
- **Edit mode** does **not** use the wizard; it renders a single-screen connection form (`_buildEditContent`) with Cancel/Save only.
- Step navigation is only `_next` / `_back` (no step tabs / `_goToStep` on account editor).

**Window sizing policy (current, supersedes earlier per-step resize docs):**
- Account editor **does not** call `resizeKeepingWindowCenter` anymore (removed in `a4197b1d`).
- Initial OS window size is fixed at spawn by `app_entry_io._accountEditorWindowSize`:
  - New account seed: `528×340` (step 0); final size is content-measured after first layout.
  - Edit mode by protocol: Baidu `520×520`, WebDAV `520×600`, S3/default `520×700`.
- Minimum size comes from `configureDesktopModalSubWindow` default `480×400`.
- Open services (`AccountEditorWindowService`) only create the window + pass creator frame; they do **not** set size.
- Shell `AccountEditorWindowApp` uses `DesktopModalSubWindowApp(scrollable: true)` only as overflow safety when content exceeds the screen clamp. Normal steps measure content and resize the OS window via `fitModalSubWindowToContentSize`.
- Dialog sub-window content returns `SizedBox(width: 480)` + `Column(mainAxisSize: min)` — it shrink-wraps height; the fixed OS window height is what creates bottom gap or forces scroll.
- Historical note: `4ce325f9` / `4483c276` used hand-tuned per-step `resizeKeepingWindowCenter` sizes (fragile). `a4197b1d` temporarily used fixed window + scroll. Current approach measures shrink-wrapped form content (`MeasureSize`) and resizes with `fitModalSubWindowToContentSize`. Sync editor still uses discrete step sizes + `resizeKeepingWindowCenter`.

**Default modal path:**
- `lib/pages/cloud_storage_page.dart` — Opens `showAppModal` + `CloudStorageAccountDialog(asDialog: true)` unless debug sub-window is supported.
- `lib/widgets/cloud_storage_account_dialog.dart` — Wizard/edit UI; dual-mode `asDialog` (default true).
- `lib/widgets/cloud_storage_account_dialog_steps.dart` — `stepProtocolPicker` / `stepConnectionFields` + protocol field builders.
- `lib/models/cloud_storage_account_draft.dart` / `lib/utils/account_config_builder.dart` / `lib/utils/account_profile_name.dart` — Draft, config build, profile key.

**Debug sub-window architecture (retained):**
- `lib/models/account_editor_window_args.dart` — Args model with `initialConfigJson`, `profileName`, `editing`, `creatorFrame*`.
- `lib/app/account_editor_window_app.dart` — `DesktopModalSubWindowApp(scrollable: true)` + `CloudStorageAccountDialog(asDialog: false)`.
- `lib/services/account_editor_window_service.dart` (+ `_io.dart` / `_web.dart`) — `isSupported => preferModalSubWindows`; otherwise returns `false`.
- `lib/app/app_entry_io.dart` / `desktop_modal_window_config.dart` / `desktop_sub_window_modal.dart` / `desktop_window_method_host.dart` — Spawn, size, chrome, `account_editor_saved` (debug path only).

#### Data flow
1. User clicks "新增账号" or row "编辑" in `CloudStoragePage`.
2. **Default:** `showAppModal` + `CloudStorageAccountDialog(asDialog: true)`; save via page `_saveNewAccount` / `_saveEditedAccount` → `api.saveProfile` → `onRefresh`.
3. **Debug only:** if `AccountEditorWindowService.openEditor` is supported, spawn OS sub-window; save notifies creator via `account_editor_saved`, then closes the child.

#### Go / bridge account storage (exploration 2026-07-11)

Accounts are multi-profile configs, not a separate "account" table. There is **no persisted custom sort order** for accounts or for buckets today.

**Key files**
- `go/config/config.go` — `RemoteStorageConfig` (full account connection JSON), `BucketSettings`, `BootstrapState`.
- `go/config/profile.go` — public profile API: `SaveProfile`, `LoadProfile`, `ListProfiles`, `DeleteProfile`, `SetActiveProfile`, `ResetAllProfiles`; summary DTO `ProfileInfo`.
- `go/config/config_db.go` — bbolt persistence in `~/.cloud-volume/config.db`:
  - bucket `profiles`: key = profile name, value = JSON `RemoteStorageConfig`
  - bucket `meta`: key `active_profile` (active name), plus global proxy via `global_proxy.go`
  - `listProfilesFromDB` sorts: active first, then name `"default"`, then alphabetical `Name`
- `go/config/store.go` — `SaveProfileWithValidation` (first-run completeness check) then `saveProfileToDB`.
- `go/config/global_proxy.go` — global proxy in `meta` (`global_proxy`), separate from account profiles.
- `bridge/dispatch_config.go` — bridge handlers for bootstrap/profile/cache.
- `bridge/dispatch.go` — method switch for config/profile/storage methods.
- `go/s3/buckets.go` — live `ListBuckets` → `[]BucketInfo{Name}`; S3 provider order, no local reorder.
- `go/storage/webdav_backend.go` / `go/storage/baidu_pan_backend.go` — single synthetic bucket (`MappedBucketLabel` / Baidu label).
- Flutter aggregation sort (not Go): `lib/pages/file_manager_page_sources.dart` sorts combined buckets by `sourceLabel` then `bucket.name`.

**JSON schemas (Go → Flutter)**
- Account/profile full config (`RemoteStorageConfig`): `endpoint`, `storageType`, `providerType`, `displayName`, `mappedBucketName`, `region`, `bucket`, `accessKeyId`, `secretAccessKey`, `hasSecretAccessKey`, `webdavUsername`, `webdavPassword`, `hasWebdavPassword`, `rootPrefix`, `defaultDownloadDirectory`, `cacheDirectory`, `resolvedCacheDirectory`, `hideDotFiles`, `fileOpenMode`, `trashDirectoryName`, `trashRetentionDays`, `bucketSettings` (map), mount/cache/proxy fields. **No order/sort field.**
- Per-bucket overrides (`BucketSettings`): `readOnly`, `trashEnabled?`, `trashDirectory`. Map key is bucket name; **map has no order**.
- Profile summary (`ProfileInfo`): `name`, `displayName`, `storageType`, `providerType`, `endpoint`, `accessKeyId`, `active`. **No order field.**
- Bootstrap (`BootstrapState`): `configPath`, `configured`, `config`, `profiles[]`.
- Live bucket row (`BucketInfo`): only `name`.

**Bridge APIs (account/profile)**
- `load_bootstrap_state` / `migrate_default` → `BootstrapState`
- `save_config` → validates + saves profile `"default"` + set active (legacy first-run path)
- `list_profiles` → `[]ProfileInfo` (hardcoded sort above)
- `load_profile` `{name}` → `RemoteStorageConfig`
- `save_profile` `{name, config}` → `{ok:true}`
- `delete_profile` `{name}` → `{ok:true}`
- `set_active_profile` `{name}` → `BootstrapState`
- `reset_user_config` `{confirm}` → empty profiles `BootstrapState`
- `update_proxy_settings` → global proxy only
- `list_buckets` `{config}` → live remote buckets (not stored)

**Custom list order (implemented 2026-07-11)**
- Meta keys in `config.db`:
  - `profile_order` JSON `[]string` profile names
  - `bucket_order` JSON `[]string` entry ids (`profileName::bucketName`)
- Go helpers: `go/config/list_order.go` (`ReorderProfiles`, `ReorderBuckets`, `ListBucketOrder`, apply/append/remove helpers).
- `listProfilesFromDB` uses `profile_order` when present; otherwise legacy sort (active → `default` → name).
- Bridge/webapi methods: `reorder_profiles` `{names}`, `reorder_buckets` `{ids}`, `list_bucket_order`.
- Flutter gateway: `reorderProfiles` / `reorderBuckets` / `listBucketOrder`.
- Account list UI: `CloudStorageAccountList` list mode `ReorderableListView` + `CloudStoragePage._reorderAccounts` (optimistic local order).
- Bootstrap soft refresh: `lib/pages/app_bootstrap_page.dart` keeps `_session` mounted and reloads bootstrap state in place; reorder no longer triggers full-screen loading shell.
- Bucket list UI: `FileManagerBucketBrowser` list mode reorder + `file_manager_page_bucket_view._reorderBuckets`; load path `file_manager_page_sources._loadBucketEntries` applies `listBucketOrder` (fallback: profile order then bucket name).
- Grid view / search / trash home do not enable drag reorder.
- Save profile appends new names to existing `profile_order`; delete profile strips profile + its `profile::` bucket ids; reset clears both orders.

#### Account list UI (exploration 2026-07-11)

- `lib/pages/cloud_storage_page.dart` — Account management page. Passes `widget.state.profiles` into list; CRUD via `api.saveProfile` / `deleteProfile` / editor modal; `onRefresh` reloads bootstrap.
- `lib/widgets/cloud_storage_account_list.dart` — Presentational list/grid only. Renders `List<ProfileInfo>` in given order:
  - table: `ListView.builder` (~L77–96)
  - grid: `GridView.builder` (~L47–64)
  - row title: `displayName` else `name`; no client sort.
- `lib/models/bootstrap_state.dart` — Dart `ProfileInfo` + `BootstrapState.profiles`.
- `lib/pages/app_bootstrap_page.dart` — Loads `api.loadBootstrapState()`; `onRefresh` reloads session so account list order comes from bridge list sort.
- `lib/pages/main_layout_page.dart` — Sidebar `storage` → `CloudStoragePage(state.profiles)`.
- No dedicated account `ChangeNotifier`; account list state is bootstrap `profiles`.

#### Bucket list UI (exploration 2026-07-11)

- `lib/pages/file_manager_page.dart` — Owns `_buckets`; `_loadBuckets()` → `_loadBucketEntries()`.
- `lib/pages/file_manager_page_sources.dart` — Multi-account aggregation:
  1. for each `widget.profiles` → `loadProfile` + `listBuckets(config)`
  2. wrap as `FileManagerBucketEntry` (`id = profileName::bucket.name`)
  3. apply persisted `listBucketOrder()` when present; otherwise keep account/profile order and sort bucket names within each account
- `lib/pages/file_manager_page_bucket_view.dart` — Builds `FileManagerBucketBrowser` from `_filteredBuckets`.
- `lib/pages/file_manager_page_state.dart` — `_filteredBuckets` filters by search only; preserves load order.
- `lib/widgets/file_manager_bucket_browser.dart` — Presentational list/grid:
  - list: `ListView.builder` (~L189+)
  - grid: `GridView.count` (~L79+)
- `lib/models/file_manager_bucket_entry.dart` / `lib/models/s3_objects.dart` (`BucketInfo`) — UI row models; no order field.
- Same aggregation pattern also used by `file_sync_tasks_page_actions.dart` for remote picker buckets.

#### Bucket custom quota (implemented 2026-07-18)

- `go/config/config.go` adds `BucketSettings.CustomQuotaBytes` (`customQuotaBytes` JSON / `custom_quota_bytes` TOML). `go/config/config_bucket_settings.go` normalizes negative values to zero and returns the override through `BucketSettingsFor`; zero means unset. Bucket-specific normalization was split out of `config.go` to keep the main file below the hand-written 500-line limit.
- `lib/models/bucket_settings.dart` mirrors the optional field, accepts camelCase and snake_case JSON, omits zero from serialized output, and clamps legacy negative values to zero. `RemoteStorageConfig.bucketSettingsFor` carries it into resolved bucket settings; `lib/models/remote_storage_config_enums.dart` now owns the imported/re-exported persistence enums so the main config model stays below 500 lines.
- `lib/widgets/bucket_settings_dialog.dart` edits the quota in GB, accepts decimals, converts to bytes, and treats zero/blank as unset. The value is informational only and does not enforce an upload limit.
- `lib/widgets/file_manager_bucket_browser.dart` uses the existing `FileListTile` size column as a responsive “配额” column and shows `--` when unset; grid items show `配额 <value>` only when configured. `lib/utils/transfer_format.dart` formats TB values as well as smaller units.
- `go/mount/mount_capacity.go` resolves mounted capacity with bucket `CustomQuotaBytes` first and a backend fallback second. WinFsp passes its global `windowsWinFspCapacityGB` as fallback; Linux FUSE has no fallback and preserves its previous zeroed Statfs when quota is unset.
- `go/mount/backend_windows_winfsp_cgo.go` snapshots the resolved capacity when a session starts; `winfsp_fs_windows.go` reports it as total/free/available blocks. `go/mount/linux_fuse_nodes.go` implements `NodeStatfser` and reports the same bucket quota. Both use 4096-byte blocks and mirror total into free/available because remote usage is unknown; changing quota requires a remount.
- Cloud Files and WebDAV mounts do not use an app-owned Statfs callback, so their reported capacity is controlled by the host filesystem/client and is not changed by custom quota.
- `test/bucket_quota_test.dart` covers legacy/current JSON, decimal input, invalid input, and list values. `go/config/config_bucket_settings_test.go`, `go/mount/mount_capacity_test.go`, `go/mount/winfsp_statfs_windows_test.go`, and the Linux Statfs test cover normalization, precedence, and filesystem block output.

#### Remote quota feasibility (exploration 2026-07-18)

- Generic S3 `ListBuckets` does not provide quota or usage. A reliable S3 quota requires a provider-specific management API; recursively summing objects is expensive, incomplete under pagination/versioning, and is not a quota.
- Baidu Pan's pinned xpan client exposes account-level `Client.Quota()` (`total`, `used`, `free`). WebDAV may expose RFC `DAV:quota-used-bytes` and `DAV:quota-available-bytes`, but server support is optional. Neither remote quota path is currently wired into the bucket list.
- Future remote quota should remain optional and distinguish its source from the current custom display value. Unsupported providers must stay unknown rather than reporting zero, and quota failures must not fail bucket loading.

#### Reorder patterns

- Account/bucket **list** mode: Flutter `ReorderableListView.builder` + `ReorderableDragStartListener` (custom grip handle; no default trailing handles).
- Canonical: `lib/widgets/cloud_storage_account_list.dart`, `lib/widgets/file_manager_bucket_browser.dart`.
- Persistence via Go meta order APIs above; not local-only.
- Other drag uses remain unrelated: `file_manager_drag_selection.dart` (marquee), local file drop upload.



### Feature: Transfer Queue (通用传输队列)

Shared upload/download queue backing both manual file operations and sync-generated tasks. Sync tasks are identified by `rawType` starting with `sync_`.

#### Key files

- `lib/state/transfer_queue.dart` — Core `TransferQueue` singleton. Polling (not streaming): `pollNow()` (:425) calls `api.listTransferJobs()`, `refreshFromSnapshots` (:302) merges `TransferSnapshot` fields into `TransferTask` (`bytesCompleted`/`totalBytes`/`itemsCompleted`/`totalItems`/`speedBytes`/…, :338-377). `_ensurePolling` (:436) picks `_activePollInterval` = 700 ms while `hasRunning`, `_idlePollInterval` = 2 s otherwise (:26-27).
- `lib/state/transfer_task.dart` — `TransferTask` model; `TransferKind { upload, download, copy, move, delete, appUpdate }` (:8); `progress` getter = `bytesCompleted/totalBytes`, 0 when `totalBytes<=0` (:150). Note the queue's `startTask` creates a pending local task optimistically, but `refreshFromSnapshots` overwrites all progress fields from Go snapshots — Go is authoritative.
- `lib/models/transfer_job.dart` — `TransferSnapshot.fromJson` mirror of Go JSON.
- `go/s3/transfer_monitor.go` — `TransferSnapshot` struct (:15) JSON: `id,type,bucket,key,localPath,targetPath,status,statusDetail,createdAt,bytesCompleted,totalBytes,itemsCompleted,totalItems,currentFileKey,currentFileBytesCompleted,currentFileTotalBytes,speedBytes,error`. `startTransfer` (:54) sets status running + TotalBytes (default StatusDetail "uploading"); `advanceTransfer` (:246) adds bytes + computes `speedBytes = completed/elapsed`; also `AddTransferTotal`/`AddTransferItems`/`AdvanceTransferItems`, `finishTransfer` (:263; when TotalBytes>0 sets completed=total). Exposed via bridge `list_transfer_jobs` (`bridge/dispatch.go:98`, handler :394 -> `s3ops.ListTransferSnapshots()` recent-first :330) and `go/webapi/invoke.go:316`.
- `lib/state/transfer_queue_*.dart` — Split concerns: metrics, sync, local progress, foreground, storage, directory children.
- `lib/pages/transfers_page.dart` — Transfers page showing the full queue. Rows (`TransferTaskRow`, `lib/widgets/transfer_task_widgets.dart:69`) show name + `_subtitleFor(task)` (:497; byte progress text only when `totalBytes>0` :529-537) + `TransferStatusBadge` (`transfer_task_widgets.dart:12`; running shows speed or `<type>中`). No per-row progress bar.
- `lib/widgets/batch_task_progress_dialog.dart` — Modal progress for foreground batches (upload/download/delete). Summary `LinearProgressIndicator(value: progress)` (:232-242) with `progress = completedBytes/totalBytes` when any task has `totalBytes>0`, else `1.0` when all finished, else `null` = indeterminate (:44-68). Per-row determinate bar only when `currentFileTotalBytes>0` (:366-382). `_modeForTasks` returns `BatchTaskProgressMode.delete` when all tasks are deletes (:152); copy/icon in `lib/widgets/batch_task_progress_mode.dart`.

#### Gotchas

- A task with `totalBytes==0` renders indeterminate (modal) or plain "删除中" text (transfers row); setting `totalBytes>0` via `startTransfer`/`AddTransferTotal` + `advanceTransfer` immediately turns the modal summary bar and transfers subtitle into real percentage/bytes — no UI change needed.

### Feature: Mount Cache Sync from External Mutations (挂载缓存外部失效)

文件管理界面的删除/重命名/移动/复制/建目录/上传通过 bridge/webapi 直接改远端对象，绕过 `go/mount`。为了让挂载点（Finder/WebDAV/FUSE）和文件管理列表不显示幽灵文件、不卡"删除中"，所有外部 mutation 在成功后必须同步失效挂载 session 的 `bucketCache`。

#### Key files

- `go/mount/external_invalidation.go` — 导出 API `NotifyExternalDelete`/`NotifyExternalUpload`/`NotifyExternalRename`，委托 `globalManager.notifyExternalMutation(cfg, bucket, callback)`。session 不存在或 cfg 不匹配时 callback 不执行，无挂载场景零开销。
- `go/mount/bucket_access_reads.go` — `bucketAccess.MarkExternalDelete`（`markDeleted` + `invalidatePath`，放 tombstone）、`InvalidateExternalUpload`（`removeLocalPath` + `invalidatePath` + 父目录，清 tombstone/staging）、`InvalidateExternalRename`（= delete old + upload new）。
- `bridge/dispatch.go` — `deleteObject`/`renameObject`/`createDirectory`/`uploadFile`/`uploadDirectory` 成功分支调 `bucketmount.NotifyExternal*`；`parentDirectoryOf`/`joinChildPath` 辅助计算路径。
- `bridge/dispatch_object_transfer.go` — `copyObject` 调 `NotifyExternalUpload(TargetKey)`；`moveObject` 调 `NotifyExternalRename(SourceKey, TargetKey)`。
- `go/webapi/invoke.go` — webapi 同名 mutation 同步接入（`delete_object`/`rename_object`/`copy_object`/`move_object`/`create_directory`），仅在 `err == nil` 时调用。
- `go/mount/external_invalidation_test.go` — 覆盖 delete/upload/rename 对 `listCache`/`objectCache`/`localEntries`/`deletedPaths` 的失效，以及 cfg 不匹配/无 session 时的 no-op。
- `lib/pages/file_manager_page_object_deletes.dart` — 删除 API 成功后立即从 `_objects`、`_selectedObjectKeys` 和 `_deletingObjectKeys` 移除该 key；批次结束时把成功 key 传给写后刷新，失败 key 恢复成普通可操作行。
- `lib/pages/file_manager_page_object_loading.dart` — `_loadObjects(... suppressObjectKeys:)` 过滤本批次已确认删除、但提供方短暂重新返回的旧 key，并丢弃对应原始页缓存，让后续导航重新请求后端。
- `test/file_manager_delete_state_test.dart` — 回归覆盖“删除成功，但 force-refresh 仍返回旧目录”的场景，确保行和删除标记都收敛。

#### Gotchas

- `InvalidateListCacheForPrefix`（仅清 `listCache`）不足以反映外部变更——`mergeLocalFiles` 会用过期 `localEntries` 把幽灵重新塞回列表，`hiddenByDeleteLocked` 也会用过期 tombstone 隐藏本应显示的对象。外部 mutation 必须用 `NotifyExternal*` 这组完整语义（同时清 `objectCache`/`localFiles`/`localEntries`/`deletedPaths`）。
- 不要只依赖 `_deletingObjectKeys.removeWhere((key) => !visibleKeys.contains(key))` 收敛状态：S3/挂载刷新可能短暂返回旧目录，导致成功任务永久显示“删除中”。删除 API 成功必须主动清 key/移除行，随后的写后刷新再用成功 key 抑制一次陈旧响应。
- `uploadDirectory` 是 `go func()` 异步：启动时先 `NotifyExternalUpload(parentDirectoryOf(Key))` 让父目录可见，goroutine 完成后再 `NotifyExternalUpload(Key, isDir=true)` 刷新目录内容。

#### Data flow

1. 界面操作 → bridge `delete_object` 等 → `storageops.ForConfig(cfg).XxxObject(...)` 改远端。
2. 成功后 bridge 调 `bucketmount.NotifyExternal*(cfg, bucket, path, isDir)` → `globalManager.notifyExternalMutation` → 匹配 session → `bucketAccess.MarkExternalDelete/InvalidateExternalUpload/InvalidateExternalRename`。
3. Flutter 收到删除成功后立即移除行和“删除中”标记；批次 `list_object_page(forceRefresh)` 使用成功 key 过滤一次陈旧响应并丢弃该页缓存。挂载点下一次 `listDirectory` 重新 `fetchDirectory`，由 tombstone/远端结果共同隐藏已删 key。

### Feature: File Preview & Upload Cache Seeding (文件预览与上传缓存衔接)

点击/双击文件打开走的是 `FileAccessService._ensureCachedObjectRequest`：`headObject` 拿远端 size/mtime → `FileCacheStore.findUsableCachePath` 通过 `RemoteStorageGateway.findCacheIndexRecord` 调 Go bridge 查询 bbolt 缓存索引 → 命中则直接用缓存文件，未命中则建 `download` 任务拉到 `<cacheDir>/files/<bucket>/<key>` 并写缓存记录。缓存命中的硬约束：记录的 `localPath` 必须 `_isInsideRoot` 缓存目录内，且 size/mtime 与远端匹配（`_matchesRemoteObject`）。

**Windows SQLite removal (2026-07-07):** Windows Debug 真实回归中界面闪退，日志为 `Failed to load dynamic library 'sqlite3.dll'`，根因是 `sqflite_common_ffi` 需要系统/打包的 SQLite 动态库，而新 Windows 开发机没有。最终方案已移除 `sqflite_common_ffi` / `sqlite3` 依赖和 `platform_bootstrap_io.dart` 的 SQLite FFI 初始化，且不再由 Flutter 前端维护 JSON 索引；缓存索引通过 bridge 方法 `cache_index_find` / `cache_index_upsert` / `cache_index_remove` / `cache_index_remove_prefix` 存进 Go config bbolt DB 的 `preview_cache` bucket。bbolt key 为 `bucket + "\x00" + objectKey`，record 字段为 `bucket`、`objectKey`、`localPath`、`fileSize`、`lastModified`、`updatedAtEpochMs`。这样 Windows 前端启动不再依赖 `sqlite3.dll`，缓存索引 I/O 也留在 Go bridge 后台 isolate 调用链上。

**Preview latency logging (2026-07-07):** 点击预览卡顿排查使用 `AppLog.debug` 的 `preview` tag。`lib/pages/file_manager_page_preview.dart` 记录 open/source-load/dialog-close；`lib/services/file_access_service_io.dart` 记录 `ensure start`、`head done`、`cache find done`、`cache path done`、download task create/reuse、cache upsert、download complete、read bytes；`lib/services/file_cache_store.dart` 记录 `cache index find` 和 `cache validate`。日志写入 bridge log（macOS/Windows 桌面端通常在 `~/.cloud-volume/runtime/logs/bridge.log`），看 `phaseMs` / `totalMs` 即可判断卡在远端 head、bridge/bbolt index、本地文件 stat/read，还是下载链路。未手动设置日志等级时，Debug 构建默认 `Debug`，Release 构建默认 `Silent`；需要在 设置 → 通用 → 日志设置 切到“调试”后再复现 release 环境问题。

**问题（2026-06-30 修复）：** 上传走传输队列，成功后只 `markTaskDone` + 刷新列表，从不动缓存表。所以"刚上传完的文件双击还要重下"——上传与预览是两套独立记账。

**修复：** 上传成功后调 `FileAccessService.seedCacheFromUpload`（io 实现 / web 空操作）：`headObject` 拿远端元数据 → 把本地源（`localSourcePath` 或 `bytes`）copy/写入缓存目录 → `upsertCacheRecord`。以远端 size/mtime 为准（不能用本地 stat，否则比对失败）。整个 seed 包 try/catch 吞异常：只是缓存优化，绝不阻断"上传已成功"。`unawaited` 后台执行，不阻塞列表回显。

#### Key files
- `lib/services/file_access_service_io.dart` — `seedCacheFromUpload`（桌面实现）、`_ensureCachedObjectRequest`（预览/打开缓存命中逻辑）。
- `lib/services/file_access_service_downloads_io.dart` — part extension，承接下载另存为/默认目录选择相关方法，保持 `file_access_service_io.dart` 在线数规则内。
- `lib/services/file_access_service_web.dart` — `seedCacheFromUpload` 空操作（浏览器无本地缓存目录）。
- `lib/pages/file_manager_page_actions.dart` — `_runUploadTask`（本地路径上传，传 `localSourcePath`）、`_runBrowserUploadTask`（bytes 上传，传 `bytes`）成功分支调 seed。
- `lib/services/file_cache_store.dart` — 只负责缓存路径生成、安全校验、size/mtime 比对、本地缓存文件删除；索引持久化全部委托 `RemoteStorageGateway` bridge 方法。缓存文件本体仍放在 `<cacheDir>/files/<bucket>/<key>`。
- `lib/models/cached_file_record.dart` — Dart cache index record，JSON 使用 bridge camelCase 字段，并兼容旧 snake_case 读取。
- `lib/services/remote_storage_gateway.dart` / `lib/services/remote_storage_api_desktop_cache.dart` / `lib/services/remote_storage_api_web.dart` — gateway cache index API。Desktop 调 bridge；Web 本地缓存索引方法为 no-op/null，因为浏览器没有本地预览缓存目录。
- `go/config/cache_index.go` — Go bbolt cache index store，复用 `config.db`，bucket 为 `preview_cache`，支持 find/upsert/remove/remove-prefix；`go/config/cache_index_test.go` 覆盖读写和前缀删除。
- `bridge/dispatch_cache_index.go` / `bridge/dispatch.go` — bridge JSON 方法路由：`cache_index_find`、`cache_index_upsert`、`cache_index_remove`、`cache_index_remove_prefix`。
- `lib/pages/file_manager_page_preview.dart` — 双击预览入口 `_showObjectPreview`。

#### Data flow
1. 预览/打开：`FileAccessService._ensureCachedObjectRequest` → `api.headObject` → `FileCacheStore.findUsableCachePath(api, cacheDir, bucket, remoteObject)` → desktop gateway `cache_index_find` → Go `config.FindCacheIndexRecord` → Dart 校验路径在 cache root 内、文件存在、size/mtime 匹配。
2. 下载成功或上传 seed 成功：文件写入 `<cacheDir>/files/<bucket>/<objectKey>` → `FileCacheStore.upsertCacheRecord(api, ...)` → desktop gateway `cache_index_upsert` → Go bbolt `preview_cache`。
3. 删除/移动/重命名对象：`FileAccessService.evictCacheForObject(api, ...)` → 文件对象走 `cache_index_remove`；目录对象走 `cache_index_remove_prefix`，Go 返回被删记录，Dart 再清理对应本地缓存文件。

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
- `lib/pages/settings_page.dart` — Settings page. Groups (通用设置, Windows 设置, 关于) use a **left vertical sidebar rail** (not top tabs). Sync management was **removed** from Settings (2026-06-26) and now lives entirely in the File Sync Tasks page. The obsolete Windows “此电脑” entry card and anchor were removed on 2026-07-15.

### Feature: Settings Page Layout (设置页布局)

The settings page uses a **two-column anchor layout**: a left vertical anchor rail with section headers (通用 / Windows / 关于), and a right scrollable page that shows all settings cards in one continuous column. Clicking a left rail item scrolls the right page to that card. The rail has **no persistent active/selected highlight** — entries only change appearance on hover (2026-07-06 change: previously a click pinned a highlighted entry via `_activeTab`; that was removed so nothing stays selected after the click).

#### Key files
- `lib/pages/settings_page.dart` — `SettingsPage` + `_SettingsPageState`. `_SettingsTab` enum identifies one card/anchor per config block. State owns `_contentScrollController` and `_sectionKeys` (**no `_activeTab` field**). `build()` renders a `Row`: left `SizedBox(width: 180)` with title + `_buildGroupRail(theme)`; right `Expanded` + `SingleChildScrollView(controller: _contentScrollController)` with `_buildAllContent`.
- `lib/pages/settings_page_layout.dart` — part file. `_SettingsLayout` extension: `_railGroups()` builds `_SettingsRailGroup` list with section headers + anchors; `_buildGroupRail` renders headers + `_SettingsGroupTile` rows; `_tabLabel` maps enum to Chinese label; `_buildAllContent` renders every visible card as one page using `KeyedSubtree` + `_sectionKeys`; `_scrollToAnchor` uses `Scrollable.ensureVisible` and **only scrolls** — it no longer updates any `_activeTab` (2026-07-06). `_SettingsGroupTile` is the hover-aware StatefulWidget tile (must be StatefulWidget — see Hover rule above); it exposes **no `active` parameter** — appearance is hover-only.
- `lib/pages/settings_page_sections.dart` — part file. `_SettingsSections` extension with per-anchor card builders (`_buildUpdateSection`, `_buildProxySection`, `_buildAppearanceSection`, `_buildLogSection`, `_buildDownloadSection`, `_buildCacheSection`, `_buildVisibilitySection`, `_buildSyncSection`, `_buildTrashSection`, `_buildWebdavSection`, `_buildResetAccountSection`, `_buildConfigManageSection`, `_buildWindowsWritebackSection`, `_buildWindowsMountSection`, `_buildAboutSection`). Each returns `[_buildCard(...)]`. The removed Windows entry has no builder or page state/action; `windowsThisPcEntryEnabled` remains in the config model only for backward compatibility.
- `lib/widgets/settings_cache_section.dart` — Settings → 通用 → 缓存设置 card body. Layout is intentionally split into three visible groups: `缓存目录设置` (resolved path + choose/reset/open actions), `缓存占用` (stats block + refresh action + error text), and `缓存清理` (manual clean buttons + auto-clean rules editor). Keep these concerns visually separated; do not collapse them back into one mixed button row.
- `lib/pages/settings_page_actions.dart` — part file with `_SettingsPageActions` extension: all config save/refresh/cleanup actions.

#### Data flow
1. `_SettingsPageState.build()` wires the right-side `SingleChildScrollView` to `_contentScrollController` and calls `_buildAllContent(theme, config)`.
2. `_railGroups()` returns 通用 (including 日志设置; download anchor only when supported; WebDAV 凭据 anchor only on Web), Windows (if `isWindowsPlatform`, with 写回并发 and 挂载恢复 only), 关于 groups.
3. `_buildAllContent` loops through those same visible anchors, wrapping each section card with the matching `_sectionKeys[tab]`.
4. Tapping `_SettingsGroupTile` calls `_scrollToAnchor(tab)`, which runs `Scrollable.ensureVisible` to scroll the right page to the keyed card. It does **not** set any active/selected state — the rail tile only shows hover feedback while the pointer is over it.
5. Left rail scrolls independently when the anchor list is taller than the viewport.

### Feature: App Diagnostic Logging (应用诊断日志)

The app has four diagnostic levels: `Silent`, `Error`, `Info`, `Debug`. Settings labels are user-facing Chinese (`安静` / `仅错误` / `常规` / `调试`), while persisted/bridge values stay lowercase English (`silent` / `error` / `info` / `debug`). If the user has never chosen a level, Flutter sets the default by build mode: Debug builds use `Debug`, Release builds use `Silent`.

- `go/logging/logging.go` — Central Go logging package. Owns `Level`, process-wide atomic level, `ConfigureOutput`, filtering writer, and `Debugf` / `Infof` / `Errorf`. Existing backend `log.Printf` lines are treated as `Info`; obvious error-like legacy lines containing `error` / `failed` / `warn` are kept at `Error` level. New backend diagnostics should use this package instead of adding another logger or ad-hoc filter.
- `bridge/logging.go` — Configures the standard Go logger to write through `go/logging` into stderr + `BridgeLogPath()` (`~/.cloud-volume/runtime/logs/bridge.log`). The backend starts at `Silent`; Flutter syncs the effective level after API bootstrap.
- `bridge/dispatch_log.go` / `bridge/dispatch.go` — Bridge JSON methods: `set_log_level`, `get_log_level`, and `write_flutter_log`. `write_flutter_log` forwards Flutter-tagged lines into the same Go logging filter, so frontend and backend diagnostics share one level.
- `lib/utils/app_log.dart` — `AppLogLevel` + `AppLog.info/debug/error`; bound in `AppBootstrapPage` after API bootstrap. The current level is persisted in SharedPreferences key `app.log.level`; `loadLevel()` and `setLevel()` both call `RemoteStorageGateway.setLogLevel`, so settings apply to Go backend logs as well as Flutter-forwarded logs.
- `lib/widgets/settings_log_section.dart` — User-facing Settings UI for the four levels. Lives under Settings → 通用 → 日志设置 and avoids implementation terms such as Flutter/bridge in visible copy.
- `lib/pages/settings_page.dart` / `settings_page_layout.dart` / `settings_page_sections.dart` — Adds the `logging` anchor/card to the Settings page.
- `RemoteStorageGateway.setLogLevel` / `writeAppLog` — desktop FFI calls; web no-op because browser builds do not write the desktop bridge log file.

### Feature: In-App Auto Update (应用内自动更新)

Detects new GitHub releases and, on desktop, downloads + installs the correct platform package in-app — no manual uninstall or command-line steps needed.

**Mirror rule (2026-07-02 fix):** The GitHub Releases **API** call (`checkLatestRelease`) is **always direct** to `api.github.com` — public download mirrors like `gh-proxy.com` reject api.github.com URLs with HTTP 403. The configured mirror prefix (`UpdateNetworkConfig.wrapUrl`) is now applied **only** to the asset **download** URL in `downloadAndInstallAsset`.
**Architecture matching (2026-07-02 fix):** `matchPlatformAsset` previously hardcoded universal-first on macOS, so an arm64 app would download the larger universal DMG. It now prefers the **running build architecture**: the Go bridge exposes `get_build_info` returning `buildArch` (injected at compile time via `-ldflags -X main.buildArch=...` in Makefile / `build_desktop_packages.sh`); Flutter reads it via `widget.api.getBuildInfo()` and passes it to `matchPlatformAsset`. If the bridge is unavailable (web, old dev build), it falls back to `runtimeCpuArchitecture` (parsed from `Platform.version`). Universal is tried only after the arch-specific package, and as a fallback when the specific arch asset is absent.
**Download progress (2026-07-02 fix):** When the server does not report `Content-Length` and the asset metadata has no size, the progress bar previously stayed stuck at 0%. `_installProgress` is now initialized to `-1` (indeterminate); the `LinearProgressIndicator` uses `null` value (continuous animation) and the status text shows downloaded bytes via `_formatBytes`.
**Windows architecture matching (2026-07-13, supersedes the Windows portion above):** Both Dart and Go asset matchers prefer exact native `yunjuan-windows-<arch>.zip` / installer names. ARM64 may fall back to amd64 because Windows 11 ARM supports x64 emulation; amd64 never selects an ARM64 package. Exact filenames prevent desktop/CLI package collisions.
Participating files: `bridge/dispatch_platform_asset.go` / `dispatch_platform_asset_test.go` implement and test bridge-side exact matching; `lib/services/platform_asset_matcher.dart` / `test/platform_asset_matcher_test.dart` implement the same Dart-side ordering with a test-only platform override.
**Timeout hardening (2026-07-04 fix):** `checkLatestRelease` used a 10s single-shot timeout and often failed on slow GitHub/proxy paths; it now uses 30s per attempt with up to 3 attempts (2s/4s backoff) for `TimeoutException` and retryable socket errors. `install_app` download used `ProxyHTTPClient(..., 120)` which caps the **entire** HTTP request at 2 minutes — large DMG/exe downloads via mirrors frequently hit that; bumped to 7200s while still cancellable via `cancel_transfer` on the request context.
**Mirror probe + kind fix (2026-07-04 fix):** Two related issues when a mirror is configured: (1) `TransferTask._transferKindFromName` defaulted `app_update` to `upload`, so the transfers page showed an empty "upload" task — now explicitly mapped to `download`. (2) Some public mirrors silently return 403/HTML for large GitHub release downloads, so the progress bar sat at 0B forever; `install_app` now HEAD-probes the wrapped download URL with a 20s client before streaming and fails the task with a clear "镜像不可用" message. The mirror field (`SettingsUpdateMirrorField`) gained a "测试镜像可用性" button that fetches the latest release's first `browser_download_url`, wraps it with the selected prefix, and HEAD-probes it to show 2xx/3xx/4xx result inline so users can pick a working mirror before triggering an update.
**App-update task kind (2026-07-04 fix):** Go transfer snapshots use `type: "app_update"`. `TransferQueue._addRemoteTask` maps `snapshot.type` via `_kindFromWire`, which previously had no `app_update` case → `TransferKind.upload` and UI label "上传". Fix: `TransferKind.appUpdate`, map in both `_transferKindFromName` and `_kindFromWire`, `typeLabel` "应用更新", transfers filter + row icon (`refreshCw`). `displayName` uses `key` (asset file name from Go `StartQueuedTransfer` target).
**Installer cache + resume (2026-07-04):** `install_app` wrote to `os.TempDir()/app_updates` and always full re-download. Now `<ResolveCacheDir>/app_updates`, `UsableCachedInstaller` + `assetSize` from Dart skips network (`statusDetail` `cached`); `downloadInstaller` uses `Range: bytes=N-` resume (206 append, 200 without Range restarts file). `installApp` JSON adds `config` + `assetSize`.
**Windows green ZIP update (2026-07-08; headless since v1.2.0):** `matchPlatformAsset` prefers `yunjuan-windows-amd64.zip` for Windows and only falls back to `yunjuan-windows-amd64-installer.exe` when the ZIP is absent; the Go installer path supports both. `installWindowsZip` extracts `cloud-volume-updater.exe` from the downloaded zip to a temp directory (old versions do not need to pre-install it) and launches it with `-zip`, `-install-dir`, `-pid`, `-exe-name`. In watched builds, the PID is the running `cloud-volume-app.exe` but `-exe-name` is the public `cloud-volume.exe` launcher. The updater waits for the app PID, then polls until the launcher has also exited and become writable before replacing the staged bundle and starting the new launcher. Since commit `8f2d0ac3` / release `v1.2.0`, `updater_window_windows.go` runs this flow without a window or message pump; failures are visible only in `%TEMP%\cloud-volume-updater-<pid>.log`. Because the bridge intentionally exits the main app before the external updater replaces locked files, any headless updater failure is perceived by users as the app disappearing or failing to restart. The updater EXE is built by `run_windows.ps1 -Build` and `build_desktop_packages.sh build_windows`, and ships inside the release zip so it can be extracted on demand during updates.

**Release artifact regression (v1.2.0):** the GitHub release for `v1.2.0` contains Windows CLI archives but no desktop `yunjuan-windows-amd64.zip` or installer. The tagged `build_desktop_packages.sh` placed a shell comment inside the continued PowerShell command used to invoke Inno Setup; commit `616a3b0c` fixed that CI command after the tag. Do not use `v1.2.0` as evidence for a desktop-runtime regression because no official Windows desktop artifact was published for that tag. Static comparison of the official `v1.1.9` and `v1.2.1` desktop ZIPs found the same 639-file layout, identical Flutter engine/plugin dependency set, x86-64 EXE/DLL/AOT architectures, and identical imported runtime DLL names; only `data/app.so`, `remote_storage_bridge.dll`, and the updater payload changed in size. This rules out a generally missing DLL or wrong-architecture package, but not a partial in-place update or user-specific startup data failure.
**Relaunch + mirror-mode persistence (2026-07-04 fix):** (1) `relaunchApp` on macOS launched `/Applications/云卷.app/Contents/MacOS/云卷` (the raw executable) with `open -n`, which spawned a foreground shell-style process without normal LaunchServices window/activation lifecycle and left the old process un-cleaned. It now launches `/Applications/云卷.app` (the bundle) so LaunchServices owns the new app. (2) `SettingsUpdateMirrorField` initialized `_mode` from `widget.initialConfig.mirrorPrefix` in `initState`, but `_SettingsUpdateSectionState._loadMirrorConfig` is **async** — the first build passed an empty `UpdateNetworkConfig`, so `_mode` resolved to `direct` and never updated when the real `mirrorPrefix` arrived (SharedPreferences actually stored `flutter.update.mirror_prefix` correctly, visible via `defaults read com.example.remoteStorage`). Added `didUpdateWidget` to re-resolve `_mode` whenever the parent passes a changed `mirrorPrefix`, clearing probe state at the same time.
**Temp download path (2026-07-03 fix):** Historical Dart-side temp-dir issue; install path is now Go `bridge/dispatch_app_install.go` (`os.TempDir()/app_updates`, `MkdirAll` before download).
**Download integrity (2026-07-06 fix):** 一键更新报「macOS 安装失败：挂载 DMG 失败：映像数据已损坏」。根因：`downloadInstaller` 收到 HTTP 响应后只按 body 流写盘，下载完成不做任何校验；部分加速镜像用 HTTP 200 返回截断内容或 HTML 错误页，被原样写入 `.dmg`，到 `hdiutil attach` 时才暴露为映像损坏（GitHub 网页直接下载同样的 asset 正常）。修复：双重完整性校验。(1) `bridge/app_install_download.go` 新增 `verifyDownloadedSize(destPath, expectedSize)`：下载并显式 `f.Close()` flush 后 stat 落盘文件，与 GitHub asset `assetSize` 不一致时删除残留文件并报「下载文件大小不匹配……镜像可能返回了截断或错误内容」；`expectedSize <= 0` 时跳过。(2) 新增 `verifyDownloadedDigest(destPath, expectedDigest)`：用 GitHub asset 的 `digest`（`sha256:<hex>`）对落盘文件读盘算 SHA-256 全文校验，大小相同但内容被替换的情况也能挡住，不匹配删除文件并报「安装包校验和不匹配：下载内容已被损改，请尝试切换镜像或直连 GitHub 重新更新」；空/非 `sha256:`/非 32 字节 hex 视为不可用摘要，跳过不阻断。缓存命中路径也做大小+校验和校验，digest 不匹配时跳过缓存重新下载。(3) `bridge/dispatch_app_install.go` `appInstallArgs` 增加 `AssetDigest`；`probeDownloadURL` 增加 `expectedSize` 参数，镜像 HEAD 返回的 `Content-Length > 0` 且与 `assetSize` 不一致时直接报「镜像报称大小为 N 字节，与 GitHub Release 的 M 字节不一致」，下载前就拒绝坏镜像。(4) `downloadInstaller` 写文件由 `defer f.Close()` 改为显式 `f.Close()`，保证 stat 前数据已落盘。(5) Dart 侧 `ReleaseAsset` 增加 `digest` 字段，解析 GitHub asset 的 `digest`；`downloadAndInstallAsset`/网关 `installApp`（desktop runtime + web）增加 `assetDigest` 参数透传到 Go。测试 `bridge/app_install_download_test.go` 覆盖大小匹配/不匹配（且文件被删除）/无期望大小，以及 digest 匹配/不匹配（且文件被删除）/空与畸形 digest 五种情形。
**Windows file handle note (2026-07-06 fix):** `verifyDownloadedDigest` must close the opened installer file before removing it on mismatch. Unix allows unlinking an open file; Windows does not, so leaving `defer f.Close()` before `os.Remove(destPath)` made `TestVerifyDownloadedDigestMismatchRemovesFile` fail and would leave a bad cached installer behind.

**Bundled dylib load order (2026-07-03 fix):** macOS bundles may contain two copies of `libremote_storage_bridge.dylib` — `Contents/Frameworks/` (from `make build-macos`) and a stale `Contents/MacOS/` copy from older dev runs. `_findBundledLibraryPath` previously preferred `MacOS/` first, so Flutter FFI loaded the old dylib without `install_app` → `unsupported bridge method "install_app"`. Fix: probe `Frameworks/` before `MacOS/`; `Makefile` `build-macos` runs `rm -f` on `Contents/MacOS/$(dylib)` before `cp` to Frameworks.
**HTTP/2 stream reset + resume retry (2026-07-06 fix):** 一键更新报「下载失败：读取响应失败：stream error: stream ID 1; INTERNAL_ERROR; received from peer」。根因：部分 GitHub 加速镜像在 HTTP/2 上转发大文件时会在中段 reset 流，`downloadInstaller` 的单次 `resp.Body.Read` 直接把错误返回用户即终止。修复：`bridge/app_install_download.go` 把单次下载抽成 `fetchOnce`，`downloadInstaller` 外层重试编排：遇到 `stream error` / `INTERNAL_ERROR` / 连接重置 / 意外 EOF 等可重试错误时按已落盘字节数用 HTTP Range 续传重试，最多 5 次（每次退避 attempt 秒，且响应 ctx 取消）；HTTP 状态码、写盘失败等不可重试错误仍立即返回。新增 `isRetryableFetchError` 判定。测试 `bridge/app_install_download_test.go` 新增 `TestIsRetryableFetchError` 覆盖可重试（stream error / connection reset / EOF）与不可重试（HTTP 403 / 写盘失败）样本。**Reverted sub-fix:** 曾尝试在 `go/config/proxy.go` 新增 `InstallerDownloadHTTPClient` 并设置 `ForceAttemptHTTP2=false` 强制 HTTP/1.1，但 `gh-proxy.com` 在该路径下返回 HTTP/2 二进制帧，Go 按 HTTP/1.x 解析时报 `net/http: HTTP/1.x transport connection broken: malformed HTTP response "\x00\x00..."`；因此撤回协议强制，保留 Go 默认协议协商 + Range 续传重试。

#### Key files

- `lib/bridge/remote_storage_bridge.dart` — FFI loader: `connect()` / `openAtPath()`; `_findBundledLibraryPath()` macOS order Frameworks → MacOS.
- `lib/services/app_update_service.dart` — `AppUpdateService.checkLatestRelease`: fetches GitHub Releases API **directly** (never wrapped by mirror), parses `tag_name` + `assets` array into `AppUpdateCheckResult` with `List<ReleaseAsset>`. Each `ReleaseAsset` carries `name`, `downloadUrl`, `size`, `contentType`, and `digest` (GitHub asset `sha256:<hex>` for post-download integrity verification); `digest` is empty when the release has none. Also has `compareVersionLabels` for semver comparison.
- `lib/services/platform_asset_matcher.dart` — `matchPlatformAsset(assets, {runtimeArchitecture})`: picks the correct asset. macOS order: arch-specific DMG/zip → universal DMG/zip → other-arch DMG/zip; Windows prefers `.zip` → `installer.exe`; Linux prefers `.AppImage` → `.tar.gz`.
- `lib/services/app_installer.dart` — Conditional export: IO → `app_installer_io.dart`, Web → `app_installer_stub.dart`. Exports `kSupportsInAppInstall` and `downloadAndInstallAsset`.
- `lib/services/app_installer_io.dart` — Desktop: delegates to `api.installApp()` → bridge `install_app`; progress via `TransferQueue` only (no Dart `Process.run` / download).
- `bridge/dispatch_app_install.go` — Go `install_app`: download (mirror/proxy), platform install (DMG/ZIP/exe/AppImage/tar), relaunch, `os.Exit(0)`; progress via `s3ops` transfer monitor. Windows installer EXE starts Inno Setup silently; Windows ZIP starts `cloud-volume-updater.exe` because the running app/launcher cannot overwrite their own EXE/DLLs. `probeDownloadURL` HEAD-probes wrapped mirror URL (with `expectedSize` Content-Length check) before download. Uses `storageconfig.ProxyHTTPClient` for installer downloads; do not force HTTP/1.1 because some mirrors return HTTP/2 frames and trigger malformed-response errors.
- `bridge/windows_process_attrs_windows.go` / `_other.go` — Small platform shim for starting the Windows ZIP updater hidden while keeping non-Windows bridge builds portable.
- `cmd/cloud-volume-updater/main.go` — Standalone Go updater entry point. Parses -zip, -install-dir, -pid, -exe-name; opens %TEMP%\cloud-volume-updater-<pid>.log at startup; runs performUpdate (wait old PID, poll writability, extract zip, copy payload skipping own exe, relaunch, then waitForNewApp to confirm the new process started).
- `cmd/cloud-volume-updater/updater_window_windows.go` — Windows headless wrapper around `performUpdate`. It logs status and exits with code 1 on failure; there is no updater UI, message pump, or visible error after `v1.2.0`.
- `cmd/cloud-volume-updater/updater_window_other.go` — Non-Windows stub so the updater cross-compiles for go vet.
- `cmd/cloud-volume-updater/process_windows.go` / `process_other.go` — waitForProcess (WaitForSingleObject), isFileWritable (exclusive CreateFile), waitForNewApp (polls tasklist for a new PID != old PID).
- `cmd/cloud-volume-updater/logger.go` — Process-wide timestamped logger writing to %TEMP%\cloud-volume-updater-<pid>.log; flushed on every logf call.
- `bridge/app_install_download.go` — Resumable installer download (`downloadInstaller`, HTTP Range), retry coordinator around `fetchOnce` (up to 5 attempts on HTTP/2 stream reset / connection reset via `isRetryableFetchError`), cache dir resolution, and post-download integrity checks: `verifyDownloadedSize` (byte count vs GitHub asset `size`) followed by `verifyDownloadedDigest` (SHA-256 vs GitHub asset `digest` `sha256:<hex>`); cache path also re-verifies digest before reuse.
- `go/config/proxy.go` — Proxy transport/client helpers. `ProxyHTTPClient` wraps `ProxyTransport`; installer downloads use this default protocol negotiation plus `downloadInstaller` Range retry, not a forced HTTP/1.1 transport.
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

Three proxy modes: system (default), direct (no proxy), custom (user-specified URL). Affects all outbound traffic. **System mode note (2026-07-08):** Dart's `HttpClient.findProxyFromEnvironment` only reads `http_proxy`/`https_proxy` env vars and ignores the Windows Settings manual proxy. The desktop app now resolves the host-level system proxy via a new bridge method `resolve_system_proxy`, which reads `HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings` (`ProxyEnable`/`ProxyServer`) on Windows. Flutter calls it before GitHub update checks and installer downloads so the "follow system" mode actually honors the Windows proxy. Go-side `ProxyTransport` still uses `http.ProxyFromEnvironment` for S3/WebDAV/Baidu traffic.

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
4. Dart http calls (GitHub API, download) use `createProxyHttpClient(ProxyConfig(mode, customUrl))`. In system mode the update section first calls `api.resolveSystemProxy()` and converts a Windows registry proxy into a custom `ProxyConfig` because Dart cannot read the Windows system proxy directly.
5. GitHub mirror wraps **download** URLs only (via `UpdateNetworkConfig.wrapUrl` in `app_installer_io.dart`); the Release API call bypasses the mirror entirely.
- `go/config/proxy.go` 鈥?`ProxyTransport(mode, customURL)` returns an `http.RoundTripper` respecting the mode. `ProxyHTTPClient` wraps it with a timeout.
- `bridge/dispatch_system_proxy.go` + `dispatch_system_proxy_windows.go` / `_other.go` 鈥?`resolve_system_proxy` bridge method: reads Windows registry `ProxyEnable`/`ProxyServer` on Windows, returns empty on other platforms.
- `lib/models/system_proxy_info.dart` 鈥?Dart mirror of the Go `systemProxyResult`.
- `lib/widgets/settings_update_section.dart` 鈥?`_resolveEffectiveProxy()` queries `api.resolveSystemProxy()` in system mode before update check and install download, converting the result to a `ProxyConfig(mode: custom)`.

### Feature: App Modal (统一拟态框)

**Binding rule (2026-07-11):** User-facing modal UI defaults to **in-app app modals** (single Flutter engine). OS `desktop_multi_window` editors are **debug-only Experimental**. Business code must not call `showShadDialog` directly — only `lib/services/app_modal.dart` may wrap it.

#### Unified API

- `lib/services/app_modal.dart` — Sole business entry for in-app modals:
  - `showAppModal` — builder returning a `ShadDialog` / dual-mode editor.
  - `showAppModalDialog` — title / description / body / actions helper for simple forms.
  - `showAppConfirmModal` — yes/no confirmations (`cancel` + `confirm`, optional `destructive`).
  - Constants: `kAppModalDefaultMaxWidth = 480`, `kAppModalDefaultContentWidth = 420`.
  - The only allowed `showShadDialog` call lives here.
- `lib/services/modal_sub_window_debug.dart` — `preferModalSubWindows = kDebugMode && USE_MODAL_SUB_WINDOWS`.
- `lib/services/desktop_overlay.dart` — `showDesktopOverlayOrDialog`: debug OS sub-window only when gate + supported; otherwise in-app modal. **Current sole production caller:** `showRemoteDirectoryPicker`.

#### Inventory (all current in-app modals)

Catalogued 2026-07-14. Presentation is always in-app `showAppModal*` unless noted under dual-mode / debug sub-window.

##### Dual-mode large editors (default `asDialog: true`; optional debug OS sub-window)

| Modal | Entry / widget | Opened from | Notes |
|-------|----------------|-------------|-------|
| Account editor | `CloudStorageAccountDialog` | `cloud_storage_page.dart` add/edit | Compact in-app max width **520**. Main form keeps connection fields only; path-style + proxy open nested **高级设置** modal (`showAppModal`, max **420**). Content-fit resize only in sub-window. |
| Sync profile editor | `FileSyncProfileEditor` | `file_sync_tasks_page_actions.dart` add/edit | Comfortable max width **600**. **3-step** wizard: 同步两端 → 同步策略 → 高级设置（排除规则 / 启用）. Nested remote picker. |
| Remote directory picker | `showRemoteDirectoryPicker` / `RemoteDirectoryPickerDialog` | Sync editor step 1 | Comfortable max width **640**, body height **480**. Via `showDesktopOverlayOrDialog`. |

Debug sub-window shells (only when `preferModalSubWindows`): `AccountEditorWindowApp`, `SyncEditorWindowApp`, `RemoteDirectoryPickerWindowApp` — see **Feature: Desktop Modal Sub-Window Shell**.

##### File manager / objects

| Modal | Entry | Opened from | Purpose |
|-------|-------|-------------|---------|
| Create directory | `CreateDirectoryDialog` | `file_manager_page_actions.dart` | Name input + create. |
| Rename object | `showRenameObjectDialog` | `file_manager_page_actions.dart` | Rename file/dir. |
| Copy / move target path | `showObjectTargetPathDialog` | file-manager actions / selection | Path form for copy or move. |
| Delete object | `showDeleteObjectDialog` | `file_manager_page_actions.dart` | Single delete confirm. |
| Batch delete objects | `showDeleteObjectsDialog` | `file_manager_page_selection.dart` | Multi-select delete confirm. |
| Bucket settings | `showBucketSettingsDialog` | `file_manager_page_bucket_policy.dart` | Per-bucket read-only + trash policy. |
| Mount bucket | `showMountBucketDialog` | `file_manager_page_mount.dart` | Mount path + read-only mode. |
| File preview | `FilePreviewDialog` via `showAppModal` | `file_manager_page_preview.dart` | In-app image/text preview; separate non-modal OS preview window also exists. |
| Batch task progress | `BatchTaskProgressDialog` via `showAppModal` | `file_manager_page_upload_feedback.dart` | Upload/download/copy/move progress; can background. |
| Breadcrumb overflow | inline `ShadDialog` via `showAppModal` | `file_manager_breadcrumb_bar.dart` | Jump to collapsed path segments. |
| Page error / message | inline `ShadDialog` via `showAppModal` | `file_manager_page_actions.dart` `_showPageMessage` | Generic failure / info. |

Object/trash dialog helpers live in `lib/widgets/object_action_dialogs.dart`. Create-directory UI is `lib/widgets/create_directory_dialog.dart`. Bucket/mount: `bucket_settings_dialog.dart`, `mount_bucket_dialog.dart`. Preview/progress: `file_preview_dialog.dart`, `batch_task_progress_dialog.dart`.

##### Trash

| Modal | Entry | Opened from | Purpose |
|-------|-------|-------------|---------|
| Permanent delete (one) | `showDeleteTrashItemDialog` | file-manager trash + `global_trash_page.dart` | Hard-delete one trash item. |
| Permanent delete (batch) | `showDeleteTrashItemsDialog` | `global_trash_page.dart` | Hard-delete multiple. |
| Empty trash | `showClearTrashDialog` | file-manager trash + global trash | Clear one bucket trash. |

##### Share

| Modal | Entry | Opened from | Purpose |
|-------|-------|-------------|---------|
| Share duration | `showShareDurationDialog` | file-manager actions, share management refresh | Hours input + presets (1h–7d). |
| Share created | `showShareLinkDialog` | after create share | Copy/open link. |
| Share details | `showShareRecordDetailsDialog` | `share_management_page.dart` | Detail + copy/open/refresh/delete actions. |
| Delete share (one) | `showDeleteShareRecordDialog` | share management | Confirm delete one record. |
| Delete share (batch) | `showDeleteShareRecordsDialog` | share management multi-select | Confirm delete many. |

All in `lib/widgets/share_dialogs.dart`.

##### Sync / accounts / settings / app chrome

| Modal | Entry | Opened from | Purpose |
|-------|-------|-------------|---------|
| Delete sync profile | `showAppConfirmModal` | `file_sync_tasks_page_actions.dart` | Confirm delete sync config. |
| Clear finished transfers | inline `ShadDialog` via `showAppModal` | `transfers_page.dart` | Remove finished/failed/cancelled queue rows. |
| Reset all accounts | inline `ShadDialog` via `showAppModal` | `settings_reset_user_config_section.dart` | Destructive clear of saved accounts. |
| Advanced S3 settings | inline `ShadDialog` via `showAppModal` | `config_right_form.dart` | Region + path-style (first-run / legacy form). |
| Close app | inline `ShadDialog` via `showAppModal` | `desktop_window_controls.dart` | Tray hide vs exit (or minimize vs exit). |
| Profile / gateway picker | `ProfilePickerDialog` | currently no live caller found | Switch remote storage gateway; keep for potential reuse. |

#### Not app modals

- `FilePreviewWindowApp` — detached non-modal preview window (no scrim / overlay release).
- Toasts (`showAppToast` / `showAppErrorToast`) — non-blocking, not modal routes.
- Context menus / overflow menus — not modal dialogs.

#### Gotchas

- Large editors with internal `Expanded` / fixed-height lists must not get an outer `SingleChildScrollView` on top. Prefer finite height inside `ShadDialog` (picker uses height 420) or `scrollable: true` only when the body is `mainAxisSize: min`.
- Hover / close chrome still follows global hover rules (`ListInteractionColors`; no ink splash; neutral wash only).
- Web always uses app modals (window services unsupported).
- Dual-mode editors must stay **smaller than the main window**: account/sync **~600–640**, remote picker **~640×480**. Prefer more steps / nested advanced modals over widening. Account path-style + proxy live in nested 高级设置; sync exclude/enable is step 3.
- Prefer `showAppConfirmModal` for simple yes/no; prefer dedicated widgets/helpers when the body has form fields, lists, or progress.
- When adding a new modal: enter only through `showAppModal*`, keep content under 500 lines (split by part/feature), and update this inventory.

### Feature: Desktop Modal Sub-Window Shell (通用子窗口壳)


Three **debug-only** modal sub-windows (account editor, sync editor, directory picker) share a common lifecycle when `preferModalSubWindows` is on: detached OS window with hidden title bar → custom 44px title bar → bootstrap bridge/data → loading/error/content body → modal scrim + overlay release on close. Previously each window re-implemented this from scratch (title bar widget × 3, close function × 3, `WindowLifecycle` × 2, `_configure*Window` × 4). A shared abstraction now handles all of it.

#### Shared components

- `lib/widgets/desktop_modal_shell.dart` — `DesktopModalShell` (StatelessWidget): 44px title bar with title + close button. Replaces `_AccountEditorTitleBar` / `_SyncEditorTitleBar` / `_PickerTitleBar`.
- `lib/app/desktop_modal_sub_window_app.dart` — `DesktopModalSubWindowApp<T>` (StatelessWidget): generic sub-window root. Encapsulates `ShadApp` + theme, `_ModalSubWindowLifecycle` (overlay release on dispose/close), `DesktopModalParentFocusRelay` (optional via `useParentFocusRelay`), `DesktopModalWindowFocusGate`, `DesktopModalScrim`, `DesktopModalShell`, and bootstrap-driven loading/error/content body. Features supply `bootstrap: Future<T> Function()` and `contentBuilder: Widget Function(BuildContext, T, Future<void> Function() close)`. The third `close` arg is the public close sequence `closeDesktopModalSubWindow(...)` (formerly private `_closeModalSubWindow`): optional `onClose` → unregister child → notify creator overlay release → clear chrome → `windowManager.close()`. **`scrollable` (default true):** when true, body is `Padding` + `SingleChildScrollView` (form-like content such as the account editor). When false, body is only `Padding` so content receives finite height from the shell `Expanded` — required for widgets that use `Expanded` / fill-height lists (`FileSyncProfileEditor`, `RemoteDirectoryPickerDialog`). Never wrap those fill-height editors in an outer scroll view.
- `lib/app/desktop_modal_window_config.dart` — `configureDesktopModalSubWindow()`: unified `WindowOptions` + `waitUntilReadyToShow` + `applyModalChildWindowChrome` + `setTitle` + `show` + `positionChildCenteredFromFrame` + `focus`. Replaces per-window `_configure*Window` functions.

#### Migrated windows

- `lib/app/account_editor_window_app.dart` — `DesktopModalSubWindowApp<RemoteStorageGateway>` with `scrollable: true` (overflow safety only when content exceeds screen clamp), `bootstrap` → `defaultRemoteStorageApiFactory()`, `contentBuilder` → `_AccountEditorContent` (save + Baidu OAuth). `onSaved` notifies parent then `close()`; `onCancel` calls `close()`. Content-fit resize lives in `CloudStorageAccountDialog` (`MeasureSize` + `fitModalSubWindowToContentSize`).
- `lib/widgets/measure_size.dart` — `MeasureSize` RenderObject reports child size changes (including descendant-only rebuilds such as proxy custom fields).
- `lib/services/desktop_sub_window_modal.dart` — `fitModalSubWindowToContentSize` converts measured body size + title bar (44) + content padding into a centered OS window size, clamped to fixed min/max only (never `FlutterView.physicalSize` — that is the child window in multi-window).
- `lib/app/sync_editor_window_app.dart` — `DesktopModalSubWindowApp<_SyncBootstrapResult>` with **`scrollable: false`** (editor owns step indicator + internal scroll + pinned nav via `Expanded`). `bootstrap` → load profiles + buckets; `contentBuilder` → `_SyncEditorContent`; `onSaved` → `close()`. Deleted: `_SyncEditorTitleBar`, `_closeSyncEditorWindow`, `SyncEditorWindowLifecycle`.
- `lib/app/remote_directory_picker_window_app.dart` — `DesktopModalSubWindowApp<RemoteStorageGateway>` with **`scrollable: false`**, `useParentFocusRelay: false`. `onConfirm` stashes result then `close()`; `onCancel` clears result then `close()`; title-bar X still runs shell `onClose` → `_sendResult` (null if no selection). Deleted: `_PickerTitleBar`, inline `_finish`, `_RemoteDirectoryPickerBody`.
- `lib/app/app_entry_io.dart` — All three modal windows now configured via `configureDesktopModalSubWindow()`. Deleted: `_configureSyncEditorWindow`, `_configureAccountEditorWindow`, `_configureRemoteDirectoryPickerWindow`. `_configurePreviewWindow` remains (non-modal, center:true, no chrome).

#### Initial window sizes (current)

- Account editor: `_accountEditorWindowSize` in `app_entry_io.dart` seeds only — new `640×360`; edit Baidu `640×480` / WebDAV `640×520` / S3 `640×560`, min `400×280`. Runtime size comes from content measure. In-app dialog max width is **640**. Nested advanced modal max width **480**.
- Sync editor: fixed initial `600×480` in `app_entry_io.dart`; step sizes `600×480` / `600×500` / `600×480`. In-app dialog max width is **640**. Three steps: endpoints, strategy, advanced.
- Remote directory picker: fixed `640×560` (min `480×400`); in-app dialog max width **640** / body height **480**; dialog fills height with `Expanded` list (`scrollable: false` shell).


#### Not migrated

- `FilePreviewWindowApp` — non-modal standalone window (no scrim, no overlay release, draggable title bar). Mode is fundamentally different; stays independent.

#### Open-path routing (policy 2026-07-11)

| Flow | Default (release / normal debug) | Debug OS sub-window |
|------|----------------------------------|---------------------|
| Account editor | `CloudStoragePage` → `showAppModal` + `CloudStorageAccountDialog(asDialog: true)` | Only when `preferModalSubWindows` → `AccountEditorWindowService.openEditor` |
| Sync editor | `file_sync_tasks_page_actions` → `showAppModal` + `FileSyncProfileEditor(asDialog: true)` | Only when `preferModalSubWindows` → `SyncEditorWindowService.openEditor` |
| Remote directory picker | `showRemoteDirectoryPicker` → in-app modal via `showDesktopOverlayOrDialog` → `showAppModal` | Only when `preferModalSubWindows` → `RemoteDirectoryPickerWindowService.openPicker` |
| Other dialogs | Always `showAppModal` / `showAppConfirmModal` | No sub-window |
| File preview | Independent non-modal window (unchanged) | Unchanged |

**Debug gate:** `lib/services/modal_sub_window_debug.dart` — `preferModalSubWindows = kDebugMode && bool.fromEnvironment('USE_MODAL_SUB_WINDOWS', defaultValue: false)`. Enable with `--dart-define=USE_MODAL_SUB_WINDOWS=true` in a debug build. Desktop window services set `isSupported => preferModalSubWindows` (web remains false). Never open multi-window modals just to look more “native” for users.

Near-500 dual-mode content widgets: `cloud_storage_account_dialog.dart` (~471), `file_sync_profile_editor.dart` (~480), `remote_directory_picker_dialog.dart` (~446). Shell/services are well under 500 except `desktop_sub_window_modal.dart` (~355).

#### Gotchas

- Never set `scrollable: true` for content that uses `Expanded`, `height: double.infinity`, or an internal scroll region (`FileSyncProfileEditor._buildSubWindowLayout`, `RemoteDirectoryPickerDialog`). The outer `SingleChildScrollView` makes height unbounded and crashes with `RenderFlex children have non-zero flex but incoming height constraints are unbounded`.
- Content must call the injected `close` from save/cancel/confirm paths. Title-bar X already calls shell `onClose` → `closeDesktopModalSubWindow`; empty `onCancel` / `onSaved` callbacks leave the window open after the migration.
- Do not nest `ShadDialog` in modal sub-windows (`asDialog: false`). File preview is not this shell — leave it alone.
- Account editor uses **content-measured** resize (`MeasureSize` + `fitModalSubWindowToContentSize`), not hand-tuned per-step heights. Only shrink-wrapped (`MainAxisSize.min`) form content may use it. Sync editor / directory picker keep discrete or fill-height layouts and must not call content-fit.
- Content-fit must add shell chrome: title bar 44px + content padding `LTRB(24,16,24,24)` (+ small height fudge). Measuring only the form body and applying that as the OS window size leaves chrome cut off or reintroduces scroll/whitespace.
- `MeasureSize` must report the **child's unconstrained height** (layout with `maxHeight: infinity`), not the short size forced by the parent `Expanded`/seed window. Reporting the clamped parent size under-measures and clips the button row.
- After content-fit resize, re-center with `positionChildCenteredFromFrame` using the creator frame from window args. Do not only call `resizeKeepingWindowCenter` on first show — the child may still be at a default OS origin and will jump/off-center.
- Never clamp content-fit with `FlutterView.physicalSize` / `platformDispatcher.views.first` inside a multi-window child engine — that reports the **current sub-window**, so `max = size * 0.9` shrinks the dialog on every next/back. Use fixed `maxSize` (or a real monitor API from the main process), never the child view size.

### Feature: Responsive Page Header Actions (页面头部响应式操作区)

All list-style pages (任务队列 / 分享管理 / 回收站 / 文件同步 / 账号管理) share the same header pattern: a left `Flexible(Column(title + subtitle))` and right-side action buttons. When many buttons are visible (e.g. bulk-selection mode), the title column was squeezed and the subtitle wrapped mid-sentence. A shared `PageHeaderActions` widget now collapses secondary actions into a `…` overflow menu (`ShadContextMenu`) when the available width drops below a threshold.

#### Key files

- `lib/widgets/page_header_actions.dart` — `PageHeaderActions` (StatelessWidget): takes `primary` (always laid out) and `secondary` (`List<SecondaryAction>`). Uses `LayoutBuilder` to compare `constraints.maxWidth` against `overflowThreshold` (default 520). When wide, renders all primary + secondary `.builder()` inline; when narrow, renders primary + an `_OverflowMenuButton` whose `ShadContextMenu` items come from `secondary` `.label` / `.onPressed`. `_OverflowMenuButton` mirrors the existing `_BucketOverflowMenuButton` pattern (`ShadContextMenuController` + `DesktopContextMenuRegistry` group `_pageHeaderOverflowGroup` + `ShadGlobalAnchor`). `SecondaryAction` carries `label`, `builder`, `onPressed`, `enabled`.
- `lib/widgets/transfer_task_widgets.dart` — `TransferTaskSelectionActions` now wraps `PageHeaderActions`. Primary: 已选 N 项 badge + 批量开始 + 批量取消. Secondary: 移除记录 / 清空选择 / 清空已完成 (new `onClearFinished` + `finishedCount` params moved from the page-level standalone button).
- `lib/pages/transfers_page.dart` — header `Row` simplified: `Flexible` title column + single `TransferTaskSelectionActions` (no separate 清空已完成 button). Subtitle gained `maxLines: 2`.
- `lib/pages/share_management_page.dart` — header rebuilt via `PageHeaderActions`. Selected: primary 已选 N 项 + 删除选中; secondary 取消选择. Unselected: primary 刷新.
- `lib/widgets/global_trash_controls.dart` — `GlobalTrashHeaderActions` now wraps `PageHeaderActions`. Selected: primary badge + 批量恢复 + 批量彻底删除; secondary 清空选择. Unselected: primary 刷新; secondary 清空回收站.
- `lib/pages/global_trash_page_view.dart`, `lib/pages/file_sync_tasks_page.dart`, `lib/pages/cloud_storage_page.dart` — title column switched `Expanded` → `Flexible(fit: FlexFit.tight)`; subtitle gained `maxLines: 2, overflow: ellipsis` as a hard floor.

#### Gotchas

- The title column must be `Flexible(flex: 1, fit: FlexFit.tight)`, not `Expanded`, so the right-side `PageHeaderActions` `Wrap` is measured by `LayoutBuilder` against the real remaining width; with `Expanded` the title took all space and the actions never saw a width constraint.
- `_OverflowMenuButton` must be a `StatefulWidget` owning the `ShadContextMenuController` and `_menuAnchorOffset`; the `onPressed` of `ShadButton.outline` computes the anchor via the button's `GlobalKey` + `localToGlobal` before `_controller.show()`.
- Single-button headers (文件同步 新建配置, 账号管理 新增账号) intentionally do NOT use `PageHeaderActions` — they can't overflow, but the `Flexible` title column + subtitle `maxLines` floor still applies for consistency.


### Feature: Per-Account Proxy (账号独立代理)

Each storage account can choose its own outbound proxy policy. The default is `inherit` (跟随全局); explicit alternatives are `system`, `direct` (no proxy), or `custom` HTTP/SOCKS5 with optional authentication. The global proxy is persisted independently in the bbolt `meta` bucket and acts only as the fallback for inheriting accounts.

#### Key files

- `go/config/config.go` — Defines `ProxyModeInherit` and normalizes all four account modes. New account configs default to `inherit`.
- `go/config/global_proxy.go` — Persists the global proxy subset under bbolt `meta/global_proxy` via `LoadGlobalProxy` / `SaveGlobalProxy`. Global mode cannot itself be `inherit`; it normalizes that value to `system`.
- `go/config/proxy.go` — `ResolveProxyConfig(account, global)` copies global proxy fields only when the account mode is `inherit`; explicit system/direct/custom accounts are untouched.
- `go/storage/types.go` — `ForConfig` loads the global proxy, resolves inheritance, then constructs S3/WebDAV/Baidu backends from the effective config.
- `go/storage/baidu_pan_sdk.go` / `baidu_pan_retry_http.go` — Builds a per-account xpan HTTP client carrying both the effective proxy transport and per-account OAuth credentials. The global xpan client remains only as a fallback for legacy code paths.
- `bridge/dispatch_config.go` — `update_proxy_settings` writes only the independent global proxy record; it no longer overwrites every profile. Bootstrap returns global proxy fields to the Settings page.
- `lib/widgets/account_proxy_section.dart` — Account-editor proxy UI: 跟随全局 / 跟随系统 / 直连 / 自定义; custom expands HTTP/SOCKS5 host/port/auth fields.
- `lib/widgets/cloud_storage_account_dialog.dart` — Embeds `AccountProxySection` for S3/WebDAV/Baidu accounts and submits proxy values with the account draft.
- `lib/models/cloud_storage_account_draft.dart` / `lib/utils/account_config_builder.dart` / `lib/models/remote_storage_config.dart` — Carries and serializes per-account proxy values; new accounts default to `inherit`.
- `lib/widgets/settings_proxy_section.dart` — Global proxy UI; copy explains that accounts may override it.
- `github.com/lfhy/xpan v0.2.0` (local repo `../xpan`) — Adds per-call HTTP clients and per-`Client` credentials so concurrent Baidu accounts no longer race on global tokens. The SDK work is split into commits `6b64c93` (per-call client) and `4ab8c36` (multi-account credentials), tagged `v0.2.0`.

#### Data flow

1. Settings global proxy -> `update_proxy_settings` -> `config.SaveGlobalProxy` (`meta/global_proxy`).
2. Account editor saves `proxyMode` plus custom fields in that profile.
3. Storage operation -> `storage.ForConfig` -> `LoadGlobalProxy` -> `ResolveProxyConfig`.
4. Explicit account modes use their own transport; `inherit` accounts receive the global proxy fields.
5. Baidu operations create `xpanclient.NewWithClient` with a retry client that exposes the account credentials and uses the resolved proxy transport.

#### Gotchas

- Do not reintroduce the old behavior where `updateProxySettings` loops over profiles; that destroys per-account overrides.
- `direct` is a valid per-account override and means no proxy even when the global proxy is custom.
- The temporary local `replace github.com/lfhy/xpan => ../xpan` is only for validation before v0.2.0 is pushed. Remove it after the tag is published and run `go mod tidy`.

### Feature: Object Delete / App Trash (软删除与回收站)

Deleting an object from the file manager is a soft delete by default for S3 accounts: the object tree is moved (CopyObject per entry + DeleteObject per source) into a bucket-level trash prefix, then metadata is persisted. That is why a UI "delete" can surface S3 CopyObject errors.

#### Key files

- `lib/pages/file_manager_page_actions.dart` (`_runObjectAction`, delete branch) and `lib/pages/file_manager_page_selection.dart` (`_deleteSelectedObjects`) — confirm via `showDeleteObjectDialog` / `showDeleteObjectsDialog` (`lib/widgets/object_action_dialogs.dart`; both take `trashEnabled:` and return `Future<DeleteDialogChoice>` (`confirmed` + `permanent`), dismiss → confirmed:false). Dialog body is the shared `DeleteDialogBody` StatefulWidget: target label + `ShadSwitch` 永久删除 (only when `trashEnabled`, sublabel 不移入回收站，删除后无法恢复) + cancel/destructive actions; description switches between 移入回收站 and 此操作不可撤销 based on trash state. Then `_queueObjectDeletes(permanent:)` + `_showDeleteProgressDialogForTasks` (`lib/pages/file_manager_page_upload_feedback.dart:16` → `BatchTaskProgressDialog` with `BatchTaskProgressMode.delete`).
- `lib/pages/file_manager_page_object_deletes.dart` — `_queueObjectDeletes` (:8, `permanent` named param) starts `TransferKind.delete` tasks (`localPath: ''`) and runs `_runDeleteTask` (:73) -> `api.deleteObject(config, bucket, key, isDir, taskId, permanent: permanent)` + cache evict + `markTaskDone/markTaskFailed`; failures are collected and surfaced via `_showPageMessage(title: '删除失败', ...)` (raw `error.toString()`, which keeps the `RemoteStorageBridgeException:` prefix).
- `lib/services/remote_storage_api_desktop_storage.dart:69` / `lib/services/remote_storage_api_web_objects.dart:61` — gateway `deleteObject` -> bridge op `delete_object` with `{config, bucket, key, isDirectory, taskId, permanent}`. Gateway interface `lib/services/remote_storage_gateway.dart:135` declares `permanent = false` named param (test fakes must match).
- `bridge/dispatch.go:66` (`delete_object` case) and `:293` (handler) — `objectMutationArgs` carries `permanent`; handler picks `backend.DeleteObjectHard` when permanent, else `backend.DeleteObject` (trash-routed); on success calls `bucketmount.NotifyExternalDelete`. Web path: `go/webapi/invoke.go:222` (same permanent routing on `invokeEnvelope.Permanent`). Trash ops: `bridge/dispatch.go:68-77` + `bridge/dispatch_trash.go` (`list_trash`, `list_trash_page` in `bridge/dispatch_paging.go`, `restore_trash_item`, `delete_trash_item`, `clear_trash`).
- `go/storage/s3_backend.go:66` — `DeleteObject` routes by per-bucket trash flag: trash disabled -> `s3ops.DeleteObjectHardContextWithTask`; trash enabled -> `s3ops.DeleteObjectContextWithTask` (soft delete). `s3Backend.DeleteObjectHard` (:82) is reachable from the file manager via the `permanent` flag, and from the mount delete queue. `go/config/config.go:397` `BucketSettingsFor` defaults `TrashEnabled=true` for `StorageTypeS3`, overridable per bucket (`bucketSettings[bucket].trashEnabled`, `trashDirectory`); Dart mirror `lib/models/remote_storage_config.dart:418` + `lib/models/bucket_settings.dart`.
- `go/s3/object_mutations.go` — soft `DeleteObjectContext(WithTask)` (:30, `startTransfer(taskID,"delete",…,0,cancel)` :46) delegates to `MoveObjectToTrashContextWithTask` (`go/s3/trash_ops.go:39`, passes taskID through). Hard path: `DeleteObjectHardContextProgress` lists via `mutationEntriesWithProgress` (reports TotalItems up front) then `deleteEntriesHardWithTask` (per-key resilient delete + `AdvanceTransferItems` per key); `DeleteObjectHardContextWithTask` (:110) registers the task and forwards taskID so hard deletes show a determinate item bar. `DeleteObjectHardContext` keeps the zero-progress path for internal callers.
- `go/s3/trash_ops.go` + `go/s3/trash_helpers.go` + `go/s3/trash_index.go` — `MoveObjectToTrashContext(WithTask)`: trims key, skips trash keys, `mutationKeys` (count), generates UUID, target = `<trashDir>/objects/<uuid>/<originalKey>` (trashDir default `.trash`, config `trashDirectoryName`), calls `MoveObjectContextWithTask` (copy + delete-source, taskID forwarded), then `buildTrashMetadata` + `persistTrashMetadata` (index objects under `.trash/index/`; legacy `.trash/entries/<id>.trashinfo.json` fallback). Retention purge: `go/s3/trash_purge_scheduler.go` (10 min cooldown, `trashRetentionDays`, default 30 / -1 disables).
- `go/s3/object_moves.go:79` `MoveObjectContextWithTask` — when taskID set, pre-reports TotalItems via `mutationEntriesWithProgress` (single enumeration reused by `buildObjectTransferPlan`), then `executeObjectCopyPlan` (`object_transfer_run.go:51`: per-entry resilient CopyObject, placeholders become PutObject markers, `advanceTransferTaskProgress` bumps bytes + items per entry) and finally `deleteObjectKeysHardWithTask` on `plan.deleteKeys` (items keep advancing past copy total, so a trash-move bar runs to 200% of copy items = 100% overall). This copy phase is the CopyObject that appears in delete error messages. Byte progress still flows via `beginObjectTransferTask` (`startTransfer(…,plan.totalBytes,cancel)`). `plan.deleteKeys` is captured at plan build time (`object_transfer_plan.go` + `transferEntryKeys` in `object_entries.go`); the cleanup must NOT re-list the source prefix, because a re-list can observe keys already deleted mid-sweep and silently skip them, leaving stale source objects behind (this was the "移动后旧文件没删掉" bug).
- `go/s3/object_transfer_progress.go` — `sumTransferEntrySizes` (byte totals) + `advanceTransferTaskProgress` (bytes + item per finished entry). `go/s3/object_delete_progress.go` — `deleteObjectKeysHardWithTask` / `deleteEntriesHardWithTask` (per-item delete progress). `go/s3/object_entries.go` `mutationEntriesWithProgress` — enumerates a prefix and reports TotalItems immediately. `go/s3/transfer_phases.go` + `PlanTransferPhaseItems`/`resetTransferPhaseItems`/`PlannedTransferItems` in `go/s3/transfer_monitor.go` — phase-aware item accounting so copy and delete phases of one sweep never double-count or overshoot. Item fields surface in Flutter via `TransferSnapshot.totalItems/itemsCompleted` → `TransferTask` → `BatchTaskProgressDialog` (determinate summary bar when `totalItems > 0`, `x / y 个对象` chips + per-row subtitle with `正在删除源对象` during the cleanup phase; transfers page `_subtitleFor` shows the same counts). Tests: `go/s3/transfer_phase_plan_test.go`.
- Flutter trash flag: `lib/models/remote_storage_config.dart` `bucketSettingsFor` (:416, `defaultTrashEnabled = storageType == StorageType.s3` :418) / `bucketTrashEnabled` (:429); `lib/models/bucket_settings.dart` `BucketSettings.isTrashEnabled` (:48). File manager: `lib/pages/file_manager_page_bucket_policy.dart` `_bucketTrashEnabled` (:14) + `_activeBucketTrashEnabled` (:20) — feeds the delete dialogs' switch visibility. Edit UI: `lib/widgets/bucket_settings_dialog.dart` (ShadSwitch inside ShadDialog via StatefulBuilder :24-63); the delete dialogs use the `DeleteDialogBody` StatefulWidget variant.
- `go/s3/client.go` — single `s3.New(opts)` client: static creds, `Region`, `BaseEndpoint=cfg.Endpoint`, `UsePathStyle`, proxy override only for direct/custom. Global client keeps the AWS SDK v2 default retry (3 attempts); sweep call sites opt into a bigger per-call budget.
- `go/s3/aws_retry.go` + `go/s3/object_copy_retry.go` — per-call retry layer for single-object sweep calls (CopyObject, HeadObject, DeleteObject, placeholder PutObject). `singleObjectCallOptions()` attaches a standard retryer with 5 attempts / 15s max backoff to individual API calls (not the client); on top of that, `runSingleObjectSweep` re-issues calls that fail with vendor-flaky non-retryable errors (`isSweepWorthyError`: InvalidArgument/InvalidRequest codes, non-retryable 5xx-ish codes, transport errors) up to 3 extra times with a 2s delay (test-shrunk via `singleObjectSweepRetryDelay`). Delete sweeps route through `go/s3/object_delete_sweep.go` `deleteObjectKeysHard`; copy sweeps through `copyObjectResilient`/`putDirectoryPlaceholderResilient` in `object_transfer_run.go`; plan sizing through `headObjectResilient` in `object_transfer_plan.go`. Tests: `object_copy_retry_test.go`.

#### Gotchas

- Soft-delete moves one object at a time; for a directory the whole tree is copied to trash before any source delete, so deleting large directories is N CopyObject + N DeleteObject calls and fails entirely if one copy fails. Per-call retries (`aws_retry.go` / `object_copy_retry.go`) absorb transient gateway errors (502 HTML pages, connection resets, vendor InvalidArgument glitches), but a persistent outage still aborts the whole delete with the raw SDK error shown in 删除失败 dialogs.
- The 永久删除 dialog switch only appears when the bucket has trash enabled; it is enforced bridge-side (`permanent` → `DeleteObjectHard`), so the Dart flag is advisory, not authoritative. Buckets with trash disabled never show the switch (their deletes are already permanent).
- Delete task progress is item-based (TotalItems/AdvanceTransferItems), not byte-based: the summary bar in `BatchTaskProgressDialog` prefers `totalItems > 0` over bytes. Item accounting is phase-aware (`PlanTransferPhaseItems` in `go/s3/transfer_monitor.go`, phases in `go/s3/transfer_phases.go`): a trash move plans a "delete" phase from the source listing (worst case) and a "copy" phase from the target-tree enumeration; identical re-enumerations replace rather than double-count. Between copy and source cleanup, `MoveObjectContextWithTask` calls `resetTransferPhaseItems` + `SetTransferStatusDetail(taskID,"deleting")` so the bar restarts at 0/N for the deletion phase. `finishTransfer` settles ItemsCompleted=TotalItems so completed tasks never show overshoot like 206/103.
- `RestoreTrashItem` copies back from trash key to original key; `DeleteTrashItem`/`ClearTrash` hard-delete trash payloads (`trash_ops.go:344+`).
- File manager page has no persistent inline transfer tray: delete feedback is the modal `BatchTaskProgressDialog` only; in-row feedback is `deletingKeys` (`_deletingObjectKeys`, `file_manager_page.dart:130` → passed as `deletingKeys` :461 to `FileManagerObjectBrowser`); finished/failed status afterwards lives only on the Transfers page (`lib/pages/transfers_page.dart`).
- Mount delete queue (`go/mount/delete_queue.go`) also calls backend `DeleteObject`/`DeleteObjectHard` and treats `CopyObject`+`InvalidArgument` errors as non-retryable.
- Trash UI: file-manager header trash icon (`lib/widgets/file_manager_action_bar.dart:153-176`, gated by `_activeBucketTrashEnabled`), per-bucket trash browser `lib/widgets/file_manager_trash_browser.dart`, global page `lib/pages/global_trash_page.dart` + `lib/widgets/global_trash_browser.dart`, settings section `lib/widgets/settings_trash_section.dart`, sidebar entry `lib/pages/main_layout_page.dart:197`.

### Feature: Windows Cloud Files Remote Deletion Projection

`NotifyExternalDelete` now synchronizes both the Go-side `bucketCache` and the physical Windows Cloud Files sync root. `bucketAccess.MarkExternalDelete` cancels pending writeback before applying the tombstone, then invokes the Windows backend projection installed while the Cloud Files session is active. The projection removes the local file/directory under `Cloud Volume\\<bucket>` and records a short-lived provider-delete marker so both fsnotify and `NOTIFY_DELETE_COMPLETION` treat the removal as provider-owned instead of scheduling a duplicate remote delete.

`InvalidateExternalUpload` uses the matching upload projector for app-side directory creation, uploads, copies, and move/rename destinations. It refreshes remote metadata, recreates an overwritten placeholder when needed, and only creates a child when its parent directory is already present in the sync root; otherwise the next Cloud Files placeholder fetch creates the missing tree.

Relevant files and flow: `go/mount/bucket_access.go` owns the session-scoped `externalDelete`/`externalUpload` projectors; `go/mount/bucket_access_reads.go` cancels pending writeback and invokes them from external mutation invalidation; `go/mount/backend_windows_cloud_files_cgo.go` installs/clears the projectors and consumes provider-delete callback markers; `go/mount/cloud_files_external_delete_windows.go` validates paths, removes placeholders, reads remote metadata, and creates new/overwritten placeholders; `go/mount/cloud_files_watcher_state_windows.go` owns provider-delete and ordinary watcher state. Watcher lifecycle tests are split between `cloud_files_watcher_windows_test.go` and `cloud_files_watcher_lifecycle_windows_test.go` to keep both files below 500 lines. File-list delete is `delete_object` -> remote soft delete -> cancel writeback -> cache tombstone -> local placeholder removal. Directory create/upload/copy/move are `NotifyExternalUpload` or `NotifyExternalRename` -> cache invalidation -> remote metadata lookup -> local placeholder creation. Explorer delete remains CFAPI delete completion -> `handleDelete` -> `deletePath` -> async remote delete.

### Feature: Windows WinFsp Virtual File System Engine

Windows mounts can now choose between the Cloud Files shell (default) and a WinFsp-backed virtual file system that reports a real volume with a user-configured capacity to Explorer. The WinFsp engine compiles into every Windows CGO build of the bridge (no build tag); `third_party/winfsp/inc/fuse` headers are vendored in the repo and pointed at via `CPATH` by `run_windows.ps1`, `build_desktop_packages.sh`, `windows/CMakeLists.txt`, and the `Makefile` `bridge-windows` target. Only the non-CGO (`CGO_ENABLED=0`) path uses the stub and reports the engine unavailable.

#### Key files

- `go/mount/backend_windows.go` — `newPlatformMountBackend` now branches on `cfg.WindowsMountEngine`: `winfsp` -> `newWindowsWinFspBackend`, otherwise the existing Cloud Files / WebDAV mode switch. `cleanupAllManagedMounts` also calls `cleanupManagedWindowsWinFspArtifacts`.
- `go/mount/backend_windows_winfsp_cgo.go` — `windowsWinFspBackend` (`//go:build windows && cgo`). `Initialize` prefers mounting straight onto the requested drive letter; otherwise falls back to `~/Cloud Volume/<bucket>-winfsp`. `Start` resolves bucket custom quota before the global WinFsp capacity, builds a `winFspBucketFS`, runs `fuse.FileSystemHost.Mount` on a goroutine, polls `IsActive` until ready, and reports volume label `Cloud Volume <bucket>` via `-o volname=...`. `Stop` unmounts once (`stopHost`), waits for the serving goroutine, drains writeback, and releases the bucket access.
- `go/mount/backend_windows_winfsp_stub.go` — `//go:build windows && !cgo`. Reports a clear unavailable error for the pure-Go build; also defines `cleanupManagedWindowsWinFspArtifacts` as a no-op for that path. (The `windows && cgo && !winfsp` stub was removed once the `winfsp` build tag was dropped.)
- `go/mount/winfsp_fs_windows.go` + `go/mount/winfsp_fs_helpers_windows.go` — cgofuse `FileSystemInterface` over `bucketAccess` (`//go:build windows && cgo`; Getattr/Readdir/Open/Create/Read/Write/Truncate/Flush/Release/Mkdir/Unlink/Rmdir/Rename/Statfs). Reads/writes reuse the cache + writeback queue. `Statfs` reports the resolved bucket-first capacity as total/free blocks so Explorer shows the configured value. Helper file holds Stat/error mapping to keep both files under 500 lines.
- `go/mount/windows_winfsp_probe_windows.go` — `WindowsWinFspAvailable()` mirrors cgofuse's DLL discovery (`winfsp-x64.dll`/`winfsp-a64.dll` then `HKLM\Software\WinFsp\InstallDir`). Also hosts `hasWinFspMountSuffix`/`isWindowsDriveMount` so tests and cleanup work without the `winfsp` tag.
- `go/mount/windows_winfsp_embedded_windows.go` — `//go:embed embedded/winfsp.msi` ships the ~2.1 MB WinFsp installer inside the bridge.
- `go/mount/windows_winfsp_install_windows.go` — `InstallWindowsWinFsp` prefers the side-by-side `{app}\winfsp\winfsp.msi` (shipped by the installer), otherwise writes the embedded MSI to temp, then elevates `msiexec /i ... /qn /norestart` via PowerShell `Start-Process -Verb RunAs -Wait` and re-probes availability.
- `go/mount/winfsp_backend_windows_test.go` / `go/mount/winfsp_statfs_windows_test.go` — unit tests for path classification and Explorer-facing Statfs blocks (no mounted driver needed).
- `bridge/dispatch_mount.go` / `bridge/dispatch.go` — bridge methods `list_windows_winfsp_available` and `install_windows_winfsp`.
- `lib/services/remote_storage_gateway.dart` — `WindowsWinFspQuery` interface (`listWindowsWinFspAvailable` + `installWindowsWinFsp`).
- `lib/services/remote_storage_api_desktop_storage.dart` — desktop bridge implementation of `WindowsWinFspQuery`.
- `lib/widgets/windows_settings_sections.dart` — `WindowsMountEngineSection`: engine dropdown (WinFsp option hidden when driver missing), inline note + "安装 WinFsp" button when absent, capacity input shown only for WinFsp.
- `lib/pages/settings_page.dart` / `settings_page_actions.dart` / `settings_page_sections.dart` — `_winFspAvailable` / `_installingWindowsWinFsp` state, `_refreshWindowsWinFspAvailability` probe on dependency change, `_installWindowsWinFsp` action.
- `lib/pages/file_manager_page_mount.dart` — before showing the mount dialog for a WinFsp-engine bucket, probes availability and offers the in-app install confirmation modal when missing.
- `scripts/run_windows.ps1` — sets `CPATH=third_party/winfsp/inc/fuse` before the bridge build; the WinFsp engine compiles in by default (no `-tags`), and the script fails fast if the vendored headers are missing.
- `scripts/build_desktop_packages.sh` — `build_windows` exports `CPATH` at the vendored header dir and fails if `fuse_common.h` is absent, so CI and local release builds compile the WinFsp engine the same way.
- `windows/CMakeLists.txt` — the `remote_storage_bridge` custom target passes `CPATH=<repo>/third_party/winfsp/inc/fuse` to the `go build` env so a bare `flutter build windows` (without `run_windows.ps1`) also gets the WinFsp engine.
- `Makefile` — `bridge-windows` passes `CPATH=<repo>/third_party/winfsp/inc/fuse` to `go build`.
- `scripts/setup_windows_dev.ps1` — `Ensure-WinFsp` installs WinFsp from the bundled MSI (or winget) for new dev machines.
- `scripts/windows_installer.iss` / `scripts/build_windows_installer.ps1` — Inno Setup now ships `winfsp.msi` to `{app}\winfsp` and adds an optional "Install WinFsp" task that runs `msiexec /qn` during setup.
- `third_party/winfsp/inc/{fuse,fuse3,winfsp}` — WinFsp 2.1 headers extracted from the MSI and committed so every Windows bridge build (local + CI) can compile cgofuse without a system WinFsp install.
- `go/mount/embedded/winfsp.msi` — WinFsp 2.1.25156 installer payload embedded via `go:embed` and reused by the installer.

#### Gotchas

- The WinFsp engine is compiled into every Windows CGO bridge build (no `winfsp` build tag). Only the pure-Go (`CGO_ENABLED=0`) path hits the stub and reports the engine unavailable, which also cannot host Cloud Files. The UI hides the WinFsp option at runtime when `WindowsWinFspAvailable()` reports the driver DLL is not installed.
- cgofuse's cgo variant (`host_cgo.go`) requires the WinFsp fuse headers via `CPATH` (it hard-codes `-I/usr/local/include/winfsp` which only works under xgo/docker). Missing headers fail the bridge build with `fatal error: 'fuse_common.h' file not found`; the build scripts therefore fail fast instead of silently building a bridge without the WinFsp engine.
- WinFsp is a user-mode driver, not a kernel one; the embedded MSI is per-machine and needs a UAC elevation. `InstallWindowsWinFsp` surfaces elevation cancellation (exit 1223) as an error so the UI can fall back gracefully.
- WinFsp reports capacity from `Statfs.Blocks * Frsize`; bucket `CustomQuotaBytes` overrides global `windowsWinFspCapacityGB` when nonzero. `winFspBlockBytes` is fixed at 4096 and `Bfree`/`Bavail` mirror total blocks because remote used space is unknown. Capacity is snapshotted at mount start, so settings changes require remounting.
- Drive-letter WinFsp mounts (`Z:`) are owned by WinFsp itself; `Stop` must not call `subst /D` on them (it would fail). `isWindowsDriveMount` distinguishes these from Cloud Files `subst` mappings.

**Shutdown lifecycle fix (2026-07-15):** Normal confirmed exit and tray-menu Exit both route through Flutter before native destruction. `AppBootstrapPage` registers the active gateway with `AppExitCleanup`; `DesktopWindowControls` first calls native `hideForExit` (hide window and remove tray icon), then awaits background `cleanupMounts`, then calls `exitApp`; tray Exit emits `requestExit` and reuses that handler. Go `CleanupMounts` stops every session, and the Windows Cloud Files backend performs `Disconnect` -> watcher close -> `Deregister`. Hide-to-tray/minimize deliberately keep mounts active. Forced process termination still relies on next-start stale cleanup because no in-process callback can run after a kill/crash.

**Shell refresh gotcha:** `windows_shell_namespace_windows.go` must call `notifyExplorerShellChanged` only when a managed This PC namespace key was actually added or removed. Broadcasting `SHCNE_ASSOCCHANGED | SHCNF_FLUSH` on every cleanup, including when no namespace entry exists, causes an unnecessary whole-desktop/Explorer refresh during exit.

**Mounted-exit warning:** `DesktopWindowControls` always shows the close choice dialog, even with zero active mounts, so users can minimize/hide to tray instead of exiting. It calls `AppExitCleanup.activeMountCount`; any live mount changes the copy to explain that Exit unmounts active roots and that "后台运行" preserves them. On Windows the keep-alive action hides to tray; on Linux it minimizes while keeping the process and mounts alive.

**Close dialog layout:** The action row must span the available dialog width (`double.infinity`) before using `MainAxisAlignment.end`; a fixed narrow width centers the buttons inside a wide warning dialog instead of placing them at the lower right.
