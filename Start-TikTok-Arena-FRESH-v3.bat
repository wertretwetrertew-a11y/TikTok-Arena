@echo off
setlocal
cd /d "%~dp0"

echo =====================================
echo  TikTok Arena - FRESH START v3 FIXED
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
echo Downloading FRESH updater from GitHub API...

powershell -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop'; $u='https://api.github.com/repos/wertretwetrertew-a11y/TikTok-Arena/contents/Update-TikTok-Arena.ps1?ref=main'; $r=Invoke-RestMethod -Uri $u -Headers @{'Accept'='application/vnd.github+json';'User-Agent'='TikTok-Arena-Launcher-FRESH-v3';'Cache-Control'='no-cache'} -Method Get; [IO.File]::WriteAllBytes('%UPDATER%', [Convert]::FromBase64String(($r.content -replace '\s','')))"
if errorlevel 1 (
  echo Failed to download the fresh updater from GitHub.
  echo.
  pause
  exit /b 1
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%UPDATER%"
set "EXITCODE=%ERRORLEVEL%"
del /q "%UPDATER%" >nul 2>nul
exit /b %EXITCODE%
