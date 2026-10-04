$ErrorActionPreference = "Stop"

$Repo = "wertretwetrertew-a11y/TikTok-Arena"
$Branch = "main"
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$Temp = Join-Path $env:TEMP "TikTok-Arena-update"
$Zip = Join-Path $Temp "latest.zip"
$Extract = Join-Path $Temp "extract"

Write-Host "====================================="
Write-Host " TikTok Arena - updater"
Write-Host "====================================="
Write-Host ""

try {
  if (Test-Path $Temp) { Remove-Item $Temp -Recurse -Force -ErrorAction SilentlyContinue }
  New-Item -ItemType Directory -Path $Temp -Force | Out-Null

  # Do not use the GitHub commits API here. Some Windows/PowerShell
  # environments receive a 422 from that endpoint. The branch ZIP/raw
  # endpoints are enough to update and start the game reliably.
  $cacheBust = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
  $download = "https://github.com/$Repo/archive/refs/heads/$Branch.zip?cacheBust=$cacheBust"

  Write-Host "Downloading the latest game from GitHub..."
  Invoke-WebRequest -Uri $download -OutFile $Zip -UseBasicParsing

  Expand-Archive -Path $Zip -DestinationPath $Extract -Force
  $source = Join-Path $Extract "TikTok-Arena-$Branch"

  if (-not (Test-Path $source)) {
    throw "GitHub archive was downloaded, but the repository folder was not found."
  }

  Write-Host "Updating game files..."
  Get-ChildItem -LiteralPath $source -Force | ForEach-Object {
    if ($_.Name -ne ".git" -and $_.Name -ne "node_modules") {
      Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $Root $_.Name) -Recurse -Force
    }
  }

  # Always refresh the critical server entrypoint directly from GitHub.
  # This avoids stale/corrupted local server.js files.
  $serverUrl = "https://raw.githubusercontent.com/$Repo/$Branch/server.js?cacheBust=$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
  Invoke-WebRequest -Uri $serverUrl -OutFile (Join-Path $Root "server.js") -UseBasicParsing

  # Mark the local install as freshly updated without relying on the
  # GitHub commits API.
  $versionFile = Join-Path $Root ".tiktok-arena-version"
  Set-Content -LiteralPath $versionFile -Value ("github-main-" + $cacheBust) -NoNewline

  Write-Host "Update installed."

  Write-Host ""
  Write-Host "Installing/checking dependencies..."
  Push-Location $Root
  npm install
  if ($LASTEXITCODE -ne 0) {
    Pop-Location
    throw "npm install failed with exit code $LASTEXITCODE."
  }
  Pop-Location

  Write-Host ""
  Write-Host "Stopping old TikTok Arena server..." -ForegroundColor Yellow
  try {
    $lines = netstat -ano | Select-String ":3000"
    foreach ($line in $lines) {
      $parts = ($line.ToString() -split "s+") | Where-Object { $_ -ne "" }
      if ($parts.Count -ge 5 -and $parts[-1] -match "^d+$") {
        $pidToKill = [int]$parts[-1]
        if ($pidToKill -ne $PID) {
          taskkill /PID $pidToKill /F /T 2>$null | Out-Null
        }
      }
    }
  } catch {}
  Start-Sleep -Seconds 2

  Write-Host "Starting TikTok Arena server..."
  Write-Host "http://localhost:3000"
  Write-Host ""

  $env:BUILD_VERSION = "github-main"
  $serverLogOut = Join-Path $Root "tiktok-arena-server.out.log"
  $serverLogErr = Join-Path $Root "tiktok-arena-server.err.log"
  if (Test-Path $serverLogOut) { Remove-Item $serverLogOut -Force -ErrorAction SilentlyContinue }
  if (Test-Path $serverLogErr) { Remove-Item $serverLogErr -Force -ErrorAction SilentlyContinue }

  $serverProcess = Start-Process -FilePath "node.exe" -ArgumentList @("server.js") -WorkingDirectory $Root -WindowStyle Normal -RedirectStandardOutput $serverLogOut -RedirectStandardError $serverLogErr -PassThru

  Write-Host "Node process started. PID: $($serverProcess.Id)"
  Write-Host "Waiting for the server to become ready..."

  $ready = $false
  for ($i = 0; $i -lt 30; $i++) {
    Start-Sleep -Seconds 1

    if ($serverProcess.HasExited) {
      $outText = if (Test-Path $serverLogOut) { Get-Content $serverLogOut -Raw -ErrorAction SilentlyContinue } else { "" }
      $errText = if (Test-Path $serverLogErr) { Get-Content $serverLogErr -Raw -ErrorAction SilentlyContinue } else { "" }
      throw ("Node server stopped immediately. Exit code: " + $serverProcess.ExitCode + [Environment]::NewLine + [Environment]::NewLine + "STDOUT:" + [Environment]::NewLine + $outText + [Environment]::NewLine + "STDERR:" + [Environment]::NewLine + $errText)
    }

    try {
      $response = Invoke-WebRequest -Uri "http://127.0.0.1:3000/api/health" -UseBasicParsing -TimeoutSec 2
      if ($response.StatusCode -eq 200) {
        $ready = $true
        Write-Host "Health check OK."
        break
      }
    } catch {}
  }

  if (-not $ready) {
    $outText = if (Test-Path $serverLogOut) { Get-Content $serverLogOut -Raw -ErrorAction SilentlyContinue } else { "" }
    $errText = if (Test-Path $serverLogErr) { Get-Content $serverLogErr -Raw -ErrorAction SilentlyContinue } else { "" }
    throw ("TikTok Arena server did not become ready at http://127.0.0.1:3000." + [Environment]::NewLine + [Environment]::NewLine + "STDOUT:" + [Environment]::NewLine + $outText + [Environment]::NewLine + "STDERR:" + [Environment]::NewLine + $errText)
  }

  Write-Host "Server is ready. Opening the updated game in your browser..."
  Start-Process "http://localhost:3000"
  Write-Host "TikTok Arena is running."
  Write-Host ""
  Start-Sleep -Seconds 2
}
catch {
  Write-Host ""
  Write-Host "UPDATE/START ERROR:"
  Write-Host $_.Exception.Message -ForegroundColor Red
  Write-Host ""
  Write-Host "The updater could not download/start TikTok Arena."
  Read-Host "Press Enter to close"
}
finally {
  if (Test-Path $Temp) { Remove-Item $Temp -Recurse -Force -ErrorAction SilentlyContinue }
}
