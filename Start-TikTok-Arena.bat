@echo off
cd /d "%~dp0"

echo TikTok Arena
echo.
if not exist node_modules (
  echo Installing dependencies...
  call npm install
  if errorlevel 1 (
    echo.
    echo npm install failed. Check that Node.js and npm are installed.
    pause
    exit /b 1
  )
)

echo.
echo Starting TikTok Arena at http://localhost:3000
echo Keep this window open while the game is running.
echo.
call npm start
pause
