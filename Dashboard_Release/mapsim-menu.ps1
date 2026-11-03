# Mapsim BOT control center - interactive management menu for Windows.
#
# Single source of truth for installing, starting, stopping, servicing and
# removing the Mapsim Live Dashboard. install.ps1 only downloads this file
# and runs it.
#
# Usage:
#   Mapsim_BOT                  open the interactive menu
#   Mapsim_BOT -Status          one-line status
#   .\mapsim-menu.ps1 -Bootstrap [-Public] [-Service] [-NoLaunch] [-Version X]
param(
  [switch]$Bootstrap,
  [switch]$Public,
  [switch]$Service,
  [switch]$NoLaunch,
  [switch]$Status,
  [switch]$Stop,
  [switch]$RemoveService,
  [switch]$Uninstall,
  [string]$Version,
  [string]$Password
)

$ErrorActionPreference = 'Stop'
$Repo = 'MAPSIM-co/Mapsim_Assistance_Bot'
$FallbackVersion = 'dashboard-v1.0.1'
$AppDir = Join-Path $env:LOCALAPPDATA 'MapsimDashboard'
$Binary = Join-Path $AppDir 'MapsimDashboard.exe'
$MenuPath = Join-Path $AppDir 'mapsim-menu.ps1'
$ShimPath = Join-Path $AppDir 'Mapsim_BOT.cmd'
$ConfigDir = Join-Path $env:APPDATA 'MapsimDashboard'
$EnvFile = Join-Path $ConfigDir 'dashboard-access.env'
$PidFile = Join-Path $ConfigDir 'dashboard.pid'
$LogFile = Join-Path $ConfigDir 'dashboard.log'
$TaskName = 'MapsimDashboard'

function Test-Installed { Test-Path $Binary }

function Get-CurrentBind {
  if (Test-Path $EnvFile) {
    $line = Get-Content $EnvFile | Where-Object { $_ -match '^MAPSIM_DASHBOARD_BIND=' } | Select-Object -Last 1
    if ($line) { return $line -replace '^MAPSIM_DASHBOARD_BIND=', '' }
  }
  return '127.0.0.1'
}

function Get-CurrentPassword {
  if (Test-Path $EnvFile) {
    $line = Get-Content $EnvFile | Where-Object { $_ -match '^MAPSIM_DASHBOARD_PASSWORD=' } | Select-Object -Last 1
    if ($line) { return $line -replace '^MAPSIM_DASHBOARD_PASSWORD=', '' }
  }
  return ''
}

function Write-EnvFile([string]$Bind, [string]$Pwd) {
  New-Item -ItemType Directory -Force $ConfigDir | Out-Null
  @("MAPSIM_DASHBOARD_BIND=$Bind", "MAPSIM_DASHBOARD_PASSWORD=$Pwd") | Set-Content $EnvFile -Encoding ASCII
}

function New-RandomPassword {
  $bytes = New-Object byte[] 16
  [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
  ($bytes | ForEach-Object { $_.ToString('x2') }) -join ''
}

function Get-DashboardPid {
  if (Test-Path $PidFile) {
    $pidValue = (Get-Content $PidFile -ErrorAction SilentlyContinue | Select-Object -First 1)
    if ($pidValue) {
      $proc = Get-Process -Id $pidValue -ErrorAction SilentlyContinue
      if ($proc) { return [int]$pidValue }
    }
  }
  $mine = Get-Process | Where-Object { $_.Path -eq $Binary } | Select-Object -First 1
  if ($mine) { return $mine.Id }
  return $null
}

function Test-PortListening([int]$Port) {
  $conn = Get-NetTCPConnection -State Listen -LocalPort $Port -ErrorAction SilentlyContinue
  return [bool]$conn
}

function Get-HttpCode([int]$Port) {
  try {
    $resp = Invoke-WebRequest -Uri "http://127.0.0.1:$Port/healthz" -TimeoutSec 2 -UseBasicParsing
    return [int]$resp.StatusCode
  } catch {
    if ($_.Exception.Response) { return [int]$_.Exception.Response.StatusCode.value__ }
    return 000
  }
}

function Test-DashboardUp([int]$Port) {
  $code = Get-HttpCode $Port
  return ($code -eq 200 -or $code -eq 401)
}

function Write-Shim {
  $cmd = "@echo off`r`npowershell -NoProfile -ExecutionPolicy Bypass -File `"$MenuPath`" %*"
  Set-Content -Path $ShimPath -Value $cmd -Encoding ASCII
  $desktop = [Environment]::GetFolderPath('Desktop')
  $shortcut = Join-Path $desktop 'Mapsim BOT.lnk'
  $wsh = New-Object -ComObject WScript.Shell
  $lnk = $wsh.CreateShortcut($shortcut)
  $lnk.TargetPath = $ShimPath
  $lnk.IconLocation = "$Binary,0"
  $lnk.Save()
}

function Install-Dashboard {
  if (-not [Environment]::Is64BitOperatingSystem) { throw 'Windows x64 is required.' }
  $ver = $Version
  if (-not $ver) {
    try {
      $rel = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo/releases?per_page=50" -TimeoutSec 15
      $tag = ($rel | Where-Object { $_.tag_name -like 'dashboard-v*' } | Select-Object -First 1).tag_name
      if ($tag) { $ver = $tag }
    } catch { }
  }
  if (-not $ver) { $ver = $FallbackVersion }
  $asset = 'MapsimDashboard-windows-x64.zip'
  $base = "https://github.com/$Repo/releases/download/$ver"
  Write-Host "installing $ver ($asset) ..."
  $tmp = Join-Path ([IO.Path]::GetTempPath()) ([IO.Path]::GetRandomFileName())
  New-Item -ItemType Directory -Force $tmp | Out-Null
  try {
    Invoke-WebRequest -Uri "$base/$asset" -OutFile (Join-Path $tmp $asset) -TimeoutSec 600
    Invoke-WebRequest -Uri "$base/$asset.sha256" -OutFile (Join-Path $tmp "$asset.sha256") -TimeoutSec 60
    $expected = ((Get-Content (Join-Path $tmp "$asset.sha256")) -split '\s+')[0].ToLower()
    $actual = (Get-FileHash (Join-Path $tmp $asset) -Algorithm SHA256).Hash.ToLower()
    if ($expected -ne $actual) { throw "checksum mismatch for $asset" }
    Stop-Dashboard | Out-Null
    if (Test-Path $AppDir) { Remove-Item -Recurse -Force $AppDir }
    New-Item -ItemType Directory -Force $AppDir | Out-Null
    Expand-Archive -Path (Join-Path $tmp $asset) -DestinationPath $AppDir -Force
    Unblock-File -Path $Binary -ErrorAction SilentlyContinue
  } finally {
    Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
  }
  Install-Self
  Write-Shim
  Write-Host "installed: $AppDir"
}

function Install-Self {
  New-Item -ItemType Directory -Force $AppDir | Out-Null
  Copy-Item -Force $PSCommandPath $MenuPath
}

function Install-Service {
  $action = New-ScheduledTaskAction -Execute $Binary -Argument '--no-browser' -WorkingDirectory $AppDir
  $trigger = New-ScheduledTaskTrigger -AtLogOn
  $principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel LeastPrivilege
  $settings = New-ScheduledTaskSettingsSet -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1) -AllowStartIfOnBatteries
  Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null
}

function Remove-Service {
  Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
}

function Test-ServiceInstalled {
  return [bool](Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue)
}

function Stop-Dashboard {
  $id = Get-DashboardPid
  if (-not $id) {
    Write-Host 'the dashboard is not running.'
    if (Test-Path $PidFile) { Remove-Item $PidFile -ErrorAction SilentlyContinue }
    return
  }
  Stop-Process -Id $id -Force -ErrorAction SilentlyContinue
  if (Test-Path $PidFile) { Remove-Item $PidFile -ErrorAction SilentlyContinue }
  Write-Host "dashboard stopped (pid $id)."
}

function Start-Dashboard([string]$Bind, [string]$Pwd, [int]$Port) {
  if (Get-DashboardPid) {
    Write-Host "the dashboard is already running (pid $(Get-DashboardPid))."
    return
  }
  if (Test-PortListening $Port) {
    Write-Host "error: port $Port is already used by another program." -ForegroundColor Red
    return
  }
  Write-EnvFile $Bind $Pwd
  $env:MAPSIM_DASHBOARD_BIND = $Bind
  $env:MAPSIM_DASHBOARD_PASSWORD = $Pwd
  New-Item -ItemType Directory -Force $ConfigDir | Out-Null
  $proc = Start-Process -FilePath $Binary -ArgumentList '--no-browser', "--port", "$Port" -WorkingDirectory $AppDir -WindowStyle Hidden -RedirectStandardOutput $LogFile -RedirectStandardError "$LogFile.err" -PassThru
  Set-Content $PidFile $proc.Id
  for ($i = 0; $i -lt 20; $i++) {
    if ((Get-DashboardPid) -and (Test-DashboardUp $Port)) {
      Write-Host 'dashboard is up:'
      Write-Host "  local   : http://127.0.0.1:$Port/"
      if ($Bind -eq '0.0.0.0') {
        Write-Host "  remote  : http://<this-pc-ip>:$Port/ (open the port in Windows Firewall)"
        Write-Host "  access  : user 'mapsim' / password '$Pwd'"
      }
      return
    }
    Start-Sleep -Seconds 1
  }
  Write-Host "error: the dashboard did not answer on port $Port; see $LogFile" -ForegroundColor Red
}

function Show-Status {
  Write-Host "system    : Windows x64"
  if (Test-Installed) { Write-Host "app       : installed ($AppDir)" } else { Write-Host 'app       : not installed' }
  $id = Get-DashboardPid
  if ($id) { Write-Host "dashboard : RUNNING (pid $id)" } else { Write-Host 'dashboard : stopped' }
  if (Test-DashboardUp 8765) { Write-Host "port 8765 : dashboard answering (HTTP $(Get-HttpCode 8765))" }
  elseif (Test-PortListening 8765) { Write-Host 'port 8765 : busy (another program)' }
  else { Write-Host 'port 8765 : free' }
  Write-Host "bind      : $(Get-CurrentBind)"
  if (Test-ServiceInstalled) { Write-Host 'service   : installed (auto-start at logon)' } else { Write-Host 'service   : not installed' }
}

function Read-Default([string]$Prompt, [string]$Default) {
  $a = Read-Host "$Prompt [$Default]"
  if ([string]::IsNullOrWhiteSpace($a)) { return $Default }
  return $a
}

function Read-Password {
  $existing = Get-CurrentPassword
  while ($true) {
    if ($existing) { $p1 = Read-Host 'password (press Enter to keep the current one)' }
    else { $p1 = Read-Host 'password (min 8 characters)' }
    if ([string]::IsNullOrWhiteSpace($p1) -and $existing) { return $existing }
    if ([string]::IsNullOrWhiteSpace($p1)) {
      $generated = New-RandomPassword
      Write-Host "generated password: $generated"
      return $generated
    }
    if ($p1.Length -lt 8) { Write-Host 'too short - at least 8 characters.'; continue }
    $p2 = Read-Host 'repeat password'
    if ($p1 -ne $p2) { Write-Host 'passwords do not match, try again.'; continue }
    return $p1
  }
}

function Choose-Port {
  $p = [int](Read-Default 'port' '8765')
  while (Test-PortListening $p) {
    Write-Host "port $p is busy."
    $p = [int](Read-Default 'choose another port' "$($p + 1)")
  }
  return $p
}

function Show-Menu {
  while ($true) {
    Write-Host ''
    Write-Host '=== Mapsim BOT control center ==='
    $id = Get-DashboardPid
    if ($id) { $st = "running (pid $id)" } else { $st = 'stopped' }
    if (Test-Installed) { $app = 'installed' } else { $app = 'not installed' }
    Write-Host "dashboard: $st   app: $app"
    Write-Host ''
    Write-Host '  1) Status'
    Write-Host '  2) Start dashboard'
    Write-Host '  3) Stop dashboard'
    Write-Host '  4) Install / update dashboard'
    Write-Host '  5) Enable auto-start service'
    Write-Host '  6) Remove auto-start service'
    Write-Host '  7) Access mode / password'
    Write-Host '  8) Uninstall everything'
    Write-Host '  9) Exit'
    Write-Host ''
    $c = Read-Host 'choose 1-9'
    switch ($c) {
      '1' { Show-Status }
      '2' {
        if (-not (Test-Installed)) { Write-Host 'not installed yet - use menu 4.'; continue }
        Write-Host 'how should the dashboard be reachable?'
        Write-Host '  1) local only   (this computer, http://127.0.0.1)'
        Write-Host '  2) internet     (any device, protected by a password)'
        $m = Read-Default 'choose 1 or 2' '1'
        $port = Choose-Port
        if ($m -eq '2') {
          $pwd = Read-Password
          Start-Dashboard '0.0.0.0' $pwd $port
        } else {
          Start-Dashboard '127.0.0.1' (Get-CurrentPassword) $port
        }
      }
      '3' { Stop-Dashboard }
      '4' { Install-Dashboard }
      '5' {
        if (-not (Test-Installed)) { Write-Host 'not installed yet - use menu 4.'; continue }
        Install-Service
        Write-Host 'service installed: the dashboard now starts automatically at logon.'
      }
      '6' {
        if (-not (Test-ServiceInstalled)) { Write-Host 'no service is installed.'; continue }
        $a = Read-Default 'remove the auto-start service? (y/n)' 'y'
        if ($a -eq 'y') { Remove-Service; Write-Host 'service removed (the app itself stays installed).' }
      }
      '7' {
        if (-not (Test-Installed)) { Write-Host 'not installed yet - use menu 4.'; continue }
        Write-Host "current bind: $(Get-CurrentBind)"
        Write-Host '  1) local only'
        Write-Host '  2) internet (password required)'
        $m = Read-Default 'choose 1 or 2' '1'
        $wasRunning = [bool](Get-DashboardPid)
        if ($m -eq '2') {
          $pwd = Read-Password
          Write-EnvFile '0.0.0.0' $pwd
          Write-Host "saved. access: user 'mapsim' / password '$pwd'"
        } else {
          if (-not (Get-CurrentPassword)) { Write-EnvFile '127.0.0.1' (New-RandomPassword) }
          else { Write-EnvFile '127.0.0.1' (Get-CurrentPassword) }
          Write-Host 'saved: local only.'
        }
        if ($wasRunning) {
          $a = Read-Default 'restart the dashboard now? (y/n)' 'y'
          if ($a -eq 'y') {
            Stop-Dashboard
            $port = Choose-Port
            Start-Dashboard (Get-CurrentBind) (Get-CurrentPassword) $port
          }
        }
      }
      '8' {
        Write-Host 'this removes the dashboard app, config, service, task and shortcuts.'
        Write-Host 'nothing is changed in MetaTrader 5 or in the Expert Advisor.'
        $a = Read-Default 'are you sure? type y to confirm' 'n'
        if ($a -eq 'y') { Uninstall-Everything } else { Write-Host 'cancelled.' }
      }
      '9' { Write-Host 'bye.'; return }
      default { Write-Host 'please choose 1-9.' }
    }
  }
}

function Uninstall-Everything {
  Remove-Service
  Stop-Dashboard | Out-Null
  if (Test-Path $AppDir) { Remove-Item -Recurse -Force $AppDir }
  if (Test-Path $ConfigDir) { Remove-Item -Recurse -Force $ConfigDir }
  $desktop = [Environment]::GetFolderPath('Desktop')
  Remove-Item (Join-Path $desktop 'Mapsim BOT.lnk') -ErrorAction SilentlyContinue
  Remove-Item (Join-Path $desktop 'MapsimDashboard.lnk') -ErrorAction SilentlyContinue
  Remove-Item (Join-Path $desktop 'Mapsim Live Dashboard.lnk') -ErrorAction SilentlyContinue
  Write-Host 'Mapsim Live Dashboard removed completely (MT5 and the EA were not touched).'
}

# ------------------------------------------------------------------ entrypoint

if ($Uninstall) { Uninstall-Everything; return }
if ($RemoveService) { Remove-Service; Write-Host 'service removed.'; return }
if ($Stop) { Stop-Dashboard; return }
if ($Status) { Show-Status; return }

if ($Bootstrap) {
  if (-not (Test-Installed)) { Install-Dashboard }
  else { Install-Self; Write-Shim }
  if ($Public) {
    $pwd = $Password
    if (-not $pwd) { $pwd = $env:MAPSIM_DASHBOARD_PASSWORD }
    if (-not $pwd) { $pwd = New-RandomPassword }
    Write-EnvFile '0.0.0.0' $pwd
    Write-Host 'public access:'
    Write-Host "  user     : mapsim"
    Write-Host "  password : $pwd"
    Write-Host "  saved in : $EnvFile"
    try {
      New-NetFirewallRule -DisplayName 'Mapsim Dashboard' -Direction Inbound -Protocol TCP -LocalPort 8765 -Action Allow -ErrorAction Stop | Out-Null
      Write-Host 'firewall  : inbound rule for port 8765 added'
    } catch {
      Write-Host 'firewall  : could not add a rule automatically - allow port 8765 manually if needed'
    }
  }
  if ($Service) {
    Install-Service
    Write-Host 'service installed: starts automatically at logon.'
  } elseif (-not $NoLaunch) {
    if (-not (Get-DashboardPid)) {
      Write-Host ''
      Write-Host 'starting the dashboard (local mode) ...'
      $port = 8765
      if ((Test-PortListening $port) -and -not (Test-DashboardUp $port)) {
        $port = 8766
        Write-Host "note: port 8765 is busy, using $port."
      }
      $pwd = Get-CurrentPassword
      if (-not $pwd) { $pwd = New-RandomPassword }
      Start-Dashboard (Get-CurrentBind) $pwd $port
    } else {
      Write-Host "the dashboard is already running (pid $(Get-DashboardPid))."
    }
  }
  Write-Host ''
  Write-Host "done. From now on manage everything with:  $ShimPath"
  return
}

Show-Menu
