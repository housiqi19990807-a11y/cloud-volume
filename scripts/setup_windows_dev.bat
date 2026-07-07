@echo off
REM Double-click launcher for the Windows development environment bootstrap.
setlocal

set "SCRIPT_DIR=%~dp0"
set "REPO_ROOT=%SCRIPT_DIR%.."
set "SETUP_SCRIPT=%SCRIPT_DIR%setup_windows_dev.ps1"

if not exist "%SETUP_SCRIPT%" (
  echo Cannot find %SETUP_SCRIPT%
  goto :failed
)

pushd "%REPO_ROOT%" >nul
powershell -NoProfile -ExecutionPolicy Bypass -File "%SETUP_SCRIPT%" %*
set "EXIT_CODE=%ERRORLEVEL%"
popd >nul

if not "%EXIT_CODE%"=="0" goto :failed

echo.
echo Windows development environment setup completed.
goto :done

:failed
echo.
echo Windows development environment setup failed.
if not defined EXIT_CODE set "EXIT_CODE=1"

:done
echo.
if not defined CLOUD_VOLUME_NO_PAUSE pause
exit /b %EXIT_CODE%

