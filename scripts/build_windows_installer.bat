@echo off
REM Double-click launcher: builds the Windows installer (.exe) from the
REM current release bundle using Inno Setup. Run scripts\build_windows.bat
REM first to produce the release bundle.

setlocal
cd /d "%~dp0\.."

powershell -NoProfile -ExecutionPolicy Bypass -File ".\scripts\build_windows_installer.ps1" %*

if %ERRORLEVEL% neq 0 (
  echo.
  echo Installer build failed.
  echo Make sure Inno Setup 6 is installed and scripts\build_windows.bat has been run.
)

if not defined CLOUD_VOLUME_NO_PAUSE pause