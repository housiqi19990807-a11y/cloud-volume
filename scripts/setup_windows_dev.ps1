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

function Save-Download {
  param(
    [string]$Url,
    [string]$Destination
  )

  $parent = Split-Path -Parent $Destination
  New-Item -ItemType Directory -Force -Path $parent | Out-Null
  $lastError = $null
  for ($attempt = 1; $attempt -le 3; $attempt++) {
    Write-Host "Downloading $Url (attempt $attempt/3)"
    try {
      Invoke-WebRequest -Uri $Url -OutFile $Destination -UseBasicParsing
      if ((Test-Path -LiteralPath $Destination) -and ((Get-Item -LiteralPath $Destination).Length -gt 0)) {
        return
      }
      $lastError = 'downloaded file is empty'
    } catch {
      $lastError = $_.Exception.Message
    }
    Start-Sleep -Seconds $attempt
  }

  $curl = Resolve-Executable -Name 'curl.exe'
  if ($curl) {
    Write-Host "Retrying $Url with curl.exe"
    & $curl -L --ssl-no-revoke --retry 5 --retry-delay 2 --fail -o $Destination $Url
    if ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $Destination) -and ((Get-Item -LiteralPath $Destination).Length -gt 0)) {
      return
    }
    $lastError = "curl.exe failed with exit code $LASTEXITCODE"
  }

  throw "Failed to download $Url. $lastError"
}

function Invoke-Installer {
  param(
    [string]$Path,
    [string[]]$Arguments,
    [string]$Name,
    [int[]]$SuccessExitCodes = @(0, 3010)
  )

  Write-Host "Running $Name installer..."
  $process = Start-Process -FilePath $Path -ArgumentList $Arguments -Wait -PassThru -WindowStyle Hidden
  if ($SuccessExitCodes -notcontains $process.ExitCode) {
    throw "$Name installer failed with exit code $($process.ExitCode)."
  }
  if ($process.ExitCode -eq 3010) {
    Write-Host "$Name installer requested a reboot; continuing because installation completed." -ForegroundColor Yellow
  }
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
    Write-Skip "winget is not available for $Name"
    return $false
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
  return $true
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

  $installedByWinget = Invoke-WingetInstall `
    -Id 'Microsoft.VisualStudio.2022.BuildTools' `
    -Name 'Visual Studio 2022 Build Tools' `
    -ExtraArgs @(
      '--silent',
      '--override',
      '--wait --quiet --norestart --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended'
    )

  if (-not $installedByWinget) {
    $installer = Join-Path $env:TEMP 'cloud-volume-dev-setup\vs_BuildTools.exe'
    Save-Download -Url 'https://aka.ms/vs/17/release/vs_BuildTools.exe' -Destination $installer
    Invoke-Installer `
      -Path $installer `
      -Name 'Visual Studio 2022 Build Tools' `
      -Arguments @(
        '--wait',
        '--quiet',
        '--norestart',
        '--add',
        'Microsoft.VisualStudio.Workload.VCTools',
        '--includeRecommended'
      )
  }

  if (-not (Test-VCToolsInstalled)) {
    throw 'Visual Studio C++ build tools were not detected after installation. Reboot or open Visual Studio Installer to finish setup, then rerun this script.'
  }
}

function Ensure-Msys2 {
  Write-Section 'MSYS2 UCRT64 toolchain'
  $bash = Join-Path $MsysRoot 'usr\bin\bash.exe'
  if (-not (Test-Path -LiteralPath $bash)) {
    $installedByWinget = Invoke-WingetInstall -Id 'MSYS2.MSYS2' -Name 'MSYS2'
    if (-not $installedByWinget) {
      $installer = Join-Path $env:TEMP 'cloud-volume-dev-setup\msys2-x86_64-latest.exe'
      Save-Download -Url 'https://github.com/msys2/msys2-installer/releases/latest/download/msys2-x86_64-latest.exe' -Destination $installer
      Invoke-Installer `
        -Path $installer `
        -Name 'MSYS2' `
        -Arguments @(
          'install',
          '--root',
          $MsysRoot,
          '--confirm-command'
        )
    }
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
    Invoke-NativeCommand -Name 'MSYS2 package installation' -Command {
      & $bash -lc 'pacman -Sy --needed --noconfirm mingw-w64-ucrt-x86_64-gcc mingw-w64-ucrt-x86_64-pkg-config make'
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
    Invoke-NativeCommand -Name 'Flutter clone' -Command {
      git clone --branch stable https://github.com/flutter/flutter.git $FlutterRoot
    }
  }

  Ensure-GitSafeDirectory -Path $FlutterRoot

  $flutterBin = Join-Path $FlutterRoot 'bin'
  Add-UserPathEntry -Entry $flutterBin
  [Environment]::SetEnvironmentVariable('FLUTTER_ROOT', $FlutterRoot, 'User')
  $env:FLUTTER_ROOT = $FlutterRoot
  if (-not $env:FLUTTER_STORAGE_BASE_URL) {
    $env:FLUTTER_STORAGE_BASE_URL = 'https://storage.flutter-io.cn'
  }
  if (-not $env:PUB_HOSTED_URL) {
    $env:PUB_HOSTED_URL = 'https://pub.flutter-io.cn'
  }

  Repair-FlutterDartSdk

  $flutter = Resolve-Executable -Name 'flutter' -Candidates @((Join-Path $flutterBin 'flutter.bat'))
  if (-not $flutter) {
    throw 'Flutter was not found after setup.'
  }

  Invoke-NativeCommand -Name 'flutter --version' -Command {
    & $flutter --version
  }
  Invoke-NativeCommand -Name 'flutter config --enable-windows-desktop' -Command {
    & $flutter config --enable-windows-desktop
  }
}

function Repair-FlutterDartSdk {
  $dart = Join-Path $FlutterRoot 'bin\cache\dart-sdk\bin\dart.exe'
  if (Test-Path -LiteralPath $dart) {
    return
  }

  $engineVersionPath = Join-Path $FlutterRoot 'bin\internal\engine.version'
  if (-not (Test-Path -LiteralPath $engineVersionPath)) {
    return
  }

  Write-Host 'Flutter Dart SDK cache is incomplete; downloading it directly.' -ForegroundColor Yellow
  $engine = (Get-Content -LiteralPath $engineVersionPath -Raw).Trim()
  $baseUrl = $env:FLUTTER_STORAGE_BASE_URL
  if (-not $baseUrl) {
    $baseUrl = 'https://storage.googleapis.com'
  }
  $baseUrl = $baseUrl.TrimEnd('/')
  $url = "$baseUrl/flutter_infra_release/flutter/$engine/dart-sdk-windows-x64.zip"
  $zip = Join-Path $env:TEMP 'cloud-volume-dev-setup\dart-sdk-windows-x64.zip'
  Save-Download -Url $url -Destination $zip
  Remove-Item -LiteralPath (Join-Path $FlutterRoot 'bin\cache\dart-sdk') -Recurse -Force -ErrorAction SilentlyContinue
  Expand-Archive -LiteralPath $zip -DestinationPath (Join-Path $FlutterRoot 'bin\cache') -Force

  if (-not (Test-Path -LiteralPath $dart)) {
    throw 'Flutter Dart SDK repair completed, but dart.exe is still missing.'
  }
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
  Invoke-NativeCommand -Name 'flutter doctor' -Command {
    & flutter doctor -v
  }
} else {
  Write-Skip 'flutter doctor skipped'
}

Test-ProjectBuildInputs

Write-Section 'Done'
Write-Host 'Open a new PowerShell window to pick up user PATH changes, then run:'
Write-Host '  powershell -ExecutionPolicy Bypass -File .\scripts\run_windows.ps1'
