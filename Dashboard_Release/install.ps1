# Mapsim Live Dashboard - installer bootstrap for Windows 10/11 (64-bit).
#
# This file only downloads the Mapsim BOT control center (mapsim-menu.ps1) and
# runs it. All real work (install, start/stop, service, uninstall, menu) lives
# in mapsim-menu.ps1 so the interactive command 'Mapsim_BOT' behaves exactly
# like the installer.
#
# Install and start:
#   irm https://raw.githubusercontent.com/MAPSIM-co/Mapsim_Assistance_Bot/main/Dashboard_Release/install.ps1 | iex
#
# Options (passed through to the control center):
#   -Public          allow remote access: bind 0.0.0.0, sign in with the license
#   -Service         also install a background task that starts at logon
#   -RemoveService   stop and remove the background task (keeps the app)
#   -Uninstall       stop the app and the task, then remove everything
#   -NoLaunch        install only, do not start the app
#   -Version dashboard-vX.Y.Z   install a specific release
param(
  [switch]$Public,
  [switch]$Service,
  [switch]$NoLaunch,
  [switch]$RemoveService,
  [switch]$Uninstall,
  [string]$Version
)

$ErrorActionPreference = 'Stop'
$Repo = 'MAPSIM-co/Mapsim_Assistance_Bot'
$MenuUrl = "https://raw.githubusercontent.com/$Repo/main/Dashboard_Release/mapsim-menu.ps1"
$MenuPath = Join-Path $env:LOCALAPPDATA 'MapsimBOT\mapsim-menu.ps1'
$LegacyMenuPath = Join-Path $env:LOCALAPPDATA 'MapsimDashboard\mapsim-menu.ps1'

# For removal commands prefer the already-installed copy (works offline).
if (($RemoveService -or $Uninstall) -and -not (Test-Path $MenuPath) -and (Test-Path $LegacyMenuPath)) {
  $MenuPath = $LegacyMenuPath
}
if (($RemoveService -or $Uninstall) -and (Test-Path $MenuPath)) {
  Write-Host 'Mapsim BOT control center (installed copy)'
  $pass = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $MenuPath)
  if ($RemoveService) { $pass += '-RemoveService' }
  if ($Uninstall) { $pass += '-Uninstall' }
  & powershell @pass
  return
}

Write-Host 'Mapsim BOT control center bootstrap'
Write-Host '  downloading the control center ...'
$tmp = Join-Path ([IO.Path]::GetTempPath()) 'mapsim-menu.ps1'
# raw.githubusercontent.com can keep serving the file from before the newest push
# for a few minutes, and a query string does not help: measured here, ?v=<ticks>
# still returned the previous control center after 1.3.3 was published. A file
# addressed by commit is immutable, so the newest commit is asked for first and
# the download is pinned to it. Without an answer the plain main URL is used,
# which is what this bootstrap always did - a rate limit never blocks an install.
$menuUri = $MenuUrl
try {
  $headers = @{ 'User-Agent' = 'Mapsim-BOT'; 'Accept' = 'application/vnd.github.sha' }
  $raw = (Invoke-WebRequest -Uri "https://api.github.com/repos/$Repo/commits/main" -Headers $headers -TimeoutSec 10 -UseBasicParsing).Content
  if ($raw -is [byte[]]) { $raw = [Text.Encoding]::ASCII.GetString($raw) }
  $sha = ([string]$raw).Trim()
  if ($sha -match '^[0-9a-f]{40}$') {
    $menuUri = "https://raw.githubusercontent.com/$Repo/$sha/Dashboard_Release/mapsim-menu.ps1"
  }
} catch { }
Invoke-WebRequest -Uri $menuUri -OutFile $tmp -TimeoutSec 60 -UseBasicParsing

$pass = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $tmp, '-Bootstrap')
if ($Public) { $pass += '-Public' }
if ($Service) { $pass += '-Service' }
if ($NoLaunch) { $pass += '-NoLaunch' }
if ($Version) { $pass += '-Version'; $pass += $Version }
& powershell @pass
