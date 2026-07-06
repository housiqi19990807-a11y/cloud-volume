# Bootstraps a Windows desktop development environment for this repository.
# It installs or verifies Flutter, Go, Visual Studio C++ tools, and MSYS2 UCRT64.
param(
  [string]$FlutterRoot = (Join-Path $HOME 'dev\flutter'),
  [string]$MsysRoot = 'C:\msys64',
  [switch]$SkipWingetInstall,
  [switch]$SkipFlutterClone,
  [switch]$SkipMsysPackages,
  [switch]$SkipDoctor,
  [switch]$ValidateProject
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Section {
  param([string]$Message)
  Write-Host ''
  Write-Host "==> $Message" -ForegroundColor Cyan
}

function Write-Skip {
  param([string]$Message)
  Write-Host "skip: $Message" -ForegroundColor DarkGray
}

function Resolve-Executable {
  param(
    [string]$Name,
    [string[]]$Candidates = @()
  )

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

function Refresh-ProcessPath {
  $machinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
  $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
  $env:Path = @($machinePath, $userPath, $env:Path) -join ';'
}

function Add-UserPathEntry {
  param([string]$Entry)

  if (-not $Entry -or -not (Test-Path -LiteralPath $Entry)) {
    return
  }

  $resolved = (Resolve-Path -LiteralPath $Entry).Path.TrimEnd('\')
  $current = [Environment]::GetEnvironmentVariable('Path', 'User')
  $items = @()
  if ($current) {
    $items = $current.Split(';') | ForEach-Object { $_.Trim().TrimEnd('\') } | Where-Object { $_ }
  }

  $alreadyPresent = $false
  foreach ($item in $items) {
    if ([string]::Equals($item, $resolved, [StringComparison]::OrdinalIgnoreCase)) {
      $alreadyPresent = $true
      break
    }
  }

  if (-not $alreadyPresent) {
    $newValue = (@($items) + $resolved) -join ';'
    [Environment]::SetEnvironmentVariable('Path', $newValue, 'User')
    Write-Host "Added to user PATH: $resolved"
  }

  if ($env:Path -notlike "*$resolved*") {
    $env:Path = "$resolved;$env:Path"
  }
}

function Invoke-WingetInstall {
  param(
    [string]$Id,
    [string]$Name,
    [string[]]$ExtraArgs = @()
  )

  if ($SkipWingetInstall) {
    Write-Skip "winget install skipped for $Name"
    return
  }

  $winget = Resolve-Executable -Name 'winget'
  if (-not $winget) {
    throw 'winget is required for automatic package installation. Install App Installer from Microsoft Store, or rerun with -SkipWingetInstall after installing dependencies manually.'
  }

  Write-Host "Installing $Name with winget..."
  $args = @(
    'install',
    '--id', $Id,
    '--exact',
    '--accept-package-agreements',
    '--accept-source-agreements'
  ) + $ExtraArgs
  & $winget @args
  if ($LASTEXITCODE -ne 0) {
    throw "winget failed while installing $Name ($Id)."
  }
  Refresh-ProcessPath
}

function Ensure-Git {
  Write-Section 'Git'
  if (Resolve-Executable -Name 'git') {
    & git --version
    return
  }

  Invoke-WingetInstall -Id 'Git.Git' -Name 'Git'
  $git = Resolve-Executable -Name 'git' -Candidates @(
    'C:\Program Files\Git\cmd\git.exe'
  )
  if (-not $git) {
    throw 'Git was not found after installation.'
  }
  & $git --version
}

function Ensure-Go {
  Write-Section 'Go'
  if (Resolve-Executable -Name 'go') {
    & go version
    return
  }

  Invoke-WingetInstall -Id 'GoLang.Go' -Name 'Go'
  Add-UserPathEntry -Entry 'C:\Program Files\Go\bin'
  $go = Resolve-Executable -Name 'go' -Candidates @(
    'C:\Program Files\Go\bin\go.exe'
  )
  if (-not $go) {
    throw 'Go was not found after installation.'
  }
  & $go version
}

function Resolve-VsWhere {
  $programFilesX86 = [Environment]::GetFolderPath('ProgramFilesX86')
  return Resolve-Executable -Name 'vswhere' -Candidates @(
    (Join-Path $programFilesX86 'Microsoft Visual Studio\Installer\vswhere.exe'),
    'C:\Program Files (x86)\Microsoft Visual Studio\Installer\vswhere.exe'
  )
}

function Test-VCToolsInstalled {
  $vswhere = Resolve-VsWhere
  if (-not $vswhere) {
    return $false
  }

  $installation = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
  return [bool]$installation
}

function Ensure-VisualStudioBuildTools {
  Write-Section 'Visual Studio C++ tools'
  if (Test-VCToolsInstalled) {
    Write-Skip 'Visual Studio C++ build tools already installed'
    return
  }

  Invoke-WingetInstall `
    -Id 'Microsoft.VisualStudio.2022.BuildTools' `
    -Name 'Visual Studio 2022 Build Tools' `
    -ExtraArgs @(
      '--silent',
      '--override',
      '--wait --quiet --norestart --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended'
    )

  if (-not (Test-VCToolsInstalled)) {
    throw 'Visual Studio C++ build tools were not detected after installation. Reboot or open Visual Studio Installer to finish setup, then rerun this script.'
  }
}

function Ensure-Msys2 {
  Write-Section 'MSYS2 UCRT64 toolchain'
  $bash = Join-Path $MsysRoot 'usr\bin\bash.exe'
  if (-not (Test-Path -LiteralPath $bash)) {
    Invoke-WingetInstall -Id 'MSYS2.MSYS2' -Name 'MSYS2'
  }

  $bash = Resolve-Executable -Name '' -Candidates @(
    (Join-Path $MsysRoot 'usr\bin\bash.exe'),
    'C:\msys64\usr\bin\bash.exe'
  )
  if (-not $bash) {
    throw 'MSYS2 bash was not found after installation.'
  }

  if (-not $SkipMsysPackages) {
    Write-Host 'Installing MSYS2 UCRT64 gcc/g++ packages...'
    & $bash -lc 'pacman -Sy --needed --noconfirm mingw-w64-ucrt-x86_64-gcc mingw-w64-ucrt-x86_64-pkg-config make'
    if ($LASTEXITCODE -ne 0) {
      throw 'MSYS2 package installation failed.'
    }
  } else {
    Write-Skip 'MSYS2 package installation skipped'
  }

  $ucrtBin = Join-Path $MsysRoot 'ucrt64\bin'
  Add-UserPathEntry -Entry $ucrtBin
  $gcc = Resolve-Executable -Name 'gcc' -Candidates @((Join-Path $ucrtBin 'gcc.exe'))
  $gxx = Resolve-Executable -Name 'g++' -Candidates @((Join-Path $ucrtBin 'g++.exe'))
  if (-not $gcc -or -not $gxx) {
    throw 'MSYS2 UCRT64 gcc/g++ were not found.'
  }

  [Environment]::SetEnvironmentVariable('BRIDGE_CC', $gcc, 'User')
  [Environment]::SetEnvironmentVariable('BRIDGE_CXX', $gxx, 'User')
  $env:BRIDGE_CC = $gcc
  $env:BRIDGE_CXX = $gxx
  & $gcc --version | Select-Object -First 1
}

function Ensure-Flutter {
  Write-Section 'Flutter'
  $existingFlutter = Resolve-Executable -Name 'flutter' -Candidates @(
    (Join-Path $FlutterRoot 'bin\flutter.bat'),
    'C:\src\flutter\bin\flutter.bat'
  )

  if (-not $existingFlutter) {
    if ($SkipFlutterClone) {
      throw 'Flutter was not found and -SkipFlutterClone was specified.'
    }

    $parent = Split-Path -Parent $FlutterRoot
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
    Write-Host "Cloning Flutter stable into $FlutterRoot..."
    & git clone --branch stable https://github.com/flutter/flutter.git $FlutterRoot
    if ($LASTEXITCODE -ne 0) {
      throw 'Flutter clone failed.'
    }
  }

  $flutterBin = Join-Path $FlutterRoot 'bin'
  Add-UserPathEntry -Entry $flutterBin
  [Environment]::SetEnvironmentVariable('FLUTTER_ROOT', $FlutterRoot, 'User')
  $env:FLUTTER_ROOT = $FlutterRoot

  $flutter = Resolve-Executable -Name 'flutter' -Candidates @((Join-Path $flutterBin 'flutter.bat'))
  if (-not $flutter) {
    throw 'Flutter was not found after setup.'
  }

  & $flutter --version
  & $flutter config --enable-windows-desktop
}

function Test-ProjectBuildInputs {
  Write-Section 'Project build input check'
  $repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
  $runScript = Join-Path $repoRoot 'scripts\run_windows.ps1'
  if (-not (Test-Path -LiteralPath $runScript)) {
    throw 'scripts/run_windows.ps1 was not found.'
  }

  if ($ValidateProject) {
    & powershell -NoProfile -ExecutionPolicy Bypass -File $runScript -Build
    if ($LASTEXITCODE -ne 0) {
      throw 'Project build validation failed.'
    }
  } else {
    Write-Host 'Skipping full project build. Rerun with -ValidateProject to build the bridge and Windows app.'
  }
}

if ($env:OS -ne 'Windows_NT') {
  throw 'This script must be run on Windows.'
}

Write-Host 'Cloud Volume Windows development environment setup'
Write-Host 'Run from a normal PowerShell first. winget or Visual Studio may prompt for elevation.'

Ensure-Git
Ensure-Go
Ensure-VisualStudioBuildTools
Ensure-Msys2
Ensure-Flutter

if (-not $SkipDoctor) {
  Write-Section 'Flutter doctor'
  & flutter doctor -v
} else {
  Write-Skip 'flutter doctor skipped'
}

Test-ProjectBuildInputs

Write-Section 'Done'
Write-Host 'Open a new PowerShell window to pick up user PATH changes, then run:'
Write-Host '  powershell -ExecutionPolicy Bypass -File .\scripts\run_windows.ps1'
