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
  [string]$Version
)

$ErrorActionPreference = 'Stop'
$Repo = 'MAPSIM-co/Mapsim_Assistance_Bot'
$FallbackVersion = 'dashboard-v1.0.5'
$AppDir = Join-Path $env:LOCALAPPDATA 'MapsimDashboard'
$Binary = Join-Path $AppDir 'MapsimDashboard.exe'
$MenuPath = Join-Path $AppDir 'mapsim-menu.ps1'
$ShimPath = Join-Path $AppDir 'Mapsim_BOT.cmd'
$ConfigDir = Join-Path $env:APPDATA 'MapsimDashboard'
$EnvFile = Join-Path $ConfigDir 'dashboard-access.env'
$PidFile = Join-Path $ConfigDir 'dashboard.pid'
$PortFile = Join-Path $ConfigDir 'dashboard.port'
$LogFile = Join-Path $ConfigDir 'dashboard.log'
$LogMaxBytes = 262144
$LogKeepLines = 200
$TaskName = 'MapsimDashboard'
$LicenseDir = Join-Path ([Environment]::GetFolderPath('UserProfile')) '.mapsim'
$LicenseFile = Join-Path $LicenseDir 'dashboard.license'
$LicenseAuthFile = Join-Path $LicenseDir 'dashboard.auth'
$VersionFile = Join-Path $ConfigDir 'dashboard.version'
$UpdatePolicyFile = Join-Path $ConfigDir 'update-policy'
$UpdateCacheFile = Join-Path $ConfigDir 'update-cache.json'
$UpdateCacheTtl = 21600
$script:UpdateInstalled = ''
$script:UpdateLatest = ''
$script:UpdateAvailable = $false

function Test-Installed { Test-Path $Binary }

function Get-CurrentBind {
  if (Test-Path $EnvFile) {
    $line = Get-Content $EnvFile | Where-Object { $_ -match '^MAPSIM_DASHBOARD_BIND=' } | Select-Object -Last 1
    if ($line) { return $line -replace '^MAPSIM_DASHBOARD_BIND=', '' }
  }
  return '127.0.0.1'
}

function Get-CurrentPort {
  if (Test-Path $PortFile) {
    $p = (Get-Content $PortFile | Select-Object -Last 1).Trim()
    if ($p -match '^\d+$') { return [int]$p }
  }
  return 8765
}

function Write-EnvFile([string]$Bind) {
  New-Item -ItemType Directory -Force $ConfigDir | Out-Null
  @("MAPSIM_DASHBOARD_BIND=$Bind") | Set-Content $EnvFile -Encoding ASCII
}

# ---------------------------------------------------------------- license

function Test-LicenseSaved {
  if (-not (Test-Path $LicenseFile)) { return $false }
  if (-not (Test-Path $LicenseAuthFile)) { return $false }
  return ((Get-Item $LicenseFile).Length -gt 0) -and ((Get-Item $LicenseAuthFile).Length -gt 0)
}

function Get-LicenseField([string]$Text, [string]$Key) {
  if (-not $Text) { return '' }
  $line = ($Text -split "`r?`n") | Where-Object { $_ -like "$Key=*" } | Select-Object -First 1
  if ($line) { return $line.Substring($Key.Length + 1) }
  return ''
}

# Quotes a value so Start-Process passes paths with spaces intact.
function Quote-Arg([string]$Value) {
  if ($Value -match '[\s"]') { return '"' + ($Value -replace '"', '\"') + '"' }
  return $Value
}

# The dashboard is a windowed app: it has no console, so the result comes back
# in a file (--license-out) instead of stdout.
function Invoke-LicenseCheck([string]$LicensePath, [string]$AuthPath) {
  $out = [IO.Path]::GetTempFileName()
  try {
    $cliArgs = @(
      '--license-check',
      '--license-file', (Quote-Arg $LicensePath),
      '--auth-file', (Quote-Arg $AuthPath),
      '--no-browser',
      '--license-out', (Quote-Arg $out)
    ) -join ' '
    Start-Process -FilePath $Binary -ArgumentList $cliArgs -Wait -WindowStyle Hidden | Out-Null
    if (Test-Path $out) { return (Get-Content $out -Raw -ErrorAction SilentlyContinue) }
    return ''
  } finally {
    Remove-Item $out -Force -ErrorAction SilentlyContinue
  }
}

function Test-LicenseSupported {
  if (-not (Test-Path $Binary)) { return $false }
  $text = Invoke-LicenseCheck 'C:\mapsim-nonexistent.license' 'C:\mapsim-nonexistent.auth'
  return [bool]($text -match '(?m)^status=')
}

function Show-LicenseResult([string]$Text) {
  $user = Get-LicenseField $Text 'user'
  $account = Get-LicenseField $Text 'account'
  $expiry = Get-LicenseField $Text 'expiry'
  $days = Get-LicenseField $Text 'days_left'
  $status = Get-LicenseField $Text 'status'
  $message = Get-LicenseField $Text 'message'
  $warning = Get-LicenseField $Text 'warning'
  if ($user) { Write-Host "  user    : $user" }
  if ($account) { Write-Host "  account : $account" }
  if ($expiry) { Write-Host "  expires : $expiry ($days day(s) left)" }
  if ($message) { Write-Host "  status  : $status - $message" }
  if ($warning) { Write-Host "  warning : $warning" }
}

function Test-LicenseReady {
  if (-not (Test-LicenseSupported)) { return $false }
  if (-not (Test-LicenseSaved)) { return $false }
  $text = Invoke-LicenseCheck $LicenseFile $LicenseAuthFile
  return ((Get-LicenseField $text 'status') -eq 'ACTIVE')
}

# Interactive gate for anything that starts the dashboard.
function Confirm-License {
  if (-not (Test-LicenseSupported)) {
    Write-Host 'the installed dashboard build does not support the license yet.'
    Write-Host 'update it from menu 4 (Install / update dashboard), then enter the license (menu 12).'
    return $false
  }
  if (-not (Test-LicenseSaved)) {
    Write-Host 'a valid Mapsim license is required to run the dashboard.'
    $a = Read-Default 'enter the license now? (y/n)' 'y'
    if ($a -ne 'y') {
      Write-Host 'the dashboard was not started - the license is required (menu 12).'
      return $false
    }
    if (-not (Enter-License)) { return $false }
  }
  $text = Invoke-LicenseCheck $LicenseFile $LicenseAuthFile
  if ((Get-LicenseField $text 'status') -ne 'ACTIVE') {
    Write-Host 'the license check failed:'
    Show-LicenseResult $text
    Write-Host 'the dashboard was not started. Fix the license in menu 12.'
    return $false
  }
  $warning = Get-LicenseField $text 'warning'
  if ($warning) { Write-Host "warning: $warning" }
  return $true
}

function Enter-License {
  if (-not (Test-LicenseSupported)) {
    Write-Host 'the installed dashboard build does not support the license yet.'
    Write-Host 'update it from menu 4 (Install / update dashboard), then try again.'
    return $false
  }
  $lic = Read-Host 'paste your license (0 = back)'
  if ($lic -eq '0') { Write-Host 'back.'; return $false }
  if ([string]::IsNullOrWhiteSpace($lic)) { Write-Host 'no license entered.'; return $false }
  $user = Read-Host 'license username (0 = back)'
  if ($user -eq '0') { Write-Host 'back.'; return $false }
  $secure = Read-Host 'license password (0 = back)' -AsSecureString
  $pass = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
    [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure))
  if ($pass -eq '0') { Write-Host 'back.'; return $false }
  if ([string]::IsNullOrWhiteSpace($user) -or [string]::IsNullOrWhiteSpace($pass)) {
    Write-Host 'the username and password must not be empty.'
    return $false
  }

  New-Item -ItemType Directory -Force $LicenseDir | Out-Null
  $tmpLic = Join-Path $LicenseDir 'dashboard.license.tmp'
  $tmpAuth = Join-Path $LicenseDir 'dashboard.auth.tmp'
  try {
    Set-Content -Path $tmpLic -Value $lic -Encoding ASCII
    Set-Content -Path $tmpAuth -Value @($user, $pass) -Encoding ASCII
    $text = Invoke-LicenseCheck $tmpLic $tmpAuth
  } finally {
    Remove-Item $tmpLic, $tmpAuth -Force -ErrorAction SilentlyContinue
  }
  if ((Get-LicenseField $text 'status') -ne 'ACTIVE') {
    Write-Host 'this license was rejected:'
    Show-LicenseResult $text
    Write-Host 'nothing was saved.'
    return $false
  }
  Set-Content -Path $LicenseFile -Value $lic -Encoding ASCII
  Set-Content -Path $LicenseAuthFile -Value @($user, $pass) -Encoding ASCII
  # The password file must stay private to this Windows account.
  $me = [Security.Principal.WindowsIdentity]::GetCurrent().Name
  & icacls $LicenseFile '/inheritance:r' '/grant:r' "${me}:(R,W)" | Out-Null
  & icacls $LicenseAuthFile '/inheritance:r' '/grant:r' "${me}:(R,W)" | Out-Null
  Write-Host 'license saved:'
  Show-LicenseResult $text
  $days = Get-LicenseField $text 'days_left'
  if ($days -match '^\d+$' -and [int]$days -le 7) {
    Write-Host "warning: this license expires in $days day(s) - renew it soon."
  }
  return $true
}

function Show-LicenseStatus {
  if (-not (Test-LicenseSupported)) {
    Write-Host 'the installed dashboard build does not support the license yet.'
    Write-Host 'update it from menu 4 (Install / update dashboard).'
    return
  }
  if (-not (Test-LicenseSaved)) {
    Write-Host 'license : not set (choose 1 to enter it)'
    return
  }
  Write-Host 'license files:'
  Write-Host "  $LicenseFile"
  Write-Host "  $LicenseAuthFile"
  $text = Invoke-LicenseCheck $LicenseFile $LicenseAuthFile
  Show-LicenseResult $text
  if ((Get-LicenseField $text 'status') -eq 'ACTIVE') { Write-Host 'license : ACTIVE' }
  else { Write-Host 'license : NOT ACTIVE - the dashboard will not start (choose 1 to fix it)' }
}

function Remove-License {
  if (-not (Test-LicenseSaved)) { Write-Host 'no license is saved.'; return }
  $a = Read-Default 'remove the saved license? the dashboard will not start without it (y/n)' 'n'
  if ($a -ne 'y') { Write-Host 'cancelled.'; return }
  Remove-Item $LicenseFile, $LicenseAuthFile -Force -ErrorAction SilentlyContinue
  if ((Test-Path $LicenseDir) -and -not (Get-ChildItem $LicenseDir -Force -ErrorAction SilentlyContinue)) {
    Remove-Item $LicenseDir -Force -ErrorAction SilentlyContinue
  }
  Write-Host 'license removed.'
}

function Show-LicenseMenu {
  while ($true) {
    Clear-Host
    Show-Title
    Write-Host 'License'
    Write-Host '  dashboard login uses the license username/password'
    if (Test-LicenseSaved) { Write-Host "  saved: yes ($LicenseFile)" } else { Write-Host '  saved: no' }
    Write-Host ''
    Write-Host '  1) Enter / update license'
    Write-Host '  2) Show license status'
    Write-Host '  3) Remove saved license'
    Write-Host '  0) Back to the main menu'
    $c = Read-Host "`nchoose 1-3 (0 = back)"
    switch ($c) {
      '0' { return }
      '1' { Enter-License | Out-Null }
      '2' { Show-LicenseStatus }
      '3' { Remove-License }
      default { Write-Host 'please choose 1-3.' }
    }
    $null = Read-Host "`nPress Enter to continue"
  }
}

function Get-DashboardPids {
  $ids = @()
  if (Test-Path $PidFile) {
    $pidValue = (Get-Content $PidFile -ErrorAction SilentlyContinue | Select-Object -First 1)
    if ($pidValue -and (Get-Process -Id $pidValue -ErrorAction SilentlyContinue)) { $ids += [int]$pidValue }
  }
  # PyInstaller --onefile runs a bootloader parent and a child; take both.
  foreach ($proc in (Get-Process -ErrorAction SilentlyContinue)) {
    if ($proc.Id -eq $PID) { continue }
    $procPath = $null
    try { $procPath = $proc.Path } catch { continue }
    if ($procPath -eq $Binary) { $ids += $proc.Id }
  }
  return @($ids | Select-Object -Unique)
}

function Get-DashboardPid {
  $ids = @(Get-DashboardPids)
  if ($ids.Count -gt 0) { return $ids[0] }
  return $null
}

function Trim-Log([string]$Path) {
  if (-not (Test-Path $Path)) { return }
  $item = Get-Item $Path -ErrorAction SilentlyContinue
  if (-not $item -or $item.Length -le $LogMaxBytes) { return }
  try { Get-Content $Path -Tail $LogKeepLines | Set-Content $Path -Encoding UTF8 } catch { }
}

function Trim-Logs {
  Trim-Log $LogFile
  Trim-Log "$LogFile.err"
}

function Wait-Dashboard([int]$Port, [int]$Seconds) {
  for ($i = 0; $i -lt $Seconds; $i++) {
    if (Test-DashboardUp $Port) { return $true }
    Start-Sleep -Seconds 1
  }
  return $false
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
    $hadService = Test-ServiceRunning
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
  New-Item -ItemType Directory -Force $ConfigDir | Out-Null
  Set-Content -Path $VersionFile -Value ($ver -replace '^dashboard-v', '') -Encoding ASCII
  Write-Host "installed: $AppDir ($($ver -replace '^dashboard-v', ''))"
  if ($hadService) {
    Start-ServiceTask
    Write-Host 'auto-start task started again with the new version.'
  }
}

function Install-Self {
  New-Item -ItemType Directory -Force $AppDir | Out-Null
  Copy-Item -Force $PSCommandPath $MenuPath
}

function Install-Service {
  # One dashboard only: the task starts immediately, so a manually started
  # instance would fight for the port.
  if ((Get-DashboardPid) -and -not (Test-ServiceRunning)) {
    Write-Host 'stopping the manually started dashboard - the task will run it.'
    Stop-Dashboard | Out-Null
  }
  $servicePort = Get-CurrentPort
  $action = New-ScheduledTaskAction -Execute $Binary -Argument "--no-browser --port $servicePort" -WorkingDirectory $AppDir
  $trigger = New-ScheduledTaskTrigger -AtLogOn
  $principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel LeastPrivilege
  # Restarts are capped (3 tries, one minute apart); no 72-hour execution limit.
  $settings = New-ScheduledTaskSettingsSet -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1) -ExecutionTimeLimit ([TimeSpan]::Zero) -MultipleInstances IgnoreNew -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
  Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null
  Enable-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue | Out-Null
  Start-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
  New-Item -ItemType Directory -Force $ConfigDir | Out-Null
  Set-Content $PortFile $servicePort -Encoding ASCII
}

function Remove-Service {
  Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
}

function Test-ServiceInstalled {
  return [bool](Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue)
}

function Test-ServiceRunning {
  $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
  if (-not $task) { return $false }
  return $task.State -eq 'Running'
}

function Test-ServiceEnabled {
  $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
  if (-not $task) { return $false }
  return $task.State -ne 'Disabled'
}

function Start-ServiceTask {
  if (Test-ServiceInstalled) { Start-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue }
}

function Stop-ServiceTask {
  if (Test-ServiceInstalled) { Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue }
}

function Restart-ServiceTask {
  Stop-ServiceTask
  Start-Sleep -Seconds 1
  Start-ServiceTask
}

function Enable-ServiceTask {
  if (Test-ServiceInstalled) { Enable-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue | Out-Null }
}

function Disable-ServiceTask {
  if (Test-ServiceInstalled) { Disable-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue | Out-Null }
}

function Stop-Dashboard {
  $wasService = Test-ServiceRunning
  if ($wasService) {
    Stop-ServiceTask
    Write-Host 'auto-start task stopped (it starts again at the next logon; menu 6 removes it).'
  }
  $ids = @(Get-DashboardPids)
  if ($ids.Count -eq 0) {
    if (-not $wasService) { Write-Host 'the dashboard is not running.' }
    if (Test-Path $PidFile) { Remove-Item $PidFile -ErrorAction SilentlyContinue }
    Trim-Logs
    return
  }
  foreach ($procId in $ids) { Stop-Process -Id $procId -Force -ErrorAction SilentlyContinue }
  if (Test-Path $PidFile) { Remove-Item $PidFile -ErrorAction SilentlyContinue }
  Write-Host ("dashboard stopped (pids: {0})." -f ($ids -join ' '))
  Trim-Logs
}

function Start-Dashboard([string]$Bind, [int]$Port) {
  if (Get-DashboardPid) {
    Write-Host "the dashboard is already running (pid $(Get-DashboardPid))."
    return
  }
  if (-not (Test-LicenseReady)) {
    Write-Host 'error: a valid Mapsim license is required - the dashboard was not started.' -ForegroundColor Red
    Write-Host 'open menu 12 (License) and enter or fix the license.'
    return
  }
  if (Test-ServiceInstalled) {
    if (Test-ServiceRunning) {
      Stop-ServiceTask
      Write-Host 'note: the auto-start task was stopped for this manual start (it starts again at the next logon).'
    } else {
      Write-Host 'note: the auto-start task is installed and will start the dashboard again at the next logon (menu 6 removes it).'
    }
  }
  if (Test-PortListening $Port) {
    Write-Host "error: port $Port is already used by another program." -ForegroundColor Red
    return
  }
  Write-EnvFile $Bind
  $env:MAPSIM_DASHBOARD_BIND = $Bind
  New-Item -ItemType Directory -Force $ConfigDir | Out-Null
  Trim-Logs
  $proc = Start-Process -FilePath $Binary -ArgumentList '--no-browser', "--port", "$Port" -WorkingDirectory $AppDir -WindowStyle Hidden -RedirectStandardOutput $LogFile -RedirectStandardError "$LogFile.err" -PassThru
  Set-Content $PidFile $proc.Id
  for ($i = 0; $i -lt 20; $i++) {
    if ((Get-DashboardPid) -and (Test-DashboardUp $Port)) {
      Set-Content $PortFile $Port -Encoding ASCII
      Write-Host 'dashboard is up:'
      Write-Host "  local   : http://127.0.0.1:$Port/"
      if ($Bind -eq '0.0.0.0') {
        Write-Host "  remote  : http://<this-pc-ip>:$Port/ (open the port in Windows Firewall)"
        Write-Host '  access  : the license username and password (menu 12)'
      }
      return
    }
    Start-Sleep -Seconds 1
  }
  Write-Host "error: the dashboard did not answer on port $Port; see $LogFile" -ForegroundColor Red
  if (Test-Path $LogFile) { Get-Content $LogFile -Tail 5 -ErrorAction SilentlyContinue | ForEach-Object { Write-Host "  $_" } }
}

function Show-Disk {
  Write-Host 'disk space:'
  Get-PSDrive -PSProvider FileSystem | ForEach-Object {
    if ($null -ne $_.Used -and ($_.Used + $_.Free) -gt 0) {
      $total = [math]::Round(($_.Used + $_.Free) / 1GB, 1)
      $free = [math]::Round($_.Free / 1GB, 1)
      $pct = [math]::Round($_.Used / ($_.Used + $_.Free) * 100)
      Write-Host ("  {0,-3} {1,8} GB free of {2,8} GB  ({3}% used)  {4}" -f $_.Name, $free, $total, $pct, $_.Root)
    }
  }
  Write-Host ''
  Write-Host 'dashboard folders:'
  foreach ($d in @($AppDir, $ConfigDir)) {
    if (Test-Path $d) {
      $size = (Get-ChildItem $d -Recurse -Force -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
      $mb = [math]::Round([double]$size / 1MB, 1)
      Write-Host ("  {0} MB  {1}" -f $mb, $d)
    }
  }
  Write-Host ''
  foreach ($f in @($LogFile, "$LogFile.err")) {
    if (Test-Path $f) {
      $mb = [math]::Round((Get-Item $f).Length / 1MB, 2)
      Write-Host ("  log {0} MB  {1}" -f $mb, $f)
    }
  }
  Write-Host 'logs are trimmed automatically above 256 KB (the newest lines are kept).'
  Write-Host 'hint: free up space by removing old dashboard logs or an unused MT5 copy.'
}

function Show-Status {
  Write-Host "system    : Windows x64"
  if (Test-Installed) { Write-Host "app       : installed ($AppDir)" } else { Write-Host 'app       : not installed' }
  $ver = Get-InstalledVersion
  if ($ver) {
    $latestTag = Get-LatestDashboardTag
    $latestPlain = ''
    if ($latestTag) { $latestPlain = $latestTag -replace '^dashboard-v', '' }
    if ($latestPlain -and (Test-NewerDashboardVersion $latestPlain $ver)) {
      Write-Host "version   : $ver (update $latestPlain available - menu 4)"
    } else {
      Write-Host "version   : $ver"
    }
  } else {
    Write-Host 'version   : unknown'
  }
  $id = Get-DashboardPid
  if ($id) { Write-Host "dashboard : RUNNING (pid $id)" } else { Write-Host 'dashboard : stopped' }
  $port = Get-CurrentPort
  if (Test-DashboardUp $port) { Write-Host "port $port : dashboard answering (HTTP $(Get-HttpCode $port))" }
  elseif (Test-PortListening $port) { Write-Host "port $port : busy (another program)" }
  else { Write-Host "port $port : free" }
  Write-Host "bind      : $(Get-CurrentBind)"
  if (-not (Test-LicenseSaved)) {
    Write-Host 'license   : not set (menu 12 - required to start)'
  } elseif (-not (Test-LicenseSupported)) {
    Write-Host 'license   : saved (the installed build is too old - menu 4)'
  } else {
    $lic = Invoke-LicenseCheck $LicenseFile $LicenseAuthFile
    $lstatus = Get-LicenseField $lic 'status'
    $luser = Get-LicenseField $lic 'user'
    $lexp = Get-LicenseField $lic 'expiry'
    if ($lstatus -eq 'ACTIVE') { Write-Host "license   : ACTIVE - $luser, expires $lexp" }
    else { Write-Host "license   : $lstatus ($(Get-LicenseField $lic 'message')) - dashboard will not start" }
  }
  $sysDrive = Get-PSDrive -Name ($env:SystemDrive.TrimEnd(':'))
  if ($null -ne $sysDrive.Used -and ($sysDrive.Used + $sysDrive.Free) -gt 0) {
    Write-Host ("disk      : {0} GB free of {1} GB ({2}% used)" -f [math]::Round($sysDrive.Free / 1GB, 1), [math]::Round(($sysDrive.Used + $sysDrive.Free) / 1GB, 1), [math]::Round($sysDrive.Used / ($sysDrive.Used + $sysDrive.Free) * 100))
  }
  $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
  if ($task) {
    $stateText = 'enabled'
    if ($task.State -eq 'Disabled') { $stateText = 'disabled' }
    $runText = 'stopped'
    if ($task.State -eq 'Running') { $runText = 'running' }
    Write-Host "service   : installed, $stateText, $runText"
  } else {
    Write-Host 'service   : not installed'
  }
}

# ---------------------------------------------------------------- dashboard version / updates

function Get-InstalledVersion {
  if (Test-Path $VersionFile) {
    $v = (Get-Content $VersionFile -Raw).Trim()
    if ($v) { return $v }
  }
  # Builds installed before the version file existed report it themselves.
  if (Test-Path $Binary) {
    try {
      $out = & $Binary --version 2>$null
      if ($out -match '(\d+(?:\.\d+)+)') {
        $v = $Matches[1]
        New-Item -ItemType Directory -Force $ConfigDir | Out-Null
        Set-Content -Path $VersionFile -Value $v -Encoding ASCII
        return $v
      }
    } catch { }
  }
  return ''
}

# Newest licensed release tag, cached for 6 hours so the menu starts fast.
function Get-LatestDashboardTag {
  if (Test-Path $UpdateCacheFile) {
    try {
      $cache = Get-Content $UpdateCacheFile -Raw | ConvertFrom-Json
      $age = [DateTimeOffset]::Now.ToUnixTimeSeconds() - [int64]$cache.checked
      if ($age -ge 0 -and $age -lt $UpdateCacheTtl -and $cache.tag) { return [string]$cache.tag }
    } catch { }
  }
  try {
    $rel = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo/releases?per_page=50" -TimeoutSec 8
    $tag = ($rel | Where-Object { -not $_.draft -and -not $_.prerelease -and $_.tag_name -match '^dashboard-v\d' } | Select-Object -First 1).tag_name
    if ($tag) {
      New-Item -ItemType Directory -Force $ConfigDir | Out-Null
      @{ checked = [DateTimeOffset]::Now.ToUnixTimeSeconds(); tag = $tag } | ConvertTo-Json | Set-Content -Path $UpdateCacheFile -Encoding ASCII
      return [string]$tag
    }
  } catch { }
  return ''
}

function Test-NewerDashboardVersion([string]$Latest, [string]$Installed) {
  if (-not $Latest -or -not $Installed) { return $false }
  try {
    return ([version]$Latest) -gt ([version]$Installed)
  } catch {
    return $false
  }
}

function Get-UpdatePolicy {
  if (Test-Path $UpdatePolicyFile) {
    $p = (Get-Content $UpdatePolicyFile -Raw).Trim()
    if ($p -in @('auto', 'notify', 'off')) { return $p }
  }
  return 'notify'
}

function Set-UpdatePolicy([string]$Policy) {
  New-Item -ItemType Directory -Force $ConfigDir | Out-Null
  Set-Content -Path $UpdatePolicyFile -Value $Policy -Encoding ASCII
}

function Update-Refresh {
  $script:UpdateInstalled = Get-InstalledVersion
  $latestTag = Get-LatestDashboardTag
  $script:UpdateLatest = ''
  if ($latestTag) { $script:UpdateLatest = $latestTag -replace '^dashboard-v', '' }
  $script:UpdateAvailable = $false
  if ($script:UpdateLatest -and $script:UpdateInstalled -and (Test-NewerDashboardVersion $script:UpdateLatest $script:UpdateInstalled)) {
    $script:UpdateAvailable = $true
  }
}

function Invoke-StartupUpdateCheck {
  $policy = Get-UpdatePolicy
  if ($policy -eq 'off') { return }
  Update-Refresh
  if (-not $script:UpdateAvailable) { return }
  if ($policy -eq 'auto') {
    Write-Host ''
    Write-Host "automatic update: $($script:UpdateInstalled) -> $($script:UpdateLatest)" -ForegroundColor Yellow
    $previousVersion = $Version
    $script:Version = "dashboard-v$($script:UpdateLatest)"
    try { Install-Dashboard } catch { Write-Host "automatic update failed: $($_.Exception.Message)" -ForegroundColor Red }
    $script:Version = $previousVersion
    Update-Refresh
    $null = Read-Host 'Press Enter to open the menu'
    return
  }
  Write-Host ''
  Write-Host "dashboard update available: $($script:UpdateInstalled) -> $($script:UpdateLatest) (menu 4 installs it)" -ForegroundColor Yellow
}

function Show-UpdatePolicyMenu {
  while ($true) {
    Clear-Host
    $cur = Get-UpdatePolicy
    Write-Host ''
    Write-Host 'dashboard updates'
    Write-Host "  current policy: $cur"
    Write-Host ''
    Write-Host '  1) notify - check when the menu starts and tell me (default)'
    Write-Host '  2) auto   - install a new version automatically when the menu starts'
    Write-Host '  3) off    - never check for updates'
    Write-Host '  4) check now'
    $a = Read-Host 'choose 1-4 (0 = back)'
    if ($a -eq '0') { return }
    switch ($a) {
      '1' { Set-UpdatePolicy 'notify'; Write-Host 'policy: notify.' }
      '2' { Set-UpdatePolicy 'auto'; Write-Host 'policy: auto - a new release installs at menu start.' }
      '3' { Set-UpdatePolicy 'off'; Write-Host 'policy: off.' }
      '4' {
        Update-Refresh
        if (-not $script:UpdateLatest) { Write-Host 'could not reach GitHub (offline or rate limited).' -ForegroundColor Yellow }
        elseif ($script:UpdateAvailable) { Write-Host "update available: $($script:UpdateInstalled) -> $($script:UpdateLatest) (menu 4 installs it)" -ForegroundColor Yellow }
        elseif ($script:UpdateInstalled) { Write-Host "dashboard is up to date ($($script:UpdateInstalled))." -ForegroundColor Green }
        else { Write-Host "latest release: $($script:UpdateLatest)" }
      }
      default { Write-Host 'please choose 1-4.' }
    }
    $null = Read-Host 'Press Enter to continue'
  }
}

function Read-Default([string]$Prompt, [string]$Default) {
  $a = Read-Host "$Prompt [$Default]"
  if ([string]::IsNullOrWhiteSpace($a)) { return $Default }
  return $a
}

# ---------------------------------------------------------------- ui (colors, boxes, title)

$ESC = [char]27
$Red     = $ESC + '[0;31m'
$Green   = $ESC + '[0;32m'
$Yellow  = $ESC + '[1;33m'
$Blue    = $ESC + '[0;34m'
$Cyan    = $ESC + '[0;36m'
$Magenta = $ESC + '[0;35m'
$White   = $ESC + '[1;37m'
$NoColor = $ESC + '[0m'

$BlockCh = [string][char]0x2588
$BoxH    = [string][char]0x2500
$BoxV    = [string][char]0x2502
$BoxTL   = [string][char]0x250C
$BoxTR   = [string][char]0x2510
$BoxBL   = [string][char]0x2514
$BoxBR   = [string][char]0x2518
$BoxL    = [string][char]0x251C
$BoxR    = [string][char]0x2524

function Show-Title {
  Write-Host ''
  Write-Host ($Magenta + '    ##   ##  #####  ######   ###### ####### ##   ##   #####   #####  #######'.Replace('#', $BlockCh) + $NoColor)
  Write-Host ($Magenta + '    ### ### ##   ## ##   ## ##      ##      ### ###  ##   ## ##   ##   ###  '.Replace('#', $BlockCh) + $NoColor)
  Write-Host ($Magenta + '    ## # ## ####### ######   #####  ####### ## # ##  ######  ##   ##   ###  '.Replace('#', $BlockCh) + $NoColor)
  Write-Host ($Magenta + '    ##   ## ##   ## ##           ## ##      ##   ##  ##   ## ##   ##   ###  '.Replace('#', $BlockCh) + $NoColor)
  Write-Host ($Magenta + '    ##   ## ##   ## ##      ######  ####### ##   ##  ######   #####    ###  '.Replace('#', $BlockCh) + $NoColor)
}

function Ui-Top    { Write-Host ($Cyan + $BoxTL + ($BoxH * 79) + $BoxTR + $NoColor) }
function Ui-Sep    { Write-Host ($Cyan + $BoxL  + ($BoxH * 79) + $BoxR  + $NoColor) }
function Ui-Bottom { Write-Host ($Cyan + $BoxBL + ($BoxH * 79) + $BoxBR + $NoColor) }

function Ui-Row([string]$Label, [string]$Plain, [string]$Colored) {
  if (-not $Colored) { $Colored = $Plain }
  $body = '{0,-10}: {1}' -f $Label, $Colored
  $plainBody = '{0,-10}: {1}' -f $Label, $Plain
  $pad = 79 - 2 - $plainBody.Length
  if ($pad -lt 0) { $pad = 0 }
  Write-Host ($Cyan + $BoxV + $NoColor + '  ' + $body + (' ' * $pad) + $Cyan + $BoxV + $NoColor)
}

function Ui-Item([string]$Num, [string]$Text) {
  Write-Host ($Cyan + $BoxV + $NoColor + '   ' + $Magenta + ('{0,2}' -f $Num) + $NoColor + ' - ' + $White + ('{0,-71}' -f $Text) + $NoColor + $Cyan + $BoxV + $NoColor)
}

function Choose-Port {
  $p = [int](Read-Default 'port' '8765')
  while (Test-PortListening $p) {
    Write-Host "port $p is busy."
    $p = [int](Read-Default 'choose another port' "$($p + 1)")
  }
  return $p
}

function Show-ServiceStatus {
  Write-Host 'auto-start task:'
  $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
  if ($task) {
    Write-Host '  installed : yes'
    $stateText = 'enabled (starts at the next logon)'
    if ($task.State -eq 'Disabled') { $stateText = 'no (choose 6 to enable it)' }
    Write-Host "  enabled   : $stateText"
    $runText = 'no'
    if ($task.State -eq 'Running') { $runText = 'yes' }
    Write-Host "  running   : $runText"
  } else {
    Write-Host '  installed : no (choose 2 to install it)'
    Write-Host '  enabled   : -'
    Write-Host '  running   : -'
  }
  $id = Get-DashboardPid
  $port = Get-CurrentPort
  if ($id) {
    Write-Host "  dashboard : pid $id, port $port"
    if ((Get-CurrentBind) -eq '0.0.0.0') { Write-Host "  url       : http://<this-pc-ip>:$port/" }
    else { Write-Host "  url       : http://127.0.0.1:$port/" }
  } else {
    Write-Host '  dashboard : not running'
  }
  Write-Host "  logs      : $LogFile (trimmed automatically above 256 KB)"
}

function Invoke-ServiceAction([string]$Action) {
  if (-not (Test-Installed)) { Write-Host 'the dashboard is not installed yet - use menu 4.'; return }
  if (-not (Test-ServiceInstalled)) { Write-Host 'the auto-start task is not installed - choose 2 first.'; return }
  $port = Get-CurrentPort
  if ($Action -in @('start', 'restart')) {
    if (-not (Confirm-License)) { Write-Host "the dashboard was not $Action-ed."; return }
  }
  switch ($Action) {
    'start' {
      Start-ServiceTask
      Write-Host 'start requested.'
      if (Wait-Dashboard $port 15) { Write-Host "dashboard is up: http://127.0.0.1:$port/" }
      else { Write-Host "it did not answer on port $port - see status (1)." }
    }
    'stop' {
      Stop-ServiceTask
      Stop-Dashboard | Out-Null
      Write-Host 'task stopped. It starts again at the next logon while it is enabled.'
    }
    'restart' {
      Restart-ServiceTask
      Write-Host 'restart requested.'
      if (Wait-Dashboard $port 15) { Write-Host "dashboard is up: http://127.0.0.1:$port/" }
      else { Write-Host "it did not answer on port $port - see status (1)." }
    }
    'enable' {
      Enable-ServiceTask
      Write-Host 'enabled: the dashboard starts automatically at the next logon.'
    }
    'disable' {
      Disable-ServiceTask
      Write-Host 'disabled: it will not start automatically any more. The running dashboard keeps running until you stop it (4).'
    }
  }
}

function Show-ServiceMenu {
  while ($true) {
    Clear-Host
    Write-Host ''
    Write-Host 'auto-start task'
    $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if ($task) {
      $stateText = 'enabled'
      if ($task.State -eq 'Disabled') { $stateText = 'disabled' }
      $runText = 'stopped'
      if ($task.State -eq 'Running') { $runText = 'running' }
      Write-Host ("  installed, {0}, {1} (port {2})" -f $stateText, $runText, (Get-CurrentPort))
    } else {
      Write-Host '  not installed'
    }
    Write-Host ''
    Write-Host '  1) Status / details'
    Write-Host '  2) Install and enable (start now and at every logon)'
    Write-Host '  3) Start now'
    Write-Host '  4) Stop now'
    Write-Host '  5) Restart now'
    Write-Host '  6) Enable at logon'
    Write-Host '  7) Disable at logon'
    Write-Host '  0) Back to the main menu'
    $m = Read-Default 'choose 1-7' '1'
    if ($m -eq '0') { return }
    switch ($m) {
      '1' { Show-ServiceStatus }
      '2' {
        if (Test-Installed) {
          if (-not (Confirm-License)) { Write-Host 'the task was not installed.'; $null = Read-Host "`nPress Enter to continue"; continue }
          Install-Service
          Write-Host 'task installed and enabled: the dashboard starts now and at every logon.'
        } else { Write-Host 'not installed yet - use menu 4.' }
      }
      '3' { Invoke-ServiceAction 'start' }
      '4' { Invoke-ServiceAction 'stop' }
      '5' { Invoke-ServiceAction 'restart' }
      '6' { Invoke-ServiceAction 'enable' }
      '7' { Invoke-ServiceAction 'disable' }
      default { Write-Host 'please choose 1-7.' }
    }
    $null = Read-Host "`nPress Enter to continue"
  }
}

function Show-Menu {
  Invoke-StartupUpdateCheck
  while ($true) {
    Clear-Host
    $id = Get-DashboardPid
    if ($id) { $stPlain = "running (pid $id)"; $stCol = $Green + $stPlain + $NoColor }
    else { $stPlain = 'stopped'; $stCol = $Red + $stPlain + $NoColor }
    if (Test-Installed) { $appPlain = 'installed'; $appCol = $Green + $appPlain + $NoColor }
    else { $appPlain = 'not installed'; $appCol = $Red + $appPlain + $NoColor }
    $ea = Get-EaInstalledVersion
    if ($ea) { $eaPlain = $ea; $eaCol = $Green + $ea + $NoColor }
    else { $eaPlain = 'not installed'; $eaCol = $Yellow + $eaPlain + $NoColor }
    $bindNow = Get-CurrentBind
    $portNow = Get-CurrentPort
    if ($bindNow -eq '0.0.0.0') { $acc = "internet (0.0.0.0) - port $portNow" }
    else { $acc = "local only - port $portNow" }
    $sysDrive = Get-PSDrive -Name ($env:SystemDrive.TrimEnd(':'))
    if ($null -ne $sysDrive.Used -and ($sysDrive.Used + $sysDrive.Free) -gt 0) {
      $totalGB = ($sysDrive.Used + $sysDrive.Free)
      $usedPct = [math]::Round($sysDrive.Used / $totalGB * 100)
      $diskLine = '{0} GB free of {1} GB ({2}% used)' -f [math]::Round($sysDrive.Free / 1GB, 1), [math]::Round($totalGB / 1GB, 1), $usedPct
      if ($usedPct -ge 90) { $diskCol = $Red } elseif ($usedPct -ge 75) { $diskCol = $Yellow } else { $diskCol = $Green }
    } else {
      $diskLine = 'unknown'
      $diskCol = $Yellow
    }

    Show-Title
    Ui-Top
    Ui-Row 'Dashboard' $stPlain $stCol
    Ui-Row 'App' $appPlain $appCol
    $verPlain = Get-InstalledVersion
    if ($verPlain) {
      if ($script:UpdateAvailable -and $script:UpdateLatest) {
        $verPlain = "$verPlain  (update $($script:UpdateLatest) available - menu 4)"
        $verCol = $Yellow + $verPlain + $NoColor
      } else {
        $verCol = $Green + $verPlain + $NoColor
      }
    } else {
      $verPlain = 'unknown'
      $verCol = $Yellow + $verPlain + $NoColor
    }
    Ui-Row 'Version' $verPlain $verCol
    if (Test-ServiceInstalled) {
      $svcState = 'enabled'; if (-not (Test-ServiceEnabled)) { $svcState = 'disabled' }
      $svcRun = 'stopped'; if (Test-ServiceRunning) { $svcRun = 'running' }
      $svcPlain = "installed, $svcState, $svcRun"
      if ($svcRun -eq 'running') { $svcCol = $Green + $svcPlain + $NoColor }
      else { $svcCol = $Yellow + $svcPlain + $NoColor }
    } else {
      $svcPlain = 'not installed'
      $svcCol = $Yellow + $svcPlain + $NoColor
    }
    Ui-Row 'Service' $svcPlain $svcCol
    Ui-Row 'Expert' $eaPlain $eaCol
    if (Test-LicenseSaved) { $licPlain = 'saved'; $licCol = $Green + $licPlain + $NoColor }
    else { $licPlain = 'not set'; $licCol = $Red + $licPlain + $NoColor }
    Ui-Row 'License' $licPlain $licCol
    Ui-Row 'Access' $acc ($Cyan + $acc + $NoColor)
    Ui-Row 'Disk' $diskLine ($diskCol + $diskLine + $NoColor)
    Ui-Sep
    Ui-Item '1' 'Status'
    Ui-Item '2' 'Start dashboard'
    Ui-Item '3' 'Stop dashboard'
    Ui-Item '4' 'Install / update dashboard'
    Ui-Item '5' 'Service management (start/stop/restart/enable/disable)'
    Ui-Item '6' 'Remove auto-start service'
    Ui-Item '7' 'Access mode (local / internet)'
    Ui-Item '8' 'Uninstall everything'
    Ui-Item '9' 'Expert Advisor: install / update'
    Ui-Item '10' 'Expert Advisor: version check'
    Ui-Item '11' 'Disk space / server storage'
    Ui-Item '12' 'License (dashboard login)'
    Ui-Item '13' 'Update policy (notify / auto / off)'
    Ui-Item '14' 'Exit'
    Ui-Bottom
    $c = Read-Host "`nEnter Number Of List"
    switch ($c) {
      '1' { Show-Status }
      '2' {
        if (-not (Test-Installed)) { Write-Host 'not installed yet - use menu 4.'; continue }
        if (-not (Confirm-License)) { continue }
        Write-Host 'how should the dashboard be reachable?'
        Write-Host '  1) local only   (this computer, http://127.0.0.1)'
        Write-Host '  2) internet     (any device + this computer, sign in with the license)'
        $m = Read-Default 'choose 1 or 2' '1'
        if ($m -eq '2') { $bind = '0.0.0.0' } else { $bind = '127.0.0.1' }
        $port = Choose-Port
        $oldId = Get-DashboardPid
        if ($oldId) {
          Write-Host "the dashboard is already running (pid $oldId, port $(Get-CurrentPort), bind $(Get-CurrentBind))."
          $a = Read-Default 'stop it and restart with the new settings? (y/n)' 'y'
          if ($a -ne 'y') { Write-Host 'cancelled - the running dashboard was not changed.'; continue }
          Stop-Dashboard
        }
        Start-Dashboard $bind $port
      }
      '3' { Stop-Dashboard }
      '4' { Install-Dashboard }
      '5' { Show-ServiceMenu }
      '6' {
        if (-not (Test-ServiceInstalled)) { Write-Host 'no service is installed.'; continue }
        $a = Read-Default 'remove the auto-start service? (y/n)' 'y'
        if ($a -eq 'y') { Remove-Service; Write-Host 'service removed (the app itself stays installed).' }
      }
      '7' {
        if (-not (Test-Installed)) { Write-Host 'not installed yet - use menu 4.'; continue }
        Write-Host "current bind: $(Get-CurrentBind)"
        Write-Host 'sign-in is always the license username and password (menu 12).'
        Write-Host '  1) local only'
        Write-Host '  2) internet (any device on your network / the internet)'
        $m = Read-Default 'choose 1 or 2' '1'
        $wasRunning = [bool](Get-DashboardPid)
        if ($m -eq '2') { Write-EnvFile '0.0.0.0'; Write-Host 'saved: internet access on 0.0.0.0.' }
        else { Write-EnvFile '127.0.0.1'; Write-Host 'saved: local only.' }
        if ($wasRunning) {
          $a = Read-Default 'restart the dashboard now? (y/n)' 'y'
          if ($a -eq 'y') {
            $port = Choose-Port
            if (-not (Confirm-License)) { Write-Host 'the dashboard was not restarted.'; continue }
            Stop-Dashboard
            Start-Dashboard (Get-CurrentBind) $port
          }
        }
      }
      '8' {
        Write-Host 'this removes the dashboard app, config, service, task and shortcuts.'
        Write-Host 'nothing is changed in MetaTrader 5 or in the Expert Advisor.'
        $a = Read-Default 'are you sure? type y to confirm' 'n'
        if ($a -eq 'y') { Uninstall-Everything } else { Write-Host 'cancelled.' }
      }
      '9' {
        $latest = Get-EaLatestVersion
        if (-not $latest) { Write-Host 'error: could not reach GitHub to find the latest Expert version.'; continue }
        $cur = Get-EaInstalledVersion
        if ($cur -and $cur -eq $latest) {
          $a = Read-Default "version $cur is already installed - reinstall? (y/n)" 'y'
          if ($a -ne 'y') { continue }
        }
        Install-Ea $latest
      }
      '10' { Show-EaStatus }
      '11' { Show-Disk }
      '12' { Show-LicenseMenu }
      '13' { Show-UpdatePolicyMenu }
      '14' { Write-Host 'bye.'; return }
      default { Write-Host 'please choose 1-14.' }
    }
    $null = Read-Host "`nPress Enter to continue"
  }
}

# ---------------------------------------------------------------- expert advisor

$EaState = Join-Path $ConfigDir 'ea-state.env'

function Get-EaLatestVersion {
  try {
    $tags = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo/tags?per_page=100" -TimeoutSec 15
    $v = $tags | Where-Object { $_.name -match '^v\d' } | ForEach-Object { $_.name }
    if (-not $v) { return '' }
    return ($v | Sort-Object { [version]($_.TrimStart('v')) } | Select-Object -Last 1)
  } catch {
    return ''
  }
}

function Get-EaInstalledVersion {
  if (Test-Path $EaState) {
    $line = Get-Content $EaState | Where-Object { $_ -match '^EA_VERSION=' } | Select-Object -Last 1
    if ($line) { return $line -replace '^EA_VERSION=', '' }
  }
  return ''
}

function Find-Mql5Folders {
  $found = @()
  $termRoot = Join-Path $env:APPDATA 'MetaQuotes\Terminal'
  if (Test-Path $termRoot) {
    $found += Get-ChildItem $termRoot -Directory -ErrorAction SilentlyContinue | ForEach-Object {
      $m = Join-Path $_.FullName 'MQL5'
      if (Test-Path $m) { $m }
    }
  }
  foreach ($pf in @($env:ProgramFiles, ${env:ProgramFiles(x86)})) {
    if ($pf -and (Test-Path $pf)) {
      $found += Get-ChildItem $pf -Directory -Filter 'MetaTrader*' -ErrorAction SilentlyContinue | ForEach-Object {
        $m = Join-Path $_.FullName 'MQL5'
        if (Test-Path $m) { $m }
      }
    }
  }
  return $found
}

function Install-Ea([string]$Version) {
  if (-not $Version) { $Version = Get-EaLatestVersion }
  if (-not $Version) {
    Write-Host 'error: could not determine the latest Expert version - check your internet connection.' -ForegroundColor Red
    return
  }
  $mql5List = @(Find-Mql5Folders)
  if ($mql5List.Count -eq 0) {
    Write-Host 'error: no MetaTrader 5 data folder (MQL5) was found.' -ForegroundColor Red
    Write-Host 'hint: install MT5, run it once (File -> Open Data Folder), then retry.' -ForegroundColor Red
    return
  }
  Write-Host "latest Expert version: $Version"
  $current = Get-EaInstalledVersion
  if ($current) { Write-Host "installed version    : $current" }
  Write-Host 'MQL5 folders found:'
  for ($i = 0; $i -lt $mql5List.Count; $i++) { Write-Host "  $($i + 1)) $($mql5List[$i])" }
  if ($mql5List.Count -gt 1) { $sel = Read-Default "choose 1-$($mql5List.Count) (or 'a' for all)" '1' }
  else { $sel = '1' }

  Write-Host "downloading Expert $Version ..."
  $tmp = Join-Path ([IO.Path]::GetTempPath()) ([IO.Path]::GetRandomFileName())
  New-Item -ItemType Directory -Force $tmp | Out-Null
  try {
    $zip = Join-Path $tmp 'ea.zip'
    Invoke-WebRequest -Uri "https://github.com/$Repo/archive/refs/tags/$Version.zip" -OutFile $zip -TimeoutSec 600 -UseBasicParsing
    Expand-Archive -Path $zip -DestinationPath (Join-Path $tmp 'src') -Force
    $root = Get-ChildItem (Join-Path $tmp 'src') -Directory | Select-Object -First 1
    $pkg = Join-Path $root.FullName 'Expert\Meta_trader_5'
    if (-not (Test-Path $pkg)) { throw "the $Version package has no Expert folder." }
    $ex5 = Get-ChildItem $pkg -Recurse -Filter '*.ex5' | Where-Object { $_.Name -match 'win' } | Select-Object -First 1
    if (-not $ex5) {
      $ex5 = Get-ChildItem $pkg -Recurse -Filter '*.ex5' | Select-Object -First 1
      if ($ex5) { Write-Host "note: no Windows build found - using $($ex5.Name)" }
    }
    if (-not $ex5) { throw "no .ex5 Expert file in the $Version package." }
    $includeZip = Get-ChildItem (Join-Path $pkg 'Include') -Filter '*.zip' -ErrorAction SilentlyContinue | Select-Object -First 1
    $dll = Join-Path $pkg 'Libraries\sqlite3.dll'
    $sounds = Join-Path $pkg 'Sounds\Mapsim_Assistance_Bot\Sounds'

    $installedTo = @()
    for ($i = 0; $i -lt $mql5List.Count; $i++) {
      if ($sel -ne 'a' -and $sel -ne 'A' -and $sel -ne [string]($i + 1)) { continue }
      $mql5 = $mql5List[$i]
      New-Item -ItemType Directory -Force "$mql5\Experts", "$mql5\Libraries", "$mql5\Include", "$mql5\Files\Mapsim_Assistance_Bot\Sounds" | Out-Null
      Copy-Item -Force $ex5.FullName "$mql5\Experts\"
      if (Test-Path $dll) { Copy-Item -Force $dll "$mql5\Libraries\" }
      if ($includeZip) { Expand-Archive -Path $includeZip.FullName -DestinationPath "$mql5\Include" -Force }
      if (Test-Path $sounds) { Copy-Item -Force "$sounds\*.wav" "$mql5\Files\Mapsim_Assistance_Bot\Sounds\" }
      $installedTo += $mql5
    }
  } finally {
    Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
  }
  New-Item -ItemType Directory -Force $ConfigDir | Out-Null
  @(
    "EA_VERSION=$Version",
    "EA_FILE=$($ex5.Name)",
    "EA_MQL5=$($installedTo -join ';')",
    "EA_UPDATED=$(Get-Date -Format yyyy-MM-dd)"
  ) | Set-Content $EaState -Encoding ASCII
  Write-Host "installed: $($ex5.Name) ($Version) -> $($installedTo -join '; ')"
  Write-Host 'next steps in MetaTrader 5:'
  Write-Host '  1) restart MetaTrader 5'
  Write-Host '  2) allow DLL imports in the EA options'
  Write-Host '  3) attach the Mapsim Assistance Bot Expert to your chart'
  Write-Host '  4) enter your license (from the Mapsim Bot in Telegram)'
}

function Show-EaStatus {
  $cur = Get-EaInstalledVersion
  $latest = Get-EaLatestVersion
  if (-not $cur) { Write-Host "Expert Advisor: not installed through Mapsim_BOT" }
  else {
    Write-Host "installed version : $cur"
    if (Test-Path $EaState) {
      $upd = (Get-Content $EaState | Where-Object { $_ -match '^EA_UPDATED=' } | Select-Object -Last 1) -replace '^EA_UPDATED=', ''
      if ($upd) { Write-Host "last updated      : $upd" }
    }
  }
  if ($latest) {
    Write-Host "latest version    : $latest"
    if ($cur -and $cur -ne $latest) {
      $a = Read-Default 'a newer version is available - install it now? (y/n)' 'y'
      if ($a -eq 'y') { Install-Ea $latest }
    }
  } else {
    Write-Host 'latest version    : (could not check - no internet?)'
  }
}

function Uninstall-Everything {
  Remove-Service
  Stop-Dashboard | Out-Null
  if (Test-Path $AppDir) { Remove-Item -Recurse -Force $AppDir }
  if (Test-Path $ConfigDir) { Remove-Item -Recurse -Force $ConfigDir }
  if (Test-Path $LicenseDir) { Remove-Item -Recurse -Force $LicenseDir }
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
    Write-EnvFile '0.0.0.0'
    Write-Host 'public access: reachable from other devices on 0.0.0.0.'
    Write-Host '  sign in with the license username and password (menu 12).'
    try {
      New-NetFirewallRule -DisplayName 'Mapsim Dashboard' -Direction Inbound -Protocol TCP -LocalPort 8765 -Action Allow -ErrorAction Stop | Out-Null
      Write-Host 'firewall  : inbound rule for port 8765 added'
    } catch {
      Write-Host 'firewall  : could not add a rule automatically - allow port 8765 manually if needed'
    }
  }
  if ($Service) {
    Install-Service
    Write-Host 'task installed and enabled: the dashboard starts now and at every logon.'
    if (-not (Test-LicenseReady)) {
      Write-Host 'note: the dashboard needs a valid Mapsim license before it runs.'
      Write-Host '      open Mapsim_BOT and choose 12 (License).'
    }
  } elseif (-not $NoLaunch) {
    if (-not (Get-DashboardPid)) {
      Write-Host ''
      if (-not (Test-LicenseReady)) {
        Write-Host 'the dashboard was not started: a valid Mapsim license is required.'
        Write-Host 'open Mapsim_BOT and choose 12 (License).'
      } else {
        Write-Host 'starting the dashboard (local mode) ...'
        $port = 8765
        if ((Test-PortListening $port) -and -not (Test-DashboardUp $port)) {
          $port = 8766
          Write-Host "note: port 8765 is busy, using $port."
        }
        Start-Dashboard (Get-CurrentBind) $port
      }
    } else {
      Write-Host "the dashboard is already running (pid $(Get-DashboardPid))."
    }
  }
  Write-Host ''
  Write-Host "done. From now on manage everything with:  $ShimPath"
  return
}

Show-Menu
