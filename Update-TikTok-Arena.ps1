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
      if ($_.Name -ne ".git" -and $_.Name -ne "node_modules" -and $_.Name -ne "Start-TikTok-Arena.bat" -and $_.Name -ne "Update-TikTok-Arena.ps1") {
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
  Write-Host "Starting TikTok Arena..."
  Write-Host "http://localhost:3000"
  Write-Host ""

  Push-Location $Root
  npm start
  Pop-Location
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
