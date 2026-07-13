# Windows local startup helper: resolves Flutter and an architecture-matched
# MinGW/LLVM toolchain, builds the Go bridge with CGO, then launches Flutter.
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

function Get-NativeWindowsArchitecture {
  # This remains correct when PowerShell is running under x64/x86 emulation.
  $architecture = $env:PROCESSOR_ARCHITEW6432
  if (-not $architecture) {
    $architecture = $env:PROCESSOR_ARCHITECTURE
  }
  switch ($architecture.ToUpperInvariant()) {
    'AMD64' { return 'amd64' }
    'ARM64' { return 'arm64' }
    default { throw "Unsupported Windows architecture: $architecture" }
  }
}

function Test-CompilerTargetArchitecture {
  param(
    [string]$Target,
    [string]$Architecture
  )

  if ($Architecture -eq 'arm64') {
    return $Target -match '(^|[-_])(aarch64|arm64)([-_]|$)'
  }
  return $Target -match '(^|[-_])(x86_64|amd64)([-_]|$)'
}

function Resolve-ArchitectureCompiler {
  param(
    [string]$Requested,
    [string[]]$Candidates,
    [string]$Architecture,
    [string]$Label
  )

  $allCandidates = @()
  if ($Requested) {
    $allCandidates += $Requested
  }
  $allCandidates += $Candidates
  $seen = @{}
  foreach ($candidate in $allCandidates) {
    if (-not $candidate) {
      continue
    }
    $compiler = Resolve-Executable -Name $candidate -Candidates @($candidate)
    if (-not $compiler -or $seen.ContainsKey($compiler)) {
      continue
    }
    $seen[$compiler] = $true
    $target = (& $compiler -dumpmachine 2>$null | Select-Object -First 1)
    if ($LASTEXITCODE -eq 0 -and $target) {
      $target = $target.Trim()
      if (Test-CompilerTargetArchitecture -Target $target -Architecture $Architecture) {
        Write-Host "Using $Label=$compiler ($target)"
        return $compiler
      }
      Write-Host "skip: $compiler targets $target, expected $Architecture" -ForegroundColor DarkGray
    }
    if ($Requested -and $candidate -eq $Requested) {
      throw "$Label '$Requested' does not target $Architecture."
    }
  }
  throw "Could not find a $Label compiler targeting $Architecture. Rerun scripts/setup_windows_dev.ps1 or pass the matching compiler path explicitly."
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
    $props = Get-ItemProperty -Path $path -ErrorAction SilentlyContinue
    if ($null -ne $props -and $null -ne $props.PSObject.Properties['AllowDevelopmentWithoutDevLicense']) {
      $enabled = ($props.AllowDevelopmentWithoutDevLicense -eq 1)
    }
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

  Write-Host 'Windows Developer Mode is not enabled; continuing. Enable it if Flutter plugin symlink creation fails.' -ForegroundColor Yellow
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
$architecture = Get-NativeWindowsArchitecture
$flutterArchitecture = if ($architecture -eq 'arm64') { 'arm64' } else { 'x64' }
$go = Resolve-Executable -Name 'go' -Candidates @('C:\Program Files\Go\bin\go.exe')
if (-not $go) {
  throw 'Could not find Go. Rerun scripts/setup_windows_dev.ps1.'
}
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

$ccCandidates = if ($architecture -eq 'arm64') {
  @($env:BRIDGE_CC, 'C:\msys64\clangarm64\bin\clang.exe', 'C:\msys64\clangarm64\bin\aarch64-w64-mingw32-clang.exe')
} else {
  @($env:BRIDGE_CC, 'C:\msys64\ucrt64\bin\gcc.exe', 'C:\msys64\mingw64\bin\gcc.exe', 'C:\msys64\clang64\bin\clang.exe')
}
$cxxCandidates = if ($architecture -eq 'arm64') {
  @($env:BRIDGE_CXX, 'C:\msys64\clangarm64\bin\clang++.exe', 'C:\msys64\clangarm64\bin\aarch64-w64-mingw32-clang++.exe')
} else {
  @($env:BRIDGE_CXX, 'C:\msys64\ucrt64\bin\g++.exe', 'C:\msys64\mingw64\bin\g++.exe', 'C:\msys64\clang64\bin\clang++.exe')
}
$cc = Resolve-ArchitectureCompiler -Requested $BridgeCc -Candidates $ccCandidates -Architecture $architecture -Label 'C compiler'
$cxx = Resolve-ArchitectureCompiler -Requested $BridgeCxx -Candidates $cxxCandidates -Architecture $architecture -Label 'C++ compiler'

$env:CGO_ENABLED = '1'
$env:GOOS = 'windows'
$env:GOARCH = $architecture
$env:BRIDGE_CC = $cc
$env:BRIDGE_CXX = $cxx
$env:CC = $cc
$env:CXX = $cxx
$env:PATH = "$(Split-Path -Parent $cc);$env:PATH"
Write-Host "Target architecture: Windows $architecture (Flutter output: $flutterArchitecture)"

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
    & $go build -buildvcs=false -buildmode=c-shared -o $bridgeDll ./bridge
  }

 if ($Build) {
   Invoke-NativeCommand -Name 'flutter build windows' -Command {
     & $flutter build windows --dart-define "APP_VERSION_LABEL=$versionLabel"
   }
    # Build the standalone updater EXE and copy it into the release dir so
    # green-package (zip) auto-updates have a visible progress dialog.
    $releaseDir = Join-Path $repoRoot "build\windows\$flutterArchitecture\runner\Release"
    $updaterExe = Join-Path $releaseDir 'cloud-volume-updater.exe'
    Write-Host 'Building standalone updater...'
    Invoke-NativeCommand -Name 'go build updater' -Command {
      & $go build -ldflags "-H windowsgui" -o $updaterExe ./cmd/cloud-volume-updater
    }
 } else {
   Invoke-NativeCommand -Name 'flutter run windows' -Command {
     & $flutter run -d windows --dart-define "APP_VERSION_LABEL=$versionLabel"
   }
 }
} finally {
  Pop-Location
}
