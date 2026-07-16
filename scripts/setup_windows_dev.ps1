# Bootstraps a Windows desktop development environment for this repository.
# It installs or verifies Flutter, Go, Rust, architecture-matched C++ tools,
# MSYS2, and Inno Setup 6.
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

function Get-NativeWindowsArchitecture {
  # PROCESSOR_ARCHITEW6432 exposes the native architecture when the current
  # PowerShell process itself is running through x64/x86 emulation.
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

function Test-IsAdministrator {
  $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
  $principal = [Security.Principal.WindowsPrincipal] $identity
  return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Ensure-WindowsSymlinkSupport {
  Write-Section 'Windows symlink support'
  $path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock'
  $enabled = $false

  # Missing registry value is normal on a fresh machine. Treat it as "not enabled"
  # instead of failing under $ErrorActionPreference = 'Stop'.
  if (Test-Path -LiteralPath $path) {
    try {
      $props = Get-ItemProperty -Path $path -ErrorAction Stop
      if ($null -ne $props.PSObject.Properties['AllowDevelopmentWithoutDevLicense']) {
        $enabled = ($props.AllowDevelopmentWithoutDevLicense -eq 1)
      }
    } catch {
      $enabled = $false
    }
  }

  if ($enabled) {
    Write-Skip 'Windows Developer Mode symlink support already enabled'
    return
  }

  if (Test-IsAdministrator) {
    Write-Host 'Enabling Windows Developer Mode symlink support for Flutter plugins...'
    try {
      New-Item -Path $path -Force | Out-Null
      New-ItemProperty -Path $path -Name AllowDevelopmentWithoutDevLicense -PropertyType DWord -Value 1 -Force | Out-Null
      Write-Host 'Developer Mode registry flag enabled.'
      return
    } catch {
      Write-Host "Could not enable Developer Mode automatically: $($_.Exception.Message)" -ForegroundColor Yellow
    }
  }

  # Soft-fail: many setups can continue, and the user can enable this later if
  # Flutter plugin symlink creation fails during pub get / Windows builds.
  Write-Host 'Windows Developer Mode is not enabled.' -ForegroundColor Yellow
  Write-Host 'This helps Flutter Windows plugins create symlinks. It is optional for initial setup,' -ForegroundColor Yellow
  Write-Host 'but recommended if flutter pub get or Windows plugin builds later fail.' -ForegroundColor Yellow
  Write-Host 'Enable it later via: Settings -> Privacy & security -> For developers -> Developer Mode' -ForegroundColor Yellow
  Write-Host 'Or open: ms-settings:developers' -ForegroundColor Yellow
  try {
    Start-Process 'ms-settings:developers' | Out-Null
    Write-Host 'Opened the Windows Developer settings page for convenience.' -ForegroundColor DarkGray
  } catch {
    # Ignore UI launch failures in non-interactive sessions.
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
    '--source', 'winget',
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

function Ensure-GoProxy {
  param([Parameter(Mandatory = $true)][string]$GoExecutable)

  # Keep deliberate custom proxy settings, but replace Go's upstream default
  # with the more reliable mainland-China module proxy for local development.
  $current = (& $GoExecutable env GOPROXY 2>$null).Trim()
  if ($LASTEXITCODE -ne 0) {
    throw 'Unable to read the current Go GOPROXY setting.'
  }
  if ($current -and $current -ne 'https://proxy.golang.org,direct') {
    Write-Skip "custom GOPROXY already configured: $current"
    return
  }

  $proxy = 'https://goproxy.cn,direct'
  Write-Host "Configuring GOPROXY=$proxy"
  Invoke-NativeCommand -Name 'go env GOPROXY' -Command {
    & $GoExecutable env -w "GOPROXY=$proxy"
  }
}

function Ensure-Go {
  Write-Section 'Go'
  $go = Resolve-Executable -Name 'go'
  if ($go) {
    & $go version
    Ensure-GoProxy -GoExecutable $go
    return
  }

  $installedByWinget = $false
  try {
    $installedByWinget = Invoke-WingetInstall -Id 'GoLang.Go' -Name 'Go'
  } catch {
    Write-Host "winget Go install failed: $($_.Exception.Message)"
    Write-Host 'Falling back to the official Go Windows installer...'
  }

  $go = Resolve-Executable -Name 'go' -Candidates @(
    'C:\Program Files\Go\bin\go.exe'
  )
  if (-not $go) {
    $goArchitecture = Get-NativeWindowsArchitecture
    $installer = Join-Path $env:TEMP "cloud-volume-dev-setup\go-windows-$goArchitecture.msi"
    Save-Download -Url "https://go.dev/dl/go1.24.4.windows-$goArchitecture.msi" -Destination $installer
    Invoke-Installer -Path $installer -Name 'Go' -Arguments @('/qn', '/norestart')
  }

  Add-UserPathEntry -Entry 'C:\Program Files\Go\bin'
  $go = Resolve-Executable -Name 'go' -Candidates @(
    'C:\Program Files\Go\bin\go.exe'
  )
  if (-not $go) {
    throw 'Go was not found after installation.'
  }
  & $go version
  Ensure-GoProxy -GoExecutable $go
}

function Ensure-Rust {
  Write-Section 'Rust toolchain (for Flutter native plugins)'
  $cargoBin = Join-Path $HOME '.cargo\bin'
  $rustup = Resolve-Executable -Name 'rustup' -Candidates @(
    (Join-Path $cargoBin 'rustup.exe')
  )
  $target = if ((Get-NativeWindowsArchitecture) -eq 'arm64') {
    'aarch64-pc-windows-msvc'
  } else {
    'x86_64-pc-windows-msvc'
  }

  if (-not $rustup) {
    $installer = Join-Path $env:TEMP "cloud-volume-dev-setup\rustup-init-$target.exe"
    Save-Download `
      -Url "https://static.rust-lang.org/rustup/dist/$target/rustup-init.exe" `
      -Destination $installer
    Write-Host "Installing the Rust $target toolchain..."
    Invoke-NativeCommand -Name 'rustup-init' -Command {
      & $installer -y --profile minimal --default-host $target --default-toolchain stable --no-modify-path
    }
  }

  Add-UserPathEntry -Entry $cargoBin
  $rustup = Resolve-Executable -Name 'rustup' -Candidates @(
    (Join-Path $cargoBin 'rustup.exe')
  )
  if (-not $rustup) {
    throw 'rustup was not found after installation.'
  }

  & $rustup --version
  # CargoKit builds Rust-backed Flutter plugins locally when rustup is present.
  # Ensure the native standard library exists even if rustup was preinstalled
  # with a different default host.
  Invoke-NativeCommand -Name "rustup target add $target" -Command {
    & $rustup target add $target --toolchain stable
  }
}

function Resolve-VsWhere {
  $programFilesX86 = [Environment]::GetFolderPath('ProgramFilesX86')
  return Resolve-Executable -Name 'vswhere' -Candidates @(
    (Join-Path $programFilesX86 'Microsoft Visual Studio\Installer\vswhere.exe'),
    'C:\Program Files (x86)\Microsoft Visual Studio\Installer\vswhere.exe'
  )
}

function Get-RequiredVCToolComponents {
  # Always keep the x64 toolset; ARM64 hosts also need the native ARM64 toolset
  # so Flutter/CMake can generate Platform=ARM64 projects.
  $components = @('Microsoft.VisualStudio.Component.VC.Tools.x86.x64')
  if ((Get-NativeWindowsArchitecture) -eq 'arm64') {
    $components += 'Microsoft.VisualStudio.Component.VC.Tools.ARM64'
  }
  return $components
}

function Get-VisualStudioInstallation {
  param([string[]]$RequiredComponents = @())

  $vswhere = Resolve-VsWhere
  if (-not $vswhere) {
    return $null
  }

  $arguments = @('-latest', '-products', '*')
  foreach ($component in $RequiredComponents) {
    if ($component) {
      # vswhere expects repeated -requires flags for multiple components.
      $arguments += @('-requires', $component)
    }
  }
  $arguments += @('-property', 'installationPath')
  $installation = & $vswhere @arguments
  if ($LASTEXITCODE -ne 0 -or -not $installation) {
    return $null
  }
  return ("$installation").Trim()
}

function Test-VisualStudioWindowsTargetReady {
  param([string]$Architecture = (Get-NativeWindowsArchitecture))

  $installation = Get-VisualStudioInstallation
  if (-not $installation) {
    return $false
  }

  # Component IDs alone are not enough: Flutter/CMake need the MSBuild platform
  # folder for the requested architecture (Platforms\ARM64 or Platforms\x64).
  $platformName = if ($Architecture -eq 'arm64') { 'ARM64' } else { 'x64' }
  $platformRoot = Join-Path $installation 'MSBuild\Microsoft\VC'
  if (-not (Test-Path -LiteralPath $platformRoot)) {
    return $false
  }

  $platformProps = Get-ChildItem -LiteralPath $platformRoot -Directory -ErrorAction SilentlyContinue |
    ForEach-Object {
      Join-Path $_.FullName ("Platforms\$platformName\Platform.props")
    } |
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
    Where-Object {
      Test-Path -LiteralPath (Join-Path $_.FullName "bin\$hostName\$targetName")
    } |
    Select-Object -First 1
  return [bool]$hasTarget
}

function Test-VCToolsInstalled {
  if (-not (Get-VisualStudioInstallation -RequiredComponents (Get-RequiredVCToolComponents))) {
    return $false
  }
  return (Test-VisualStudioWindowsTargetReady)
}

function Ensure-VisualStudioBuildTools {
  Write-Section 'Visual Studio C++ tools'
  $architecture = Get-NativeWindowsArchitecture
  if (Test-VCToolsInstalled) {
    Write-Skip "Visual Studio C++ build tools already installed for $architecture"
    return
  }

  $requiredComponents = Get-RequiredVCToolComponents
  $existingInstallation = Get-VisualStudioInstallation
  if ($existingInstallation) {
    $vsSetup = 'C:\Program Files (x86)\Microsoft Visual Studio\Installer\setup.exe'
    if (-not (Test-Path -LiteralPath $vsSetup)) {
      throw "Visual Studio Installer was not found at $vsSetup."
    }
    Write-Host "Adding architecture-specific Visual Studio components to $existingInstallation..."
    Write-Host ("Required components: " + ($requiredComponents -join ', '))
    # setup.exe does not accept --wait; Start-Process -Wait already blocks.
    $modifyArguments = @(
      'modify',
      '--installPath', $existingInstallation,
      '--quiet',
      '--norestart'
    )
    foreach ($component in $requiredComponents) {
      $modifyArguments += @('--add', $component)
    }
    Invoke-Installer -Path $vsSetup -Name 'Visual Studio C++ tools modification' -Arguments $modifyArguments
  } else {
    $override = '--wait --quiet --norestart --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended'
    foreach ($component in $requiredComponents) {
      $override += " --add $component"
    }

    $installedByWinget = Invoke-WingetInstall `
      -Id 'Microsoft.VisualStudio.2022.BuildTools' `
      -Name 'Visual Studio 2022 Build Tools' `
      -ExtraArgs @('--silent', '--override', $override)

    if (-not $installedByWinget) {
      $installer = Join-Path $env:TEMP 'cloud-volume-dev-setup\vs_BuildTools.exe'
      Save-Download -Url 'https://aka.ms/vs/17/release/vs_BuildTools.exe' -Destination $installer
      $installArguments = @(
        '--wait',
        '--quiet',
        '--norestart',
        '--add', 'Microsoft.VisualStudio.Workload.VCTools',
        '--includeRecommended'
      )
      foreach ($component in $requiredComponents) {
        $installArguments += @('--add', $component)
      }
      Invoke-Installer -Path $installer -Name 'Visual Studio 2022 Build Tools' -Arguments $installArguments
    }
  }

  if (-not (Test-VCToolsInstalled)) {
    $hint = if ($architecture -eq 'arm64') {
      'On ARM64 hosts, install "MSVC v143 - VS 2022 C++ ARM64/ARM64EC build tools" (Microsoft.VisualStudio.Component.VC.Tools.ARM64) so MSBuild has Platforms\ARM64.'
    } else {
      'Install the Visual Studio C++ desktop build tools workload and the MSVC x64 toolset.'
    }
    throw "Visual Studio C++ build tools for $architecture were not detected after installation. $hint Reboot if the installer requested it, then rerun this script."
  }
}
function Ensure-Msys2 {
  $architecture = Get-NativeWindowsArchitecture
  $environmentName = if ($architecture -eq 'arm64') { 'CLANGARM64' } else { 'UCRT64' }
  Write-Section "MSYS2 $environmentName toolchain"
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
    Write-Host "Installing MSYS2 $environmentName compiler packages..."
    $packages = if ($architecture -eq 'arm64') {
      'mingw-w64-clang-aarch64-clang mingw-w64-clang-aarch64-pkg-config make'
    } else {
      'mingw-w64-ucrt-x86_64-gcc mingw-w64-ucrt-x86_64-pkg-config make'
    }
    Invoke-NativeCommand -Name 'MSYS2 package installation' -Command {
      & $bash -lc "pacman -Sy --needed --noconfirm $packages"
    }
  } else {
    Write-Skip 'MSYS2 package installation skipped'
  }

  $toolchainBin = Join-Path $MsysRoot $(if ($architecture -eq 'arm64') { 'clangarm64\bin' } else { 'ucrt64\bin' })
  $ccName = if ($architecture -eq 'arm64') { 'clang.exe' } else { 'gcc.exe' }
  $cxxName = if ($architecture -eq 'arm64') { 'clang++.exe' } else { 'g++.exe' }
  Add-UserPathEntry -Entry $toolchainBin
  $cc = Resolve-Executable -Name '' -Candidates @((Join-Path $toolchainBin $ccName))
  $cxx = Resolve-Executable -Name '' -Candidates @((Join-Path $toolchainBin $cxxName))
  if (-not $cc -or -not $cxx) {
    throw "MSYS2 $environmentName $ccName/$cxxName were not found."
  }

  [Environment]::SetEnvironmentVariable('BRIDGE_CC', $cc, 'User')
  [Environment]::SetEnvironmentVariable('BRIDGE_CXX', $cxx, 'User')
  $env:BRIDGE_CC = $cc
  $env:BRIDGE_CXX = $cxx
  & $cc --version | Select-Object -First 1
  & $cc -dumpmachine
}


function Test-HttpEndpoint {
  param(
    [Parameter(Mandatory = $true)][string]$Url,
    [int]$TimeoutSec = 8
  )

  try {
    $request = [System.Net.HttpWebRequest]::Create($Url)
    $request.Method = 'HEAD'
    $request.Timeout = $TimeoutSec * 1000
    $request.ReadWriteTimeout = $TimeoutSec * 1000
    $request.AllowAutoRedirect = $true
    $request.UserAgent = 'cloud-volume-setup'
    try {
      $response = $request.GetResponse()
      $status = [int]$response.StatusCode
      $response.Close()
      return ($status -ge 200 -and $status -lt 500)
    } catch [System.Net.WebException] {
      # Some mirrors reject HEAD or return 405/403; treat that as reachable if TLS succeeded.
      $resp = $_.Exception.Response
      if ($null -ne $resp) {
        $status = [int]$resp.StatusCode
        $resp.Close()
        return ($status -ge 200 -and $status -lt 500) -or ($status -eq 405) -or ($status -eq 403)
      }

      # Retry once with GET for hosts that dislike HEAD.
      try {
        $getRequest = [System.Net.HttpWebRequest]::Create($Url)
        $getRequest.Method = 'GET'
        $getRequest.Timeout = $TimeoutSec * 1000
        $getRequest.ReadWriteTimeout = $TimeoutSec * 1000
        $getRequest.AllowAutoRedirect = $true
        $getRequest.UserAgent = 'cloud-volume-setup'
        $getResponse = $getRequest.GetResponse()
        $status = [int]$getResponse.StatusCode
        $getResponse.Close()
        return ($status -ge 200 -and $status -lt 500)
      } catch {
        return $false
      }
    }
  } catch {
    return $false
  }
}

function Set-FlutterPackageMirrors {
  # Prefer an explicit caller/user override. Otherwise probe China mirrors first,
  # then fall back to the official pub.dev / Google storage endpoints.
  $preferredPub = $env:PUB_HOSTED_URL
  $preferredStorage = $env:FLUTTER_STORAGE_BASE_URL
  $userForced = -not [string]::IsNullOrWhiteSpace($preferredPub) -or -not [string]::IsNullOrWhiteSpace($preferredStorage)

  if ($userForced) {
    if ([string]::IsNullOrWhiteSpace($preferredPub)) {
      $preferredPub = 'https://pub.dev'
    }
    if ([string]::IsNullOrWhiteSpace($preferredStorage)) {
      $preferredStorage = 'https://storage.googleapis.com'
    }
    $env:PUB_HOSTED_URL = $preferredPub
    $env:FLUTTER_STORAGE_BASE_URL = $preferredStorage
    Write-Host "Using caller-provided Flutter mirrors:"
    Write-Host "  PUB_HOSTED_URL=$($env:PUB_HOSTED_URL)"
    Write-Host "  FLUTTER_STORAGE_BASE_URL=$($env:FLUTTER_STORAGE_BASE_URL)"
    return
  }

  $chinaPub = 'https://pub.flutter-io.cn'
  $chinaStorage = 'https://storage.flutter-io.cn'
  $officialPub = 'https://pub.dev'
  $officialStorage = 'https://storage.googleapis.com'

  Write-Host 'Probing Flutter package mirrors...'
  $chinaOk = (Test-HttpEndpoint -Url $chinaPub) -and (Test-HttpEndpoint -Url $chinaStorage)
  if ($chinaOk) {
    $env:PUB_HOSTED_URL = $chinaPub
    $env:FLUTTER_STORAGE_BASE_URL = $chinaStorage
    Write-Host "China mirror reachable; using:"
    Write-Host "  PUB_HOSTED_URL=$chinaPub"
    Write-Host "  FLUTTER_STORAGE_BASE_URL=$chinaStorage"
    return
  }

  Write-Host 'China mirror probe failed (TLS/network). Falling back to official sources...' -ForegroundColor Yellow
  $officialOk = (Test-HttpEndpoint -Url $officialPub) -and (Test-HttpEndpoint -Url $officialStorage)
  $env:PUB_HOSTED_URL = $officialPub
  $env:FLUTTER_STORAGE_BASE_URL = $officialStorage
  if ($officialOk) {
    Write-Host "Official sources reachable; using:"
  } else {
    Write-Host "Official source probe also failed; still configuring official endpoints and letting Flutter report the real error:" -ForegroundColor Yellow
  }
  Write-Host "  PUB_HOSTED_URL=$officialPub"
  Write-Host "  FLUTTER_STORAGE_BASE_URL=$officialStorage"
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
  Set-FlutterPackageMirrors

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

function Ensure-InnoSetup {
  Write-Section 'Inno Setup 6 (for Windows installer packaging)'
  $iscc = Join-Path $env:ProgramFiles 'Inno Setup 6\ISCC.exe'
  if (-not (Test-Path $iscc)) {
    $iscc = Join-Path ${env:ProgramFiles(x86)} 'Inno Setup 6\ISCC.exe'
  }
  if (Test-Path $iscc) {
    Write-Skip "Inno Setup already installed at $iscc"
    return
  }

  # Download and install silently. The redirect URL always points to the
  # latest stable release.
  $installer = Join-Path $env:TEMP 'cloud-volume-dev-setup\innosetup.exe'
  Save-Download -Url 'https://jrsoftware.org/download.php/is.exe' -Destination $installer
  Write-Host 'Installing Inno Setup 6...'
  $exitCode = (Start-Process -FilePath $installer -ArgumentList '/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART','/SP-' -Wait -PassThru).ExitCode
  if ($exitCode -ne 0) {
    throw "Inno Setup installer exited with code $exitCode."
  }
  if (-not (Test-Path $iscc)) {
    throw 'Inno Setup ISCC.exe was not found after installation.'
  }
  Write-Host "Installed ISCC.exe at $iscc"
}

function Ensure-WinFsp {
  Write-Section 'WinFsp (optional: enables the WinFsp virtual file system mount engine)'

  $arch = Get-NativeWindowsArchitecture
  $dllName = if ($arch -eq 'arm64') { 'winfsp-a64.dll' } else { 'winfsp-x64.dll' }

  $winFspDir = $null
  $reg = Join-Path 'HKLM:\SOFTWARE\WOW6432Node' 'WinFsp'
  if (-not (Test-Path $reg)) { $reg = 'HKLM:\SOFTWARE\WinFsp' }
  if (Test-Path $reg) {
    $props = Get-ItemProperty -Path $reg -ErrorAction SilentlyContinue
    if ($props -and $props.PSObject.Properties['InstallDir']) {
      $winFspDir = $props.InstallDir
    }
  }
  if (-not $winFspDir -and $env:ProgramFiles) {
    $candidate = Join-Path $env:ProgramFiles 'WinFsp'
    if (Test-Path (Join-Path $candidate "bin\$dllName")) {
      $winFspDir = $candidate
    }
  }
  if ($winFspDir -and (Test-Path (Join-Path $winFspDir "bin\$dllName"))) {
    Write-Skip "WinFsp already installed at $winFspDir"
    return
  }

  $repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
  $bundledMsi = Join-Path $repoRoot 'go\mount\embedded\winfsp.msi'
  if (Test-Path $bundledMsi) {
    Write-Host "Installing WinFsp from bundled MSI: $bundledMsi"
    $exitCode = (Start-Process -FilePath 'msiexec.exe' -ArgumentList @('/i', $bundledMsi, '/qn', '/norestart') -Wait -PassThru -Verb RunAs).ExitCode
    if ($exitCode -eq 0 -or $exitCode -eq 3010) {
      Write-Host 'WinFsp installed from the bundled MSI.'
      return
    }
    Write-Host "Bundled WinFsp MSI install exited with code $exitCode; trying winget next."
  }

  $installedByWinget = $false
  if (-not $SkipWingetInstall) {
    try {
      $installedByWinget = Invoke-WingetInstall -Id 'WinFsp.WinFsp' -Name 'WinFsp'
    } catch {
      Write-Host "winget WinFsp install failed: $($_.Exception.Message)"
    }
  } else {
    Write-Skip 'winget install skipped for WinFsp'
  }
  if ($installedByWinget) {
    return
  }

  Write-Host 'WinFsp was not installed. The app will continue to use the Cloud Files engine by default.'
  Write-Host 'To enable the WinFsp virtual file system mount engine, install WinFsp from the Settings page or from https://winfsp.dev/ and relaunch.'
}

if ($env:OS -ne 'Windows_NT') {
  throw 'This script must be run on Windows.'
}

Write-Host 'Cloud Volume Windows development environment setup'
Write-Host 'Run from a normal PowerShell first. winget or Visual Studio may prompt for elevation.'

Ensure-Git
Ensure-GitSafeDirectory -Path (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Ensure-Go
Ensure-VisualStudioBuildTools
Ensure-Rust
Ensure-WindowsSymlinkSupport
Ensure-Msys2
Ensure-Flutter
Ensure-InnoSetup
Ensure-WinFsp

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

