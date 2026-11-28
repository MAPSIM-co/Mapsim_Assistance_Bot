# START HERE - Mapsim Assistance Bot, first run

**This page is the whole journey, start to finish.** Follow it once and both
halves of the product are running on your machine:

* the **Expert Advisor** (`Mapsim_Assistance_Bot.ex5`) inside MetaTrader 5, and
* the **dashboard** (the live panel in your browser).

> **One licence, two programs.** The serial you buy on the site opens the Expert
> *and* the dashboard. There is no second licence to buy for the dashboard, and
> nothing to type twice.

Everything happens from one command: **`Mapsim_BOT`**, the control centre this
repository installs for you.

---

## 1. What you need

| | Windows | macOS / Linux |
|---|---|---|
| System | Windows 10 or 11, 64-bit | macOS 12+ (Intel/Apple) or a 64-bit Linux desktop |
| Terminal | MetaTrader 5 (64-bit, build 3000 or newer) | MetaTrader 5 for macOS / Wine |
| Internet | required for the install, the licence and updates | same |
| Time | about 15 minutes, plus the time the shop needs to confirm your payment | same |

You do **not** need Python, a database, or anything else. The control centre
downloads what it needs.

---

## 2. Install the control centre

Open a terminal and run **one line**, depending on your system.

**Windows** (PowerShell - press `Win`, type `PowerShell`, Enter):

```powershell
irm https://raw.githubusercontent.com/MAPSIM-co/Mapsim_Assistance_Bot/main/Dashboard_Release/install.ps1 | iex
```

**macOS / Linux** (Terminal):

```sh
curl -fsSL https://raw.githubusercontent.com/MAPSIM-co/Mapsim_Assistance_Bot/main/Dashboard_Release/install.sh | sh
```

The installer downloads the control centre, puts the command `Mapsim_BOT` on your
machine, installs the dashboard and opens the menu. From now on you never run the
installer again - use:

```
Mapsim_BOT
```

> If Windows says *"running scripts is disabled"*, run the same installer with:
> `powershell -ExecutionPolicy Bypass -Command "irm https://raw.githubusercontent.com/MAPSIM-co/Mapsim_Assistance_Bot/main/Dashboard_Release/install.ps1 | iex"`

The menu is bilingual. Press **L** to switch between English and Persian.

---

## 3. Install the Expert into MetaTrader 5

In the menu:

* **Windows:** `9) Expert Advisor: install / update`
* **macOS / Linux:** `9) Expert Advisor: install / update`

The menu asks which MetaTrader folder to use (if you have several, it lists them
and you can choose `a` for all). It copies the Expert, the SQLite library and the
sound files into place, then prints the version it installed.

Then, in MetaTrader 5:

1. **Restart MetaTrader 5** (it must see the new files).
2. Open a **M15 chart** of the symbol you trade.
3. Drag **Mapsim Assistance Bot** from the Navigator onto the chart.
4. In the dialog that opens, on the **Common** tab tick:
   * *Allow DLL imports*
   * *Allow algorithmic trading*
5. Press OK, and make sure the **Algo Trading** button in the toolbar is green.

The Expert now shows *no licence* until step 5. That is expected.

---

## 4. Buy the licence on the site

Open **<https://shop.mapsim.shop>** and work through these four screens:

1. **Sign up** (`/signup`) with your email, a username and a password.
2. **Wallet** (`/app/wallet`) - deposit **USDT**. Choose the network
   (**TRC20**, **ERC20** or **BEP20**), send the amount to the address shown and
   paste the **transaction id**. An operator confirms it; the balance appears in
   your wallet.
3. **Plans** (`/plans`) - pick the plan you want and pay from your wallet balance.
4. **Licences** (`/app/licences`) - your **serial** is created immediately.
   Press **Reveal** to see it. Every reveal is recorded, so treat it like a
   password.

| Plan | Price | Length | Devices |
|---|---|---|---|
| Assist · 1 month | 49 USDT | 30 days | 1 |
| Assist · 3 months | 129 USDT | 90 days | 1 |
| Assist · 12 months | 399 USDT | 365 days | 2 |
| Assist · 12 months (hardware key) | 749 USDT | 365 days | 1 |

Prices and availability are always the ones shown on `/plans` - that page is the
source of truth.

The serial looks like `MAPSIM-XXXX-XXXX-XXXX-XXXX`. Keep the page open, you need
it in the next step.

---

## 5. Activate the serial (one serial, both programs)

Back in the **`Mapsim_BOT`** menu:

* **Windows:** `12) License (one serial: Expert + dashboard)`
* **macOS / Linux:** `13) License (one serial: Expert + dashboard)`

Then choose **`4) Activate the Expert with a serial`** and paste the serial.

The menu:

1. registers your MetaTrader folder (so the Expert can read the licence),
2. contacts the licence server and binds the serial to **this** machine,
3. writes the licence where the Expert reads it,
4. **builds the dashboard login from the same licence** - you will see:

```
the dashboard login was prepared from your Expert licence:
  login    : ................................
  password : ................................
  account  : 12345678
  valid to : 2027.01.15 14:30
```

Write down the **login** and **password**, or come back any time to
`License → 1) Build / refresh the dashboard login now` - it prints them again.
Both values are the same string; the dashboard asks for it in the browser.

---

## 6. Start the Expert

In MetaTrader 5, on the chart you prepared:

* the Expert's panel should now show **ACTIVE** and the days left;
* if it still shows *no licence*, open the chart menu → **Expert Advisors** →
  **Properties** and confirm that *Allow DLL imports* is ticked, then
  right-click the chart → **Expert Advisors → Restart**.

Nothing else is required: the licence refreshes itself in the background every
few hours (`License → 10)` turns that on or off).

---

## 7. Open the dashboard

In the menu, choose **`2) Start dashboard`**. The first start prepares the login
from your licence, so you never enter a second one.

Your browser opens **<http://127.0.0.1:8765>**. If it asks for a username and
password, use the **dashboard login** from step 5 (the same value in both boxes).

The dashboard reads the Expert's live data. Until MetaTrader is running with the
Expert attached and has written its first snapshot, it shows an empty view - that
is normal, not an error.

---

## 8. Every day after this

You only need two things: `Mapsim_BOT` when you want to manage the product, and
MetaTrader 5 with the Expert on a chart.

Main menu, Windows:

| # | Item |
|---|---|
| 1 | Status |
| 2 | Start dashboard |
| 3 | Stop dashboard |
| 4 | Install / update dashboard |
| 5 | Service management (start/stop/restart/enable/disable) |
| 6 | Remove auto-start service |
| 7 | Access mode (local / internet) |
| 8 | Uninstall everything |
| 9 | Expert Advisor: install / update |
| 10 | Expert Advisor: version check |
| 11 | Disk space / server storage |
| 12 | License (one serial: Expert + dashboard) |
| 13 | Update policy (notify / auto / off) |
| 14 | Exit |
| L | Language: English / Persian |

On macOS / Linux the list has one extra item in the middle (`12) Snapshot file /
data source`), so **License is 13** and **Exit is 15**. Every other number is the
same.

Inside **License**:

| # | Item | When you use it |
|---|---|---|
| 1 | Build / refresh the dashboard login now | you need the browser login again |
| 2 | Show the dashboard login status | is it still valid? |
| 3 | Remove the saved dashboard login | it is rebuilt on the next start |
| 4 | Activate the Expert with a serial | first run, or a new serial |
| 5 | Show the Expert licence status | what the Expert sees |
| 6 | Register the MetaTrader folder | you moved MT5 or added a second terminal |
| 7 | Refresh the licence now | after a renewal |
| 8 | Verify the licence locally | is this machine still licensed? |
| 9 | Device identity | support needs to move the licence |
| 10 | Automatic refresh on / off | rarely |
| 11 | Remove the licence from this machine | moving to a new computer |
| 12 | Enter an old dashboard licence | only if support sent you one |

---

## 9. Troubleshooting

| What you see | What to do |
|---|---|
| `that serial is not valid` | The serial is mistyped or has expired. Copy it again from `shop.mapsim.shop → /app/licences` |
| `this serial was already used` | The serial belongs to another machine. Ask support to move it, or rebind it from the licence page on the site |
| `the licence server could not be reached` | Check the internet, then try again. Nothing is charged and nothing is lost |
| The Expert shows `NO_LEASE` in MetaTrader | Menu → `License → 6` to register the MQL5 folder, then `7` to refresh, then restart MetaTrader |
| The Expert shows `ACTIVE` but the panel still draws nothing | The Expert needs at least one tick of live data; check that the market is open and the chart symbol is subscribed |
| The dashboard says `dashboard login : NOT ACTIVE` | Menu → `License → 1` rebuilds it |
| The browser asks for a password you do not have | Menu → `License → 1` prints both login and password |
| The dashboard starts but its page is empty | MetaTrader is not running, or the Expert is not attached to a chart |
| `error: the licence Agent could not be installed` | The download was blocked. Check the internet / firewall, then repeat `License → 4` |
| Windows blocks the installer | Re-run it with `-ExecutionPolicy Bypass` as shown in step 2 |

---

## 10. Renew, move, uninstall

* **Renew** - buy the same plan again for the same licence on the site, then
  `License → 7) Refresh the licence now`. The dashboard login follows
  automatically.
* **Move to another computer** - `License → 11` on the old machine, then activate
  the same serial on the new one (or ask support to rebind it).
* **Remove everything** - `8) Uninstall everything`. To keep the licence files,
  remove only the dashboard with `6) Remove auto-start service` and `3) Stop
  dashboard`.

Support: <https://github.com/MAPSIM-co/Mapsim_Assistance_Bot/issues> · Telegram
@Tarantula_trade

---

<div dir="rtl">

# از اینجا شروع کنید — Mapsim Assistance Bot، اجرای اول

**این صفحه کل مسیر است، از اول تا آخر.** یک بار آن را انجام دهید تا هر دو بخش
محصول روی رایانه شما اجرا شود:

* **اکسپرت** (`Mapsim_Assistance_Bot.ex5`) داخل متاتریدر ۵، و
* **داشبورد** (پنل زنده در مرورگر).

> **یک لایسنس، دو برنامه.** سریالی که از سایت می‌خرید هم اکسپرت را باز می‌کند و
> هم داشبورد را. لایسنس دوم برای داشبورد وجود ندارد و چیزی را دو بار وارد
> نمی‌کنید.

همه کارها با یک دستور انجام می‌شود: **`Mapsim_BOT`** — همان مرکز کنترلی که این
مخزن نصب می‌کند.

---

## ۱. چه چیزی لازم است

| | ویندوز | مک / لینوکس |
|---|---|---|
| سیستم | ویندوز ۱۰ یا ۱۱ نسخه ۶۴ بیتی | مک ۱۲ به بالا یا لینوکس ۶۴ بیتی |
| ترمینال | متاتریدر ۵ (۶۴ بیتی، بیلد ۳۰۰۰ یا جدیدتر) | متاتریدر ۵ برای مک / واین |
| اینترنت | برای نصب، لایسنس و بروزرسانی لازم است | همین طور |
| زمان | حدود ۱۵ دقیقه، به‌علاوه زمان تأیید پرداخت | همین طور |

به پایتون، دیتابیس یا چیز دیگری نیاز ندارید؛ مرکز کنترل هر چه لازم باشد خودش
دانلود می‌کند.

---

## ۲. نصب مرکز کنترل

در ترمینال **یک خط** دستور را اجرا کنید.

**ویندوز** (پاورشل: کلید `Win` را بزنید، بنویسید `PowerShell` و اینتر):

```powershell
irm https://raw.githubusercontent.com/MAPSIM-co/Mapsim_Assistance_Bot/main/Dashboard_Release/install.ps1 | iex
```

**مک / لینوکس** (Terminal):

```sh
curl -fsSL https://raw.githubusercontent.com/MAPSIM-co/Mapsim_Assistance_Bot/main/Dashboard_Release/install.sh | sh
```

نصب‌کننده مرکز کنترل را دانلود می‌کند، دستور `Mapsim_BOT` را روی سیستم می‌گذارد،
داشبورد را نصب می‌کند و منو را باز می‌کند. از این پس دیگر نصب‌کننده را اجرا
نمی‌کنید؛ فقط:

```
Mapsim_BOT
```

> اگر ویندوز پیام *«running scripts is disabled»* داد، همان نصب‌کننده را با این
> دستور اجرا کنید:
> `powershell -ExecutionPolicy Bypass -Command "irm https://raw.githubusercontent.com/MAPSIM-co/Mapsim_Assistance_Bot/main/Dashboard_Release/install.ps1 | iex"`

منو دوزبانه است؛ با کلید **L** بین انگلیسی و فارسی جابه‌جا شوید.

---

## ۳. نصب اکسپرت در متاتریدر ۵

در منو گزینه **`9) Expert Advisor: install / update`** را بزنید (در هر دو سیستم
شماره ۹ است). منو می‌پرسد کدام پوشه متاتریدر را استفاده کند؛ اگر چند ترمینال
دارید، فهرست نشان داده می‌شود و با `a` هر سه نصب می‌شوند. اکسپرت، کتابخانه
SQLite و صداها کپی می‌شوند و نسخه نصب‌شده نمایش داده می‌شود.

سپس در متاتریدر ۵:

1. **متاتریدر را ری‌استارت کنید** تا فایل‌های جدید را ببیند.
2. یک چارت **M15** از نمادی که معامله می‌کنید باز کنید.
3. اکسپرت **Mapsim Assistance Bot** را از Navigator روی چارت بکشید.
4. در پنجره تنظیمات، تب **Common**، دو گزینه را تیک بزنید:
   * *Allow DLL imports*
   * *Allow algorithmic trading*
5. OK بزنید و مطمئن شوید دکمه **Algo Trading** در نوار ابزار سبز است.

تا مرحله ۵، اکسپرت پیام «بدون لایسنس» می‌دهد؛ این طبیعی است.

---

## ۴. خرید لایسنس از سایت

به **<https://shop.mapsim.shop>** بروید و چهار صفحه را طی کنید:

1. **ثبت‌نام** (`/signup`) با ایمیل، نام کاربری و رمز.
2. **کیف پول** (`/app/wallet`) — **USDT** واریز کنید: شبکه را انتخاب کنید
   (**TRC20**، **ERC20** یا **BEP20**)، مبلغ را به آدرس داده‌شده بفرستید و
   **شناسه تراکنش** را وارد کنید. اپراتور تأیید می‌کند و موجودی در کیف پول
   می‌نشیند.
3. **پلن‌ها** (`/plans`) — پلن مورد نظر را انتخاب و از موجودی کیف پول پرداخت کنید.
4. **لایسنس‌ها** (`/app/licences`) — **سریال** همان لحظه ساخته می‌شود. دکمه
   **Reveal** را بزنید. هر Reveal ثبت می‌شود، پس مثل رمز با آن رفتار کنید.

| پلن | قیمت | مدت | تعداد دستگاه |
|---|---|---|---|
| Assist یک ماهه | ۴۹ USDT | ۳۰ روز | ۱ |
| Assist سه ماهه | ۱۲۹ USDT | ۹۰ روز | ۱ |
| Assist دوازده ماهه | ۳۹۹ USDT | ۳۶۵ روز | ۲ |
| Assist دوازده ماهه (کلید سخت‌افزاری) | ۷۴۹ USDT | ۳۶۵ روز | ۱ |

قیمت و موجودی همیشه همان است که در `/plans` نمایش داده می‌شود.

سریال به شکل `MAPSIM-XXXX-XXXX-XXXX-XXXX` است. صفحه را باز نگه دارید؛ در مرحله
بعد لازم می‌شود.

---

## ۵. فعال‌سازی سریال (یک سریال، هر دو برنامه)

دوباره در منوی **`Mapsim_BOT`**:

* **ویندوز:** `12) License (one serial: Expert + dashboard)`
* **مک / لینوکس:** `13) License (one serial: Expert + dashboard)`

سپس **`4) Activate the Expert with a serial`** را بزنید و سریال را بچسبانید. منو:

1. پوشه متاتریدر را ثبت می‌کند تا اکسپرت لایسنس را ببیند،
2. با سرور لایسنس ارتباط می‌گیرد و سریال را به **همین** دستگاه می‌بندد،
3. لایسنس را جایی می‌نویسد که اکسپرت می‌خواند،
4. **ورود داشبورد را از همان لایسنس می‌سازد** و نشان می‌دهد:

```
the dashboard login was prepared from your Expert licence:
  login    : ................................
  password : ................................
  account  : 12345678
  valid to : 2027.01.15 14:30
```

**login** و **password** را یادداشت کنید؛ هر وقت لازم شد از مسیر
`License → 1) Build / refresh the dashboard login now` دوباره نمایش داده می‌شوند.
هر دو مقدار یک رشته‌اند و مرورگر همان را می‌خواهد.

---

## ۶. اجرای اکسپرت

در متاتریدر ۵ روی همان چارت:

* پنل اکسپرت باید **ACTIVE** و روزهای باقی‌مانده را نشان دهد؛
* اگر هنوز «بدون لایسنس» است: منوی چارت → **Expert Advisors** → **Properties**،
  تیک *Allow DLL imports* را بزنید، سپس راست‌کلیک روی چارت →
  **Expert Advisors → Restart**.

کار دیگری لازم نیست؛ لایسنس هر چند ساعت خودش تازه می‌شود
(`License → 10` این را روشن/خاموش می‌کند).

---

## ۷. باز کردن داشبورد

در منو **`2) Start dashboard`** را بزنید. اولین اجرا ورود را از لایسنس شما
می‌سازد، پس هیچ لایسنس دومی وارد نمی‌کنید.

مرورگر روی **<http://127.0.0.1:8765>** باز می‌شود. اگر نام کاربری و رمز خواست،
همان **ورود داشبورد** مرحله ۵ را در هر دو کادر بگذارید.

داشبورد داده زنده اکسپرت را می‌خواند. تا زمانی که متاتریدر با اکسپرت روی چارت
اجرا نشده و اولین snapshot را ننوشته، صفحه خالی است؛ این خطا نیست.

---

## ۸. از این پس

فقط دو چیز لازم دارید: `Mapsim_BOT` برای مدیریت محصول، و متاتریدر ۵ با اکسپرت
روی چارت.

منوی اصلی ویندوز:

| # | گزینه |
|---|---|
| ۱ | وضعیت |
| ۲ | اجرای داشبورد |
| ۳ | توقف داشبورد |
| ۴ | نصب / بروزرسانی داشبورد |
| ۵ | مدیریت سرویس (اجرا/توقف/ری‌استارت/فعال/غیرفعال) |
| ۶ | حذف سرویس اجرای خودکار |
| ۷ | حالت دسترسی (محلی / اینترنت) |
| ۸ | حذف کامل |
| ۹ | اکسپرت: نصب / بروزرسانی |
| ۱۰ | اکسپرت: بررسی نسخه |
| ۱۱ | فضای دیسک |
| ۱۲ | لایسنس (یک سریال: اکسپرت + داشبورد) |
| ۱۳ | روش بروزرسانی (اطلاع / خودکار / خاموش) |
| ۱۴ | خروج |
| L | زبان: انگلیسی / فارسی |

در مک و لینوکس یک گزینه اضافه در میانه فهرست هست (`12) Snapshot file / data
source`)، پس **License شماره ۱۳** و **Exit شماره ۱۵** است؛ بقیه شماره‌ها یکی است.

داخل **License**:

| # | گزینه | کاربرد |
|---|---|---|
| ۱ | ساخت / بازسازی ورود داشبورد | وقتی دوباره به ورود مرورگر نیاز دارید |
| ۲ | وضعیت ورود داشبورد | آیا هنوز معتبر است؟ |
| ۳ | حذف ورود ذخیره‌شده داشبورد | در اجرای بعدی خودکار ساخته می‌شود |
| ۴ | فعال‌سازی اکسپرت با سریال | بار اول یا سریال جدید |
| ۵ | وضعیت لایسنس اکسپرت | آنچه اکسپرت می‌بیند |
| ۶ | ثبت پوشه متاتریدر | جابه‌جایی متاتریدر یا ترمینال دوم |
| ۷ | بازسازی لایسنس | بعد از تمدید |
| ۸ | بررسی محلی لایسنس | آیا این دستگاه هنوز مجاز است؟ |
| ۹ | شناسه دستگاه | انتقال لایسنس با پشتیبانی |
| ۱۰ | بروزرسانی خودکار روشن/خاموش | به‌ندرت |
| ۱۱ | حذف لایسنس از این دستگاه | رفتن به رایانه جدید |
| ۱۲ | ورود لایسنس قدیمی داشبورد | فقط اگر پشتیبانی فرستاده باشد |

---

## ۹. رفع اشکال

| چه می‌بینید | چه کار کنید |
|---|---|
| `that serial is not valid` | سریال اشتباه یا منقضی است. از `shop.mapsim.shop → /app/licences` دوباره کپی کنید |
| `this serial was already used` | سریال به دستگاه دیگری بسته است. از پشتیبانی بخواهید منتقل کند یا در صفحه لایسنس rebind کنید |
| `the licence server could not be reached` | اینترنت را بررسی و دوباره تلاش کنید؛ نه پولی کم می‌شود نه چیزی از دست می‌رود |
| اکسپرت `NO_LEASE` نشان می‌دهد | منو → `License → 6` برای ثبت پوشه MQL5، سپس `7` برای بازسازی، سپس ری‌استارت متاتریدر |
| اکسپرت `ACTIVE` است ولی پنل چیزی نمی‌کشد | اکسپرت به تیک زنده نیاز دارد؛ بازار باز باشد و نماد چارت مشترک باشد |
| داشبورد `dashboard login : NOT ACTIVE` | منو → `License → 1` آن را بازسازی می‌کند |
| مرورگر رمزی می‌خواهد که ندارید | منو → `License → 1` هر دو مقدار را نشان می‌دهد |
| داشبورد بالا می‌آید ولی صفحه خالی است | متاتریدر اجرا نیست یا اکسپرت روی چارت نیست |
| `error: the licence Agent could not be installed` | دانلود بلاک شده. اینترنت/فایروال را بررسی و `License → 4` را تکرار کنید |
| ویندوز نصب‌کننده را بلاک می‌کند | با `-ExecutionPolicy Bypass` مطابق مرحله ۲ اجرا کنید |

---

## ۱۰. تمدید، انتقال، حذف

* **تمدید** — همان پلن را برای همان لایسنس دوباره بخرید، سپس
  `License → 7) Refresh the licence now`. ورود داشبورد خودش بروز می‌شود.
* **انتقال به رایانه دیگر** — روی دستگاه قدیمی `License → 11`، سپس همان سریال
  روی دستگاه جدید (یا از پشتیبانی بخواهید rebind کند).
* **حذف کامل** — `8) Uninstall everything`. اگر می‌خواهید فایل‌های لایسنس بمانند،
  فقط با `6` و `3` داشبورد را بردارید.

پشتیبانی: <https://github.com/MAPSIM-co/Mapsim_Assistance_Bot/issues> ·
تلگرام @Tarantula_trade

</div>
