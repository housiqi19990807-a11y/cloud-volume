# Build a Windows installer (.exe) from the Flutter release bundle using Inno Setup.
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File .\scripts\build_windows_installer.ps1
#   powershell -ExecutionPolicy Bypass -File .\scripts\build_windows_installer.ps1 -Version 1.2.3
#
# Requires Inno Setup 6 (install via scripts\setup_windows_dev.ps1 or from jrsoftware.org).
param(
  [string]$Version,
  [switch]$SkipBuild
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$releaseDir = Join-Path $repoRoot 'build\windows\x64\runner\Release'
$outputDir = Join-Path $repoRoot 'dist\release'
$issPath = Join-Path $repoRoot 'scripts\windows_installer.iss'

# Resolve ISCC.exe
$iscc = $null
foreach ($candidate in @(
  (Join-Path $env:ProgramFiles 'Inno Setup 6\ISCC.exe'),
  (Join-Path ${env:ProgramFiles(x86)} 'Inno Setup 6\ISCC.exe')
)) {
  if (Test-Path $candidate) { $iscc = $candidate; break }
}
if (-not $iscc) {
  throw 'Inno Setup 6 not found. Run scripts\setup_windows_dev.ps1 or install from https://jrsoftware.org/isdl.php'
}

if (-not (Test-Path $releaseDir)) {
  throw "Release directory not found: $releaseDir. Run scripts\build_windows.bat first."
}
if (-not (Test-Path "$releaseDir\cloud-volume.exe")) {
  throw "cloud-volume.exe not found in $releaseDir. Run scripts\build_windows.bat first."
}

# Resolve version label
if (-not $Version) {
  $Version = (& git -C $repoRoot describe --tags --always --dirty 2>$null)
  if (-not $Version) { $Version = '0.0.0' }
}
Write-Host "Building installer version: $Version"

# Ensure output dir exists
New-Item -ItemType Directory -Force -Path $outputDir | Out-Null

# Build the installer via ISCC.
# AppName/AppPublisher/AppInstallDirName are NOT passed as /D defines because
# PowerShell transmits arguments to external processes using the system ANSI
# code page (GBK), which corrupts Chinese characters. The .iss file has UTF-8
# BOM so ISCC reads its built-in Chinese defaults correctly.
$installerBase = "yunjuan-windows-amd64-installer"
Write-Host "Running Inno Setup compiler..."
& $iscc /Qp `
  "/DAppVersion=$Version" `
  "/DSourceDir=$releaseDir" `
  "/DOutputDir=$outputDir" `
  "/DOutputBaseFilename=$installerBase" `
  "/DArchitecturesAllowed=x64compatible" `
  "/DArchitecturesInstallIn64BitMode=x64compatible" `
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