$ErrorActionPreference = "Stop"

$Repo = "wertretwetrertew-a11y/TikTok-Arena"
$Branch = "main"
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$Temp = Join-Path $env:TEMP "TikTok-Arena-update-fresh"

Write-Host "====================================="
Write-Host " TikTok Arena - updater v5"
Write-Host "====================================="
Write-Host ""

try {
  if (Test-Path $Temp) { Remove-Item $Temp -Recurse -Force -ErrorAction SilentlyContinue }
  New-Item -ItemType Directory -Path $Temp -Force | Out-Null

  $headers = @{
    "User-Agent" = "TikTok-Arena-Updater"
    "Accept" = "application/vnd.github+json"
    "Cache-Control" = "no-cache"
  }

  $treeUrl = "https://api.github.com/repos/$Repo/git/trees/$Branch?recursive=1"

  Write-Host "Reading the latest file list from GitHub API..."
  $treeResponse = Invoke-RestMethod -Uri $treeUrl -Headers $headers -Method Get

  if (-not $treeResponse.tree) {
    throw "GitHub returned an empty repository tree."
  }

  if ($treeResponse.truncated -eq $true) {
    throw "GitHub repository tree is truncated; refusing to perform an incomplete update."
  }

  $files = @($treeResponse.tree | Where-Object {
    $_.type -eq "blob" -and
    $_.path -notlike ".git/*" -and
    $_.path -ne ".git"
  })

  Write-Host ("Found " + $files.Count + " repository files.")
  Write-Host "Downloading the latest game files through GitHub API..."

  foreach ($file in $files) {
    $relativePath = [string]$file.path
    $target = Join-Path $Root $relativePath
    $parent = Split-Path -Parent $target

    if ($parent -and -not (Test-Path $parent)) {
      New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    if (-not $file.sha) {
      throw "GitHub did not return a blob SHA for $relativePath."
    }

    $blobUrl = "https://api.github.com/repos/$Repo/git/blobs/$($file.sha)"
    $blob = Invoke-RestMethod -Uri $blobUrl -Headers $headers -Method Get

    if ($blob.encoding -ne "base64" -or -not $blob.content) {
      throw "GitHub returned an invalid blob response for $relativePath."
    }

    $bytes = [Convert]::FromBase64String(($blob.content -replace "\s", ""))
    [IO.File]::WriteAllBytes($target, $bytes)
  }

  Set-Content -LiteralPath (Join-Path $Root ".tiktok-arena-version") -Value ("github-main-" + [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()) -NoNewline

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
      $parts = [regex]::Split($line.ToString().Trim(), '\s+') | Where-Object { $_ -ne "" }
      if ($parts.Count -ge 5 -and $parts[-1] -match '^\d+$') {
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
  Remove-Item $serverLogOut,$serverLogErr -Force -ErrorAction SilentlyContinue

  $serverProcess = Start-Process -FilePath "node.exe" -ArgumentList @("server.js") -WorkingDirectory $Root -WindowStyle Normal -RedirectStandardOutput $serverLogOut -RedirectStandardError $serverLogErr -PassThru

  Write-Host "Node process started. PID: $($serverProcess.Id)"
  Write-Host "Waiting for the server to become ready..."

  $ready = $false
  for ($i = 0; $i -lt 30; $i++) {
    Start-Sleep -Seconds 1

    if ($serverProcess.HasExited) {
      $outText = if (Test-Path $serverLogOut) { Get-Content $serverLogOut -Raw -ErrorAction SilentlyContinue } else { "" }
      $errText = if (Test-Path $serverLogErr) { Get-Content $serverLogErr -Raw -ErrorAction SilentlyContinue } else { "" }
      throw ("Node server stopped immediately. Exit code: " + $serverProcess.ExitCode + [Environment]::NewLine + "STDOUT:" + [Environment]::NewLine + $outText + [Environment]::NewLine + "STDERR:" + [Environment]::NewLine + $errText)
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
    throw ("TikTok Arena server did not become ready at http://127.0.0.1:3000." + [Environment]::NewLine + "STDOUT:" + [Environment]::NewLine + $outText + [Environment]::NewLine + "STDERR:" + [Environment]::NewLine + $errText)
  }

  Write-Host "Server is ready. Opening the updated game in your browser..."
  Start-Process "http://localhost:3000"
  Write-Host "TikTok Arena is running."
  Start-Sleep -Seconds 2
}
catch {
  Write-Host ""
  Write-Host "UPDATE/START ERROR:"
  Write-Host $_.Exception.Message -ForegroundColor Red
  Write-Host ""
  Read-Host "Press Enter to close"
}
finally {
  if (Test-Path $Temp) { Remove-Item $Temp -Recurse -Force -ErrorAction SilentlyContinue }
}
