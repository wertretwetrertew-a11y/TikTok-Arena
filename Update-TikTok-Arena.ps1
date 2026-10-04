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
  New-Item -ItemType Directory -Path $Temp | Out-Null

  $api = "https://api.github.com/repos/$Repo/commits/$Branch?cacheBust=$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
  Write-Host "Checking GitHub for updates..."
  $remote = Invoke-RestMethod -Uri $api -UseBasicParsing
  $remoteSha = $remote.sha

  $localShaFile = Join-Path $Root ".tiktok-arena-version"
  $localSha = ""
  if (Test-Path $localShaFile) { $localSha = (Get-Content $localShaFile -Raw).Trim() }

  if ($localSha -eq $remoteSha) {
    Write-Host "Already up to date."
  } else {
    Write-Host "New version found: $($remoteSha.Substring(0,7))"
    Write-Host "Downloading latest version..."

    $download = "https://github.com/$Repo/archive/refs/heads/$Branch.zip?cacheBust=$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
    Invoke-WebRequest -Uri $download -OutFile $Zip -UseBasicParsing

    Expand-Archive -Path $Zip -DestinationPath $Extract -Force
    $source = Join-Path $Extract "TikTok-Arena-$Branch"

    Write-Host "Updating game files..."

    Get-ChildItem -LiteralPath $source -Force | ForEach-Object {
      if ($_.Name -ne ".git" -and $_.Name -ne "node_modules") {
        Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $Root $_.Name) -Recurse -Force
      }
    }

    Set-Content -LiteralPath $localShaFile -Value $remoteSha -NoNewline
    Write-Host "Update installed."
  }

  # Always refresh the critical server entrypoint from the exact GitHub commit,
  # even when the local version marker incorrectly says the app is current.
  $serverUrl = "https://raw.githubusercontent.com/$Repo/$remoteSha/server.js?cacheBust=$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
  Invoke-WebRequest -Uri $serverUrl -OutFile (Join-Path $Root "server.js") -UseBasicParsing

  if (-not (Test-Path (Join-Path $Root "node_modules"))) {
    Write-Host "Installing dependencies..."
    Push-Location $Root
    npm install
    Pop-Location
  } elseif (Test-Path (Join-Path $Root "package.json")) {
    Write-Host "Checking dependencies..."
    Push-Location $Root
    npm install
    Pop-Location
  }

  Write-Host ""
  Write-Host "Stopping old TikTok Arena server..." -ForegroundColor Yellow
  try {
    $lines = netstat -ano | Select-String ":3000"
    foreach ($line in $lines) {
      $parts = ($line.ToString() -split "\s+") | Where-Object { $_ -ne "" }
      if ($parts.Count -ge 5 -and $parts[-1] -match "^\d+$") {
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

  $env:BUILD_VERSION = $remoteSha
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
      throw ("Node server stopped immediately. Exit code: " + $serverProcess.ExitCode + "[Environment]::NewLine[Environment]::NewLineSTDOUT:[Environment]::NewLine" + $outText + "[Environment]::NewLineSTDERR:[Environment]::NewLine" + $errText)
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
    throw ("TikTok Arena server did not become ready at http://127.0.0.1:3000." + "[Environment]::NewLine[Environment]::NewLineSTDOUT:[Environment]::NewLine" + $outText + "[Environment]::NewLineSTDERR:[Environment]::NewLine" + $errText)
  }

  Write-Host "Server is ready. Opening the updated game in your browser..."
  Start-Process "http://localhost:3000"
  Write-Host "TikTok Arena is running."
  Write-Host ""

  # Keep the updater window available long enough to show the result.
  Start-Sleep -Seconds 2
}
catch {
  Write-Host ""
  Write-Host "UPDATE/START ERROR:"
  Write-Host $_.Exception.Message -ForegroundColor Red
  Write-Host ""
  Write-Host "Check your internet connection and that Node.js is installed."
  Read-Host "Press Enter to close"
}
finally {
  if (Test-Path $Temp) { Remove-Item $Temp -Recurse -Force -ErrorAction SilentlyContinue }
}
