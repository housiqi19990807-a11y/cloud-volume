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

  # Bare names like "go" must not resolve to a same-named directory
  # (this repository has a top-level /go package directory).
  $looksLikePath = $false
  if ($Name) {
    if ($Name.Contains('\') -or $Name.Contains('/') -or $Name.Contains(':')) {
      $looksLikePath = $true
    } elseif ($Name -like '*.exe' -or $Name -like '*.bat' -or $Name -like '*.cmd' -or $Name -like '*.ps1') {
      $looksLikePath = $true
    }
  }
  if ($looksLikePath -and (Test-Path -LiteralPath $Name -PathType Leaf)) {
    return (Resolve-Path -LiteralPath $Name).Path
  }

  if ($Name) {
    $command = Get-Command $Name -ErrorAction SilentlyContinue
    if ($command) {
      return $command.Source
    }
  }

  foreach ($candidate in $Candidates) {
    if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)) {
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

function Get-CompilerDumpMachine {
  param([Parameter(Mandatory = $true)][string]$Compiler)

  # MSYS2/LLVM tools can return empty output under PowerShell's call operator
  # on some Windows ARM hosts. Probe via ProcessStartInfo instead.
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = $Compiler
  $psi.Arguments = '-dumpmachine'
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  $psi.UseShellExecute = $false
  $psi.CreateNoWindow = $true
  $compilerDir = Split-Path -Parent $Compiler
  $psi.EnvironmentVariables['Path'] = "$compilerDir;$env:Path"
  $process = [System.Diagnostics.Process]::Start($psi)
  $stdout = $process.StandardOutput.ReadToEnd()
  $stderr = $process.StandardError.ReadToEnd()
  $process.WaitForExit()
  return [pscustomobject]@{
    ExitCode = $process.ExitCode
    Target = (($stdout + $stderr).Trim())
  }
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
  $tried = @()
  foreach ($candidate in $allCandidates) {
    if (-not $candidate) {
      continue
    }

    $compiler = $null
    if (Test-Path -LiteralPath $candidate) {
      $compiler = (Resolve-Path -LiteralPath $candidate).Path
    } else {
      $command = Get-Command $candidate -ErrorAction SilentlyContinue
      if ($command) {
        $compiler = $command.Source
      }
    }
    if (-not $compiler -or $seen.ContainsKey($compiler)) {
      continue
    }
    $seen[$compiler] = $true

    $probe = Get-CompilerDumpMachine -Compiler $compiler
    $target = $probe.Target
    if ($probe.ExitCode -eq 0 -and $target) {
      if (Test-CompilerTargetArchitecture -Target $target -Architecture $Architecture) {
        Write-Host "Using $Label=$compiler ($target)"
        return $compiler
      }
      $tried += "$compiler => $target"
      Write-Host "skip: $compiler targets $target, expected $Architecture" -ForegroundColor DarkGray
    } else {
      $tried += "$compiler => dumpmachine failed (exit=$($probe.ExitCode))"
      Write-Host "skip: $compiler dumpmachine failed (exit=$($probe.ExitCode))" -ForegroundColor DarkGray
    }

    if ($Requested -and $candidate -eq $Requested) {
      throw "$Label '$Requested' does not target $Architecture."
    }
  }

  $detail = if ($tried.Count -gt 0) { ' Tried: ' + ($tried -join '; ') } else { '' }
  throw "Could not find a $Label targeting $Architecture.$detail Rerun scripts/setup_windows_dev.ps1 or pass -BridgeCc/-BridgeCxx."
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

function Get-VisualStudioInstallPath {
  $vswhere = Resolve-Executable -Name 'vswhere' -Candidates @(
    'C:\Program Files (x86)\Microsoft Visual Studio\Installer\vswhere.exe',
    'C:\Program Files\Microsoft Visual Studio\Installer\vswhere.exe'
  )
  if (-not $vswhere) {
    return $null
  }
  $installation = & $vswhere -latest -products * -property installationPath
  if ($LASTEXITCODE -ne 0 -or -not $installation) {
    return $null
  }
  return ("$installation").Trim()
}

function Test-VisualStudioWindowsTargetReady {
  param([string]$Architecture)

  $installation = Get-VisualStudioInstallPath
  if (-not $installation) {
    return $false
  }
  $platformName = if ($Architecture -eq 'arm64') { 'ARM64' } else { 'x64' }
  $platformRoot = Join-Path $installation 'MSBuild\Microsoft\VC'
  if (-not (Test-Path -LiteralPath $platformRoot)) {
    return $false
  }
  $platformProps = Get-ChildItem -LiteralPath $platformRoot -Directory -ErrorAction SilentlyContinue |
    ForEach-Object { Join-Path $_.FullName ("Platforms\$platformName\Platform.props") } |
    Where-Object { Test-Path -LiteralPath $_ } |
    Select-Object -First 1
  if (-not $platformProps) {
    return $false
  }
  $msvcRoot = Join-Path $installation 'VC\Tools\MSVC'
  if (-not (Test-Path -LiteralPath $msvcRoot)) {
    return $false
  }
  $hostName = if ($Architecture -eq 'arm64') { 'Hostarm64' } else { 'Hostx64' }
  $targetName = if ($Architecture -eq 'arm64') { 'arm64' } else { 'x64' }
  $hasTarget = Get-ChildItem -LiteralPath $msvcRoot -Directory -ErrorAction SilentlyContinue |
    Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName "bin\$hostName\$targetName") } |
    Select-Object -First 1
  return [bool]$hasTarget
}

function Ensure-VisualStudioWindowsTarget {
  param([string]$Architecture)

  if (Test-VisualStudioWindowsTargetReady -Architecture $Architecture) {
    return
  }

  if ($Architecture -eq 'arm64') {
    throw @"
Visual Studio Build Tools are missing the ARM64 C++ platform toolset required by Flutter/CMake.

Install component Microsoft.VisualStudio.Component.VC.Tools.ARM64, then rerun.

Admin PowerShell:
  & "C:\Program Files (x86)\Microsoft Visual Studio\Installer\setup.exe" modify --installPath "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools" --add Microsoft.VisualStudio.Component.VC.Tools.ARM64 --quiet --norestart

Or rerun:
  powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\setup_windows_dev.ps1
"@
  }

  throw 'Visual Studio C++ x64 build tools were not detected. Rerun scripts/setup_windows_dev.ps1.'
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
$goBin = Split-Path -Parent $go
if ($env:PATH -notlike "*$goBin*") {
  $env:PATH = "$goBin;$env:PATH"
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
  # Prefer known ARM64 toolchain paths before any stale BRIDGE_CC value
  # left over from an earlier x64-only setup (commonly UCRT64 gcc).
  @(
    'C:\msys64\clangarm64\bin\clang.exe',
    'C:\msys64\clangarm64\bin\aarch64-w64-mingw32-clang.exe',
    $env:BRIDGE_CC
  )
} else {
  @(
    'C:\msys64\ucrt64\bin\gcc.exe',
    'C:\msys64\mingw64\bin\gcc.exe',
    'C:\msys64\clang64\bin\clang.exe',
    $env:BRIDGE_CC
  )
}
$cxxCandidates = if ($architecture -eq 'arm64') {
  @(
    'C:\msys64\clangarm64\bin\clang++.exe',
    'C:\msys64\clangarm64\bin\aarch64-w64-mingw32-clang++.exe',
    $env:BRIDGE_CXX
  )
} else {
  @(
    'C:\msys64\ucrt64\bin\g++.exe',
    'C:\msys64\mingw64\bin\g++.exe',
    'C:\msys64\clang64\bin\clang++.exe',
    $env:BRIDGE_CXX
  )
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

# Keep user env in sync so the next shell does not prefer a stale x64 compiler.
$storedCc = [Environment]::GetEnvironmentVariable('BRIDGE_CC', 'User')
$storedCxx = [Environment]::GetEnvironmentVariable('BRIDGE_CXX', 'User')
if ($storedCc -ne $cc) {
  [Environment]::SetEnvironmentVariable('BRIDGE_CC', $cc, 'User')
  Write-Host "Updated user BRIDGE_CC=$cc"
}
if ($storedCxx -ne $cxx) {
  [Environment]::SetEnvironmentVariable('BRIDGE_CXX', $cxx, 'User')
  Write-Host "Updated user BRIDGE_CXX=$cxx"
}
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
  Ensure-VisualStudioWindowsTarget -Architecture $architecture
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


