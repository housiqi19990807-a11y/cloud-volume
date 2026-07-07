@echo off
REM Double-click launcher for a Windows release build through the Go bridge workflow.
setlocal

set "SCRIPT_DIR=%~dp0"
set "REPO_ROOT=%SCRIPT_DIR%.."
set "RUN_SCRIPT=%SCRIPT_DIR%run_windows.ps1"

if not exist "%RUN_SCRIPT%" (
  echo Cannot find %RUN_SCRIPT%
  goto :failed
)

pushd "%REPO_ROOT%" >nul
powershell -NoProfile -ExecutionPolicy Bypass -File "%RUN_SCRIPT%" -Build %*
set "EXIT_CODE=%ERRORLEVEL%"
popd >nul

if not "%EXIT_CODE%"=="0" goto :failed

echo.
echo Windows release build completed.
goto :done

:failed
echo.
echo Windows release build failed.
if not defined EXIT_CODE set "EXIT_CODE=1"

:done
echo.
if not defined CLOUD_VOLUME_NO_PAUSE pause
exit /b %EXIT_CODE%

