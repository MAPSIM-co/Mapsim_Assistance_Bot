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
  [switch]$Console,
  [string]$Version
)

$ErrorActionPreference = 'Stop'
$Repo = 'MAPSIM-co/Mapsim_Assistance_Bot'
# Bumped whenever this file changes in a way an installed copy must receive: at
# start the menu compares this number with the copy published on main and
# replaces its own installed file when that one is newer (Update-MenuSelf).
$MapsimMenuVersion = '1.3.1'
$MenuUrl = "https://raw.githubusercontent.com/$Repo/main/Dashboard_Release/mapsim-menu.ps1"

# raw.githubusercontent.com keeps serving the previous file for a few minutes
# after a push. Measured here: right after 1.3.1 was published, a plain fetch of
# this menu still returned 1.3.0, so the installer and the self-update below both
# gave the customer the old build and reported success. The query string is part
# of the cache key, so a fresh value goes to the origin and the newest file is
# the one that lands. Release archives are unaffected and do not use this.
function Get-FreshUrl([string]$Url) {
  return $Url + '?v=' + [DateTime]::UtcNow.Ticks
}
# Used only when GitHub cannot be reached at all (offline, DNS, rate limit), so
# a first install can never land on a build older than the newest release known
# when this file was written. It is never installed over a newer build.
$FallbackVersion = 'dashboard-v1.0.9'
$AppDir = Join-Path $env:LOCALAPPDATA 'MapsimDashboard'
$Binary = Join-Path $AppDir 'MapsimDashboard.exe'
# Kept outside AppDir: an update replaces AppDir wholesale, and a menu that
# lived inside it would be deleted mid-update along with the running script.
$MenuDir = Join-Path $env:LOCALAPPDATA 'MapsimBOT'
$MenuPath = Join-Path $MenuDir 'mapsim-menu.ps1'
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
# The licence Agent (the EA half): the only thing on the customer machine that
# talks to the licence server. It used to have its own menu
# (Agent\mapsim-license.ps1), which meant two menus for one product; the
# customer now does everything from here and never sees a second entry point.
$AgentDir = Join-Path $MenuDir 'agent'
$AgentExe = Join-Path $AgentDir 'dist\mapsim-license-agent.exe'
$AgentPy = Join-Path $AgentDir 'mapsim_license_agent.py'
$AgentUrl = "https://raw.githubusercontent.com/$Repo/main/Agent/mapsim_license_agent.py"
$AgentLeaseFile = Join-Path $LicenseDir 'lease.json'
# The MQL5 folder(s) the Agent writes the lease into. One path per line; empty
# or missing means the Expert cannot see the licence at all.
$AgentMql5File = Join-Path $LicenseDir 'ea_mql5.txt'
$AgentTaskName = 'MapsimLicenseAgent'
$script:AgentLauncher = $null
$script:AgentSummary = $null
$script:AgentFields = $null
# Why the derived dashboard login could not be built; printed by the callers.
$script:DashboardLoginNote = ''
$VersionFile = Join-Path $ConfigDir 'dashboard.version'
$UpdatePolicyFile = Join-Path $ConfigDir 'update-policy'
$UpdateCacheFile = Join-Path $ConfigDir 'update-cache.json'

# ---------------------------------------------------------------- language (presentation only)
# Menu text is translated at the output layer: the Write-Host replacement below,
# Ui-Row, Ui-Item and Read-Default pass every string through Find-FaText before it
# is printed. A string with no entry and no matching pattern is printed unchanged,
# so both languages run exactly the same code and a missing line can never break
# the menu. The choice is stored in %APPDATA%\MapsimDashboard\dashboard-lang;
# press L in the main menu to switch.
#
# Persian is not drawn by the console: a console shows Persian letters unjoined
# and lays a line that mixes Persian with numbers and English words out piece by
# piece from the left, so the sentence reads scrambled on every Windows version
# and in every font. Persian mode therefore uses the window host below, which is
# the only host that shapes and orders the text correctly. English and the
# non-interactive switches keep the plain console.
$MenuLangFile = Join-Path $ConfigDir 'dashboard-lang'
$script:MapsimLang = 'en'
try {
  if (Test-Path $MenuLangFile) {
    $savedLang = (Get-Content -Path $MenuLangFile -Raw).Trim().ToLowerInvariant()
    if ($savedLang -eq 'fa') { $script:MapsimLang = 'fa' }
  }
} catch { }

$script:FaWord = @{
  'running'  = 'در حال اجرا'
  'stopped'  = 'متوقف'
  'enabled'  = 'فعال'
  'disabled' = 'غیرفعال'
  'installed'= 'نصب‌شده'
  'yes'      = 'بله'
  'no'       = 'خیر'
  'unknown'  = 'نامشخص'
  'saved'    = 'ذخیره‌شده'
  'not set'  = 'تنظیم‌نشده'
  'notify'   = 'اطلاع‌دهی'
  'auto'     = 'خودکار'
  'off'      = 'خاموش'
  'local'    = 'محلی'
  'internet' = 'اینترنت'
  'free'     = 'آزاد'
  'active'   = 'فعال'
  'not active' = 'غیرفعال'
}

$script:FaText = @{
  # --- main frame ---------------------------------------------------------
  'Dashboard'                         = 'داشبورد'
  'App'                               = 'برنامه'
  'Version'                           = 'نسخه'
  'Service'                           = 'اجرای خودکار'
  'Expert'                            = 'اکسپرت'
  'License'                           = 'لایسنس'
  'Access'                            = 'دسترسی'
  'Disk'                              = 'دیسک'
  'not installed'                     = 'نصب نشده'
  'unknown'                           = 'نامشخص'
  'saved'                             = 'ذخیره‌شده'
  'not set'                           = 'تنظیم‌نشده'

  # --- main menu items ----------------------------------------------------
  'Status'                            = 'وضعیت'
  'Start dashboard'                   = 'اجرای داشبورد'
  'Stop dashboard'                    = 'توقف داشبورد'
  'Install / update dashboard'        = 'نصب / بروزرسانی داشبورد'
  'Service management (start/stop/restart/enable/disable)' = 'مدیریت اجرای خودکار (اجرا / توقف / ری‌استارت / فعال / غیرفعال)'
  'Remove auto-start service'         = 'حذف اجرای خودکار'
  'Access mode (local / internet)'    = 'حالت دسترسی (فقط این رایانه / اینترنت)'
  'Uninstall everything'              = 'حذف کامل برنامه'
  'Expert Advisor: install / update'  = 'اکسپرت: نصب / بروزرسانی'
  'Expert Advisor: version check'     = 'اکسپرت: بررسی نسخه'
  'Disk space / server storage'       = 'فضای دیسک / ذخیره‌سازی'
  'License (one serial: Expert + dashboard)' = 'لایسنس (یک سریال: اکسپرت + داشبورد)'
  'Dashboard login'                   = 'ورود داشبورد'
  'ready'                             = 'آماده'
  'not built'                         = 'ساخته نشده'
  'Update policy (notify / auto / off)' = 'روش بروزرسانی (اطلاع / خودکار / خاموش)'
  'Exit'                              = 'خروج'
  # The L item names the language it switches TO, never the one on screen, so
  # it reads "Language: FA" in English and "زبان: EN" in Persian.
  'Language: FA'                      = 'زبان: EN'

  # --- prompts ------------------------------------------------------------
  'Enter Number Of List'              = 'شماره گزینه را وارد کنید'
  'choose 1-7'                        = 'یک شماره از ۱ تا ۷ وارد کنید'
  'choose 1-4 (0 = back)'             = 'یک شماره از ۱ تا ۴ وارد کنید (۰ = بازگشت)'
  'choose 1-3 (0 = back)'             = 'یک شماره از ۱ تا ۳ وارد کنید (۰ = بازگشت)'
  'choose 1 or 2'                     = '۱ یا ۲ را وارد کنید'
  'port'                              = 'پورت'
  'choose another port'               = 'پورت دیگری وارد کنید'
  'Press Enter to continue'           = 'برای ادامه کلید Enter را بزنید'
  'Press Enter to open the menu'      = 'برای باز شدن منو کلید Enter را بزنید'
  'paste your license (0 = back)'     = 'کد لایسنس را وارد کنید (۰ = بازگشت)'
  'license username (0 = back)'       = 'نام کاربری لایسنس (۰ = بازگشت)'
  'license password (0 = back)'       = 'رمز لایسنس (۰ = بازگشت)'

  # --- service menu -------------------------------------------------------
  'auto-start task'                   = 'اجرای خودکار'
  '1) Status / details'               = '۱) وضعیت / جزئیات'
  '2) Install and enable (start now and at every logon)' = '۲) نصب و فعال‌سازی (همین حالا و در هر ورود ویندوز اجرا شود)'
  '3) Start now'                      = '۳) اجرای همین حالا'
  '4) Stop now'                       = '۴) توقف همین حالا'
  '5) Restart now'                    = '۵) ری‌استارت همین حالا'
  '6) Enable at logon'                = '۶) فعال‌سازی در شروع ویندوز'
  '7) Disable at logon'               = '۷) غیرفعال‌سازی در شروع ویندوز'
  '0) Back to the main menu'          = '۰) بازگشت به منوی اصلی'
  'auto-start task:'                  = 'اجرای خودکار:'
  'task installed and enabled: the dashboard starts now and at every logon.' = 'اجرای خودکار نصب و فعال شد: داشبورد همین حالا و در هر ورود ویندوز اجرا می‌شود.'
  'the task was not installed.'       = 'اجرای خودکار نصب نشد.'
  'not installed yet - use menu 4.'   = 'هنوز نصب نشده — از گزینه ۴ استفاده کنید.'

  # --- update policy ------------------------------------------------------
  'dashboard updates'                 = 'بروزرسانی داشبورد'
  '1) notify - check when the menu starts and tell me (default)' = '۱) اطلاع‌دهی — هنگام باز شدن منو بررسی شود و نتیجه اعلام شود (پیش‌فرض)'
  '2) auto   - install a new version automatically when the menu starts' = '۲) خودکار — نسخه جدید هنگام باز شدن منو نصب شود'
  '3) off    - never check for updates' = '۳) خاموش — هرگز بروزرسانی بررسی نشود'
  '4) check now'                      = '۴) بررسی فوری'
  'policy: notify.'                   = 'روش بروزرسانی: اطلاع‌دهی.'
  'policy: auto - a new release installs at menu start.' = 'روش بروزرسانی: خودکار — نسخه جدید هنگام باز شدن منو نصب می‌شود.'
  'policy: off.'                      = 'روش بروزرسانی: خاموش.'
  'could not reach GitHub (offline or rate limited).' = 'به GitHub دسترسی نبود (اینترنت قطع است یا درخواست‌ها زیاد بوده).'
  'please choose 1-4.'                = 'یک شماره از ۱ تا ۴ وارد کنید.'
  'please choose 1-7.'                = 'یک شماره از ۱ تا ۷ وارد کنید.'

  # --- access and status messages -----------------------------------------
  'how should the dashboard be reachable?' = 'داشبورد از کجا در دسترس باشد؟'
  '1) local only   (this computer, http://127.0.0.1)' = '۱) فقط این رایانه (http://127.0.0.1)'
  '2) internet     (any device + this computer, sign in with the license)' = '۲) اینترنت (هر دستگاه + این رایانه، ورود با لایسنس)'
  'the dashboard is not installed yet - use menu 4.' = 'داشبورد هنوز نصب نشده — از گزینه ۴ استفاده کنید.'
  'the auto-start task is not installed - choose 2 first.' = 'اجرای خودکار نصب نشده — ابتدا گزینه ۲ را انتخاب کنید.'
  'start requested.'                  = 'درخواست اجرا ثبت شد.'
  'restart requested.'                = 'درخواست ری‌استارت ثبت شد.'
  'task stopped. It starts again at the next logon while it is enabled.' = 'اجرای خودکار متوقف شد. تا وقتی فعال باشد، در ورود بعدی ویندوز دوباره اجرا می‌شود.'
  'enabled: the dashboard starts automatically at the next logon.' = 'فعال شد: داشبورد در ورود بعدی ویندوز خودکار اجرا می‌شود.'
  'installed : yes'                   = 'نصب‌شده: بله'
  'enabled (starts at the next logon)' = 'فعال (در ورود بعدی ویندوز اجرا می‌شود)'
  'no (choose 6 to enable it)'        = 'خیر (برای فعال‌سازی گزینه ۶ را بزنید)'
  'installed : no (choose 2 to install it)' = 'نصب‌شده: خیر (برای نصب گزینه ۲ را بزنید)'
  'dashboard : not running'           = 'داشبورد: اجرا نشده'
  'dashboard is up to date'            = 'داشبورد بروز است'
  'Exit the menu? (y/N)'              = 'از منو خارج می‌شوید؟ (y/N)'

  # --- language ----------------------------------------------------------
  'Language'                          = 'زبان'
  'Persian'                           = 'فارسی'
  'English'                           = 'انگلیسی'
  'Dashboard control center'          = 'مرکز کنترل داشبورد'
  'please choose 1-14 or L.'          = 'یک شماره از ۱ تا ۱۴ یا L را وارد کنید.'
  'bye.'                              = 'خداحافظ.'

  # --- window host --------------------------------------------------------
  'note: the Persian window could not be opened; the menu continues in this console.' = 'توجه: پنجره فارسی باز نشد؛ منو در همین پنجره متنی ادامه پیدا می‌کند.'
  'note: Persian needs the window; press L and choose English for the console.' = 'توجه: فارسی به پنجره نیاز دارد؛ کلید L را بزنید و انگلیسی را برای همین پنجره متنی انتخاب کنید.'

  # --- license -----------------------------------------------------------
  # One serial, two programs: the dashboard login is derived from the Expert
  # licence, so the customer never buys or types a second one.
  'one serial for both halves: the Expert and the dashboard' = 'یک سریال برای هر دو بخش: اکسپرت و داشبورد'
  'dashboard login: not built yet'    = 'ورود داشبورد: هنوز ساخته نشده'
  'Dashboard login (built from your Expert licence - nothing extra to buy)' = 'ورود داشبورد (از لایسنس اکسپرت ساخته می‌شود — چیز اضافه‌ای لازم نیست)'
  '1) Build / refresh the dashboard login now' = '۱) ساخت / بازسازی ورود داشبورد'
  '2) Show the dashboard login status' = '۲) وضعیت ورود داشبورد'
  '3) Remove the saved dashboard login' = '۳) حذف ورود داشبورد ذخیره‌شده'
  'Expert licence (the serial from the shop)' = 'لایسنس اکسپرت (سریالی که از فروشگاه گرفتید)'
  '12) Enter an old dashboard licence (only if support sent one)' = '۱۲) ورود لایسنس قدیمی داشبورد (فقط اگر پشتیبانی فرستاده باشد)'
  'the dashboard login is ready - start the dashboard from the main menu (2).' = 'ورود داشبورد آماده است — داشبورد را از منوی اصلی (گزینه ۲) اجرا کنید.'
  'dashboard login : not prepared - item 1 builds it from your Expert licence' = 'ورود داشبورد: آماده نیست — گزینه ۱ آن را از لایسنس اکسپرت می‌سازد'
  'dashboard login : ACTIVE'          = 'ورود داشبورد: فعال'
  'dashboard login : NOT ACTIVE - the dashboard will not start (item 1 rebuilds it)' = 'ورود داشبورد: فعال نیست — داشبورد اجرا نمی‌شود (گزینه ۱ بازسازی می‌کند)'
  'remove the saved dashboard login? it is rebuilt from your Expert licence on the next start (y/n)' = 'ورود داشبورد ذخیره‌شده حذف شود؟ در اجرای بعدی از لایسنس اکسپرت ساخته می‌شود (y/N)'
  'dashboard login files:'            = 'فایل‌های ورود داشبورد:'
  'the dashboard login was removed.'   = 'ورود داشبورد حذف شد.'
  'the dashboard login was prepared from your Expert licence:' = 'ورود داشبورد از لایسنس اکسپرت شما ساخته شد:'
  '  it renews itself whenever the Expert licence is refreshed.' = '  با هر بازسازی لایسنس اکسپرت خودش بروز می‌شود.'
  'the dashboard runs on your Expert licence - preparing the login ...' = 'داشبورد با لایسنس اکسپرت شما کار می‌کند — در حال ساخت ورود ...'
  'the Expert licence is not active on this machine yet.' = 'لایسنس اکسپرت هنوز روی این رایانه فعال نیست.'
  'activate your serial in the License menu (item 4), then start the dashboard again.' = 'سریال خود را در منوی License (مورد ۴) فعال کنید، سپس داشبورد را دوباره اجرا کنید.'
  'this license was rejected:'        = 'این لایسنس رد شد:'
  'nothing was saved.'                = 'چیزی ذخیره نشد.'
  'license saved:'                    = 'لایسنس ذخیره شد:'
  'no license entered.'               = 'لایسنسی وارد نشد.'
  'back.'                             = 'بازگشت.'
  'no license is saved.'              = 'لایسنسی ذخیره نشده است.'
  'cancelled.'                        = 'لغو شد.'
  'cancelled - the running dashboard was not changed.' = 'لغو شد — داشبورد در حال اجرا تغییر نکرد.'
  'the username and password must not be empty.' = 'نام کاربری و رمز نباید خالی باشند.'
  'the license check failed:'         = 'بررسی لایسنس انجام نشد:'
  'the dashboard was not started. Rebuild the login from the License menu (item 1).' = 'داشبورد اجرا نشد. ورود را از منوی License (مورد ۱) بازسازی کنید.'
  'the dashboard was not started - the license is required (menu 12).' = 'داشبورد اجرا نشد — لایسنس لازم است (گزینه ۱۲).'
  'a valid Mapsim license is required to run the dashboard.' = 'برای اجرای داشبورد یک لایسنس معتبر Mapsim لازم است.'
  'the installed dashboard build does not support the license yet.' = 'نسخه نصب‌شده داشبورد هنوز از لایسنس پشتیبانی نمی‌کند.'
  'update it from menu 4 (Install / update dashboard), then enter the license (menu 12).' = 'آن را از گزینه ۴ (نصب / بروزرسانی داشبورد) بروزرسانی کنید، سپس لایسنس را وارد کنید (گزینه ۱۲).'
  'update it from menu 4 (Install / update dashboard), then try again.' = 'آن را از گزینه ۴ (نصب / بروزرسانی داشبورد) بروزرسانی کنید و دوباره تلاش کنید.'
  'update it from menu 4 (Install / update dashboard).' = 'آن را از گزینه ۴ (نصب / بروزرسانی داشبورد) بروزرسانی کنید.'
  'enter the license now? (y/n)'      = 'همین حالا لایسنس وارد شود؟ (y/n)'
  'dashboard login uses the license username/password' = 'ورود به داشبورد با نام کاربری و رمز لایسنس انجام می‌شود'
  '1) Enter / update license'         = '۱) ورود / بروزرسانی لایسنس'
  '2) Show license status'            = '۲) نمایش وضعیت لایسنس'
  '3) Remove saved license'           = '۳) حذف لایسنسِ ذخیره‌شده'
  'remove the saved license? the dashboard will not start without it (y/n)' = 'لایسنس ذخیره‌شده حذف شود؟ بدون آن داشبورد اجرا نمی‌شود (y/n)'
  'saved: no'                         = 'ذخیره‌شده: خیر'
  'please choose 1-3.'                = 'یک شماره از ۱ تا ۳ وارد کنید.'
  'no (choose 2 to install it)'       = 'خیر (برای نصب گزینه ۲ را بزنید)'

  # --- licence agent (the Expert's serial) ---------------------------------
  # One menu for the whole product: the Agent used to have its own window.
  'one menu for everything: the dashboard login and the Expert licence' = 'همه چیز در همین منو: ورود داشبورد و لایسنس اکسپرت'
  'Expert licence'                    = 'لایسنس اکسپرت'
  'Dashboard login (username / password)' = 'ورود داشبورد (نام کاربری / رمز)'
  'Expert licence (serial)'           = 'لایسنس اکسپرت (سریال)'
  '4) Activate the Expert with a serial' = '۴) فعال‌سازی اکسپرت با سریال'
  '5) Show the Expert licence status'  = '۵) نمایش وضعیت لایسنس اکسپرت'
  '6) Register the MetaTrader folder (MQL5)' = '۶) معرفی پوشه متاتریدر (MQL5)'
  '7) Refresh the Expert licence now'  = '۷) به‌روزرسانی همین حالا لایسنس اکسپرت'
  '8) Verify the licence locally'      = '۸) بررسی محلی لایسنس'
  '9) Device identity (for support)'   = '۹) شناسه دستگاه (برای پشتیبانی)'
  '10) Automatic refresh on / off'     = '۱۰) به‌روزرسانی خودکار روشن / خاموش'
  '11) Remove the licence from this machine' = '۱۱) حذف لایسنس از این دستگاه'
  'choose 0-11 (0 = back)'            = 'یک شماره از ۰ تا ۱۱ وارد کنید (۰ = بازگشت)'
  'please choose 0-12.'               = 'یک شماره از ۰ تا ۱۲ وارد کنید.'
  'please choose 0-11.'               = 'یک شماره از ۰ تا ۱۱ وارد کنید.'
  'not activated'                     = 'فعال نشده'
  'not readable - the Agent is missing' = 'خوانده نشد — Agent موجود نیست'
  'the licence Agent was downloaded to:' = 'Agent لایسنس در این مسیر دانلود شد:'
  'hint: check the internet, then try again; the dashboard is not affected.' = 'راهنما: اینترنت را بررسی کنید و دوباره تلاش کنید؛ به داشبورد دست زده نشد.'
  'the licence Agent is not installed yet.' = 'Agent لایسنس هنوز نصب نشده است.'
  'choose 5 or activate once - the menu downloads it automatically.' = 'گزینه ۵ را بزنید یا یک بار فعال‌سازی کنید — منو آن را خودکار دانلود می‌کند.'
  'error: Python was not found, and no frozen Agent is installed.' = 'خطا: Python پیدا نشد و نسخه بسته‌بندی‌شده Agent هم نصب نیست.'
  'hint: install Python 3, or drop the frozen mapsim-license-agent.exe into the agent\dist folder.' = 'راهنما: Python 3 را نصب کنید یا فایل mapsim-license-agent.exe را در پوشه agent\dist بگذارید.'
  'the EA reads the licence from <MQL5>\Files\MapsimLive.' = 'اکسپرت لایسنس را از <MQL5>\Files\MapsimLive می‌خواند.'
  'MQL5 folder (empty = find it automatically)' = 'مسیر پوشه MQL5 (خالی = جستجوی خودکار)'
  'the MetaTrader folder was not registered - without it the EA cannot see the licence.' = 'پوشه متاتریدر معرفی نشد — بدون آن اکسپرت لایسنس را نمی‌بیند.'
  'continue with the activation anyway? (y/n)' = 'بدون آن هم فعال‌سازی ادامه یابد؟ (y/N)'
  'licence serial (MAPSIM-XXXX-XXXX-XXXX-XXXX)' = 'سریال لایسنس (MAPSIM-XXXX-XXXX-XXXX-XXXX)'
  'no serial was entered.'             = 'سریالی وارد نشد.'
  'activated.'                        = 'فعال شد.'
  'that serial is not valid.'         = 'این سریال معتبر نیست.'
  'this serial was already used - ask support to move it to this machine.' = 'این سریال قبلاً استفاده شده — برای انتقال به این دستگاه با پشتیبانی تماس بگیرید.'
  'this machine could not be identified - send the device identity to support.' = 'این دستگاه شناسایی نشد — شناسه دستگاه (گزینه ۹) را برای پشتیبانی بفرستید.'
  'the licence server could not be reached - check the internet and try again.' = 'به سرور لایسنس دسترسی نبود — اینترنت را بررسی و دوباره تلاش کنید.'
  'the server refused the activation - read the message above.' = 'سرور فعال‌سازی را رد کرد — پیام بالا را بخوانید.'
  'this licence is revoked or suspended.' = 'این لایسنس لغو یا معلق شده است.'
  'this licence belongs to another machine - ask support to move it.' = 'این لایسنس برای دستگاه دیگری است — برای انتقال با پشتیبانی تماس بگیرید.'
  'in MetaTrader 5: attach the Expert to a chart and allow DLL imports.' = 'در MetaTrader 5: اکسپرت را روی چارت بیندازید و اجازه DLL بدهید.'
  'the licence was refreshed.'         = 'لایسنس به‌روز شد.'
  'the licence server could not be reached - check the internet.' = 'به سرور لایسنس دسترسی نبود — اینترنت را بررسی کنید.'
  'this licence belongs to another machine.' = 'این لایسنس برای دستگاه دیگری است.'
  'the local licence is valid.'       = 'لایسنس محلی معتبر است.'
  'the local licence is not valid - see the code above.' = 'لایسنس محلی معتبر نیست — کد بالا را ببینید.'
  'automatic licence refresh removed.' = 'به‌روزرسانی خودکار لایسنس حذف شد.'
  'automatic licence refresh enabled (every hour).' = 'به‌روزرسانی خودکار لایسنس فعال شد (هر ساعت).'
  'the scheduled refresh could not be created.' = 'به‌روزرسانی زمان‌بندی‌شده ساخته نشد.'
  'this machine has no licence to remove.' = 'لایسنسی برای حذف روی این دستگاه نیست.'
  'remove the licence from this machine? the Expert stops trading (y/n)' = 'لایسنس از این دستگاه حذف شود؟ اکسپرت معامله نمی‌کند (y/N)'
  'the licence was removed from this machine.' = 'لایسنس از این دستگاه حذف شد.'
  # A verdict is a word, never a sentence: it is printed inside a line.
  'ACTIVE'                            = 'فعال'
  'GRACE'                             = 'دورهٔ ارفاق'
  'EXPIRED'                           = 'منقضی'
  'NO_LEASE'                          = 'بدون لایسنس'
  'REVOKED'                           = 'لغو‌شده'
  'SUSPENDED'                         = 'معلق'
  'assist'                            = 'دستیار'
  'full'                              = 'کامل'

  # --- start / stop / status lines ---------------------------------------
  'error: a valid Mapsim license is required - the dashboard was not started.' = 'خطا: لایسنس معتبر Mapsim لازم است — داشبورد اجرا نشد.'
  'open menu 12 (License) and enter or fix the license.' = 'گزینه ۱۲ (لایسنس) را باز کنید و لایسنس را وارد یا اصلاح کنید.'
  'note: the auto-start task was stopped for this manual start (it starts again at the next logon).' = 'توجه: برای این اجرای دستی، اجرای خودکار موقتاً متوقف شد (در ورود بعدی ویندوز دوباره اجرا می‌شود).'
  'note: the auto-start task is installed and will start the dashboard again at the next logon (menu 6 removes it).' = 'توجه: اجرای خودکار نصب است و در ورود بعدی ویندوز داشبورد را دوباره اجرا می‌کند (گزینه ۶ آن را حذف می‌کند).'
  'dashboard is up:'                  = 'داشبورد اجرا شد:'
  'access  : the license username and password (menu 12)' = 'دسترسی: نام کاربری و رمز لایسنس (گزینه ۱۲)'
  'auto-start task stopped (it starts again at the next logon; menu 6 removes it).' = 'اجرای خودکار متوقف شد (در ورود بعدی ویندوز دوباره اجرا می‌شود؛ گزینه ۶ آن را حذف می‌کند).'
  'the dashboard is not running.'     = 'داشبورد اجرا نشده است.'
  'the dashboard was not restarted.'  = 'داشبورد ری‌استارت نشد.'
  'disabled: it will not start automatically any more. The running dashboard keeps running until you stop it (4).' = 'غیرفعال شد: دیگر خودکار اجرا نمی‌شود. داشبوردِ در حال اجرا تا وقتی خودتان متوقفش نکنید (گزینه ۴) اجرا می‌ماند.'
  'busy (another program)'            = 'در استفاده برنامه دیگر'

  # --- disk ---------------------------------------------------------------
  'disk space:'                       = 'فضای دیسک:'
  'dashboard folders:'                = 'پوشه‌های داشبورد:'
  'logs are trimmed automatically above 256 KB (the newest lines are kept).' = 'لاگ‌ها بالای ۲۵۶ کیلوبایت خودکار کوتاه می‌شوند (جدیدترین خطوط می‌مانند).'
  'hint: free up space by removing old dashboard logs or an unused MT5 copy.' = 'راهنما: با حذف لاگ‌های قدیمی داشبورد یا یک نسخه بلااستفاده MT5 فضا آزاد کنید.'

  # --- main menu actions --------------------------------------------------
  'no service is installed.'          = 'اجرای خودکار نصب نشده است.'
  'remove the auto-start service? (y/n)' = 'اجرای خودکار حذف شود؟ (y/N)'
  'service removed (the app itself stays installed).' = 'اجرای خودکار حذف شد (خود برنامه نصب‌شده می‌ماند).'
  'sign-in is always the license username and password (menu 12).' = 'ورود همیشه با نام کاربری و رمز لایسنس است (گزینه ۱۲).'
  '1) local only'                     = '۱) فقط این رایانه'
  '2) internet (any device on your network / the internet)' = '۲) اینترنت (هر دستگاه در شبکه یا اینترنت)'
  'saved: internet access on 0.0.0.0.' = 'ذخیره شد: دسترسی اینترنت روی 0.0.0.0.'
  'saved: local only.'                = 'ذخیره شد: فقط این رایانه.'
  'restart the dashboard now? (y/n)'  = 'داشبورد همین حالا ری‌استارت شود؟ (y/N)'
  'this removes the dashboard app, config, service, task and shortcuts.' = 'با این کار برنامه، تنظیمات، اجرای خودکار و میان‌برهای داشبورد حذف می‌شوند.'
  'nothing is changed in MetaTrader 5 or in the Expert Advisor.' = 'به MetaTrader 5 و اکسپرت هیچ تغییری داده نمی‌شود.'
  'are you sure? type y to confirm'   = 'مطمئن هستید؟ برای تأیید y را بزنید'
  'stop it and restart with the new settings? (y/n)' = 'متوقف شود و با تنظیمات جدید اجرا شود؟ (y/N)'
  'error: could not reach GitHub to find the latest Expert version.' = 'خطا: برای یافتن آخرین نسخه اکسپرت به GitHub دسترسی نبود.'

  # --- expert advisor -----------------------------------------------------
  'error: could not determine the latest Expert version - check your internet connection.' = 'خطا: آخرین نسخه اکسپرت مشخص نشد — اتصال اینترنت را بررسی کنید.'
  'error: no MetaTrader 5 data folder (MQL5) was found.' = 'خطا: پوشه داده MetaTrader 5 (MQL5) پیدا نشد.'
  'hint: install MT5, run it once (File -> Open Data Folder), then retry.' = 'راهنما: MT5 را نصب و یک بار اجرا کنید (منوی File ← Open Data Folder) و دوباره تلاش کنید.'
  'MQL5 folders found:'               = 'پوشه‌های MQL5 پیدا شده:'
  'next steps in MetaTrader 5:'       = 'مراحل بعدی در MetaTrader 5:'
  '1) restart MetaTrader 5'           = '۱) MetaTrader 5 را ری‌استارت کنید'
  '2) allow DLL imports in the EA options' = '۲) در تنظیمات اکسپرت اجازه وارد کردن DLL را بدهید'
  '3) attach the Mapsim Assistance Bot Expert to your chart' = '۳) اکسپرت Mapsim Assistance Bot را روی چارت خود بیندازید'
  '4) activate your serial in the License menu (item 4)' = '۴) سریال خود را در منوی License فعال کنید (مورد ۴)'
  '5) the same serial opens the dashboard (main menu - 2)' = '۵) همان سریال داشبورد را نیز باز می‌کند (منوی اصلی — گزینه ۲)'
  'Expert Advisor: not installed through Mapsim_BOT' = 'اکسپرت: از طریق Mapsim_BOT نصب نشده'
  '(could not check - no internet?)'  = '(بررسی نشد — اینترنت قطع است؟)'
  'a newer version is available - install it now? (y/n)' = 'نسخه جدیدتری موجود است — همین حالا نصب شود؟ (y/N)'

  # --- uninstall / bootstrap ---------------------------------------------
  'Mapsim Live Dashboard removed completely (MT5 and the EA were not touched).' = 'Mapsim Live Dashboard کامل حذف شد (به MT5 و اکسپرت دست زده نشد).'
  'public access: reachable from other devices on 0.0.0.0.' = 'دسترسی عمومی: از دستگاه‌های دیگر روی 0.0.0.0 در دسترس است.'
  'sign in with the license username and password (menu 12).' = 'با نام کاربری و رمز لایسنس وارد شوید (گزینه ۱۲).'
  'service removed.'                  = 'اجرای خودکار حذف شد.'
  'note: the dashboard needs a valid Mapsim license before it runs.' = 'توجه: داشبورد پیش از اجرا به لایسنس معتبر Mapsim نیاز دارد.'
  'open Mapsim_BOT and choose 12 (License).' = 'Mapsim_BOT را باز کنید و گزینه ۱۲ (لایسنس) را انتخاب کنید.'
  'the dashboard was not started: a valid Mapsim license is required.' = 'داشبورد اجرا نشد: لایسنس معتبر Mapsim لازم است.'
  'starting the dashboard (local mode) ...' = 'در حال اجرای داشبورد (حالت محلی) ...'
  'auto-start task started again with the new version.' = 'اجرای خودکار با نسخه جدید دوباره اجرا شد.'
  'stopping the manually started dashboard - the task will run it.' = 'داشبوردی که دستی اجرا شده بود متوقف می‌شود — اجرای خودکار آن را اجرا می‌کند.'

  # --- licence screens (values, tags, rows) --------------------------------
  # The three verdict tags: the whole point is that these are the only words a
  # customer has to recognise to know whether something is fine.
  '[ OK ]'                            = '[ موفق ]'
  '[WARN]'                            = '[ هشدار ]'
  '[FAIL]'                            = '[ خطا ]'
  '[INFO]'                            = '[ اطلاع ]'
  'Licence'                           = 'لایسنس'
  'Valid to'                          = 'معتبر تا'
  'Terminal'                          = 'متاتریدر'
  'Refresh'                           = 'بروزرسانی'
  'Next step'                         = 'قدم بعدی'
  'Result'                            = 'نتیجه'
  'Product'                           = 'محصول'
  'Grace to'                          = 'مهلت تا'
  'Lease'                             = 'مهلت تمدید'
  'Rights'                            = 'دسترسی‌ها'
  'Agent'                             = 'ایجنت'
  'Device'                            = 'دستگاه'
  'Note'                              = 'یادداشت'
  'Login'                             = 'کاربر'
  'Password'                          = 'رمز عبور'
  'Account'                           = 'حساب'
  'Files'                             = 'فایل‌ها'
  'it renews itself whenever the Expert licence is refreshed.' = 'با هر بار به‌روزرسانی لایسنس اکسپرت، خودکار تمدید می‌شود.'
  'Dashboard login - same serial, nothing extra to buy' = 'ورود داشبورد — همان سریال، چیز اضافه‌ای لازم نیست'
  'Expert licence - the serial from the shop' = 'لایسنس اکسپرت — همان سریالی که از فروشگاه خریدید'
  'Support'                           = 'پشتیبانی'
  'Build / refresh the dashboard login now' = 'ساخت / بازسازی ورود داشبورد همین حالا'
  'Show the dashboard login status'  = 'نمایش وضعیت ورود داشبورد'
  'Remove the saved dashboard login' = 'حذف ورود داشبورد ذخیره‌شده'
  'Activate the Expert with a serial' = 'فعال‌سازی اکسپرت با سریال'
  'Show the Expert licence in detail' = 'نمایش جزئیات لایسنس اکسپرت'
  'Register the MetaTrader folder (MQL5)' = 'ثبت پوشه متاتریدر (MQL5)'
  'Refresh the Expert licence now'   = 'به‌روزرسانی فوری لایسنس اکسپرت'
  'Verify the licence locally (no internet)' = 'بررسی لایسنس به‌صورت محلی (بدون اینترنت)'
  'Device identity (send this to support)' = 'شناسه دستگاه (برای ارسال به پشتیبانی)'
  'Automatic refresh on / off'      = 'روشن/خاموش کردن بروزرسانی خودکار'
  'Remove the licence from this machine' = 'حذف لایسنس از این رایانه'
  'Enter an old dashboard licence (only if support sent one)' = 'وارد کردن لایسنس قدیمی داشبورد (فقط اگر پشتیبانی فرستاده باشد)'
  'Back to the main menu'           = 'بازگشت به منوی اصلی'

  # --- licence verdicts and one-line results --------------------------------
  'ready - built from the Expert licence' = 'آماده — از لایسنس اکسپرت ساخته شده'
  'unreadable - item 1 rebuilds it' = 'خوانا نیست — گزینه ۱ بازسازی می‌کند'
  'the dashboard login ends before the licence - rebuild it (item 1)' = 'ورود داشبورد پیش از لایسنس تمام می‌شود — با گزینه ۱ بازسازی کنید'
  'not built yet - item 1 or it builds itself on start' = 'هنوز ساخته نشده — گزینه ۱، یا هنگام اجرا خودکار ساخته می‌شود'
  'not built yet - item 1 builds it from your Expert licence.' = 'هنوز ساخته نشده — گزینه ۱ آن را از لایسنس اکسپرت می‌سازد.'
  'not registered - the Expert cannot read the licence' = 'ثبت نشده — اکسپرت لایسنس را نمی‌بیند'
  'hourly task installed'           = 'زمان‌بند ساعتی نصب است'
  'not scheduled - item 10 turns it on' = 'زمان‌بند نصب نیست — گزینه ۱۰ آن را روشن می‌کند'
  'not in this lease yet - refresh the licence (item 7)' = 'در این نسخه از لایسنس نیست — آن را به‌روزرسانی کنید (گزینه ۷)'
  'nothing to do - the Expert and the dashboard are ready' = 'کاری لازم نیست — اکسپرت و داشبورد آماده‌اند'
  'activate the Expert first - item 4 asks for the serial' = 'ابتدا اکسپرت را فعال کنید — گزینه ۴ سریال را می‌پرسد'
  'the licence has expired - it still works for a few days, renew it now' = 'لایسنس منقضی شده — چند روز مهلت دارد، همین حالا تمدید کنید'
  'the licence is not active - refresh it (item 7), then contact support if it stays red' = 'لایسنس فعال نیست — گزینه ۷ را بزنید و اگر قرمز ماند با پشتیبانی تماس بگیرید'
  'register the MetaTrader folder (item 6) or the Expert reads no licence' = 'پوشه متاتریدر را ثبت کنید (گزینه ۶) وگرنه اکسپرت لایسنس نمی‌بیند'
  'build the dashboard login from the same serial (item 1)' = 'ورود داشبورد را از همان سریال بسازید (گزینه ۱)'
  'the dashboard login is not built yet - item 1 builds it from your Expert licence.' = 'ورود داشبورد هنوز ساخته نشده — گزینه ۱ آن را از لایسنس اکسپرت می‌سازد.'
  'the dashboard will not start until item 1 rebuilds this login.' = 'داشبورد تا زمانی که گزینه ۱ این ورود را نسازد اجرا نمی‌شود.'
  'install or update it from the main menu, item 4.' = 'آن را از منوی اصلی، گزینه ۴ نصب یا به‌روزرسانی کنید.'
  'no licence on this machine yet - item 4 activates one.' = 'هنوز لایسنسی روی این رایانه نیست — گزینه ۴ آن را فعال می‌کند.'
  'the serial from the shop is the only thing you need.' = 'تنها چیزی که لازم دارید همان سریال فروشگاه است.'
  'the MetaTrader folder is registered - the Expert can read the licence now.' = 'پوشه متاتریدر ثبت شد — اکسپرت اکنون لایسنس را می‌بیند.'
  'the MetaTrader folder was not registered - the Expert reads no licence without it.' = 'پوشه متاتریدر ثبت نشد — بدون آن اکسپرت لایسنس نمی‌بیند.'
  'item 6 asks again; the folder ends in \MQL5.' = 'گزینه ۶ دوباره می‌پرسد؛ نام پوشه با \MQL5 تمام می‌شود.'
  'step 1 of 2: tell the Agent where MetaTrader keeps its files.' = 'گام ۱ از ۲: محل فایل‌های متاتریدر را به ایجنت بگویید.'
  'step 2 of 2: paste the serial exactly as the shop sent it.' = 'گام ۲ از ۲: سریال را دقیقاً همان‌طور که فروشگاه فرستاده بچسبانید.'
  'no serial was entered - nothing was changed.' = 'سریالی وارد نشد — هیچ چیز تغییر نکرد.'
  'the serial was accepted - the Expert is active on this machine.' = 'سریال پذیرفته شد — اکسپرت روی این رایانه فعال است.'
  'that serial is not valid - check for a typo in what you pasted.' = 'این سریال معتبر نیست — با دقت بررسی کنید درست چسبانده اید.'
  'this machine could not be identified - send the device identity (item 9) to support.' = 'این رایانه شناسایی نشد — شناسه دستگاه (گزینه ۹) را برای پشتیبانی بفرستید.'
  'the server refused the activation - the reason is printed above.' = 'سرور فعال‌سازی را رد کرد — دلیل در بالای صفحه نوشته شده است.'
  'this licence is revoked or suspended - contact support.' = 'این لایسنس باطل یا معلق شده — با پشتیبانی تماس بگیرید.'
  'next, in MetaTrader 5:'         = 'مرحله بعد، در متاتریدر ۵:'
  '  1  open the chart you trade on' = '  ۱  چارتی که می‌خواهید معامله کنید را باز کنید'
  '  2  attach Mapsim_Assistance_Bot and allow DLL imports' = '  ۲  اکسپرت Mapsim_Assistance_Bot را روی چارت بیندازید و اجازه DLL بدهید'
  'the dashboard login was rebuilt from the same serial - nothing extra to buy.' = 'ورود داشبورد از همان سریال بازسازی شد — چیز اضافه‌ای لازم نیست.'
  'the dashboard login was renewed with it.' = 'ورود داشبورد هم همراهش تمدید شد.'
  'the Expert keeps working while the current lease lasts.' = 'تا پایان مهلت فعلی، اکسپرت به کار خود ادامه می‌دهد.'
  'the licence on this machine is valid - no internet needed.' = 'لایسنس روی این رایانه معتبر است — به اینترنت نیاز نیست.'
  'the licence on this machine is not valid - the reason is printed above.' = 'لایسنس روی این رایانه معتبر نیست — دلیل در بالای صفحه نوشته شده است.'
  'refresh it (item 7); if it stays red, send item 9 to support.' = 'گزینه ۷ را بزنید؛ اگر باز قرمز ماند گزینه ۹ را برای پشتیبانی بفرستید.'
  'cancelled - the licence was not touched.' = 'لغو شد — به لایسنس دست زده نشد.'
  'the serial is not lost: item 4 activates it again on this machine.' = 'سریال از بین نرفته: گزینه ۴ دوباره آن را روی این رایانه فعال می‌کند.'
}

# Each rule matches the trimmed line and receives {0}, {1} ... for its groups.
# The groups are translated by the same lookup before the rule text is built,
# so "service    : installed, enabled, running" translates in one step and a new
# value word only needs a dictionary entry, never a new rule.
# Label rules come first, then the values they can contain.
$script:FaRules = @(
  # --- lines that look like a label but are not ---------------------------
  @{ p = '^version\s*:\s*(.+)  \(update (.+) available - menu 4\)$'; r = 'نسخه: {0}  (بروزرسانی {1} موجود است — گزینه ۴)' }
  @{ p = '^warning: this license expires in (\d+) day\(s\) - renew it soon\.$'; r = 'هشدار: این لایسنس تا {0} روز دیگر منقضی می‌شود — زودتر تمدید کنید.' }

  # --- label : value lines ------------------------------------------------
  @{ p = '^system\s*:\s*(.+)$'; r = 'سیستم: {0}' }
  @{ p = '^app\s*:\s*(.+)$'; r = 'برنامه: {0}' }
  @{ p = '^version\s*:\s*(.+)$'; r = 'نسخه: {0}' }
  @{ p = '^dashboard\s*:\s*(.+)$'; r = 'داشبورد: {0}' }
  @{ p = '^service\s*:\s*(.+)$'; r = 'اجرای خودکار: {0}' }
  @{ p = '^bind\s*:\s*(.+)$'; r = 'آدرس اتصال: {0}' }
  @{ p = '^license\s*:\s*(.+)$'; r = 'لایسنس: {0}' }
  @{ p = '^Expert licence\s*:\s*(.+)$'; r = 'لایسنس اکسپرت: {0}' }
  @{ p = '^expert\s*:\s*(.+)$'; r = 'اکسپرت: {0}' }
  @{ p = '^disk\s*:\s*(.+)$'; r = 'دیسک: {0}' }
  @{ p = '^firewall\s*:\s*(.+)$'; r = 'فایروال: {0}' }
  @{ p = '^port (\d+)\s*:\s*(.+)$'; r = 'پورت {0}: {1}' }
  @{ p = '^installed\s*:\s*(.+)$'; r = 'نصب‌شده: {0}' }
  @{ p = '^enabled\s*:\s*(.+)$'; r = 'فعال: {0}' }
  @{ p = '^running\s*:\s*(.+)$'; r = 'اجرا: {0}' }
  @{ p = '^url\s*:\s*(.+)$'; r = 'آدرس: {0}' }
  @{ p = '^logs\s*:\s*(.+)$'; r = 'لاگ‌ها: {0}' }
  @{ p = '^user\s*:\s*(.+)$'; r = 'کاربر: {0}' }
  @{ p = '^account\s*:\s*(.+)$'; r = 'حساب: {0}' }
  @{ p = '^expires\s*:\s*(.+) \((\d+) day\(s\) left\)$'; r = 'انقضا: {0} ({1} روز باقی‌مانده)' }
  @{ p = '^status\s*:\s*(.+) - (.+)$'; r = 'وضعیت: {0} — {1}' }
  @{ p = '^warning\s*:\s*(.+)$'; r = 'هشدار: {0}' }
  @{ p = '^installed version\s*:\s*(.+)$'; r = 'نسخه نصب‌شده: {0}' }
  @{ p = '^last updated\s*:\s*(.+)$'; r = 'آخرین بروزرسانی: {0}' }
  @{ p = '^latest version\s*:\s*(.+)$'; r = 'آخرین نسخه: {0}' }

  # --- values inside those lines -----------------------------------------
  @{ p = '^dashboard login: ready \((.+)\)$'; r = 'ورود داشبورد: آماده ({0})' }
  # The dashboard row of the card. The date inside the sealed login is compared
  # with the end of the licence, so a login that is complete but dated to the
  # 72 h lease reads as a warning instead of a green "ready".
  @{ p = '^ready - ends (.+)$'; r = 'آماده — تا {0}' }
  @{ p = '^ends (.+) - the licence ends later, item 1 rebuilds it$'; r = 'تا {0} است ولی لایسنس دیرتر تمام می‌شود — گزینه ۱ بازسازی می‌کند' }
  @{ p = '^the login ends (.+) but the licence ends (.+) UTC - item 1 rebuilds it$'; r = 'ورود تا {0} است ولی لایسنس تا {1} UTC — گزینه ۱ بازسازی می‌کند' }
  @{ p = '^the Expert licence cannot open the dashboard \((.+)\): (.+)$'; r = 'لایسنس اکسپرت داشبورد را باز نمی‌کند ({0}): {1}' }
  @{ p = '^the dashboard login could not be saved - (.+)$'; r = 'ورود داشبورد ذخیره نشد — {0}' }
  @{ p = '^  login    : (.+)$'; r = '  کاربر: {0}' }
  @{ p = '^  password : (.+)$'; r = '  رمز: {0}' }
  @{ p = '^  account  : (.+)$'; r = '  حساب: {0}' }
  @{ p = '^  valid to : (.+)$'; r = '  معتبر تا: {0}' }
  @{ p = '^running \(pid (\d+)\)$'; r = 'در حال اجرا (شناسه {0})' }
  @{ p = '^pid (\d+), port (\d+)$'; r = 'شناسه {0}، پورت {1}' }
  @{ p = '^installed \((.+)\)$'; r = 'نصب‌شده ({0})' }
  @{ p = '^installed, (.+), (.+)$'; r = 'نصب‌شده، {0}، {1}' }
  @{ p = '^active - (.+), expires (.+)$'; r = 'فعال — {0}، انقضا {1}' }
  # The Expert's licence line: a verdict, an optional product and the days left.
  @{ p = '^([A-Z_]+) \((assist|full)\), (\d+) day\(s\) left$'; r = '{0} ({1})، {2} روز باقی‌مانده' }
  @{ p = '^([A-Z_]+), (\d+) day\(s\) left$'; r = '{0}، {1} روز باقی‌مانده' }
  @{ p = '^(.+) \((.*)\) - dashboard will not start$'; r = '{0} ({1}) — داشبورد اجرا نمی‌شود' }
  @{ p = '^dashboard answering \(HTTP (\d+)\)$'; r = 'داشبورد پاسخ می‌دهد (HTTP {0})' }
  @{ p = '^(.+) \(trimmed automatically above 256 KB\)$'; r = '{0} (بالای ۲۵۶ کیلوبایت خودکار کوتاه می‌شود)' }
  @{ p = '^inbound rule for port (\d+) added$'; r = 'قاعده ورودی فایروال برای پورت {0} اضافه شد' }
  @{ p = '^could not add a rule automatically - allow port (\d+) manually if needed$'; r = 'قاعده فایروال خودکار اضافه نشد — در صورت نیاز پورت {0} را دستی باز کنید' }

  # --- one-line messages --------------------------------------------------
  @{ p = '^internet \(0\.0\.0\.0\) - port (\d+)$'; r = 'اینترنت (0.0.0.0) — پورت {0}' }
  @{ p = '^local only - port (\d+)$'; r = 'فقط این رایانه — پورت {0}' }
  @{ p = '^current policy: (.+)$'; r = 'روش بروزرسانی فعلی: {0}' }
  @{ p = '^current bind: (.+)$'; r = 'آدرس اتصال فعلی: {0}' }
  @{ p = '^port (\d+) is busy\.$'; r = 'پورت {0} آزاد نیست.' }
  @{ p = '^port (\d+) is already used by another program\.$'; r = 'پورت {0} را برنامه دیگری استفاده می‌کند.' }
  @{ p = '^error: port (\d+) is already used by another program\.$'; r = 'خطا: پورت {0} را برنامه دیگری استفاده می‌کند.' }
  @{ p = '^note: port (\d+) is busy, using (\d+)\.$'; r = 'توجه: پورت {0} آزاد نبود، از پورت {1} استفاده می‌شود.' }
  @{ p = '^dashboard is up: (.+)$'; r = 'داشبورد اجرا شد: {0}' }
  @{ p = '^it did not answer on port (\d+) - see status \(1\)\.$'; r = 'روی پورت {0} پاسخ نداد — وضعیت (گزینه ۱) را ببینید.' }
  @{ p = '^the dashboard did not answer on port (\d+); see (.+)$'; r = 'داشبورد روی پورت {0} پاسخ نداد؛ {1} را ببینید.' }
  @{ p = '^the dashboard is already running \(pid (\d+), port (\d+), bind (.+)\)\.$'; r = 'داشبورد از قبل در حال اجراست (شناسه {0}، پورت {1}، آدرس اتصال {2}).' }
  @{ p = '^the dashboard is already running \(pid (\d+)\)\.$'; r = 'داشبورد از قبل در حال اجراست (شناسه {0}).' }
  @{ p = '^dashboard stopped \(pids: (.+)\)\.$'; r = 'داشبورد متوقف شد (شناسه‌ها: {0}).' }
  @{ p = '^latest release: (.+)$'; r = 'آخرین انتشار: {0}' }
  @{ p = '^update available: (.+) -> (.+) \(menu 4 installs it\)$'; r = 'بروزرسانی موجود است: {0} ← {1} (گزینه ۴ نصب می‌کند)' }
  @{ p = '^dashboard update available: (.+) -> (.+) \(menu 4 installs it\)$'; r = 'بروزرسانی داشبورد موجود است: {0} ← {1} (گزینه ۴ نصب می‌کند)' }
  @{ p = '^automatic update: (.+) -> (.+)$'; r = 'بروزرسانی خودکار: {0} ← {1}' }
  @{ p = '^version (\d[\d.]*) is already installed - reinstall\? \(y/n\)$'; r = 'نسخه {0} از قبل نصب است — دوباره نصب شود؟ (y/N)' }
  @{ p = '^latest Expert version: (.+)$'; r = 'آخرین نسخه اکسپرت: {0}' }
  @{ p = '^downloading Expert (.+) \.\.\.$'; r = 'در حال دانلود اکسپرت {0} ...' }
  @{ p = '^note: no Windows build found - using (.+)$'; r = 'توجه: نسخه ویندوزی پیدا نشد — از {0} استفاده می‌شود.' }
  @{ p = '^choose 1-(\d+) \(or ''a'' for all\)$'; r = 'یک شماره از ۱ تا {0} (یا ''a'' برای همه)' }
  @{ p = '^done\. From now on manage everything with:\s*(.+)$'; r = 'تمام شد. از این پس همه چیز را با این دستور مدیریت کنید:  {0}' }
  @{ p = '^the dashboard was not (.+)-ed\.$'; r = 'داشبورد {0} نشد.' }
  @{ p = '^activation failed \(code (\d+)\)\.$'; r = 'فعال‌سازی ناموفق (کد {0}).' }
  @{ p = '^refresh failed \(code (\d+)\)\.$'; r = 'به‌روزرسانی ناموفق (کد {0}).' }
  @{ p = '^error: the licence Agent could not be installed - (.+)$'; r = 'خطا: Agent لایسنس نصب نشد — {0}' }

  @{ p = '^\[ OK \] (.+)$'; r = '[ موفق ] {0}' }
  @{ p = '^\[WARN\] (.+)$'; r = '[ هشدار ] {0}' }
  @{ p = '^\[FAIL\] (.+)$'; r = '[ خطا ] {0}' }
  @{ p = '^(.+) - grace period, renew now$'; r = '{0} — مهلت پایان، همین حالا تمدید کنید' }
  @{ p = '^linked: (\d+) MetaTrader folder\(s\)$'; r = 'متصل: {0} پوشه متاتریدر' }
  @{ p = '^(\d{4}-\d{2}-\d{2} \d{2}:\d{2}) UTC$'; r = '{0} به وقت جهانی' }
  @{ p = '^(\d{4}-\d{2}-\d{2} \d{2}:\d{2}) UTC - expired$'; r = '{0} به وقت جهانی — منقضی' }
  @{ p = '^(\d{4}-\d{2}-\d{2} \d{2}:\d{2}) UTC\s+\((\d+) day\(s\) left\)$'; r = '{0} به وقت جهانی ({1} روز باقی‌مانده)' }
  @{ p = '^(\d{4}-\d{2}-\d{2} \d{2}:\d{2}) UTC \((\d+) day\(s\)\)$'; r = '{0} به وقت جهانی ({1} روز)' }
  @{ p = '^(\d+) of 8 - no automatic entry$'; r = '{0} از ۸ — بدون ورود خودکار' }
  @{ p = '^(\d+) of 8$'; r = '{0} از ۸' }
  @{ p = '^License valid for (\d+) day\(s\)\.$'; r = 'لایسنس تا {0} روز دیگر معتبر است.' }
  @{ p = '^valid until (.+)\.$'; r = 'معتبر تا {0}.' }

  # --- numbers ------------------------------------------------------------
  @{ p = '^(\S+)\s+([\d.,]+) GB free of\s+([\d.,]+) GB\s+\((\d+)% used\)\s*(.*)$'; r = '{0}   {1} گیگابایت آزاد از {2} گیگابایت ({3}٪ مصرف)   {4}' }
  @{ p = '^([\d.,]+) GB free of ([\d.,]+) GB \((\d+)% used\)$'; r = '{0} گیگابایت آزاد از {1} گیگابایت ({2}٪ مصرف)' }
  @{ p = '^([\d.,]+) GB free of ([\d.,]+) GB$'; r = '{0} گیگابایت آزاد از {1} گیگابایت' }
  @{ p = '^log ([\d.,]+) MB\s+(.+)$'; r = 'لاگ {0} مگابایت   {1}' }
  @{ p = '^([\d.,]+) MB\s+(.+)$'; r = '{0} مگابایت   {1}' }
)

function Find-FaText([string]$Text) {
  return Find-FaTextDepth $Text 0
}

# A string with no entry and no matching rule is printed unchanged, so the two
# languages always run exactly the same code path.
function Find-FaTextDepth([string]$Text, [int]$Depth) {
  if ($script:MapsimLang -ne 'fa' -or [string]::IsNullOrWhiteSpace($Text)) { return $Text }
  if ($Text -match '[\u0600-\u06FF]') { return $Text }
  if ($Text -notmatch '[A-Za-z]') { return $Text }
  $lead = [regex]::Match($Text, '^\s*').Value
  $trail = [regex]::Match($Text, '\s*$').Value
  $core = $Text.Substring($lead.Length, $Text.Length - $lead.Length - $trail.Length)
  if (-not $core) { return $Text }
  if ($script:FaText.ContainsKey($core)) { return $lead + $script:FaText[$core] + $trail }
  foreach ($rule in $script:FaRules) {
    if ($core -match $rule.p) {
      $values = @()
      for ($i = 1; $i -lt $Matches.Count; $i++) { $values += [string]$Matches[$i] }
      if ($Depth -lt 2) {
        for ($i = 0; $i -lt $values.Count; $i++) { $values[$i] = Find-FaTextDepth $values[$i] ($Depth + 1) }
      }
      try { return $lead + ([string]::Format($rule.r, $values)) + $trail } catch { return $Text }
    }
  }
  $word = $core.ToLowerInvariant()
  if ($script:FaWord.ContainsKey($word)) { return $lead + $script:FaWord[$word] + $trail }
  return $Text
}

# Translation-aware Write-Host. Colour and -NoNewline are forwarded untouched, so
# every call site keeps its exact behaviour; only the visible text is swapped.
# In the Persian window the same line is painted into the log instead of the
# console (see "window host" near the end of this file).
function Write-Host {
  [CmdletBinding()]
  param(
    [Parameter(Position = 0, ValueFromRemainingArguments = $true)]
    [object[]]$Object,
    [switch]$NoNewline,
    [object]$Separator,
    [System.ConsoleColor]$ForegroundColor,
    [System.ConsoleColor]$BackgroundColor
  )
  $converted = @()
  foreach ($item in $Object) {
    if ($item -is [string]) { $converted += (Find-FaText $item) } else { $converted += $item }
  }
  if ($script:GuiHost) {
    $glue = ' '
    if ($PSBoundParameters.ContainsKey('Separator')) { $glue = [string]$Separator }
    $line = (@($converted | ForEach-Object { [string]$_ }) -join $glue)
    $tint = $null
    if ($PSBoundParameters.ContainsKey('ForegroundColor')) { $tint = $ForegroundColor }
    Write-GuiLine $line ([bool]$NoNewline) $tint
    return
  }
  $forward = @{}
  if ($PSBoundParameters.ContainsKey('Separator')) { $forward['Separator'] = $Separator }
  if ($PSBoundParameters.ContainsKey('ForegroundColor')) { $forward['ForegroundColor'] = $ForegroundColor }
  if ($PSBoundParameters.ContainsKey('BackgroundColor')) { $forward['BackgroundColor'] = $BackgroundColor }
  if ($NoNewline) { $forward['NoNewline'] = $true }
  Microsoft.PowerShell.Utility\Write-Host -Object $converted @forward
}

# Clear-Host belongs to the host as well: the window empties its log.
function Clear-Host {
  if ($script:GuiHost) { Clear-GuiScreen; return }
  try { [System.Console]::Clear() } catch { }
}

# An answer is tidied, never rewritten when it is secret: a Persian keyboard types
# ۱ ۲ ۳ where the menu compares 1 2 3, so those digits are mapped to the plain
# ones, and بله / خیر are accepted instead of y / n. Passwords and the license code
# are returned exactly as typed.
function ConvertFrom-MenuAnswer([string]$Text) {
  $sb = New-Object System.Text.StringBuilder
  foreach ($ch in ([string]$Text).ToCharArray()) {
    $code = [int]$ch
    if ($code -ge 0x06F0 -and $code -le 0x06F9) { [void]$sb.Append([char](0x30 + $code - 0x06F0)) }
    elseif ($code -ge 0x0660 -and $code -le 0x0669) { [void]$sb.Append([char](0x30 + $code - 0x0660)) }
    else { [void]$sb.Append($ch) }
  }
  $answer = $sb.ToString().Trim()
  switch -Regex ($answer) {
    '^(y|Y|yes|Yes|YES)$|^(بله|بلی|بلي|آره|اره)$' { return 'y' }
    '^(n|N|no|No|NO)$|^(خیر|نه)$' { return 'n' }
  }
  return $answer
}

# The reverse of the digit mapping above, for text that is only shown: a Persian
# list is numbered ۱ ۲ ۳, and typing either form is accepted.
function ConvertTo-FaDigits([string]$Text) {
  $sb = New-Object System.Text.StringBuilder
  foreach ($ch in ([string]$Text).ToCharArray()) {
    $code = [int]$ch
    if ($code -ge 0x30 -and $code -le 0x39) { [void]$sb.Append([char](0x06F0 + $code - 0x30)) }
    else { [void]$sb.Append($ch) }
  }
  return $sb.ToString()
}

# Translation-aware Read-Host. Only the prompt is translated; the answer goes back
# to the same switch statements, so numbers, y/n and the license behave the same in
# both languages and in both hosts.
function Read-Host {
  [CmdletBinding()]
  param(
    [Parameter(Position = 0)]
    [object]$Prompt,
    [switch]$AsSecureString,
    [switch]$MaskInput
  )
  $text = $Prompt
  if ($text -is [string]) { $text = Find-FaText $text }
  $secret = [bool]($AsSecureString -or $MaskInput)
  if ($script:GuiHost) {
    $answer = Read-GuiLine ([string]$text).Trim() $secret
    if ($AsSecureString) {
      # An empty answer stays an empty secure string: ConvertTo-SecureString
      # refuses an empty string, and the license prompt must accept nothing.
      if (-not $answer) { return (New-Object System.Security.SecureString) }
      return (ConvertTo-SecureString -String $answer -AsPlainText -Force)
    }
    if ($secret) { return $answer }
    return (ConvertFrom-MenuAnswer $answer)
  }
  $forward = @{}
  if ($AsSecureString) { $forward['AsSecureString'] = $true }
  if ($MaskInput) { $forward['MaskInput'] = $true }
  if ([string]::IsNullOrEmpty([string]$text)) { $answer = Microsoft.PowerShell.Utility\Read-Host @forward }
  else { $answer = Microsoft.PowerShell.Utility\Read-Host -Prompt $text @forward }
  if ($secret) { return $answer }
  return (ConvertFrom-MenuAnswer $answer)
}
# The cached tag only saves a round trip while a newer release is already known;
# a short life keeps a fresh release visible within minutes instead of hours.
$UpdateCacheTtl = 900
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
  # The dashboard login is derived from the Expert licence: prepare it here so a
  # customer who only activated the serial never meets a second licence.
  if (-not (Test-LicenseSaved)) { $null = Sync-DashboardLogin -Quiet }
  if (-not (Test-LicenseSaved)) { return $false }
  $text = Invoke-LicenseCheck $LicenseFile $LicenseAuthFile
  if ((Get-LicenseField $text 'status') -eq 'ACTIVE') { return $true }
  # A stale login (renewed licence, another account) is rebuilt once and retried.
  if (Sync-DashboardLogin -Quiet) {
    $text = Invoke-LicenseCheck $LicenseFile $LicenseAuthFile
    return ((Get-LicenseField $text 'status') -eq 'ACTIVE')
  }
  return $false
}

# Interactive gate for anything that starts the dashboard.
function Confirm-License {
  if (-not (Test-LicenseSupported)) {
    Write-Host 'the installed dashboard build does not support the license yet.'
    Write-Host 'update it from menu 4 (Install / update dashboard), then enter the license (menu 12).'
    return $false
  }
  if (-not (Test-LicenseSaved)) {
    Write-Host 'the dashboard runs on your Expert licence - preparing the login ...'
    if (-not (Sync-DashboardLogin)) {
      Write-Host 'the Expert licence is not active on this machine yet.'
      Write-Host 'activate your serial in the License menu (item 4), then start the dashboard again.'
      return $false
    }
  }
  $text = Invoke-LicenseCheck $LicenseFile $LicenseAuthFile
  if ((Get-LicenseField $text 'status') -ne 'ACTIVE') {
    Write-Host 'the license check failed:'
    Show-LicenseResult $text
    Write-Host 'the dashboard was not started. Rebuild the login from the License menu (item 1).'
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
    Write-Host ''
    Write-Tag 'WARN' 'the installed dashboard build does not support the license yet.'
    Write-Hint 'install or update it from the main menu, item 4.'
    Write-Host ''
    return
  }
  if (-not (Test-LicenseSaved)) {
    Write-Host ''
    Write-Tag 'WARN' 'the dashboard login is not built yet - item 1 builds it from your Expert licence.'
    Write-Host ''
    return
  }
  # The dashboard half is checked by its own program, not by the Agent, and it
  # answers in the same card as the rest of the licence screen: one verdict tag
  # at the top, the dates below it, the files last.
  $text = Invoke-LicenseCheck $LicenseFile $LicenseAuthFile
  $state = Get-LicenseField $text 'status'
  $user = Get-LicenseField $text 'user'
  $account = Get-LicenseField $text 'account'
  $expiry = Get-LicenseField $text 'expiry'
  $days = Get-LicenseField $text 'days_left'
  $message = Get-LicenseField $text 'message'
  $warning = Get-LicenseField $text 'warning'
  $kind = 'FAIL'
  if ($state -eq 'ACTIVE') { $kind = 'OK' }
  elseif ($state -eq 'GRACE') { $kind = 'WARN' }
  if (-not $state) { $state = 'unknown' }

  Write-Host ''
  Ui-Top
  Ui-Status 'Dashboard' $kind $state
  if ($user) { Ui-Row 'Login' $user ($Cyan + $user + $NoColor) }
  if ($account) { Ui-Row 'Account' $account ($Cyan + $account + $NoColor) }
  if ($expiry) {
    $endPlain = $expiry
    if ($days -match '^\d+$') { $endPlain = "$expiry  ($days day(s) left)" }
    Ui-Row 'Valid to' $endPlain ($(if ($kind -eq 'OK') { $Green } else { $Yellow }) + $endPlain + $NoColor)
  }
  Ui-Row 'Files' 'saved' ($Cyan + 'saved' + $NoColor)
  Ui-Bottom
  Write-Host "    $LicenseFile" -ForegroundColor DarkGray
  Write-Host "    $LicenseAuthFile" -ForegroundColor DarkGray
  if ($message) { Write-Tag $kind $message }
  if ($warning) { Write-Tag 'WARN' $warning }
  # The binary answers ACTIVE because the login is in date today. The date sealed
  # inside the file is what decides when it stops, and a login built before Agent
  # 2.2.0 carries the 72 h lease end - so say so here as well, or this card and
  # the licence card would disagree about the same login.
  $loginEnd = Get-DashboardLoginExpiry $LicenseFile
  $licUtc = [string](Get-AgentFields)['license_expiry_utc']
  if ($loginEnd -and $licUtc -and $licUtc -ne '-') {
    $licEnd = $null
    $loginEndDate = $null
    try { $licEnd = [datetime]::ParseExact($licUtc, 'yyyy-MM-dd HH:mm', [Globalization.CultureInfo]::InvariantCulture) } catch { }
    try { $loginEndDate = [datetime]::ParseExact($loginEnd, 'yyyy.MM.dd HH:mm', [Globalization.CultureInfo]::InvariantCulture) } catch { }
    if ($licEnd -and $loginEndDate -and $loginEndDate.Date -lt $licEnd.Date) {
      Write-Tag 'WARN' "the login ends $loginEnd but the licence ends $licUtc UTC - item 1 rebuilds it"
    }
  }
  Write-Host ''
}

function Remove-License {
  if (-not (Test-LicenseSaved)) { Write-Host 'no license is saved.'; return }
  $a = Read-Default 'remove the saved dashboard login? it is rebuilt from your Expert licence on the next start (y/n)' 'n'
  if ($a -ne 'y') { Write-Host 'cancelled.'; return }
  Remove-Item $LicenseFile, $LicenseAuthFile -Force -ErrorAction SilentlyContinue
  if ((Test-Path $LicenseDir) -and -not (Get-ChildItem $LicenseDir -Force -ErrorAction SilentlyContinue)) {
    Remove-Item $LicenseDir -Force -ErrorAction SilentlyContinue
  }
  Write-Host 'the dashboard login was removed.'
}

function Show-LicenseMenu {
  while ($true) {
    Clear-Host
    Show-Title

    $fields = Get-AgentFields
    $state = [string]$fields['status']
    $saved = Test-LicenseSaved
    $folders = Get-AgentTerminalCount
    $hourly = Test-AgentSchedule

    # The Expert half in one line a customer can read. The status word comes
    # from the Agent and is never translated as free text: ACTIVE / GRACE are
    # the two that mean "the Expert will trade".
    if (-not (Test-Path $AgentLeaseFile)) {
      $expKind = 'WARN'; $expText = 'not activated'
    } elseif ($state -eq 'ACTIVE') {
      $expKind = 'OK'; $expText = Get-AgentSummary
    } elseif ($state -eq 'GRACE') {
      $expKind = 'WARN'; $expText = (Get-AgentSummary) + ' - grace period, renew now'
    } else {
      $expKind = 'FAIL'; $expText = Get-AgentSummary
    }

    # The date the customer paid for. A lease signed by a server older than
    # licence platform v1.6.2 carries no end date; saying so beats printing the
    # 72 h lease as if it were the licence, which is what showed "2 days" for a
    # licence with a month left.
    $licUtc = [string]$fields['license_expiry_utc']
    if (-not $licUtc -or $licUtc -eq '-') {
      $endKind = 'WARN'; $endText = 'not in this lease yet - refresh the licence (item 7)'
    } elseif ($state -eq 'ACTIVE') {
      $endKind = 'OK'; $endText = "$licUtc UTC"
    } else {
      $endKind = 'WARN'; $endText = "$licUtc UTC - expired"
    }

    # The dashboard half ends on the date sealed inside its own file, and that
    # date is what the customer's login stops at - not the presence of the file.
    # Only the day is compared: the two clocks differ by the machine's offset.
    $dashEnd = Get-DashboardLoginExpiry $LicenseFile
    $licEnd = $null
    if ($licUtc -and $licUtc -ne '-') {
      try { $licEnd = [datetime]::ParseExact($licUtc, 'yyyy-MM-dd HH:mm', [Globalization.CultureInfo]::InvariantCulture) } catch { $licEnd = $null }
    }
    $dashStale = $false
    if ($saved -and $dashEnd -and $licEnd) {
      try {
        $loginEnd = [datetime]::ParseExact($dashEnd, 'yyyy.MM.dd HH:mm', [Globalization.CultureInfo]::InvariantCulture)
        $dashStale = $loginEnd.Date -lt $licEnd.Date
      } catch { $dashStale = $false }
    }
    if (-not $saved) { $dashKind = 'WARN'; $dashText = 'not built yet - item 1 or it builds itself on start' }
    elseif (-not $dashEnd) { $dashKind = 'WARN'; $dashText = 'unreadable - item 1 rebuilds it' }
    elseif ($dashStale) { $dashKind = 'WARN'; $dashText = "ends $dashEnd - the licence ends later, item 1 rebuilds it" }
    else { $dashKind = 'OK'; $dashText = "ready - ends $dashEnd" }

    if ($folders -gt 0) { $termKind = 'OK'; $termText = "linked: $folders MetaTrader folder(s)" }
    else { $termKind = 'WARN'; $termText = 'not registered - the Expert cannot read the licence' }

    if ($hourly) { $autoKind = 'OK'; $autoText = 'hourly task installed' }
    else { $autoKind = 'WARN'; $autoText = 'not scheduled - item 10 turns it on' }

    $next = Get-LicenceNextStep $state $saved $folders $dashStale

    Ui-Top
    Ui-Status 'Licence' $expKind $expText
    Ui-Status 'Valid to' $endKind $endText
    Ui-Status 'Dashboard' $dashKind $dashText
    Ui-Status 'Terminal' $termKind $termText
    Ui-Status 'Refresh' $autoKind $autoText
    Ui-Sep
    Ui-Status 'Next step' $next.Kind $next.Text
    Ui-Sep
    Ui-Head 'Dashboard login - same serial, nothing extra to buy'
    Ui-Item '1' 'Build / refresh the dashboard login now'
    Ui-Item '2' 'Show the dashboard login status'
    Ui-Item '3' 'Remove the saved dashboard login'
    Ui-Head 'Expert licence - the serial from the shop'
    Ui-Item '4' 'Activate the Expert with a serial'
    Ui-Item '5' 'Show the Expert licence in detail'
    Ui-Item '6' 'Register the MetaTrader folder (MQL5)'
    Ui-Item '7' 'Refresh the Expert licence now'
    Ui-Item '8' 'Verify the licence locally (no internet)'
    Ui-Head 'Support'
    Ui-Item '9' 'Device identity (send this to support)'
    Ui-Item '10' 'Automatic refresh on / off'
    Ui-Item '11' 'Remove the licence from this machine'
    Ui-Item '12' 'Enter an old dashboard licence (only if support sent one)'
    Ui-Sep
    Ui-Item '0' 'Back to the main menu'
    Ui-Bottom

    $c = Read-Host "`nEnter Number Of List"
    switch ($c) {
      '0' { return }
      '1' {
        if (Sync-DashboardLogin) {
          Write-Tag 'OK' 'the dashboard login is ready - start the dashboard from the main menu (2).'
        } else { Write-Tag 'FAIL' $script:DashboardLoginNote }
      }
      '2' { Show-LicenseStatus }
      '3' { Remove-License }
      '4' { Activate-Agent }
      '5' { Show-AgentStatus }
      '6' { $null = Register-AgentTerminal '' }
      '7' { Update-AgentLease }
      '8' { Test-AgentLease }
      '9' { Show-AgentDevice }
      '10' { Toggle-AgentSchedule }
      '11' { Remove-AgentLease }
      '12' { $null = Enter-License }
      default { Write-Host 'please choose 0-12.' }
    }
    $null = Read-Host "`nPress Enter to continue"
  }
}

# What the customer should do next, worked out from the same five facts the
# screen above prints, so the recommendation and the rows can never disagree.
function Get-LicenceNextStep([string]$State, [bool]$Saved, [int]$Folders, [bool]$DashStale = $false) {
  if (-not (Test-Path $AgentLeaseFile)) {
    return @{ Kind = 'WARN'; Text = 'activate the Expert first - item 4 asks for the serial' }
  }
  if ($State -eq 'GRACE') {
    return @{ Kind = 'WARN'; Text = 'the licence has expired - it still works for a few days, renew it now' }
  }
  if ($State -ne 'ACTIVE') {
    return @{ Kind = 'FAIL'; Text = 'the licence is not active - refresh it (item 7), then contact support if it stays red' }
  }
  if ($Folders -le 0) {
    return @{ Kind = 'WARN'; Text = 'register the MetaTrader folder (item 6) or the Expert reads no licence' }
  }
  if (-not $Saved) {
    return @{ Kind = 'WARN'; Text = 'build the dashboard login from the same serial (item 1)' }
  }
  if ($DashStale) {
    return @{ Kind = 'WARN'; Text = 'the dashboard login ends before the licence - rebuild it (item 1)' }
  }
  return @{ Kind = 'OK'; Text = 'nothing to do - the Expert and the dashboard are ready' }
}

# ---------------------------------------------------------------- licence agent
# The half of the product that talks to the licence server. It used to ship
# with its own menu (Agent\mapsim-license.ps1), so a customer had two entry
# points for one product; it is folded in here and the second menu is gone.
#
# The Agent is a single-shot CLI (spec 9.2) and knows nothing about MetaTrader
# folders. Without `link-terminal` the lease is written into ~/.mapsim but never
# reaches <MQL5>\Files\MapsimLive, the EA reads no lease, and the customer sees
# NO_LEASE with no explanation. This menu is the only place that order is
# enforced: link the terminal, then activate, then refresh.
#
# Delivery: the menu is installed alone, so the Agent is fetched from the
# product repository the first time it is needed and kept next to the menu. A
# frozen build dropped into agent\dist wins, so a machine without Python works.

function Test-AgentPresent {
  return ((Test-Path $AgentExe) -or (Test-Path $AgentPy))
}

# AGENT_VERSION of a downloaded Agent file, or '' when the file is missing or
# carries no readable version. The Agent is one script, so the constant is read
# from the text instead of starting an interpreter.
function Get-AgentFileVersion([string]$Path) {
  if (-not (Test-Path $Path)) { return '' }
  $hit = Select-String -Path $Path -Pattern '^\s*AGENT_VERSION\s*=\s*"([0-9][0-9.]*)"' -ErrorAction SilentlyContinue |
         Select-Object -First 1
  if ($hit -and $hit.Matches.Count -gt 0) { return $hit.Matches[0].Groups[1].Value }
  return ''
}

# A frozen build in agent\dist always wins and is never touched. Otherwise the
# published script is fetched even when a copy is already installed: a fix that
# lands in the Agent (a server address, a new call) must reach a machine that
# still holds the older file, which the previous early return made impossible.
# Nothing is overwritten unless the published AGENT_VERSION is strictly greater,
# and a failed download leaves the installed copy working.
function Install-Agent {
  if (Test-Path $AgentExe) { return $true }
  $local = Get-AgentFileVersion $AgentPy
  try {
    New-Item -ItemType Directory -Force $AgentDir | Out-Null
    $text = (Invoke-WebRequest -Uri (Get-FreshUrl $AgentUrl) -TimeoutSec 30 -UseBasicParsing).Content
    if (-not ($text -is [string]) -or $text -notmatch 'AGENT_VERSION') {
      throw 'the downloaded file is not the licence Agent.'
    }
    $remote = ''
    if ($text -match '(?m)^\s*AGENT_VERSION\s*=\s*"([0-9][0-9.]*)"') { $remote = $Matches[1] }
    # same number, older copy, or no version in the published file: keep what is
    # installed and touch nothing.
    if ($local -and (-not $remote -or -not (Test-NewerDashboardVersion $remote $local))) { return $true }
    Set-Content -Path $AgentPy -Value $text -Encoding UTF8
    Write-Host 'the licence Agent was downloaded to:'
    Write-Host "  $AgentDir"
    if ($local) { Write-Host "  (replaced $local with $remote)" }
    return $true
  } catch {
    if (Test-AgentPresent) {
      Write-Host "warning: the licence Agent could not be refreshed - $($_.Exception.Message)" -ForegroundColor Yellow
      Write-Host 'the installed copy keeps working.' -ForegroundColor Yellow
      return $true
    }
    Write-Host "error: the licence Agent could not be installed - $($_.Exception.Message)" -ForegroundColor Red
    Write-Host 'hint: check the internet, then try again; the dashboard is not affected.' -ForegroundColor Yellow
    return $false
  }
}

function Get-AgentLauncher([switch]$Quiet) {
  if ($script:AgentLauncher) { return $script:AgentLauncher }
  if (Test-Path $AgentExe) {
    $script:AgentLauncher = @{ File = $AgentExe; Args = @() }
    return $script:AgentLauncher
  }
  if (-not (Test-Path $AgentPy)) {
    if (-not $Quiet) {
      Write-Host 'the licence Agent is not installed yet.'
      Write-Host 'choose 5 or activate once - the menu downloads it automatically.'
    }
    return $null
  }
  $python = Get-Command python -ErrorAction SilentlyContinue
  if (-not $python) {
    if (-not $Quiet) {
      Write-Host 'error: Python was not found, and no frozen Agent is installed.' -ForegroundColor Red
      Write-Host 'hint: install Python 3, or drop the frozen mapsim-license-agent.exe into the agent\dist folder.' -ForegroundColor Yellow
    }
    return $null
  }
  $script:AgentLauncher = @{ File = $python.Source; Args = @($AgentPy) }
  return $script:AgentLauncher
}

# The output is captured and re-printed on purpose: in the Persian window a
# child process writes to a console nobody can see, so the same lines must go
# through Write-Host to reach the page. The Agent prints key=value and this menu
# never reformats it - that contract is older than this window.
function Invoke-Agent([string[]]$Arguments) {
  $launcher = Get-AgentLauncher
  if (-not $launcher) { return 1 }
  $all = @($launcher.Args) + $Arguments
  $text = (& $launcher.File @all 2>&1 | Out-String)
  $code = $LASTEXITCODE
  foreach ($line in ($text -split "`r?`n")) {
    if ($line -ne '') { Write-Host $line }
  }
  $script:AgentSummary = $null
  $script:AgentFields = $null
  return $code
}

# The Agent answers `status` with one key=value pair per line. The licence
# screen reads eight of them and every call costs a Python start, so the whole
# answer is parsed once and cached; Invoke-Agent clears it after an action.
function Get-AgentFields {
  if ($script:AgentFields) { return $script:AgentFields }
  $fields = @{}
  if (Test-Path $AgentLeaseFile) {
    $launcher = Get-AgentLauncher -Quiet
    if ($launcher) {
      $all = @($launcher.Args) + @('status')
      $previous = $ErrorActionPreference
      # A rejected lease makes the Agent exit non-zero with the reason on
      # stderr. That answer is data here, not a reason to abort the menu.
      $ErrorActionPreference = 'Continue'
      try { $text = (& $launcher.File @all 2>&1 | Out-String) } finally { $ErrorActionPreference = $previous }
      foreach ($line in ($text -split "`r?`n")) {
        $at = $line.IndexOf('=')
        if ($at -gt 0) { $fields[$line.Substring(0, $at).Trim()] = $line.Substring($at + 1).Trim() }
      }
    }
  }
  $script:AgentFields = $fields
  return $fields
}

# The folder(s) the Agent copies the lease into. The count is what tells a
# customer whether the Expert can see the licence at all.
function Get-AgentTerminalCount {
  if (-not (Test-Path $AgentMql5File)) { return 0 }
  $lines = @(Get-Content -Path $AgentMql5File -ErrorAction SilentlyContinue | Where-Object { $_ -and $_.Trim() -ne '' })
  return $lines.Count
}

function Test-AgentSchedule {
  # `schtasks` prints "ERROR: The system cannot find the file specified" on a
  # machine without the task, and that banner used to land in the middle of the
  # licence screen as if the menu had broken. Both streams are swallowed here;
  # the exit code is the whole answer.
  $previous = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  try { & schtasks.exe /Query /TN $AgentTaskName *> $null } finally { $ErrorActionPreference = $previous }
  return ($LASTEXITCODE -eq 0)
}

# One line for the submenu and the main frame, built from the same parse.
function Get-AgentSummary {
  if ($script:AgentSummary) { return $script:AgentSummary }
  if (-not (Test-Path $AgentLeaseFile)) {
    $script:AgentSummary = 'not activated'
    return $script:AgentSummary
  }
  $fields = Get-AgentFields
  $state = [string]$fields['status']
  if (-not $state) {
    $script:AgentSummary = 'not readable - the Agent is missing'
    return $script:AgentSummary
  }
  $summary = $state
  $product = [string]$fields['product']
  if ($product) { $summary = "$summary ($product)" }
  # `days_left` is the licence now, not the 72 h lease (Agent 2.2.0).
  $days = [string]$fields['days_left']
  if ($days -match '^\d+$') { $summary = "$summary, $days day(s) left" }
  $script:AgentSummary = $summary
  return $summary
}

# ------------------------------------------------------------ derived login
# One licence, two programs. The serial bought on the site activates the EA half
# (the Agent holds a signed lease); the dashboard half reads its own two files,
# dashboard.license and dashboard.auth. They used to be a second licence a
# customer had to buy and type himself. The Agent now reports what the lease
# already proves - user, password, account, expiry - and these functions seal
# that into the files the installed dashboard build expects: nine fields joined
# by a dash, AES-256-ECB with zero padding, lowercase hex. Nothing is invented
# here: every field is checked by the dashboard against the Expert's own export,
# so a wrong value could not unlock anything.

# Like Invoke-Agent, but silent: a stale login must refresh before the dashboard
# starts without printing an Agent report in the middle of the screen.
function Invoke-AgentQuiet([string[]]$Arguments) {
  $launcher = Get-AgentLauncher -Quiet
  if (-not $launcher) { return '' }
  $previous = $ErrorActionPreference
  # The Agent exits non-zero by design (20 = no licence yet). With 'Stop' the
  # redirected stderr would abort the menu instead of returning the text.
  $ErrorActionPreference = 'Continue'
  try {
    $all = @($launcher.Args) + $Arguments
    $text = (& $launcher.File @all 2>&1 | Out-String)
  } finally {
    $ErrorActionPreference = $previous
  }
  $script:AgentSummary = $null
  $script:AgentFields = $null
  return $text
}

# Carried inside the published dashboard build, so they are not a secret stored
# here - they are the lock the shipped program already has.
$DashAesKey = '765BC5720769C61677895D7563GHH0TM'
$DashActiveCode = '213250101'

function Get-DashboardLoginMaterial {
  $text = Invoke-AgentQuiet @('dashboard-login')
  $status = Get-LicenseField $text 'status'
  if ($status -ne 'OK') {
    $code = Get-LicenseField $text 'code'
    if (-not $code) { $code = 'AGENT_ERROR' }
    $note = Get-LicenseField $text 'message'
    if (-not $note) { $note = 'the licence Agent did not answer.' }
    $script:DashboardLoginNote = "the Expert licence cannot open the dashboard ($code): $note"
    return $null
  }
  $user = Get-LicenseField $text 'user'
  $pass = Get-LicenseField $text 'password'
  $account = Get-LicenseField $text 'account'
  $expiry = Get-LicenseField $text 'expiry'
  if (-not $user -or -not $pass -or -not $account -or -not $expiry) {
    $script:DashboardLoginNote = 'the Agent returned an incomplete dashboard login.'
    return $null
  }
  # The dashboard reads the expiry as year.month.day hour:minute.
  if ($expiry -notmatch '^(\d{4})\.(\d{2})\.(\d{2}) (\d{2}):(\d{2})$') {
    $script:DashboardLoginNote = "the Agent returned an unreadable expiry ($expiry)."
    return $null
  }
  return @{
    User = $user; Password = $pass; Account = $account; Expiry = $expiry
    Year = $Matches[1]; Month = $Matches[2]; Day = $Matches[3]
    Hour = $Matches[4]; Minute = $Matches[5]
  }
}

function Write-DashboardLicense($Material) {
  $plain = @(
    $Material.User, $Material.Password,
    $Material.Year, $Material.Month, $Material.Day,
    $Material.Hour, $Material.Minute,
    $DashActiveCode, $Material.Account
  ) -join '-'
  $bytes = [Text.Encoding]::ASCII.GetBytes($plain)
  $blocks = [int][Math]::Ceiling($bytes.Length / 16.0)
  $padded = New-Object 'byte[]' ($blocks * 16)
  [Array]::Copy($bytes, $padded, $bytes.Length)
  $aes = [Security.Cryptography.Aes]::Create()
  try {
    $aes.Mode = [Security.Cryptography.CipherMode]::ECB
    $aes.Padding = [Security.Cryptography.PaddingMode]::None
    $aes.Key = [Text.Encoding]::ASCII.GetBytes($DashAesKey)
    $sealed = $aes.CreateEncryptor().TransformFinalBlock($padded, 0, $padded.Length)
  } finally {
    $aes.Dispose()
  }
  $hex = ([BitConverter]::ToString($sealed) -replace '-', '').ToLowerInvariant()

  New-Item -ItemType Directory -Force $LicenseDir | Out-Null
  Set-Content -Path $LicenseFile -Value $hex -Encoding ASCII
  Set-Content -Path $LicenseAuthFile -Value @($Material.User, $Material.Password) -Encoding ASCII
  # The password file must stay private to this Windows account.
  $me = [Security.Principal.WindowsIdentity]::GetCurrent().Name
  & icacls $LicenseFile '/inheritance:r' '/grant:r' "${me}:(R,W)" | Out-Null
  & icacls $LicenseAuthFile '/inheritance:r' '/grant:r' "${me}:(R,W)" | Out-Null
}

# The login file is sealed with the key the dashboard build carries, so the menu
# can read the date inside it instead of treating "a file exists" as "the login
# is right". A login built by Agent 2.1 or older holds the end of the 72 h lease,
# not the end of the licence: the file is complete and the dashboard stops
# accepting it a year early, which is the same "2 days" the card used to show.
# Returns 'yyyy.MM.dd HH:mm', or '' when the file is missing or not readable.
function Get-DashboardLoginExpiry([string]$Path) {
  if (-not (Test-Path $Path)) { return '' }
  try {
    $hex = ((Get-Content $Path -Raw) -replace '\s', '')
    if ($hex.Length -lt 32 -or ($hex.Length % 2) -ne 0) { return '' }
    $bytes = New-Object 'byte[]' ($hex.Length / 2)
    for ($i = 0; $i -lt $bytes.Length; $i++) { $bytes[$i] = [Convert]::ToByte($hex.Substring($i * 2, 2), 16) }
    $aes = [Security.Cryptography.Aes]::Create()
    try {
      $aes.Mode = [Security.Cryptography.CipherMode]::ECB
      $aes.Padding = [Security.Cryptography.PaddingMode]::None
      $aes.Key = [Text.Encoding]::ASCII.GetBytes($DashAesKey)
      $plain = $aes.CreateDecryptor().TransformFinalBlock($bytes, 0, $bytes.Length)
    } finally { $aes.Dispose() }
    $text = ([Text.Encoding]::ASCII.GetString($plain)).TrimEnd([char]0)
    # user-password-yyyy-mm-dd-hh-mm-code-account, and the first two fields may
    # contain a dash, so the date is counted from the end.
    $parts = $text.Split('-')
    $n = $parts.Count
    if ($n -lt 9) { return '' }
    $stamp = '{0}.{1}.{2} {3}:{4}' -f $parts[$n - 7], $parts[$n - 6], $parts[$n - 5], $parts[$n - 4], $parts[$n - 3]
    if ($stamp -notmatch '^\d{4}\.\d{2}\.\d{2} \d{2}:\d{2}$') { return '' }
    return $stamp
  } catch { return '' }
}

# Rebuilds the dashboard login from the active Expert licence. Returns $false and
# leaves $script:DashboardLoginNote set when the Expert half is not ready, so the
# caller can say why instead of asking for a licence the customer never had.
function Sync-DashboardLogin([switch]$Quiet) {
  $script:DashboardLoginNote = ''
  if (-not (Install-Agent)) {
    $script:DashboardLoginNote = 'the licence Agent is not installed.'
    if (-not $Quiet) { Write-Host $script:DashboardLoginNote -ForegroundColor Red }
    return $false
  }
  if (-not (Test-Path $AgentLeaseFile)) {
    $script:DashboardLoginNote = 'no Expert licence is active on this machine yet.'
    if (-not $Quiet) { Write-Host $script:DashboardLoginNote }
    return $false
  }
  $material = Get-DashboardLoginMaterial
  if (-not $material) {
    if (-not $Quiet) { Write-Host $script:DashboardLoginNote }
    return $false
  }
  try {
    Write-DashboardLicense $material
  } catch {
    $script:DashboardLoginNote = "the dashboard login could not be saved - $($_.Exception.Message)"
    if (-not $Quiet) { Write-Host $script:DashboardLoginNote -ForegroundColor Red }
    return $false
  }
  if (-not (Test-LicenseSaved)) {
    $script:DashboardLoginNote = 'the dashboard login files were not created.'
    if (-not $Quiet) { Write-Host $script:DashboardLoginNote -ForegroundColor Red }
    return $false
  }
  if (-not $Quiet) {
    Write-Tag 'OK' 'the dashboard login was prepared from your Expert licence:'
    Ui-Top
    Ui-Row 'Login' ([string]$material.User) ($Cyan + [string]$material.User + $NoColor)
    Ui-Row 'Password' ([string]$material.Password) ($Cyan + [string]$material.Password + $NoColor)
    Ui-Row 'Account' ([string]$material.Account) ($Cyan + [string]$material.Account + $NoColor)
    Ui-Row 'Valid to' ([string]$material.Expiry) ($Green + [string]$material.Expiry + $NoColor)
    Ui-Bottom
    Write-Hint 'it renews itself whenever the Expert licence is refreshed.'
  }
  return $true
}

function Show-AgentStatus {
  if (-not (Install-Agent)) { return }
  if (-not (Test-Path $AgentLeaseFile)) {
    Write-Host ''
    Write-Tag 'WARN' 'no licence on this machine yet - item 4 activates one.'
    Write-Hint 'the serial from the shop is the only thing you need.'
    Write-Host ''
    return
  }
  # This screen used to dump the Agent's raw key=value lines. Every field has a
  # label, a colour and a sentence now, because `days_source=lease` answers
  # nothing for a customer.
  $fields = Get-AgentFields
  $state = [string]$fields['status']
  $kind = 'FAIL'
  if ($state -eq 'ACTIVE') { $kind = 'OK' }
  elseif ($state -eq 'GRACE') { $kind = 'WARN' }
  if (-not $state) { $state = 'unknown' }

  $product = [string]$fields['product']
  if (-not $product) { $product = '-' }
  $licUtc = [string]$fields['license_expiry_utc']
  $licDays = [string]$fields['days_left']
  $leaseUtc = [string]$fields['lease_expiry_utc']
  $leaseDays = [string]$fields['lease_days']
  $graceUtc = [string]$fields['grace_until_utc']
  $agent = [string]$fields['agent']
  $device = [string]$fields['device']
  if (-not $device) { $device = '-' }
  $rights = @(([string]$fields['entitlements']) -split ',' | Where-Object { $_ -ne '' })
  $entry = @($rights | Where-Object { $_ -like 'ENTRY_*' }).Count
  $rightsText = "$($rights.Count) of 8"
  if ($entry -eq 0) { $rightsText = "$rightsText - no automatic entry" }

  $note = [string]$fields['warning']

  Write-Host ''
  Ui-Top
  Ui-Status 'Result' $kind $state
  Ui-Row 'Product' $product ($Cyan + $product + $NoColor)
  if ($licUtc -and $licUtc -ne '-') {
    $endPlain = "$licUtc UTC"
    if ($licDays -match '^\d+$') { $endPlain = "$endPlain  ($licDays day(s) left)" }
    Ui-Row 'Valid to' $endPlain ($(if ($kind -eq 'OK') { $Green } else { $Yellow }) + $endPlain + $NoColor)
  } else {
    Ui-Status 'Valid to' 'WARN' 'not in this lease yet - refresh the licence (item 7)'
  }
  if ($graceUtc -and $graceUtc -ne '-' -and $kind -ne 'OK') {
    Ui-Row 'Grace to' "$graceUtc UTC" ($Yellow + "$graceUtc UTC" + $NoColor)
  }
  # The lease is the renewal ticket, not the licence: it is printed small and
  # last, so nobody reads "2 days" as the end of what they paid for.
  if ($leaseUtc -and $leaseUtc -ne '-') {
    $leasePlain = "$leaseUtc UTC auto-renews"
    if ($leaseDays -match '^\d+$') { $leasePlain = "$leaseUtc UTC ($leaseDays day(s))" }
    Ui-Row 'Lease' $leasePlain ($(if ($leaseDays -eq '0') { $Yellow } else { $Green }) + $leasePlain + $NoColor)
  }
  Ui-Row 'Rights' $rightsText ($Cyan + $rightsText + $NoColor)
  Ui-Row 'Agent' $agent ($Cyan + $agent + $NoColor)
  Ui-Row 'Device' $device ($Cyan + $device + $NoColor)
  if ($note) { Ui-Status 'Note' 'WARN' $note }
  Ui-Bottom
  Write-Host ''
}

function Register-AgentTerminal([string]$Target) {
  if (-not (Install-Agent)) { return $false }
  if (-not $Target) {
    Write-Host 'the EA reads the licence from <MQL5>\Files\MapsimLive.'
    $Target = (Read-Host 'MQL5 folder (empty = find it automatically)').Trim('"')
  }
  $call = @('link-terminal')
  if ($Target) { $call += @('--path', $Target) }
  $code = Invoke-Agent $call
  if ($code -ne 0) {
    Write-Tag 'WARN' 'the MetaTrader folder was not registered - the Expert reads no licence without it.'
    Write-Hint "item 6 asks again; the folder ends in \MQL5."
    return $false
  }
  Write-Tag 'OK' 'the MetaTrader folder is registered - the Expert can read the licence now.'
  return $true
}

function Activate-Agent {
  if (-not (Install-Agent)) { return }
  if (-not (Test-Path $AgentLeaseFile)) {
    # Order matters the first time: a lease with no terminal path is a licence
    # the EA cannot see.
    Write-Host ''
    Write-Hint 'step 1 of 2: tell the Agent where MetaTrader keeps its files.'
    if (-not (Register-AgentTerminal '')) {
      $a = Read-Default 'continue with the activation anyway? (y/n)' 'n'
      if ($a -ne 'y') { return }
    }
  }
  Write-Host ''
  Write-Hint 'step 2 of 2: paste the serial exactly as the shop sent it.'
  $serial = Read-Host 'licence serial (MAPSIM-XXXX-XXXX-XXXX-XXXX)'
  if (-not $serial) { Write-Tag 'WARN' 'no serial was entered - nothing was changed.'; return }
  # No --product: the serial decides which product was bought (D-68), so this
  # one menu activates the assistant and the full licence alike.
  $code = Invoke-Agent @('activate', '--serial', $serial)
  switch ($code) {
    0  { Write-Tag 'OK' 'the serial was accepted - the Expert is active on this machine.' }
    10 { Write-Tag 'FAIL' 'that serial is not valid - check for a typo in what you pasted.' }
    11 { Write-Tag 'FAIL' 'this serial was already used - ask support to move it to this machine.' }
    12 { Write-Tag 'FAIL' 'this machine could not be identified - send the device identity (item 9) to support.' }
    13 { Write-Tag 'FAIL' 'the licence server could not be reached - check the internet and try again.' }
    14 { Write-Tag 'FAIL' 'the server refused the activation - the reason is printed above.' }
    15 { Write-Tag 'FAIL' 'this licence is revoked or suspended - contact support.' }
    16 { Write-Tag 'FAIL' 'this licence belongs to another machine - ask support to move it.' }
    default { Write-Tag 'FAIL' "activation failed (code $code)." }
  }
  if ($code -eq 0) {
    Write-Host ''
    Write-Hint 'next, in MetaTrader 5:'
    Write-Hint '  1  open the chart you trade on'
    Write-Hint '  2  attach Mapsim_Assistance_Bot and allow DLL imports'
    # The same serial now covers the dashboard: prepare its login right away.
    $null = Sync-DashboardLogin -Quiet
    if (Test-LicenseSaved) {
      Write-Hint 'the dashboard login was rebuilt from the same serial - nothing extra to buy.'
    }
  }
}

function Update-AgentLease {
  if (-not (Install-Agent)) { return }
  $code = Invoke-Agent @('refresh', '--force')
  switch ($code) {
    0  {
      Write-Tag 'OK' 'the licence was refreshed.'
      $fields = Get-AgentFields
      $licUtc = [string]$fields['license_expiry_utc']
      if ($licUtc -and $licUtc -ne '-') { Write-Hint "valid until $licUtc UTC." }
      # Renewal must reach the dashboard too, or it would expire before the EA.
      $null = Sync-DashboardLogin -Quiet
      if (Test-LicenseSaved) { Write-Hint 'the dashboard login was renewed with it.' }
    }
    13 { Write-Tag 'FAIL' 'the licence server could not be reached - check the internet.'
         Write-Hint 'the Expert keeps working while the current lease lasts.' }
    15 { Write-Tag 'FAIL' 'this licence is revoked or suspended - contact support.' }
    16 { Write-Tag 'FAIL' 'this licence belongs to another machine - ask support to move it.' }
    default { Write-Tag 'FAIL' "refresh failed (code $code)." }
  }
}

function Test-AgentLease {
  if (-not (Install-Agent)) { return }
  $code = Invoke-Agent @('verify')
  if ($code -eq 0) { Write-Tag 'OK' 'the licence on this machine is valid - no internet needed.' }
  else {
    Write-Tag 'FAIL' 'the licence on this machine is not valid - the reason is printed above.'
    Write-Hint 'refresh it (item 7); if it stays red, send item 9 to support.'
  }
}

function Show-AgentDevice {
  if (-not (Install-Agent)) { return }
  Write-Host ''
  $null = Invoke-Agent @('device-info')
  Write-Host ''
}

function Toggle-AgentSchedule {
  # The same reason as Test-AgentSchedule: on a machine without the task,
  # schtasks answers with "ERROR: The system cannot find the file specified" on
  # stderr, and 2>&1 put that banner in the middle of the screen. Both streams
  # are dropped; the exit code alone decides which way the toggle goes.
  $previous = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  try { & schtasks.exe /Query /TN $AgentTaskName *> $null } finally { $ErrorActionPreference = $previous }
  if ($LASTEXITCODE -eq 0) {
    & schtasks.exe /Delete /TN $AgentTaskName /F | Out-Null
    Write-Host 'automatic licence refresh removed.'
    return
  }
  $launcher = Get-AgentLauncher
  if (-not $launcher) { return }
  $target = '"{0}" {1}refresh' -f $launcher.File, (($launcher.Args | ForEach-Object { '"{0}" ' -f $_ }) -join '')
  $null = & schtasks.exe /Create /SC HOURLY /TN $AgentTaskName /TR $target /F 2>&1
  if ($LASTEXITCODE -eq 0) { Write-Host 'automatic licence refresh enabled (every hour).' }
  else { Write-Host 'the scheduled refresh could not be created.' -ForegroundColor Yellow }
}

function Remove-AgentLease {
  if (-not (Test-Path $AgentLeaseFile)) { Write-Tag 'WARN' 'this machine has no licence to remove.'; return }
  $a = Read-Default 'remove the licence from this machine? the Expert stops trading (y/n)' 'n'
  if ($a -ne 'y') { Write-Tag 'WARN' 'cancelled - the licence was not touched.'; return }
  $null = Invoke-Agent @('uninstall')
  Write-Tag 'OK' 'the licence was removed from this machine.'
  Write-Hint 'the serial is not lost: item 4 activates it again on this machine.'
}

# Uninstall-Everything calls this: a removed dashboard must not leave a licence
# agent and its hourly task behind.
function Remove-AgentInstall {
  $null = & schtasks.exe /Query /TN $AgentTaskName 2>&1
  if ($LASTEXITCODE -eq 0) { & schtasks.exe /Delete /TN $AgentTaskName /F | Out-Null }
  if (Test-Path $AgentDir) { Remove-Item -Recurse -Force $AgentDir -ErrorAction SilentlyContinue }
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
  # MAPSIM_MENU_SHIM tells the menu the console window belongs to this shim, so
  # the Persian window may hide it once it is on screen.
  $cmd = "@echo off`r`nset MAPSIM_MENU_SHIM=1`r`npowershell -NoProfile -ExecutionPolicy Bypass -File `"$MenuPath`" %*"
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
  $installed = Get-InstalledVersion
  $ver = $Version
  if (-not $ver) {
    # Ask GitHub directly instead of reading the cache: an install the user asked
    # for must never act on a tag cached hours ago.
    try { $tags = @(Get-ReleaseTagList); if ($tags.Count -gt 0) { $ver = [string]$tags[0] } } catch { }
  }
  if (-not $ver) { $ver = $FallbackVersion }
  $plain = $ver -replace '^dashboard-v', ''
  # An update that replaces a newer build with an older one is the worst silent
  # outcome of a failed lookup, so it is never done without an explicit yes.
  if ($installed -and -not (Test-NewerDashboardVersion $plain $installed)) {
    $a = Read-Default "version $installed is already installed - reinstall $plain anyway? (y/n)" 'n'
    if ($a -ne 'y') { Write-Host 'nothing was changed.'; return }
  }
  $asset = 'MapsimDashboard-windows-x64.zip'
  $base = "https://github.com/$Repo/releases/download/$ver"
  Write-Host "installing $ver ($asset) ..."
  $tmp = Join-Path ([IO.Path]::GetTempPath()) ([IO.Path]::GetRandomFileName())
  New-Item -ItemType Directory -Force $tmp | Out-Null
  try {
    Invoke-WebRequest -Uri "$base/$asset" -OutFile (Join-Path $tmp $asset) -TimeoutSec 600 -UseBasicParsing
    Invoke-WebRequest -Uri "$base/$asset.sha256" -OutFile (Join-Path $tmp "$asset.sha256") -TimeoutSec 60 -UseBasicParsing
    $expected = ((Get-Content (Join-Path $tmp "$asset.sha256")) -split '\s+')[0].ToLower()
    $actual = (Get-FileHash (Join-Path $tmp $asset) -Algorithm SHA256).Hash.ToLower()
    if ($expected -ne $actual) { throw "checksum mismatch for $asset" }
    # Copy the menu out before AppDir is replaced: on older installs the running
    # script lived inside it and would be gone by the time Install-Self reads it.
    Install-Self
    $hadService = Test-ServiceRunning
    $wasRunning = [bool](Get-DashboardPid)
    Stop-Dashboard | Out-Null
    if (Test-Path $AppDir) { Remove-Item -Recurse -Force $AppDir }
    New-Item -ItemType Directory -Force $AppDir | Out-Null
    Expand-Archive -Path (Join-Path $tmp $asset) -DestinationPath $AppDir -Force
    Unblock-File -Path $Binary -ErrorAction SilentlyContinue
  } finally {
    Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
  }
  Write-Shim
  New-Item -ItemType Directory -Force $ConfigDir | Out-Null
  Set-Content -Path $VersionFile -Value $plain -Encoding ASCII
  # The tag that was just installed is the newest one, so the cached answer is
  # stale by definition; drop it and let the next check read GitHub.
  Remove-Item $UpdateCacheFile -Force -ErrorAction SilentlyContinue
  $now = Get-InstalledVersion
  if (-not $now) {
    Write-Host "warning: $AppDir was written but reports no version - check the dashboard log." -ForegroundColor Yellow
  } elseif ($now -ne $plain) {
    Write-Host "warning: the installed build reports $now, expected $plain." -ForegroundColor Yellow
  } else {
    Write-Host "installed: $AppDir ($plain)"
  }
  # The update is only real once the new build runs: the task if it was the task,
  # otherwise the instance the user had started by hand.
  if ($hadService) {
    Start-ServiceTask
    Write-Host 'auto-start task started again with the new version.'
  } elseif ($wasRunning) {
    Write-Host 'starting the updated dashboard again ...'
    Start-Dashboard (Get-CurrentBind) (Get-CurrentPort)
  }
}

function Install-Self {
  New-Item -ItemType Directory -Force $MenuDir | Out-Null
  # The copy is a convenience, never a precondition: failing it must not abort a
  # dashboard update that has already been downloaded and verified.
  if ($PSCommandPath) {
    $sourcePath = [IO.Path]::GetFullPath($PSCommandPath)
    $menuPath = [IO.Path]::GetFullPath($MenuPath)
    if (-not [string]::Equals($sourcePath, $menuPath, [StringComparison]::OrdinalIgnoreCase)) {
      try {
        Copy-Item -Force $sourcePath $menuPath -ErrorAction Stop
      } catch {
        # The same file under two spellings (short 8.3 path, a mapped drive) makes
        # Copy-Item fail with "with itself"; the running script is already the
        # installed control center, so there is nothing to copy.
        if ($_.Exception.Message -notmatch 'with itself') {
          Write-Host "note: the control center could not copy itself to $MenuPath - $($_.Exception.Message)" -ForegroundColor Yellow
          Write-Host '      the dashboard update continues; run install.ps1 once to refresh the menu.' -ForegroundColor Yellow
        }
      }
    }
  }
  $legacy = Join-Path $AppDir 'mapsim-menu.ps1'
  if ((Test-Path $legacy) -and ($legacy -ne $MenuPath) -and ($legacy -ne $PSCommandPath)) {
    Remove-Item $legacy -Force -ErrorAction SilentlyContinue
  }
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
    Write-Host 'error: the dashboard needs an active Expert licence - it was not started.' -ForegroundColor Red
    Write-Host 'activate your serial in menu 12 (item 4), then start the dashboard again.'
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
    Write-Host 'license   : not built yet - the License menu (item 1) builds it from the Expert licence'
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
  Write-Host "expert    : $(Get-AgentSummary)"
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

# "dashboard-v1.0.9" -> [version]1.0.9, or $null for a tag that is not a version.
function ConvertTo-ReleaseVersion([string]$Tag) {
  if (-not $Tag) { return $null }
  try { return [version]($Tag -replace '^dashboard-v', '') } catch { return $null }
}

# Every release lookup goes through here. A draft or a prerelease is never
# offered (the held-back license-free builds are drafts), and the newest tag is
# chosen by version number instead of by the order the API happened to return
# it in.
function Get-ReleaseTagList {
  $rel = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo/releases?per_page=50" -TimeoutSec 12
  $rows = @()
  foreach ($r in @($rel)) {
    if ($r.draft -or $r.prerelease) { continue }
    if ($r.tag_name -notmatch '^dashboard-v\d') { continue }
    $v = ConvertTo-ReleaseVersion $r.tag_name
    if (-not $v) { continue }
    $rows += [pscustomobject]@{ tag = [string]$r.tag_name; ver = $v }
  }
  return @($rows | Sort-Object -Property ver -Descending | ForEach-Object { $_.tag })
}

# Newest licensed release tag, cached so the menu starts fast. -Force skips the
# cache: anything the user asked for explicitly must see today's release.
function Get-LatestDashboardTag([switch]$Force) {
  if (-not $Force -and (Test-Path $UpdateCacheFile)) {
    try {
      $cache = Get-Content $UpdateCacheFile -Raw | ConvertFrom-Json
      $age = [DateTimeOffset]::Now.ToUnixTimeSeconds() - [int64]$cache.checked
      if ($age -ge 0 -and $age -lt $UpdateCacheTtl -and $cache.tag) { return [string]$cache.tag }
    } catch { }
  }
  try {
    $tags = @(Get-ReleaseTagList)
    if ($tags.Count -gt 0) {
      $tag = [string]$tags[0]
      New-Item -ItemType Directory -Force $ConfigDir | Out-Null
      @{ checked = [DateTimeOffset]::Now.ToUnixTimeSeconds(); tag = $tag } | ConvertTo-Json | Set-Content -Path $UpdateCacheFile -Encoding ASCII
      return $tag
    }
  } catch { }
  # The network failed: a stale tag is still a better answer than none.
  if (Test-Path $UpdateCacheFile) {
    try {
      $cache = Get-Content $UpdateCacheFile -Raw | ConvertFrom-Json
      if ($cache.tag) { return [string]$cache.tag }
    } catch { }
  }
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

function Update-Refresh([switch]$Force) {
  $script:UpdateInstalled = Get-InstalledVersion
  $latestTag = Get-LatestDashboardTag -Force:$Force
  $script:UpdateLatest = ''
  if ($latestTag) { $script:UpdateLatest = $latestTag -replace '^dashboard-v', '' }
  $script:UpdateAvailable = $false
  if ($script:UpdateLatest -and $script:UpdateInstalled -and (Test-NewerDashboardVersion $script:UpdateLatest $script:UpdateInstalled)) {
    $script:UpdateAvailable = $true
    return
  }
  # "Nothing new" is the one answer the cache cannot be trusted for: it may have
  # been written before the release that is now on GitHub. Ask once more before
  # telling the user the build is up to date.
  if (-not $Force -and $script:UpdateInstalled) {
    $freshTag = Get-LatestDashboardTag -Force
    if ($freshTag) {
      $script:UpdateLatest = $freshTag -replace '^dashboard-v', ''
      $script:UpdateAvailable = Test-NewerDashboardVersion $script:UpdateLatest $script:UpdateInstalled
    }
  }
}

# The control center replaces its own installed copy when main publishes a newer
# one. Without this a fix can never reach a user who only opens the shortcut:
# the dashboard archive does not carry this file.
function Update-MenuSelf {
  try {
    $text = (Invoke-WebRequest -Uri (Get-FreshUrl $MenuUrl) -TimeoutSec 15 -UseBasicParsing).Content
    if (-not ($text -is [string]) -or -not $text) { return }
    if ($text -notmatch '(?m)^\$MapsimMenuVersion = ''([0-9][0-9.]*)''') { return }
    $remote = $Matches[1]
    if (-not (Test-NewerDashboardVersion $remote $MapsimMenuVersion)) { return }
    if ($text -notmatch 'function Show-Menu') { return }
    New-Item -ItemType Directory -Force $MenuDir | Out-Null
    $tmp = "$MenuPath.new"
    Set-Content -Path $tmp -Value $text -Encoding UTF8
    Move-Item -Force $tmp $MenuPath
    Write-Host "control center updated to $remote - it is used from the next start." -ForegroundColor Yellow
  } catch { }
}

function Invoke-StartupUpdateCheck {
  Update-MenuSelf
  $policy = Get-UpdatePolicy
  if ($policy -eq 'off') { return }
  # Forced: acting on a cached tag is how a release published minutes ago stays
  # invisible for hours, which is exactly the "auto update does nothing" bug.
  Update-Refresh -Force
  if (-not $script:UpdateAvailable) { return }
  if ($policy -eq 'auto') {
    Write-Host ''
    Write-Host "automatic update: $($script:UpdateInstalled) -> $($script:UpdateLatest)" -ForegroundColor Yellow
    $previousVersion = $Version
    $script:Version = "dashboard-v$($script:UpdateLatest)"
    try { Install-Dashboard } catch { Write-Host "automatic update failed: $($_.Exception.Message)" -ForegroundColor Red }
    $script:Version = $previousVersion
    Update-Refresh -Force
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
    Write-Host '  3) off    - never check for a new dashboard (the menu still fixes itself)'
    Write-Host '  4) check now'
    $a = Read-Host 'choose 1-4 (0 = back)'
    if ($a -eq '0') { return }
    switch ($a) {
      '1' { Set-UpdatePolicy 'notify'; Write-Host 'policy: notify.' }
      '2' { Set-UpdatePolicy 'auto'; Write-Host 'policy: auto - a new release installs at menu start.' }
      '3' { Set-UpdatePolicy 'off'; Write-Host 'policy: off.' }
      '4' {
        Write-Host 'checking GitHub ...'
        Update-Refresh -Force
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
  $a = Read-Host "$(Find-FaText $Prompt) [$Default]"
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
  # The console logo is block art: a window with a shaped, proportional font
  # paints it as a smear wider than the page, so the window gets a wordmark
  # built from real text and the console keeps the art it can draw.
  if ($script:GuiHost) {
    Write-Host ''
    Write-GuiWordmark
    Write-Host 'Dashboard control center' -ForegroundColor DarkGray
    return
  }
  Write-Host ''
  Write-Host ($Magenta + '    ##   ##  #####  ######   ###### ####### ##   ##   #####   #####  #######'.Replace('#', $BlockCh) + $NoColor)
  Write-Host ($Magenta + '    ### ### ##   ## ##   ## ##      ##      ### ###  ##   ## ##   ##   ###  '.Replace('#', $BlockCh) + $NoColor)
  Write-Host ($Magenta + '    ## # ## ####### ######   #####  ####### ## # ##  ######  ##   ##   ###  '.Replace('#', $BlockCh) + $NoColor)
  Write-Host ($Magenta + '    ##   ## ##   ## ##           ## ##      ##   ##  ##   ## ##   ##   ###  '.Replace('#', $BlockCh) + $NoColor)
  Write-Host ($Magenta + '    ##   ## ##   ## ##      ######  ####### ##   ##  ######   #####    ###  '.Replace('#', $BlockCh) + $NoColor)
}

# A padded cell of a fixed width can never line up in Persian: the script joins
# letters, so the width of a word is not the sum of its characters. Whenever the
# text is drawn without a console able to pad it - the window, and the console
# when it is showing Persian - the frame drops the vertical bars and the padding
# and keeps only a horizontal rule. English in the console keeps the full box.
function Test-PlainUi {
  return [bool]($script:GuiHost -or $script:MapsimLang -eq 'fa')
}

function Ui-Top {
  if (Test-PlainUi) {
    if ($script:GuiHost) { Write-GuiRule; return }
    Write-Host ($Cyan + ($BoxH * 79) + $NoColor); return
  }
  Write-Host ($Cyan + $BoxTL + ($BoxH * 79) + $BoxTR + $NoColor)
}
function Ui-Sep {
  if (Test-PlainUi) {
    if ($script:GuiHost) { Write-GuiRule; return }
    Write-Host ($Cyan + ($BoxH * 79) + $NoColor); return
  }
  Write-Host ($Cyan + $BoxL + ($BoxH * 79) + $BoxR + $NoColor)
}
function Ui-Bottom {
  if (Test-PlainUi) {
    if ($script:GuiHost) { Write-GuiRule; return }
    Write-Host ($Cyan + ($BoxH * 79) + $NoColor); return
  }
  Write-Host ($Cyan + $BoxBL + ($BoxH * 79) + $BoxBR + $NoColor)
}

function Ui-Row([string]$Label, [string]$Plain, [string]$Colored) {
  if (-not $Colored) { $Colored = $Plain }
  if (Test-PlainUi) {
    # 'label: value' with the label tinted, so a status reads as one sentence
    # instead of a padded table cell. The window aligns the line by language.
    $faLabel = Find-FaText $Label
    $faValue = Find-FaText $Plain
    $valueText = $faValue
    if ($Colored -ne $Plain) { $valueText = $Colored.Replace($Plain, $faValue) }
    Write-Host ('  ' + $Cyan + $faLabel + $NoColor + ': ' + $valueText)
    return
  }
  $body = '{0,-10}: {1}' -f $Label, $Colored
  $plainBody = '{0,-10}: {1}' -f $Label, $Plain
  $pad = 79 - 2 - $plainBody.Length
  if ($pad -lt 0) { $pad = 0 }
  Write-Host ($Cyan + $BoxV + $NoColor + '  ' + $body + (' ' * $pad) + $Cyan + $BoxV + $NoColor)
}

function Ui-Item([string]$Num, [string]$Text) {
  $faText = Find-FaText $Text
  if (Test-PlainUi) {
    $shown = '{0,2}' -f $Num
    if ($script:MapsimLang -eq 'fa') { $shown = ConvertTo-FaDigits $shown }
    # A number written in front of a Persian sentence is laid out at the far left
    # of a line that is otherwise right aligned, so the row starts visually with
    # its number and ends with its text - the wrong end for a Persian reader.
    # Last in the line puts it back on the right, which is where a Persian list
    # keeps the number it is asking you to type.
    if ($script:GuiHost -and $script:MapsimLang -eq 'fa') {
      Write-Host ('   ' + $White + $faText + $NoColor + '   ' + $Magenta + '(' + $shown.Trim() + ')' + $NoColor)
      return
    }
    Write-Host ('   ' + $Magenta + $shown + $NoColor + ' - ' + $White + $faText + $NoColor)
    return
  }
  Write-Host ($Cyan + $BoxV + $NoColor + '   ' + $Magenta + ('{0,2}' -f $Num) + $NoColor + ' - ' + $White + ('{0,-71}' -f $Text) + $NoColor + $Cyan + $BoxV + $NoColor)
}

# A group title inside the frame. Without it a flat list of twelve numbered
# lines is a wall: the licence screen prints three of these so the customer can
# see which block answers which question.
function Ui-Head([string]$Text) {
  $faText = Find-FaText $Text
  if (Test-PlainUi) { Write-Host ('  ' + $Yellow + $faText + $NoColor); return }
  $pad = 79 - 3 - $Text.Length
  if ($pad -lt 0) { $pad = 0 }
  Write-Host ($Cyan + $BoxV + $NoColor + '  ' + $Yellow + $Text + $NoColor + (' ' * $pad) + $Cyan + $BoxV + $NoColor)
}

# ---------------------------------------------------------------- status tags
# A customer must see at a glance whether something is fine, needs attention or
# is broken, so every verdict is printed through these three tags and never as
# plain prose in a grey wall of text. The tag is coloured and the rest of the
# line carries the same tint, which is also what the window host can paint (it
# maps 31/32/33 to red/amber/green and ignores nothing).
function Get-TagText([string]$Kind) {
  switch ($Kind) {
    'OK'   { return '[ OK ]' }
    'WARN' { return '[WARN]' }
    'FAIL' { return '[FAIL]' }
  }
  return '[INFO]'
}

function Get-TagColor([string]$Kind) {
  switch ($Kind) {
    'OK'   { return $Green }
    'WARN' { return $Yellow }
    'FAIL' { return $Red }
  }
  return $Cyan
}

# A frame row whose value is a verdict: "Expert licence  [ OK ] active ...".
function Ui-Status([string]$Label, [string]$Kind, [string]$Text) {
  $plain = (Get-TagText $Kind) + ' ' + $Text
  Ui-Row $Label $plain ((Get-TagColor $Kind) + $plain + $NoColor)
}

# The same tag for a line outside the frame: the text is translated first and
# coloured afterwards, so the dictionary still matches the bare sentence.
function Write-Tag([string]$Kind, [string]$Text) {
  $tag = Find-FaText (Get-TagText $Kind)
  Write-Host ('  ' + (Get-TagColor $Kind) + $tag + $NoColor + ' ' + (Find-FaText $Text))
}

# A quiet line under a result: what to do next, or why nothing was changed.
function Write-Hint([string]$Text) {
  Write-Host ('  ' + (Find-FaText $Text)) -ForegroundColor DarkGray
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
    if (Test-LicenseSaved) { $licPlain = 'ready'; $licCol = $Green + $licPlain + $NoColor }
    else { $licPlain = 'not built'; $licCol = $Red + $licPlain + $NoColor }
    Ui-Row 'Dashboard login' $licPlain $licCol
    # The Expert's own licence: taken from the Agent, which reads it locally.
    $agentPlain = Get-AgentSummary
    if ($agentPlain -like 'ACTIVE*') { $agentCol = $Green + $agentPlain + $NoColor }
    elseif ($agentPlain -eq 'not activated') { $agentCol = $Yellow + $agentPlain + $NoColor }
    else { $agentCol = $Red + $agentPlain + $NoColor }
    Ui-Row 'Expert licence' $agentPlain $agentCol
    Ui-Row 'Access' $acc ($Cyan + $acc + $NoColor)
    Ui-Row 'Disk' $diskLine ($diskCol + $diskLine + $NoColor)
    if ($script:MapsimLang -eq 'fa') { $langPlain = 'Persian' } else { $langPlain = 'English' }
    Ui-Row 'Language' $langPlain ($Cyan + $langPlain + $NoColor)
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
    Ui-Item '12' 'License (one serial: Expert + dashboard)'
    Ui-Item '13' 'Update policy (notify / auto / off)'
    Ui-Item '14' 'Exit'
    Ui-Item 'L' 'Language: FA'
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
      '4' {
        try { Install-Dashboard; Update-Refresh -Force }
        catch { Write-Host "update failed: $($_.Exception.Message)" -ForegroundColor Red }
      }
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
      'l' {
        if ($script:MapsimLang -eq 'fa') { $script:MapsimLang = 'en' } else { $script:MapsimLang = 'fa' }
        New-Item -ItemType Directory -Force $ConfigDir | Out-Null
        Set-Content -Path $MenuLangFile -Value $script:MapsimLang -Encoding ASCII
        if ($script:MapsimLang -eq 'fa') {
          # Switching to Persian in a console session must open the window now:
          # a console cannot draw Persian, so it must never fall back to one.
          Initialize-MapsimHost
          Set-GuiLanguage
          Write-Host 'زبان فارسی فعال شد.'
        } else {
          # English belongs to the console: it gets its box frame and its padded
          # rows back. Leaving the window open painted an English page into a
          # right-to-left log, which is the broken English layout reported.
          Close-MapsimHost
          Write-Host 'English is active.'
        }
        continue
      }
      default { Write-Host 'please choose 1-14 or L.' }
    }
    $null = Read-Host "`nPress Enter to continue"
  }
}

# ---------------------------------------------------------------- expert advisor

$EaState = Join-Path $ConfigDir 'ea-state.env'

function Get-EaLatestVersion {
  try {
    $tags = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo/tags?per_page=100" -TimeoutSec 15
    # v213.x is the old publishing series (the V_213 builds). It is numerically
    # larger than the current v24.x line, so it would hide every newer Expert.
    $v = @($tags | ForEach-Object { $_.name } | Where-Object {
        $_ -match '^v(\d+)(\.\d+){1,3}$' -and [int]$Matches[1] -lt 100
      })
    if ($v.Count -eq 0) { return '' }
    return ($v | Sort-Object { [version]($_.Substring(1)) } | Select-Object -Last 1)
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
    # The published package carries the Windows builds under the sub folders; the
    # newest one is the last by name, not the first one found, and a 64-bit build
    # always beats a 32-bit one.
    $winBuilds = @(Get-ChildItem $pkg -Recurse -Filter '*.ex5' | Where-Object { $_.Name -match 'win' } | Sort-Object Name)
    $win64 = @($winBuilds | Where-Object { $_.Name -match '64' })
    if ($win64.Count -gt 0) { $winBuilds = $win64 }
    $ex5 = $winBuilds | Select-Object -Last 1
    if (-not $ex5) {
      $ex5 = Get-ChildItem $pkg -Recurse -Filter '*.ex5' | Sort-Object Name | Select-Object -Last 1
      if ($ex5) { Write-Host "note: no Windows build found - using $($ex5.Name)" }
    }
    if (-not $ex5) { throw "no .ex5 Expert file in the $Version package." }
    if ($winBuilds.Count -gt 1) {
      Write-Host "Windows builds in $Version :"
      foreach ($b in $winBuilds) { Write-Host "  $($b.Name)  ($([math]::Round($b.Length / 1KB)) KB)" }
    }
    if ($ex5.Name -notmatch '64') {
      Write-Host "warning: $($ex5.Name) is a 32-bit Windows build and MetaTrader 5 runs 64-bit Experts." -ForegroundColor Yellow
    }
    $existing = @()
    foreach ($mql5 in @($mql5List)) {
      $f = Join-Path $mql5 "Experts\$($ex5.Name)"
      if (Test-Path $f) { $existing += $f }
    }
    if ($existing.Count -gt 0) {
      Write-Host "this replaces an Expert that is already installed ($($ex5.Name)):"
      foreach ($f in $existing) { Write-Host "  $f" }
      $a = Read-Default 'replace it? (y/n)' 'n'
      if ($a -ne 'y') { Write-Host 'nothing was changed.'; return }
    }
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
  Write-Host '  4) activate your serial in the License menu (item 4)'
  Write-Host '  5) the same serial opens the dashboard (main menu - 2)'
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
  Remove-AgentInstall
  Remove-Service
  Stop-Dashboard | Out-Null
  if (Test-Path $AppDir) { Remove-Item -Recurse -Force $AppDir }
  if (Test-Path $MenuDir) { Remove-Item -Recurse -Force $MenuDir }
  if (Test-Path $ConfigDir) { Remove-Item -Recurse -Force $ConfigDir }
  if (Test-Path $LicenseDir) { Remove-Item -Recurse -Force $LicenseDir }
  $desktop = [Environment]::GetFolderPath('Desktop')
  Remove-Item (Join-Path $desktop 'Mapsim BOT.lnk') -ErrorAction SilentlyContinue
  Remove-Item (Join-Path $desktop 'MapsimDashboard.lnk') -ErrorAction SilentlyContinue
  Remove-Item (Join-Path $desktop 'Mapsim Live Dashboard.lnk') -ErrorAction SilentlyContinue
  Write-Host 'Mapsim Live Dashboard removed completely (MT5 and the EA were not touched).'
}

# ---------------------------------------------------------------- window host
# Why a window at all: a console cannot join Persian letters and orders a line
# that mixes Persian, digits and English words run by run from the left, so the
# sentence comes out scrambled on Windows 10, 11 and Server alike whichever font
# is set. The window is the same menu drawn by a text engine that shapes and
# orders it: the overridden Write-Host paints into a rich-text log, Read-Host
# waits for a text box, Clear-Host empties the log, so no menu function changes -
# only where its text lands. English keeps the console, and MAPSIM_MENU_CONSOLE=1
# (or -Console) keeps it for Persian as well.
$script:GuiHost = $false
$script:GuiAlive = $false
$script:GuiClosed = $false
$script:GuiAnswer = $null
$script:GuiPending = ''
$script:GuiSnapTaken = $false
$script:GuiSnapshot = $env:MAPSIM_MENU_SNAPSHOT
$script:GuiTitleFont = $null

# Any machine that can run the dashboard also has Segoe UI or Tahoma, both of
# which shape Persian, so the window never needs a font file installed; a bundled
# Persian face is used when the user already has one.
function Get-GuiFontFamily {
  $wanted = @('Vazirmatn', 'Vazir', 'IRANSansX', 'IRANSans', 'IRANYekan', 'Sahel', 'Shabnam', 'Segoe UI', 'Tahoma')
  $names = @()
  try {
    $fonts = New-Object System.Drawing.Text.InstalledFontCollection
    $names = @($fonts.Families | ForEach-Object { $_.Name })
  } catch { }
  foreach ($name in $wanted) { if ($names -contains $name) { return $name } }
  return 'Segoe UI'
}

# One page, one direction. Persian reads from the right; English reads from the
# left and is drawn by the console, but the window still honours it when it has
# to paint an English line.
function Get-GuiAlignment {
  if ($script:MapsimLang -eq 'fa') { return 'Right' }
  return 'Left'
}

# A console rule is 79 characters. In a window that is a short line floating at
# one edge of a 940-pixel page, so the rule is measured from the mono font and
# spans the page; it is recomputed on every redraw, so it follows a resize.
function Get-GuiRuleCount {
  $width = 0
  try { $width = $script:GuiLog.ClientSize.Width } catch { }
  if ($width -le 0) { $width = 900 }
  $unit = 0
  try {
    $sample = [string][char]0x2500
    $unit = [System.Windows.Forms.TextRenderer]::MeasureText(($sample * 10), $script:GuiMono).Width / 10.0
  } catch { }
  if ($unit -le 0) { $unit = 7 }
  $count = [int](($width - 40) / $unit)
  if ($count -lt 24) { $count = 24 }
  return $count
}

function Write-GuiRule {
  $line = [string][char]0x2500
  Write-Host ($Cyan + ($line * (Get-GuiRuleCount)) + $NoColor)
}

# The window title is text, not art: one wordmark at a size a proportional font
# can draw without clipping.
function Write-GuiWordmark {
  $log = $script:GuiLog
  if (-not $log -or -not $script:GuiTitleFont) { return }
  $log.SelectionStart = $log.TextLength
  $log.SelectionLength = 0
  try { $log.SelectionAlignment = Get-GuiAlignment } catch { }
  $log.SelectionFont = $script:GuiTitleFont
  $log.SelectionColor = [System.Drawing.ColorTranslator]::FromHtml('#D2A8FF')
  # One colour run on purpose: two runs split the wordmark into two bidi units,
  # and a right-to-left page lays those units out backwards ('BOT MAPSIM').
  # The accent colour goes on the subtitle line instead.
  $log.AppendText("MAPSIM BOT`n")
  $log.SelectionStart = $log.TextLength
  $log.ScrollToCaret()
}

# The direction is set from the language every time it changes: an English page
# painted into a right-to-left window is exactly the broken English layout that
# was reported, so this pair of calls is the guard against it.
function Set-GuiLanguage {
  if (-not $script:GuiForm) { return }
  $rtl = ($script:MapsimLang -eq 'fa')
  $direction = $(if ($rtl) { 'Yes' } else { 'No' })
  try { $script:GuiForm.RightToLeft = $direction } catch { }
  try { $script:GuiForm.RightToLeftLayout = $rtl } catch { }
  try { $script:GuiLog.RightToLeft = $direction } catch { }
  try { $script:GuiInput.RightToLeft = $direction } catch { }
  try { $script:GuiButton.Text = $(if ($rtl) { 'تأیید' } else { 'OK' }) } catch { }
}

# The console colours (30-37) on a dark log; the palette is the same as the
# console one so a red line still means the same thing.
function Get-GuiColor([object]$Code, [string]$Fallback = '#E6EDF3') {
  $key = -1
  [void][int]::TryParse([string]$Code, [ref]$key)
  switch ($key) {
    31 { return '#FF7B72' }
    32 { return '#7EE787' }
    33 { return '#E3B341' }
    34 { return '#79C0FF' }
    35 { return '#D2A8FF' }
    36 { return '#56D4DD' }
    37 { return '#E6EDF3' }
    90 { return '#8B949E' }
  }
  return $Fallback
}

function Get-GuiTintCode([object]$Tint) {
  switch ([string]$Tint) {
    'Red' { return 31 }
    'Green' { return 32 }
    'Yellow' { return 33 }
    'Blue' { return 34 }
    'Magenta' { return 35 }
    'Cyan' { return 36 }
    'White' { return 37 }
    'Gray' { return 90 }
    'DarkGray' { return 90 }
  }
  return 0
}

function Add-GuiRun([string]$Text, [string]$Hex) {
  $log = $script:GuiLog
  $log.SelectionStart = $log.TextLength
  $log.SelectionLength = 0
  $log.SelectionColor = [System.Drawing.ColorTranslator]::FromHtml($Hex)
  $log.AppendText($Text)
}

function Clear-GuiScreen {
  if (-not $script:GuiHost -or -not $script:GuiAlive) { return }
  try { $script:GuiLog.Clear(); $script:GuiPending = '' } catch { }
}

# A RichEdit takes the paragraph direction from the paragraph format and offers
# no public API for it: the only lever is EM_SETPARAFORMAT, which on this engine
# rewrites the first paragraph of a page and leaves the rest as they were, so it
# cannot turn a whole screen around. The menu keeps the plain layout in Persian
# (no padded columns, no box) and hands the direction to the control's own
# RightToLeft setting in Set-GuiLanguage.

function Write-GuiLine([string]$Text, [bool]$NoNewline, [object]$Tint) {
  if (-not $script:GuiHost -or -not $script:GuiAlive) { return }
  if ($null -eq $Text) { $Text = '' }
  if ($script:GuiPending) { $Text = $script:GuiPending + $Text; $script:GuiPending = '' }
  if ($NoNewline) { $script:GuiPending = $Text; return }
  $log = $script:GuiLog
  # The console padded a label with spaces to line its colon up; a proportional
  # font does not need that and the gap reads as a hole inside the sentence.
  # Only runs inside the line are collapsed - the leading spaces are the indent
  # of the row and must survive, or every line loses its margin.
  if ($Text -match '[\u0600-\u06FF]') {
    $indent = [regex]::Match($Text, '^[ \t]+').Value
    $rest = $Text.Substring($indent.Length)
    $Text = $indent + (($rest.TrimEnd() -replace '[ \t]{2,}', ' ') -replace ' +:', ':')
  }
  $base = Get-GuiColor -Code (Get-GuiTintCode $Tint)
  if ($log.TextLength -gt 150000) {
    try {
      $log.ReadOnly = $false
      $log.Select(0, 40000)
      $log.SelectedText = ''
      $log.ReadOnly = $true
    } catch { }
  }
  $log.SelectionStart = $log.TextLength
  $log.SelectionLength = 0
  # A page carries one alignment, taken from the language of the page. Mixing
  # them by line leaves the menu ragged on one side, and an English page in a
  # right-to-left log is exactly the broken English layout reported on 1.0.9.
  $log.SelectionAlignment = Get-GuiAlignment
  $log.SelectionFont = $(if ($Text -match '[\u2588\u2500-\u254B]') { $script:GuiMono } else { $script:GuiFont })
  $cursor = 0
  foreach ($m in [regex]::Matches($Text, "$([char]27)\[([0-9;]*)m")) {
    if ($m.Index -gt $cursor) { Add-GuiRun $Text.Substring($cursor, $m.Index - $cursor) $base }
    $parts = $m.Groups[1].Value.Split(';')
    $code = 0
    [void][int]::TryParse($parts[$parts.Count - 1], [ref]$code)
    if ($code -eq 0) { $base = Get-GuiColor -Code (Get-GuiTintCode $Tint) }
    else { $base = Get-GuiColor -Code $code -Fallback $base }
    $cursor = $m.Index + $m.Length
  }
  if ($cursor -lt $Text.Length) { Add-GuiRun $Text.Substring($cursor) $base }
  Add-GuiRun "`n" (Get-GuiColor -Code 0 -Fallback '#E6EDF3')
  $log.SelectionStart = $log.TextLength
  $log.ScrollToCaret()
  # Keep the window painted while a download or a service call blocks the script.
  [System.Windows.Forms.Application]::DoEvents()
}

function Save-GuiSnapshot {
  # Diagnostics only (MAPSIM_MENU_SNAPSHOT): a screen grab of the window plus the
  # plain text it holds, so the log can be checked without a person looking at it.
  try {
    $form = $script:GuiForm
    # A screen grab only shows the window while it is on top.
    $wasTop = [bool]$form.TopMost
    $form.TopMost = $true
    try { $form.Activate() } catch { }
    [System.Windows.Forms.Application]::DoEvents()
    Start-Sleep -Milliseconds 300
    $bounds = $form.Bounds
    $bmp = New-Object System.Drawing.Bitmap($bounds.Width, $bounds.Height)
    $graphics = [System.Drawing.Graphics]::FromImage($bmp)
    try { $graphics.CopyFromScreen($bounds.Location, [System.Drawing.Point]::Empty, $bounds.Size) }
    catch { $form.DrawToBitmap($bmp, (New-Object System.Drawing.Rectangle(0, 0, $bounds.Width, $bounds.Height))) }
    $graphics.Dispose()
    $bmp.Save($script:GuiSnapshot, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
    $form.TopMost = $wasTop
    $log = $script:GuiLog
    $dump = @("chars : $($log.TextLength)", "lines : $($log.Lines.Count)", '--- text ---') + @($log.Lines)
    [IO.File]::WriteAllLines("$($script:GuiSnapshot).txt", $dump, (New-Object System.Text.UTF8Encoding($false)))
  } catch {
    try { [IO.File]::AppendAllText("$($script:GuiSnapshot).err", $_.Exception.Message) } catch { }
  }
}

function Read-GuiLine([string]$Prompt, [bool]$Secret) {
  if (-not $script:GuiAlive) { exit }
  if ($Prompt) { Write-GuiLine $Prompt $false $null }
  $script:GuiAnswer = $null
  $script:GuiInput.Text = ''
  $script:GuiInput.UseSystemPasswordChar = $Secret
  $script:GuiPanel.Visible = $true
  [void]$script:GuiInput.Focus()
  $tick = [Environment]::TickCount
  while ($null -eq $script:GuiAnswer) {
    if (-not $script:GuiAlive) { exit }
    [System.Windows.Forms.Application]::DoEvents()
    Start-Sleep -Milliseconds 20
    if ($script:GuiSnapshot -and -not $script:GuiSnapTaken -and (([Environment]::TickCount - $tick) -gt 600)) {
      $script:GuiSnapTaken = $true
      Save-GuiSnapshot
      exit
    }
  }
  $answer = [string]$script:GuiAnswer
  $script:GuiAnswer = $null
  $script:GuiInput.UseSystemPasswordChar = $false
  $script:GuiPanel.Visible = $false
  [System.Windows.Forms.Application]::DoEvents()
  return $answer
}

function Initialize-MapsimHost {
  if ($script:GuiHost) { return }
  if ($script:MapsimLang -ne 'fa') { return }
  if ($Console -or $env:MAPSIM_MENU_CONSOLE -eq '1') {
    # Asked to stay in the console: say so in Persian, then draw text only.
    Write-Host 'note: Persian needs the window; press L and choose English for the console.'
    return
  }
  try {
    Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
    Add-Type -AssemblyName System.Drawing -ErrorAction Stop
    [System.Windows.Forms.Application]::EnableVisualStyles()

    $family = Get-GuiFontFamily
    try { $script:GuiFont = New-Object System.Drawing.Font($family, 11.5) }
    catch { $script:GuiFont = New-Object System.Drawing.Font('Segoe UI', 11.5) }
    try { $script:GuiMono = New-Object System.Drawing.Font('Consolas', 10.5) }
    catch { $script:GuiMono = $script:GuiFont }
    try { $script:GuiTitleFont = New-Object System.Drawing.Font($family, 21, [System.Drawing.FontStyle]::Bold) }
    catch { $script:GuiTitleFont = New-Object System.Drawing.Font('Segoe UI', 21, [System.Drawing.FontStyle]::Bold) }

    $form = New-Object System.Windows.Forms.Form
    $form.Text = 'Mapsim BOT'
    $form.ClientSize = New-Object System.Drawing.Size(940, 740)
    $form.MinimumSize = New-Object System.Drawing.Size(720, 520)
    $form.StartPosition = 'CenterScreen'
    $form.BackColor = [System.Drawing.ColorTranslator]::FromHtml('#14161B')
    $form.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#E6EDF3')
    $form.Font = $script:GuiFont

    $log = New-Object System.Windows.Forms.RichTextBox
    $log.Dock = 'Fill'
    $log.ReadOnly = $true
    $log.BorderStyle = 'None'
    $log.WordWrap = $true
    # No scrollbar: an RTL RichTextBox paints its scrollbar over the left end of
    # the text, and the log already follows the caret at the end of every line.
    $log.ScrollBars = 'None'
    $log.BackColor = [System.Drawing.ColorTranslator]::FromHtml('#14161B')
    $log.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#E6EDF3')
    $log.Font = $script:GuiFont
    $log.DetectUrls = $false

    $panel = New-Object System.Windows.Forms.Panel
    $panel.Dock = 'Bottom'
    $panel.Height = 58
    $panel.Padding = New-Object System.Windows.Forms.Padding(12, 10, 12, 10)
    $panel.BackColor = [System.Drawing.ColorTranslator]::FromHtml('#1B1F26')
    $panel.Visible = $false

    $grid = New-Object System.Windows.Forms.TableLayoutPanel
    $grid.Dock = 'Fill'
    $grid.ColumnCount = 2
    $grid.RowCount = 1
    [void]$grid.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))
    [void]$grid.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute, 110)))

    $input = New-Object System.Windows.Forms.TextBox
    $input.Dock = 'Fill'
    $input.BorderStyle = 'FixedSingle'
    $input.BackColor = [System.Drawing.ColorTranslator]::FromHtml('#0F1115')
    $input.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#E6EDF3')
    $input.Font = $script:GuiFont
    $input.Margin = New-Object System.Windows.Forms.Padding(0, 0, 8, 0)

    $ok = New-Object System.Windows.Forms.Button
    $ok.Dock = 'Fill'
    $ok.Text = 'OK'
    $ok.FlatStyle = 'Flat'
    $ok.BackColor = [System.Drawing.ColorTranslator]::FromHtml('#2F6FEB')
    $ok.ForeColor = [System.Drawing.Color]::White
    $ok.Font = $script:GuiFont

    [void]$grid.Controls.Add($input, 0, 0)
    [void]$grid.Controls.Add($ok, 1, 0)
    [void]$panel.Controls.Add($grid)
    # A RichTextBox paints from its own edge and has no padding of its own, so a
    # right-to-left page ran every line into the right border and clipped the
    # last letter. A padded host gives the text the same margin in either
    # direction, which is what the screenshots of the licence screen showed.
    $host3 = New-Object System.Windows.Forms.Panel
    $host3.Dock = 'Fill'
    $host3.BackColor = [System.Drawing.ColorTranslator]::FromHtml('#14161B')
    $host3.Padding = New-Object System.Windows.Forms.Padding(16, 6, 16, 6)
    [void]$host3.Controls.Add($log)
    [void]$form.Controls.Add($host3)
    [void]$form.Controls.Add($panel)
    $form.AcceptButton = $ok

    $ok.Add_Click({
      if ($null -eq $script:GuiAnswer) { $script:GuiAnswer = $script:GuiInput.Text }
    })
    $form.Add_FormClosing({
      $script:GuiClosed = $true
      $script:GuiAlive = $false
      if ($null -eq $script:GuiAnswer) { $script:GuiAnswer = '' }
    })

    $script:GuiForm = $form
    $script:GuiLog = $log
    $script:GuiPanel = $panel
    $script:GuiInput = $input
    $script:GuiButton = $ok
    $script:GuiAlive = $true
    $script:GuiHost = $true
    # Direction, button text and input alignment all come from the language;
    # nothing here is hard-wired to right-to-left.
    Set-GuiLanguage
    $form.Show()
    [System.Windows.Forms.Application]::DoEvents()
    $form.Activate()

    # The shim owns the console window it opened, so it is hidden once the menu
    # has a window of its own; started from an existing terminal the console is
    # left alone. Close-MapsimHost brings it back when the menu returns to
    # English.
    if ($env:MAPSIM_MENU_SHIM -eq '1') {
      $hostType = Get-ConsoleHostType
      if ($hostType) {
        try {
          $handle = $hostType::GetConsoleWindow()
          if ($handle -ne [IntPtr]::Zero) { [void]$hostType::ShowWindow($handle, 0) }
        } catch { }
      }
    }
  } catch {
    $script:GuiHost = $false
    $script:GuiAlive = $false
    Write-Host 'note: the Persian window could not be opened; the menu continues in this console.'
    Write-Host 'note: Persian needs the window; press L and choose English for the console.'
  }
}

# The console handle is needed twice: once to hide the console the shim opened,
# once to bring it back when the menu switches to English.
function Get-ConsoleHostType {
  if (-not ('Mapsim.ConsoleHost' -as [type])) {
    try {
      Add-Type -Namespace Mapsim -Name ConsoleHost -MemberDefinition '[DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow(); [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow); [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);'
    } catch { return $null }
  }
  return ('Mapsim.ConsoleHost' -as [type])
}

# Closing the window is not the same as exiting the menu: the console takes the
# next page. English is a console language here, so leaving the window open
# would paint it into a right-to-left page - the broken layout reported on 1.0.9.
function Close-MapsimHost {
  if (-not $script:GuiHost) { return }
  $script:GuiAlive = $false
  $script:GuiHost = $false
  try { $script:GuiForm.Close() } catch { }
  try { $script:GuiForm.Dispose() } catch { }
  $script:GuiForm = $null
  $script:GuiLog = $null
  $script:GuiPanel = $null
  $script:GuiInput = $null
  $script:GuiButton = $null
  $script:GuiPending = ''
  $script:GuiSnapTaken = $false
  $hostType = Get-ConsoleHostType
  if ($hostType) {
    try {
      $handle = $hostType::GetConsoleWindow()
      if ($handle -ne [IntPtr]::Zero) {
        [void]$hostType::ShowWindow($handle, 5)
        [void]$hostType::SetForegroundWindow($handle)
      }
    } catch { }
  }
}

# ------------------------------------------------------------------ entrypoint

# The one-shot switches print into this console, which cannot draw Persian, so
# they answer in English even when the menu itself is set to Persian. Only the
# file on disk decides the language; this never writes it.
if ($Status -or $Stop -or $RemoveService -or $Uninstall -or $Bootstrap) { $script:MapsimLang = 'en' }

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

Initialize-MapsimHost
Show-Menu
if ($script:GuiHost) { try { $script:GuiForm.Close() } catch { } }
