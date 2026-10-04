@echo off
setlocal
cd /d "%~dp0"

echo =====================================
echo  TikTok Arena - FRESH START v3
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

set "UPDATER=%TEMP%\TikTok-Arena-Updater-FRESH-v3.ps1"
set "CACHE=%RANDOM%%RANDOM%%RANDOM%"
echo Downloading FRESH updater v3 from GitHub...
powershell -NoProfile -ExecutionPolicy Bypass -Command "$u='https://raw.githubusercontent.com/wertretwetrertew-a11y/TikTok-Arena/main/Update-TikTok-Arena.ps1?fresh=%CACHE%'; Invoke-WebRequest -Uri $u -Headers @{'Cache-Control'='no-cache';'Pragma'='no-cache'} -OutFile '%UPDATER%' -UseBasicParsing"
if errorlevel 1 (
  echo Failed to download the fresh updater.
  echo.
  pause
  exit /b 1
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%UPDATER%"
set "EXITCODE=%ERRORLEVEL%"
del /q "%UPDATER%" >nul 2>nul
exit /b %EXITCODE%
