# Windows local startup helper: resolves a usable Flutter binary and MinGW
# toolchain, builds the Go bridge with CGO enabled, then launches Flutter.
param(
  [string]$FlutterPath,
  [string]$BridgeCc,
  [string]$BridgeCxx,
  [string]$Version,
  [switch]$Build,
  [switch]$SkipPubGet,
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$ExtraArgs
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

foreach ($arg in $ExtraArgs) {
  switch ($arg) {
    '--build' {
      $Build = $true
      continue
    }
    '--skip-pub-get' {
      $SkipPubGet = $true
      continue
    }
    default {
      throw "Unknown argument: $arg"
    }
  }
}

function Add-NoProxyEntry {
  param(
    [string]$CurrentValue,
    [string]$Entry
  )

  $items = @()
  if ($CurrentValue) {
    $items = $CurrentValue.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ }
  }
  if ($items -contains $Entry) {
    return ($items -join ',')
  }
  return (@($items) + $Entry) -join ','
}

function Resolve-Executable {
  param(
    [string]$Name,
    [string[]]$Candidates
  )

  if ($Name -and (Test-Path -LiteralPath $Name)) {
    return (Resolve-Path -LiteralPath $Name).Path
  }

  if ($Name) {
    $command = Get-Command $Name -ErrorAction SilentlyContinue
    if ($command) {
      return $command.Source
    }
  }

  foreach ($candidate in $Candidates) {
    if ($candidate -and (Test-Path -LiteralPath $candidate)) {
      return (Resolve-Path -LiteralPath $candidate).Path
    }
  }

  return $null
}

function Invoke-NativeCommand {
  param(
    [string]$Name,
    [scriptblock]$Command
  )

  & $Command
  if ($LASTEXITCODE -ne 0) {
    throw "$Name failed with exit code $LASTEXITCODE."
  }
}

function Test-IsAdministrator {
  $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
  $principal = [Security.Principal.WindowsPrincipal] $identity
  return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Ensure-WindowsSymlinkSupport {
  $path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock'
  $enabled = $false
  if (Test-Path -LiteralPath $path) {
    $value = (Get-ItemProperty -Path $path -Name AllowDevelopmentWithoutDevLicense -ErrorAction SilentlyContinue).AllowDevelopmentWithoutDevLicense
    $enabled = ($value -eq 1)
  }
  if ($enabled) {
    return
  }

  if (Test-IsAdministrator) {
    Write-Host 'Enabling Windows Developer Mode symlink support for Flutter plugins...'
    New-Item -Path $path -Force | Out-Null
    New-ItemProperty -Path $path -Name AllowDevelopmentWithoutDevLicense -PropertyType DWord -Value 1 -Force | Out-Null
    return
  }

  Start-Process 'ms-settings:developers' | Out-Null
  throw 'Flutter Windows plugins require symlink support. Enable Developer Mode in Windows Settings, then rerun this script. The settings page has been opened.'
}

function Ensure-GitSafeDirectory {
  param([string]$Path)

  if (-not (Test-Path -LiteralPath (Join-Path $Path '.git'))) {
    return
  }
  $resolved = (Resolve-Path -LiteralPath $Path).Path.Replace('\', '/')
  $existing = @(& git config --global --get-all safe.directory 2>$null)
  foreach ($entry in $existing) {
    if ([string]::Equals($entry.TrimEnd('/'), $resolved.TrimEnd('/'), [StringComparison]::OrdinalIgnoreCase)) {
      return
    }
  }
  Write-Host "Adding Git safe.directory: $resolved"
  Invoke-NativeCommand -Name 'git config safe.directory' -Command {
    git config --global --add safe.directory $resolved
  }
}

function Resolve-VersionLabel {
  param(
    [bool]$ForBuild,
    [string]$ExplicitVersion
  )

  if ($ExplicitVersion) {
    return $ExplicitVersion
  }
  if (-not $ForBuild) {
    return 'dev'
  }

  $version = (& git describe --tags --always --dirty 2>$null)
  if ($LASTEXITCODE -eq 0 -and $version) {
    return $version.Trim()
  }
  return 'dev'
}

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$repoRootPath = $repoRoot.Path
$bridgeDir = Join-Path $repoRoot 'bin/bridge'
$bridgeDll = Join-Path $bridgeDir 'remote_storage_bridge.dll'
$flutterCandidates = @()
if ($env:FLUTTER_ROOT) {
  $flutterCandidates += (Join-Path $env:FLUTTER_ROOT 'bin/flutter.bat')
}
$flutterCandidates += @(
  (Join-Path $HOME 'dev/flutter/bin/flutter.bat'),
  'C:\src\flutter\bin\flutter.bat'
)
$flutter = Resolve-Executable -Name $FlutterPath -Candidates $flutterCandidates
if (-not $flutter) {
  throw 'Could not find flutter. Pass -FlutterPath or set FLUTTER_ROOT.'
}
$flutterRoot = Resolve-Path (Join-Path (Split-Path -Parent $flutter) '..')
Ensure-GitSafeDirectory -Path $flutterRoot
Ensure-GitSafeDirectory -Path $repoRootPath

$gcc = Resolve-Executable -Name $BridgeCc -Candidates @(
  $env:BRIDGE_CC,
  'C:\msys64\ucrt64\bin\gcc.exe',
  'C:\msys64\mingw64\bin\gcc.exe',
  'C:\msys64\clang64\bin\gcc.exe'
)
if (-not $gcc) {
  throw 'Could not find gcc. Install the MSYS2 UCRT64 toolchain or pass -BridgeCc.'
}

$gxx = Resolve-Executable -Name $BridgeCxx -Candidates @(
  $env:BRIDGE_CXX,
  'C:\msys64\ucrt64\bin\g++.exe',
  'C:\msys64\mingw64\bin\g++.exe',
  'C:\msys64\clang64\bin\g++.exe'
)
if (-not $gxx) {
  throw 'Could not find g++. Install the MSYS2 UCRT64 toolchain or pass -BridgeCxx.'
}

$env:CGO_ENABLED = '1'
$env:BRIDGE_CC = $gcc
$env:BRIDGE_CXX = $gxx
$env:CC = (Split-Path -Leaf $gcc)
$env:CXX = (Split-Path -Leaf $gxx)
$env:PATH = "$(Split-Path -Parent $gcc);$env:PATH"

if ($env:HTTP_PROXY -or $env:HTTPS_PROXY -or $env:ALL_PROXY) {
  $noProxy = $env:NO_PROXY
  $noProxy = Add-NoProxyEntry -CurrentValue $noProxy -Entry '127.0.0.1'
  $noProxy = Add-NoProxyEntry -CurrentValue $noProxy -Entry 'localhost'
  $env:NO_PROXY = $noProxy
  $env:no_proxy = $noProxy
  Write-Host "Using NO_PROXY=$noProxy for local Flutter VM service connections."
}

Push-Location $repoRoot
try {
  if ($Build) {
    Write-Host 'run_windows.ps1 mode: build'
  } else {
    Write-Host 'run_windows.ps1 mode: run'
  }
  $versionLabel = Resolve-VersionLabel -ForBuild ([bool]$Build) -ExplicitVersion $Version
  Write-Host "Using APP_VERSION_LABEL=$versionLabel"
  Ensure-WindowsSymlinkSupport
  Invoke-NativeCommand -Name 'flutter config --enable-windows-desktop' -Command {
    & $flutter config --enable-windows-desktop
  }
  if (-not $SkipPubGet) {
    Invoke-NativeCommand -Name 'flutter pub get' -Command {
      & $flutter pub get
    }
  }

  New-Item -ItemType Directory -Force -Path $bridgeDir | Out-Null
  Invoke-NativeCommand -Name 'go bridge build' -Command {
    & go build -buildvcs=false -buildmode=c-shared -o $bridgeDll ./bridge
  }

 if ($Build) {
   Invoke-NativeCommand -Name 'flutter build windows' -Command {
     & $flutter build windows --dart-define "APP_VERSION_LABEL=$versionLabel"
   }
    # Build the standalone updater EXE and copy it into the release dir so
    # green-package (zip) auto-updates have a visible progress dialog.
    $releaseDir = Join-Path $repoRoot 'build\windows\x64\runner\Release'
    $updaterExe = Join-Path $releaseDir 'cloud-volume-updater.exe'
    Write-Host 'Building standalone updater...'
    Invoke-NativeCommand -Name 'go build updater' -Command {
      & go build -o $updaterExe ./cmd/cloud-volume-updater
    }
 } else {
   Invoke-NativeCommand -Name 'flutter run windows' -Command {
     & $flutter run -d windows --dart-define "APP_VERSION_LABEL=$versionLabel"
   }
 }
} finally {
  Pop-Location
}
