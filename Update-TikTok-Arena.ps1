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

  $api = "https://api.github.com/repos/$Repo/commits/$Branch"
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

    $download = "https://github.com/$Repo/archive/refs/heads/$Branch.zip"
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
    $connections = Get-NetTCPConnection -LocalPort 3000 -State Listen -ErrorAction SilentlyContinue
    foreach ($connection in $connections) {
      if ($connection.OwningProcess -and $connection.OwningProcess -ne $PID) {
        Stop-Process -Id $connection.OwningProcess -Force -ErrorAction SilentlyContinue
      }
    }
  } catch {}
  Start-Sleep -Seconds 1

  Write-Host "Starting TikTok Arena server..."
  Write-Host "http://localhost:3000"
  Write-Host ""

  $serverProcess = Start-Process -FilePath "cmd.exe" -ArgumentList "/c","set BUILD_VERSION=$remoteSha&& npm start" -WorkingDirectory $Root -WindowStyle Normal -PassThru

  Write-Host "Waiting for the server to become ready..."
  $ready = $false
  for ($i = 0; $i -lt 30; $i++) {
    Start-Sleep -Seconds 1
    try {
      $response = Invoke-WebRequest -Uri "http://localhost:3000/api/health" -UseBasicParsing -TimeoutSec 2
      if ($response.StatusCode -eq 200) {
        $ready = $true
        break
      }
    } catch {}
  }

  if (-not $ready) {
    throw "TikTok Arena server did not become ready at http://localhost:3000"
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
