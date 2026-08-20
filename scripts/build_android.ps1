# Builds the Android ARM64 release APK after packaging the Go FFI bridge.
param(
  [string]$FlutterRoot = $(if ($env:FLUTTER_ROOT) { $env:FLUTTER_ROOT } else { Join-Path $HOME 'dev\flutter' }),
  [switch]$Debug
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$flutter = Join-Path $FlutterRoot 'bin\flutter.bat'
if (-not (Test-Path -LiteralPath $flutter)) {
  throw "Flutter was not found: $flutter"
}

& (Join-Path $PSScriptRoot 'build_android_bridge.ps1')
if ($LASTEXITCODE -ne 0) {
  throw "Android bridge build failed with exit code $LASTEXITCODE."
}

Push-Location $repoRoot
try {
  $mode = if ($Debug) { 'debug' } else { 'release' }
  & $flutter build apk "--$mode" --target-platform android-arm64 --dart-define=APP_VERSION_LABEL=dev
  if ($LASTEXITCODE -ne 0) {
    throw "Android APK build failed with exit code $LASTEXITCODE."
  }
} finally {
  Pop-Location
}

$apk = Join-Path $repoRoot $(if ($Debug) { 'build\app\outputs\flutter-apk\app-debug.apk' } else { 'build\app\outputs\flutter-apk\app-release.apk' })
if (-not (Test-Path -LiteralPath $apk)) {
  throw "Android APK was not produced: $apk"
}
Write-Host "Built Android APK: $apk" -ForegroundColor Green
