@echo off
REM Double-click launcher: builds the Flutter release bundle AND packages
REM it as a Windows installer (.exe) in one step using Inno Setup.
REM Requires setup_windows_dev.bat to have been run once.

setlocal
cd /d "%~dp0\.."

powershell -NoProfile -ExecutionPolicy Bypass -File ".\scripts\build_windows_installer.ps1" %*

if %ERRORLEVEL% neq 0 (
  echo.
  echo Installer build failed. Make sure Inno Setup 6 and the Flutter/CGO toolchain are installed.
)

if not defined CLOUD_VOLUME_NO_PAUSE pause