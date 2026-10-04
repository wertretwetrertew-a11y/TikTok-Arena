@echo off
cd /d "%~dp0"

echo =====================================
echo  TikTok Arena
echo  Update + Start
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

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Update-TikTok-Arena.ps1"
