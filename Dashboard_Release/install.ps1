# Mapsim Live Dashboard - one-line installer for Windows 10/11 (64-bit).
# Downloads the latest published build, verifies its SHA-256 checksum,
# installs it for the current user, creates a desktop shortcut and starts it.
#
#   irm https://raw.githubusercontent.com/MAPSIM-co/Mapsim_Assistance_Bot/main/Dashboard_Release/install.ps1 | iex
#
# Options when running the file directly:
#   -NoLaunch                   install only, do not start the dashboard
param(
    [switch]$NoLaunch
)

$ErrorActionPreference = 'Stop'

$Repo = 'MAPSIM-co/Mapsim_Assistance_Bot'
$FallbackVersion = 'dashboard-v1.0.0'
$Asset = 'MapsimDashboard-windows-x64.zip'

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

if (-not [Environment]::Is64BitOperatingSystem) {
    throw 'Mapsim Live Dashboard requires 64-bit Windows.'
}

$Version = $env:MAPSIM_DASHBOARD_VERSION
if (-not $Version) {
    try {
        $releases = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo/releases?per_page=50" -UseBasicParsing -Headers @{ 'User-Agent' = 'mapsim-installer' }
        $Version = ($releases |
            Where-Object { $_.tag_name -like 'dashboard-v*' -and -not $_.draft -and -not $_.prerelease } |
            Select-Object -First 1).tag_name
    } catch {
        $Version = $null
    }
    if (-not $Version) { $Version = $FallbackVersion }
}

$Base = "https://github.com/$Repo/releases/download/$Version"
$Dest = Join-Path $env:LOCALAPPDATA 'MapsimDashboard'
$Tmp = Join-Path $env:TEMP ('mapsim-' + [guid]::NewGuid().ToString('N'))

New-Item -ItemType Directory -Force -Path $Tmp | Out-Null

try {
    Write-Host 'Mapsim Live Dashboard installer'
    Write-Host "  version: $Version"

    $zip = Join-Path $Tmp $Asset
    $shaFile = Join-Path $Tmp "$Asset.sha256"

    Write-Host "downloading $Asset ..."
    Invoke-WebRequest -Uri "$Base/$Asset" -OutFile $zip -UseBasicParsing
    Invoke-WebRequest -Uri "$Base/$Asset.sha256" -OutFile $shaFile -UseBasicParsing

    Write-Host 'verifying checksum ...'
    $expected = ((Get-Content -Path $shaFile -TotalCount 1) -split '\s+')[0].ToLower()
    $actual = (Get-FileHash -Path $zip -Algorithm SHA256).Hash.ToLower()
    if ($expected -ne $actual) {
        throw "checksum mismatch: expected $expected, got $actual"
    }

    if (Test-Path $Dest) { Remove-Item -Recurse -Force $Dest }
    New-Item -ItemType Directory -Force -Path $Dest | Out-Null
    Expand-Archive -Path $zip -DestinationPath $Dest -Force

    $exe = Join-Path $Dest 'MapsimDashboard.exe'
    Unblock-File -Path $exe

    $desktop = [Environment]::GetFolderPath('Desktop')
    if ($desktop) {
        $shell = New-Object -ComObject WScript.Shell
        $shortcut = $shell.CreateShortcut((Join-Path $desktop 'Mapsim Live Dashboard.lnk'))
        $shortcut.TargetPath = $exe
        $shortcut.WorkingDirectory = $Dest
        $shortcut.Save()
    }

    Write-Host "installed: $exe"

    if ($NoLaunch) {
        Write-Host "run with: `"$exe`""
    } else {
        Write-Host 'starting the dashboard; your browser will open at http://127.0.0.1:8765/'
        Start-Process -FilePath $exe -WorkingDirectory $Dest
    }
} finally {
    Remove-Item -Recurse -Force $Tmp -ErrorAction SilentlyContinue
}
