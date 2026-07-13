# Build the Flutter Windows release bundle AND package it as an installer (.exe)
# using Inno Setup, all in one step.
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File .\scripts\build_windows_installer.ps1
#   powershell -ExecutionPolicy Bypass -File .\scripts\build_windows_installer.ps1 -Version 1.2.3
#
# Requires Inno Setup 6 and the CGO/Flutter toolchain
# (install both via scripts\setup_windows_dev.bat).
param(
  [string]$Version,
  [switch]$SkipBuild
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-NativeWindowsArchitecture {
  # Detect the OS architecture even when this PowerShell is emulated.
  $architecture = $env:PROCESSOR_ARCHITEW6432
  if (-not $architecture) { $architecture = $env:PROCESSOR_ARCHITECTURE }
  switch ($architecture.ToUpperInvariant()) {
    'AMD64' { return 'x64' }
    'ARM64' { return 'arm64' }
    default { throw "Unsupported Windows architecture: $architecture" }
  }
}

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$architecture = Get-NativeWindowsArchitecture
$releaseDir = Join-Path $repoRoot "build\windows\$architecture\runner\Release"
$outputDir = Join-Path $repoRoot 'dist\release'
$issPath = Join-Path $repoRoot 'scripts\windows_installer.iss'

# Step 1: Build the Flutter release bundle (unless -SkipBuild).
if (-not $SkipBuild) {
  Write-Host '=== Step 1: Building Flutter release bundle ===' -ForegroundColor Cyan
  $runScript = Join-Path $PSScriptRoot 'run_windows.ps1'
  $runArgs = @('-Build', '-SkipPubGet')
  if ($Version) { $runArgs += @('-Version', $Version) }
  & powershell -NoProfile -ExecutionPolicy Bypass -File $runScript @runArgs
  if ($LASTEXITCODE -ne 0) {
    throw "Flutter build failed with exit code $LASTEXITCODE."
  }
}

# Step 2: Verify the release bundle exists.
if (-not (Test-Path "$releaseDir\cloud-volume.exe")) {
  throw "cloud-volume.exe not found in $releaseDir. Run without -SkipBuild."
}

# Step 3: Resolve ISCC.exe.
$iscc = $null
foreach ($candidate in @(
  (Join-Path $env:ProgramFiles 'Inno Setup 6\ISCC.exe'),
  (Join-Path ${env:ProgramFiles(x86)} 'Inno Setup 6\ISCC.exe')
)) {
  if (Test-Path $candidate) { $iscc = $candidate; break }
}
if (-not $iscc) {
  throw 'Inno Setup 6 not found. Run scripts\setup_windows_dev.bat or install from https://jrsoftware.org/isdl.php'
}

# Step 4: Resolve version label.
if (-not $Version) {
  $Version = (& git -C $repoRoot describe --tags --always --dirty 2>$null)
  if (-not $Version) { $Version = '0.0.0' }
}
Write-Host "=== Step 2: Packaging installer version: $Version ===" -ForegroundColor Cyan

New-Item -ItemType Directory -Force -Path $outputDir | Out-Null

# Step 5: Run ISCC. AppName/AppPublisher use .iss UTF-8 BOM defaults (not passed
# here because PowerShell corrupts Chinese when transmitting args to ISCC).
$installerBase = "yunjuan-windows-$architecture-installer"
$innoArchitecture = if ($architecture -eq 'arm64') { 'arm64' } else { 'x64compatible' }
& $iscc /Qp `
  "/DAppVersion=$Version" `
  "/DSourceDir=$releaseDir" `
  "/DOutputDir=$outputDir" `
  "/DOutputBaseFilename=$installerBase" `
  "/DArchitecturesAllowed=$innoArchitecture" `
  "/DArchitecturesInstallIn64BitMode=$innoArchitecture" `
  $issPath

if ($LASTEXITCODE -ne 0) {
  throw "Inno Setup compiler failed with exit code $LASTEXITCODE."
}

$installerPath = Join-Path $outputDir "$installerBase.exe"
if (Test-Path $installerPath) {
  $size = [math]::Round((Get-Item $installerPath).Length / 1MB, 1)
  Write-Host "Installer created: $installerPath ($size MB)" -ForegroundColor Green
  Start-Process explorer.exe -ArgumentList "/select,`"$installerPath`""
} else {
  throw "Installer file was not found at expected path: $installerPath"
}
