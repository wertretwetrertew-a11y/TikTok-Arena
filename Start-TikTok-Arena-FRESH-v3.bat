@echo off
setlocal EnableExtensions
cd /d "%~dp0"

echo =====================================
echo  TikTok Arena - FRESH START v3
echo  SELF-CONTAINED FIX
echo =====================================
echo.

where node >nul 2>nul
if errorlevel 1 (
  echo ERROR: Node.js was not found.
  echo Install Node.js LTS first.
  pause
  exit /b 1
)

set "ROOT=%~dp0"
set "ZIP=%TEMP%\TikTok-Arena-main.zip"
set "EXTRACT=%TEMP%\TikTok-Arena-main-extract"
set "URL=https://github.com/wertretwetrertew-a11y/TikTok-Arena/archive/refs/heads/main.zip"

echo [1/5] Downloading repository directly from GitHub...
echo URL: %URL%
powershell -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop'; try { Invoke-WebRequest -Uri '%URL%' -OutFile '%ZIP%' -UseBasicParsing; Write-Host ('HTTP download OK. Size: ' + (Get-Item '%ZIP%').Length + ' bytes') } catch { Write-Host ('DOWNLOAD ERROR: ' + $_.Exception.Message) -ForegroundColor Red; if ($_.Exception.Response) { Write-Host ('HTTP STATUS: ' + [int]$_.Exception.Response.StatusCode) -ForegroundColor Red }; exit 1 }"
if errorlevel 1 (
  echo.
  echo The 404 is coming from the GitHub repository download itself.
  echo This launcher does NOT use raw.githubusercontent.com or the old updater.
  pause
  exit /b 1
)

echo [2/5] Extracting fresh repository...
powershell -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop'; if (Test-Path '%EXTRACT%') { Remove-Item '%EXTRACT%' -Recurse -Force }; Expand-Archive -LiteralPath '%ZIP%' -DestinationPath '%EXTRACT%' -Force"
if errorlevel 1 (
  echo ERROR: Could not extract the GitHub archive.
  pause
  exit /b 1
)

set "SOURCE=%EXTRACT%\TikTok-Arena-main"
if not exist "%SOURCE%\server.js" (
  echo ERROR: GitHub archive does not contain server.js.
  echo This proves the downloaded repository is not the expected project.
  pause
  exit /b 1
)

echo [3/5] Installing fresh game files...
robocopy "%SOURCE%" "%ROOT%" /E /XD ".git" "node_modules" /XF "Start-TikTok-Arena-FRESH-v3.bat" >nul
if errorlevel 8 (
  echo ERROR: Failed to copy fresh game files.
  pause
  exit /b 1
)

echo [4/5] Installing dependencies...
cd /d "%ROOT%"
call npm install
if errorlevel 1 (
  echo ERROR: npm install failed.
  pause
  exit /b 1
)

echo [5/5] Starting TikTok Arena...
for /f "tokens=5" %%P in ('netstat -ano ^| findstr ":3000"') do taskkill /PID %%P /F /T >nul 2>nul
start "TikTok Arena Server" cmd /c "cd /d ""%ROOT%"" && node server.js"

echo Waiting for server...
powershell -NoProfile -ExecutionPolicy Bypass -Command "$ok=$false; for($i=0;$i -lt 30;$i++){ Start-Sleep 1; try{$r=Invoke-WebRequest -Uri 'http://127.0.0.1:3000/api/health' -UseBasicParsing -TimeoutSec 2; if($r.StatusCode -eq 200){$ok=$true;break}}catch{}}; if(-not $ok){exit 1}"
if errorlevel 1 (
  echo ERROR: Server did not become ready on port 3000.
  echo Check tiktok-arena-server logs if present.
  pause
  exit /b 1
)

echo.
echo SUCCESS: TikTok Arena server is running.
start "" "http://localhost:3000"
exit /b 0
