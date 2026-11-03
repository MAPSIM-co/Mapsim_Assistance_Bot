# Mapsim Live Dashboard - installer / service manager for Windows 10/11 (64-bit).
#
# Install and start:
#   irm https://raw.githubusercontent.com/MAPSIM-co/Mapsim_Assistance_Bot/main/Dashboard_Release/install.ps1 | iex
#
# Options (run the file directly to pass options, e.g. .\install.ps1 -Public):
#   -Public          allow remote access: bind 0.0.0.0 with a generated password
#   -Service         also install a scheduled task that starts the dashboard at logon
#   -RemoveService   stop and remove the scheduled task (keeps the app)
#   -Uninstall       stop the app and the task, then remove everything
#   -NoLaunch        install only, do not start the app
param(
    [switch]$Public,
    [switch]$Service,
    [switch]$RemoveService,
    [switch]$Uninstall,
    [switch]$NoLaunch
)

$ErrorActionPreference = 'Stop'

$Repo = 'MAPSIM-co/Mapsim_Assistance_Bot'
$FallbackVersion = 'dashboard-v1.0.1'
$Asset = 'MapsimDashboard-windows-x64.zip'
$TaskName = 'MapsimDashboard'
$AppName = 'MapsimDashboard'
$WrapperName = 'run-dashboard.cmd'
$AccessEnvName = 'dashboard-access.env'

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

if (-not [Environment]::Is64BitOperatingSystem) {
    throw 'Mapsim Live Dashboard requires 64-bit Windows.'
}

$Dest = Join-Path $env:LOCALAPPDATA 'MapsimDashboard'
$DataDir = Join-Path $env:APPDATA 'MapsimDashboard'
$WrapperCmd = Join-Path $Dest $WrapperName
$AccessEnv = Join-Path $Dest $AccessEnvName

function New-RandomPassword {
    $bytes = New-Object byte[] 16
    [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
    ([System.BitConverter]::ToString($bytes) -replace '-', '').ToLower()
}

function Write-AccessEnv {
    if ($env:MAPSIM_DASHBOARD_PASSWORD) {
        $script:AccessPassword = $env:MAPSIM_DASHBOARD_PASSWORD
    } else {
        $script:AccessPassword = New-RandomPassword
    }
    @(
        'MAPSIM_DASHBOARD_BIND=0.0.0.0'
        "MAPSIM_DASHBOARD_PASSWORD=$script:AccessPassword"
    ) | Set-Content -Path $AccessEnv -Encoding ASCII
}

function Write-WrapperCmd {
    $lines = @(
        '@echo off',
        'set "BIND=127.0.0.1"',
        "if exist `"%~dp0$AccessEnvName`" for /f `"usebackq tokens=1,* delims==`" %%a in (`"%~dp0$AccessEnvName`") do set `"%%a=%%b`"",
        'if defined MAPSIM_DASHBOARD_BIND set "BIND=%MAPSIM_DASHBOARD_BIND%"',
        "`"%~dp0MapsimDashboard.exe`" --bind %BIND% %*"
    )
    $lines | Set-Content -Path $WrapperCmd -Encoding ASCII
}

function Remove-DashboardService {
    $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if ($task) {
        Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
        Write-Host 'service removed.'
    } else {
        Write-Host 'note: no service installed.'
    }
}

function Install-DashboardService {
    $action = New-ScheduledTaskAction -Execute $WrapperCmd -WorkingDirectory $Dest
    $trigger = New-ScheduledTaskTrigger -AtLogOn -User ([System.Security.Principal.WindowsIdentity]::GetCurrent().Name)
    $settings = New-ScheduledTaskSettingsSet -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)
    Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Settings $settings -Force | Out-Null
    Start-ScheduledTask -TaskName $TaskName
    Write-Host 'service installed: starts automatically at logon.'
}

function Uninstall-Dashboard {
    Remove-DashboardService
    Get-Process -Name $AppName -ErrorAction SilentlyContinue | Stop-Process -Force
    if (Test-Path $Dest) { Remove-Item -Recurse -Force $Dest }
    if (Test-Path $DataDir) { Remove-Item -Recurse -Force $DataDir }
    $desktop = [Environment]::GetFolderPath('Desktop')
    if ($desktop) {
        $shortcut = Join-Path $desktop 'Mapsim Live Dashboard.lnk'
        if (Test-Path $shortcut) { Remove-Item -Force $shortcut }
    }
    Write-Host 'Mapsim Live Dashboard removed completely.'
}

if ($Uninstall) {
    Uninstall-Dashboard
    return
}

if ($RemoveService) {
    Remove-DashboardService
    return
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
$Tmp = Join-Path $env:TEMP ('mapsim-' + [guid]::NewGuid().ToString('N'))

New-Item -ItemType Directory -Force -Path $Tmp | Out-Null

try {
    Write-Host 'Mapsim Live Dashboard installer'
    Write-Host "  version: $Version"
    if ($Public) { Write-Host '  mode   : public (bind 0.0.0.0, password required)' }
    if ($Service) { Write-Host '  service: will install and enable at logon' }

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

    $script:AccessPassword = ''
    if ($Public) {
        Write-AccessEnv
        Write-Host 'public access:'
        Write-Host '  user     : mapsim'
        Write-Host "  password : $script:AccessPassword"
        Write-Host "  saved in : $AccessEnv"
        $ip = (Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
            Where-Object { $_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.254.*' } |
            Select-Object -First 1).IPAddress
        if ($ip) {
            Write-Host "  remote   : http://$ip`:8765/ (open port 8765 in your firewall first)"
        } else {
            Write-Host '  remote   : http://<this-pc-ip>:8765/ (open port 8765 in your firewall first)'
        }
        try {
            New-NetFirewallRule -DisplayName 'Mapsim Live Dashboard' -Direction Inbound -Protocol TCP -LocalPort 8765 -Action Allow -ErrorAction Stop | Out-Null
            Write-Host '  firewall : inbound rule for port 8765 added'
        } catch {
            Write-Host '  firewall : could not add a rule (run PowerShell as Administrator to allow inbound port 8765)'
        }
    }

    Write-WrapperCmd

    $desktop = [Environment]::GetFolderPath('Desktop')
    if ($desktop) {
        $shell = New-Object -ComObject WScript.Shell
        $shortcut = $shell.CreateShortcut((Join-Path $desktop 'Mapsim Live Dashboard.lnk'))
        $shortcut.TargetPath = $WrapperCmd
        $shortcut.WorkingDirectory = $Dest
        $shortcut.Save()
    }

    Write-Host "installed: $exe"
    Write-Host "command  : $WrapperCmd"

    if ($Service) {
        Install-DashboardService
    } elseif (-not $NoLaunch) {
        Write-Host 'starting the dashboard; your browser will open at http://127.0.0.1:8765/'
        Start-Process -FilePath $WrapperCmd -WorkingDirectory $Dest
    } else {
        Write-Host "run with: `"$WrapperCmd`""
    }
} finally {
    Remove-Item -Recurse -Force $Tmp -ErrorAction SilentlyContinue
}
