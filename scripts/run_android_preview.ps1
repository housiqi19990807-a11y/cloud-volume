# Runs the existing Flutter UI with in-memory data on a narrow Android device.
param(
  [string]$FlutterPath = 'D:\toolchains\flutter\bin\flutter.bat',
  [string]$Device
)

$ErrorActionPreference = 'Stop'
$env:ANDROID_SDK_ROOT = 'D:\android-sdk'
$env:ANDROID_HOME = $env:ANDROID_SDK_ROOT
$env:JAVA_HOME = 'D:\toolchains\jdk-17.0.20.8-hotspot'
$env:PUB_CACHE = 'D:\flutter-cache\Pub\Cache'
$env:GRADLE_USER_HOME = 'D:\flutter-cache\gradle'

if (-not (Test-Path -LiteralPath $FlutterPath -PathType Leaf)) {
  throw "Flutter not found at $FlutterPath"
}

& $FlutterPath pub get
if ($LASTEXITCODE -ne 0) { throw 'flutter pub get failed.' }

$target = if ($Device) { $Device } else { 'android' }
& $FlutterPath run -d $target -t lib/main_android_preview.dart --dart-define=UI_PREVIEW=true
exit $LASTEXITCODE
