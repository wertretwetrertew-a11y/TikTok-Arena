@echo off
setlocal
cd /d "%~dp0"

echo =====================================
echo  TikTok Arena
echo  Bootstrap + Update + Start
echo =====================================
echo.

where node >nul 2>nul
if errorlevel 1 (
  echo Node.js was not found.
  echo Install Node.js LTS first.
  echo.
  pause
  exit /b 1
)

set "UPDATER=%TEMP%\TikTok-Arena-Updater-Latest.ps1"
echo Downloading the latest updater from GitHub...
powershell -NoProfile -ExecutionPolicy Bypass -Command "Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/wertretwetrertew-a11y/TikTok-Arena/main/Update-TikTok-Arena.ps1' -OutFile '%UPDATER%' -UseBasicParsing"
if errorlevel 1 (
  echo Failed to download the latest updater.
  echo.
  pause
  exit /b 1
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%UPDATER%"
set "EXITCODE=%ERRORLEVEL%"
del /q "%UPDATER%" >nul 2>nul
exit /b %EXITCODE%
