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
#   -Public          allow remote access: bind 0.0.0.0 with a generated password
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
$MenuPath = Join-Path $env:LOCALAPPDATA 'MapsimDashboard\mapsim-menu.ps1'

# For removal commands prefer the already-installed copy (works offline).
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
Invoke-WebRequest -Uri $MenuUrl -OutFile $tmp -TimeoutSec 60 -UseBasicParsing

$pass = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $tmp, '-Bootstrap')
if ($Public) { $pass += '-Public' }
if ($Service) { $pass += '-Service' }
if ($NoLaunch) { $pass += '-NoLaunch' }
if ($Version) { $pass += '-Version'; $pass += $Version }
& powershell @pass
