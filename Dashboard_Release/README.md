# Mapsim Live Dashboard — Desktop Release

Packaging and release automation for the **Mapsim Live Dashboard**, a read-only
desktop dashboard for MetaTrader 5 accounts.

The dashboard source code is **not** published in this repository. Ready-to-run
builds are attached to the repository's **Releases** page; everything here is
either the tooling that produces those builds or instructions for using them.

> The dashboard is read-only. It never sends orders and never writes to
> MetaTrader 5 or to the Expert Advisor.

---

## Contents

| Path | Purpose |
|---|---|
| `install.sh` | One-line bootstrap for macOS and Linux (downloads the control center) |
| `install.ps1` | One-line bootstrap for Windows 10/11 |
| `mapsim-menu.sh` | Mapsim BOT control center for macOS/Linux (all real logic) |
| `mapsim-menu.ps1` | Mapsim BOT control center for Windows (all real logic) |
| `build.py` | Copies a whitelist of dashboard files and packages them with PyInstaller |
| `entry.py` | Frozen-app entry point (safe logging in windowed builds) |
| `smoke_test.py` | Launches a built app on a free port and verifies the API and assets |
| `requirements-build.txt` | Build-time Python dependencies |
| `.github/workflows/dashboard-build.yml` (repository root) | Four-runner CI matrix and tagged GitHub releases |

---

## One-command install (recommended)

**macOS and Linux** — paste in Terminal:

```sh
curl -fsSL https://raw.githubusercontent.com/MAPSIM-co/Mapsim_Assistance_Bot/main/Dashboard_Release/install.sh | sh
```

**Windows 10/11 (64-bit)** — paste in PowerShell:

```powershell
irm https://raw.githubusercontent.com/MAPSIM-co/Mapsim_Assistance_Bot/main/Dashboard_Release/install.ps1 | iex
```

The bootstrap detects your system, downloads the latest `dashboard-v*` release,
verifies its SHA-256 checksum, installs it for the current user and starts it
in local mode. From then on everything is managed through one command:

```sh
Mapsim_BOT          # macOS / Linux
```

```powershell
Mapsim_BOT.cmd      # Windows (on the Desktop shortcut or in %LOCALAPPDATA%\MapsimDashboard)
```

On macOS and Linux the `Mapsim_BOT` command is always placed in
`~/.local/bin`, and the installer adds that folder to `PATH` in your shell
startup files (`~/.profile`, `~/.bashrc`, `~/.zprofile`, `~/.zshrc`, whichever
exist). It never needs `sudo` and never overwrites your shell configuration —
the block is added once and removed again on uninstall. If the terminal that
ran the installer still says `Mapsim_BOT: command not found`, either open a new
terminal or run:

```sh
export PATH="$HOME/.local/bin:$PATH"
```

## Mapsim BOT control center

`Mapsim_BOT` opens an interactive menu that asks only when a decision is
needed and does everything else by itself (port checks, license check, service
setup):

```
     ██   ██  █████  ██████   ██████ ███████ ██   ██   █████   █████  ███████
     ███ ███ ██   ██ ██   ██ ██      ██      ███ ███  ██   ██ ██   ██   ███
     ██ █ ██ ███████ ██████   █████  ███████ ██ █ ██  ██████  ██   ██   ███
     ██   ██ ██   ██ ██           ██ ██      ██   ██  ██   ██ ██   ██   ███
     ██   ██ ██   ██ ██      ██████  ███████ ██   ██  ██████   █████    ███

┌───────────────────────────────────────────────────────────────────────────────┐
│  Dashboard : running (pid 4242)                                               │
│  App       : installed                                                        │
│  Expert    : v213.1.6                                                         │
│  License   : saved                                                            │
│  Access    : internet (0.0.0.0) - port 8766                                   │
│  URL       : http://203.0.113.10:8766/                                        │
│  Snapshot  : ok (12s ago)                                                     │
│  Disk      : 42.3 GB free of 80 GB (47% used)                                 │
├───────────────────────────────────────────────────────────────────────────────┤
│    1 - Status                                                                 │
│    2 - Start dashboard                                                        │
│  ...                                                                          │
└───────────────────────────────────────────────────────────────────────────────┘
```

The panel always shows whether the dashboard is running, the installed Expert
version, the access mode/port, the address to open in a browser (server IP in
internet mode, `http://127.0.0.1:...` locally — terminals make it clickable and
you can copy it), whether the live snapshot file is being read
(and how old it is) and free disk space (green below 75% used, yellow
75–89%, red 90% or more).

  1) Status                        - installed? running? which port? service? disk?
  2) Start dashboard               - checks the license first (asks for it when
                                     none is saved), then local only or internet,
                                     checks ports; if the dashboard is already
                                     running it offers to stop it and restart with
                                     the new settings
  3) Stop dashboard                - stops every dashboard process, frees the
                                     port; if the auto-start service is running it
                                     is stopped too (otherwise it would restart it)
  4) Install / update dashboard    - downloads the newest release, checksum-checked
  5) Service management            - submenu: status, install + enable, start,
                                     stop, restart, enable at boot/login, disable
                                     at boot/login (systemd / LaunchAgent /
                                     scheduled task)
  6) Remove auto-start service     - uninstalls the service/task, keeps the app
  7) Access mode (local / internet)- switch the bind address and restart; the
                                     dashboard login is always the license
  8) Uninstall everything          - full removal, asks for confirmation first
  9) Expert Advisor: install/update- downloads the newest EA from the newest v*
                                     release tag, copies it (OS-matched .ex5,
                                     Include, Libraries, Sounds) into the detected
                                     MetaTrader 5 MQL5 folder(s)
 10) Expert Advisor: version check - shows installed vs latest, offers the update
 11) Disk space / server storage   - all filesystems, dashboard folder sizes,
                                     free space and the dashboard log sizes
 12) Snapshot file / data source   - shows the snapshot the dashboard reads,
                                     auto-detects it in every Wine prefix, or lets
                                     you type a path. You can enter the file itself,
                                     the MQL5 folder, the MT5 folder in native form
                                     (`/home/user/mt5/drive_c/Program Files/MetaTrader 5`)
                                     or Windows form (`C:\Program Files\MetaTrader 5`);
                                     `C:` and other drive letters are mapped to the
                                     detected Wine prefix and `MQL5/Files/MapsimLive/
                                     snapshot.json` is derived from it
 13) License (dashboard login)     - enter or update the Mapsim license (license
                                     code + username + password), show its status
                                     (user, account, expiry, days left) or remove
                                     it. The dashboard only starts with a valid,
                                     unexpired license and uses the same username
                                     and password for the web sign-in
 14) Exit

The Windows menu (`mapsim-menu.ps1`) has no separate snapshot item, so the
numbering there shifts up by one: **12) License (dashboard login)** and
**13) Exit**. Every other option number is the same on all platforms.

Inside any of these options, type **0** (or `b` / `back` / `q`) at a prompt to
leave it and return to the main menu. Nothing is changed when you do that — the
running dashboard, the saved settings and MetaTrader 5 stay untouched. This
works for the folder, port, license and path prompts and for every yes/no
question.

### Service submenu (menu 5)

The auto-start service/task is managed in one place; **Remove auto-start
service** stays as menu 6 on purpose.

  1) Status / details              - installed? enabled? running? pid, port, URL
                                     and where the logs are
  2) Install and enable            - writes the unit/task and starts the dashboard
                                     now; it also starts at every boot/login
  3) Start now                     - start through systemd / launchd / the task
  4) Stop now                      - stop now, keep it installed and enabled
                                     (it comes back at the next boot/login)
  5) Restart now                   - restart through the service manager
  6) Enable at boot/login          - `systemctl enable`, `launchctl enable`,
                                     `Enable-ScheduledTask`
  7) Disable at boot/login         - `systemctl disable`, `launchctl disable`,
                                     `Disable-ScheduledTask`; a running dashboard
                                     keeps running until you stop it

Starting the dashboard manually (menu 2) while the service is enabled prints a
note, because the service would start a second copy at the next login; stopping
it from menu 3 stops the service too so nothing restarts behind your back.
Installing, starting and restarting through the service check the license too —
without a valid license the service is not started.

### License

The dashboard runs on the **same license as the Expert Advisor**. Enter it once
in menu **13**: paste the license code, then the license username and password
(typed hidden). The values are validated like the EA does — username, password,
active code, expiry date and the account number read from the live snapshot —
and are only saved when the license is active. They are stored in
`~/.mapsim/dashboard.license` and `~/.mapsim/dashboard.auth`
(`%USERPROFILE%\.mapsim\...` on Windows), readable only by your account.

- No license, an expired license, a wrong username/password or another account
  in the snapshot → the dashboard is **not started**.
- If the license expires while the dashboard is running, it shuts itself down.
- The web sign-in (local and internet) is the license username and password.
- If the snapshot is not there yet, the dashboard starts with a warning and
  enforces the account number as soon as the snapshot appears.

### Snapshot / data source

The dashboard only reads files — it never writes to MetaTrader. It looks for
`MQL5/Files/MapsimLive/snapshot.json` in every Wine prefix it can find
(`~/.wine/drive_c`, `~/<prefix>/drive_c`, the Flatpak prefix and the macOS MT5
container) and uses the newest file.
If your MT5 lives somewhere unusual, open menu **12**, pick option 2 and type
either the snapshot file, the MQL5 folder or the MT5 folder — Windows-style
paths such as `C:\Program Files\MetaTrader 5` are understood and translated
into the right `drive_c` folder. The chosen path is stored in
`~/.config/mapsim-dashboard/mapsim-dashboard.env` as `MAPSIM_SNAPSHOT` and
passed to the dashboard at every start; option 3 clears it again so the
dashboard searches by itself.

### Expert Advisor management

Menu 9 detects the MetaTrader 5 data folder(s) automatically
(`~/.../net.metaquotes.wine.metatrader5/drive_c/**/MQL5` on macOS,
`~/.wine/drive_c/**/MQL5` on Linux, `%APPDATA%\MetaQuotes\Terminal\<id>\MQL5` on
Windows), downloads the newest `v*` release of this repository, and copies:

- the Expert `.ex5` that matches your operating system → `MQL5/Experts/`
- `Mapsim_Assistance_Bot_lnclude.zip` (extracted) → `MQL5/Include/`
- `sqlite3.dll` → `MQL5/Libraries/`
- alert sounds → `MQL5/Files/Mapsim_Assistance_Bot/Sounds/`

If several MT5 instances are found you can pick one or apply to all. After the
copy it reminds you to restart MT5, allow DLL imports and enter your license.
Menu 10 compares the installed version (recorded in
`~/.config/mapsim-dashboard/ea-state.env` / `%APPDATA%\MapsimDashboard\ea-state.env`)
with the newest `v*` tag and offers to update. Uninstalling the dashboard never
touches the Expert files inside MetaTrader 5.

The installer flags still work when the installer file is run directly
(download it first), and map to the same actions:

| Option | macOS/Linux | Windows | Effect |
|---|---|---|---|
| `--public` / `-Public` | ✓ | ✓ | install with internet access (sign in with the license) |
| `--service` / `-Service` | ✓ | ✓ | also enable auto-start after every reboot |
| `--remove-service` / `-RemoveService` | ✓ | ✓ | remove the auto-start service (keeps the app) |
| `--uninstall` / `-Uninstall` | ✓ | ✓ | remove the dashboard completely |
| `--no-launch` / `-NoLaunch` | ✓ | ✓ | install only, do not start the app |
| `--version=…` / `-Version` | ✓ | ✓ | install a specific release |

| System | Installed to |
|---|---|
| macOS | `~/Applications/MapsimDashboard.app` |
| Linux | `~/.local/share/MapsimDashboard` (plus `mapsim-dashboard` / `Mapsim_BOT` commands and an app-menu entry) |
| Windows | `%LOCALAPPDATA%\MapsimDashboard` (plus a `Mapsim_BOT` Desktop shortcut) |

No Python installation is required.

---

## Access the dashboard from the internet

By default the dashboard listens on `127.0.0.1` and can only be opened on the
same computer. To watch it from other machines (your phone, another computer,
the office), run it with **public mode**: it binds to `0.0.0.0` and asks for
the license username and password on every request (the same credentials you
entered in menu 13). The easiest way is the control center: run `Mapsim_BOT`,
choose **7) Access mode (local / internet)** (or start with menu 2 and pick
"internet") — it checks the license and the port and restarts the dashboard for
you. For scripted installs:

```sh
# macOS / Linux (install + start, public)
sh install.sh --public

# or, for an installed dashboard (the license is read from ~/.mapsim):
mapsim-dashboard --bind 0.0.0.0 --no-browser
```

```powershell
# Windows (install + start, public)
.\install.ps1 -Public
```

After that, open `http://<machine-ip>:8765/` from any device and sign in with
the license username and password. They are stored in
`~/.mapsim/dashboard.license` and `~/.mapsim/dashboard.auth`
(`%USERPROFILE%\.mapsim\...` on Windows), readable only by your account.

> Security notes
> - The app requires a valid license before it starts, and the web login is the
>   license username and password — there is no separate dashboard password.
> - For anything beyond a trusted LAN, put the dashboard behind **HTTPS**
>   (for example `caddy reverse-proxy --from https://dash.example.com
>   --to 127.0.0.1:8765`) or an **SSH tunnel** / VPN, because the sign-in
>   travels unencrypted over plain HTTP.
> - On Linux you may need to open the port, e.g. `sudo ufw allow 8765/tcp`.
> - On Windows the installer adds a firewall rule when it can; otherwise run
>   PowerShell as Administrator once.

---

## Run at startup (background service)

To have the dashboard start automatically after every reboot:

```sh
sh install.sh --service        # macOS/Linux (add --public if it must also be reachable remotely)
```

```powershell
.\install.ps1 -Service         # Windows: scheduled task that starts at logon
```

This installs:
- **Linux** — a systemd service (`systemctl status mapsim-dashboard`) that
  starts at boot. Run as root for a system-wide service; otherwise it becomes
  a user service that survives logout (`loginctl enable-linger`).
- **macOS** — a per-user LaunchAgent that starts at login and restarts the app
  only if it crashes (`launchctl list | grep mapsim`).
- **Windows** — a scheduled task `MapsimDashboard` that starts at logon and
  restarts on failure (`Get-ScheduledTask MapsimDashboard`).

Restarts are capped on every operating system (systemd `StartLimitBurst`,
launchd `ThrottleInterval`, task `RestartCount 3`), so a broken install cannot
spin forever in the background. After installing, `Mapsim_BOT` → **5) Service
management** has start / stop / restart / enable / disable / status; **6) Remove
auto-start service** uninstalls it.

When you stop the dashboard (menu 3, `Mapsim_BOT --stop`), the menu stops every
process of the packaged app — PyInstaller onefile runs a parent and a child, and
killing only one leaves the other holding the port — and also stops the service
when it is enabled, so nothing restarts behind your back. An update restarts the
service afterwards with the new version.

### Background processes and logs

- The dashboard runs as one process tree. `Mapsim_BOT --status` shows the PID,
  port and URL; `Mapsim_BOT --stop` stops the whole tree and verifies the port
  was released.
- Only startup and error lines are logged (HTTP access lines are off in the
  dashboard itself). `dashboard.log` is capped: past 256 KB the newest 200
  lines are kept, and the same rule applies to the app's own windowed-build log.
  Nothing grows without bound.
- Service output goes to the service manager (systemd journal, `journalctl
  --user -u mapsim-dashboard`) or to the same capped `dashboard.log` on macOS,
  so access logs never fill the disk.


To remove the service (the app stays installed):

```sh
sh install.sh --remove-service
```

```powershell
.\install.ps1 -RemoveService
```

---

## Remove everything (uninstall)

To stop the dashboard and delete every file it installed:

```sh
sh install.sh --uninstall      # macOS/Linux
```

```powershell
.\install.ps1 -Uninstall       # Windows
```

This removes the app, the auto-start service/task, the `mapsim-dashboard` and
`Mapsim_BOT` commands, the `PATH` line the installer added to your shell startup
files, the desktop shortcut / app-menu entry, the saved license (`~/.mapsim`)
and the log folder. Nothing is left behind and MetaTrader 5 / the Expert
Advisor are never touched. Manual equivalent:

- **macOS** — quit the app, then delete `~/Applications/MapsimDashboard.app`
  and `~/Library/Application Support/MapsimDashboard`; remove
  `~/.local/bin/mapsim-dashboard` and `~/.local/bin/Mapsim_BOT`, and the
  `# Mapsim BOT: put ~/.local/bin on PATH` block from your shell startup file;
  if a service was installed also delete `~/Library/LaunchAgents/com.mapsim.dashboard.plist`
  and run `launchctl bootout gui/$UID ~/Library/LaunchAgents/com.mapsim.dashboard.plist`.
- **Linux** — `pkill -f MapsimDashboard`, then delete `~/.local/share/MapsimDashboard`,
  `~/.local/bin/mapsim-dashboard`, `~/.local/bin/Mapsim_BOT`,
  `~/.local/share/applications/mapsim-dashboard.desktop` and
  `~/.config/mapsim-dashboard`, and remove the
  `# Mapsim BOT: put ~/.local/bin on PATH` block from your shell startup file;
  if a root service was installed also run
  `sudo systemctl disable --now mapsim-dashboard.service` and delete
  `/etc/systemd/system/mapsim-dashboard.service`.
- **Windows** — end `MapsimDashboard.exe` in Task Manager, then delete
  `%LOCALAPPDATA%\MapsimDashboard`, `%APPDATA%\MapsimDashboard` and the
  `Mapsim Live Dashboard` shortcut; if a service was installed also run
  `Unregister-ScheduledTask -TaskName MapsimDashboard -Confirm:$false`.

---

## Run the app (end users)

You can use the one-command installer above, or install manually:

1. Open the **Releases** page of this repository and download the archive for
   your system:

   | System | Asset |
   |---|---|
   | macOS (Apple Silicon) | `MapsimDashboard-macos-arm64.zip` |
   | macOS (Intel) | `MapsimDashboard-macos-x64.zip` |
   | Windows x64 | `MapsimDashboard-windows-x64.zip` |
   | Linux x64 | `MapsimDashboard-linux-x64.tar.gz` |

2. Unpack and start the app:
   - **macOS** — open `MapsimDashboard.app`. If macOS blocks it, right-click the
     app and choose **Open**.
   - **Windows** — run `MapsimDashboard.exe`. If SmartScreen appears, choose
     **More info → Run anyway**.
   - **Linux** — `chmod +x MapsimDashboard` once, then run it.

The dashboard opens in your browser at `http://127.0.0.1:8765/`. If that port is
busy, start it from a terminal with `--port 8799` (or any free port).

Each release ships a `.sha256` checksum file next to the archive. Verify it
before running a downloaded build.

### Where the data comes from

The app only reads data. It accepts a snapshot from any of these sources:

1. **Local MetaTrader 5 — detected automatically.** The dashboard scans the
   default MT5 data folders for `MapsimLive/snapshot.json`:
   - Windows: `%APPDATA%\MetaQuotes\Terminal\<instance>\MQL5\Files\MapsimLive\snapshot.json`
     for every installed terminal, plus portable installs under
     `%ProgramFiles%\MetaTrader 5\MQL5\Files`
   - macOS: `~/Library/Application Support/net.metaquotes.wine.metatrader5/drive_c/Program Files/MetaTrader 5/MQL5/Files/MapsimLive/snapshot.json`
   - Linux (Wine): `~/.wine/drive_c/Program Files/MetaTrader 5/MQL5/Files/MapsimLive/snapshot.json`

   When several terminals or snapshots exist, the newest file wins. The path is
   resolved once at startup: with a single MT5 data folder the dashboard picks
   up the snapshot as soon as the EA writes it, even if MT5 was started after
   the app. With several terminals, start MT5 first and restart the app if the
   wrong snapshot was chosen. If MT5 uses a custom data folder, use one of the
   options below instead.
2. **Snapshot file** — `--file /path/to/snapshot.json` or the
   `MAPSIM_SNAPSHOT` environment variable.
3. **User data folder** — if started with no arguments and a `snapshot.json`
   exists in the per-user folder below, it is used automatically:
   - macOS: `~/Library/Application Support/MapsimDashboard/snapshot.json`
   - Windows: `%APPDATA%\MapsimDashboard\snapshot.json`
   - Linux: `~/.local/share/MapsimDashboard/snapshot.json`
4. **Link tab** — connect over SFTP from inside the dashboard. The password is
   kept in memory only and is never returned by the local API or written to
   logs.

If no data is available, the UI opens in a waiting state. Simulated data is
never shown automatically.

### Logs

Fatal startup errors and redirected output in windowed builds are written to
`dashboard.log` in the same per-user folder.

---

## Build locally (maintainers)

You need Python 3.9–3.13 and local access to the private dashboard source
folder. The source is never modified.

```bash
cd Dashboard_Release

python3 -m venv .venv
source .venv/bin/activate          # Windows: .venv\Scripts\activate
python -m pip install --upgrade pip
python -m pip install -r requirements-build.txt

python build.py --source /absolute/path/to/dashboard-source --out dist
```

Outputs:

| System | Artifact |
|---|---|
| macOS | `dist/MapsimDashboard.app` |
| Windows | `dist/MapsimDashboard.exe` |
| Linux | `dist/MapsimDashboard` |

`dist/SHA256SUMS` contains the checksum of the executable.

### Verify the build

The dashboard needs a valid license even in demo mode, so the smoke test takes
a license and the matching username/password:

```bash
# macOS
python smoke_test.py --artifact dist/MapsimDashboard.app \
  --license-file path/to/test.license --auth-file path/to/test.auth

# Windows
python smoke_test.py --artifact dist/MapsimDashboard.exe \
  --license-file path\to\test.license --auth-file path\to\test.auth

# Linux
python smoke_test.py --artifact dist/MapsimDashboard \
  --license-file path/to/test.license --auth-file path/to/test.auth
```

`test.auth` holds the license username on the first line and its password on
the second. The smoke test starts the app in demo mode on a free port, signs in
with those credentials, waits for `/api/snapshot`, fetches the bundled page,
stylesheet, script and logo, then stops the whole process tree and confirms the
port was released. The CI workflow creates a short-lived (2-day) license from
`license_gate` in the private source before this step and deletes it
afterwards; nothing is committed and nothing is attached to the release.

### What is bundled

Only these files are copied into the build:

- `live_dashboard.py`, `license_gate.py`, `market_engine.py`, `mock_feed.py`,
  `news_feed.py`
- `web/` (the UI)
- `Logo/` (logo and icon)
- `runtime/candles_sampled.json` (sample candles for the Market tab)

These are rejected and never copied:

- `sftp.evd` and any `*.evd`, `*.p12`, `*.pfx`, `*.key`, `*.pem`
- `runtime/snapshot.json` (live account data)
- `backup_*` folders, `.env`, `.DS_Store`, live logs

### Safety checks in `build.py`

- The source is only read; staging happens inside `Dashboard_Release/.build`
  and is deleted afterwards.
- SHA-256 hashes of every whitelisted source file are compared before and
  after the build; any difference fails the build.
- The finished artifact is scanned for the password value stored in
  `sftp.evd`; a match fails the build and the value is never printed.
- `PYTHONDONTWRITEBYTECODE=1` prevents even `__pycache__` from appearing next
  to the source.

### `build.py` options

| Option | Purpose |
|---|---|
| `--source` | **Required.** Path to the private dashboard source folder |
| `--out` | Output folder (default `./dist`) |
| `--name` | Artifact name (default `MapsimDashboard`) |
| `--console` | Keep a console window (debugging only) |
| `--icon` | Custom `.png`, `.ico` or `.icns` icon |
| `--keep-stage` | Keep `.build/` for inspection |
| `--skip-secret-scan` | Skip the credential scan (not recommended) |

---

## Automated releases

The workflow builds on four GitHub-hosted runners:

- `macos-latest` (Apple Silicon)
- `macos-15-intel` (Intel)
- `windows-latest` (x64)
- `ubuntu-22.04` (x64)

It runs from **Actions → dashboard-build → Run workflow**, or automatically when
a tag starting with `dashboard-v` is pushed. Other tags in this repository are
not affected.

The workflow file lives at the repository root (`.github/workflows/`) because
GitHub only reads workflows from that location; it operates on the
`Dashboard_Release/` folder.

### Setup

1. Keep the dashboard source in a **private** repository.
2. In this repository, under **Settings → Secrets and variables → Actions**:
   - Variables: `SOURCE_REPO` = `owner/private-source-repo`,
     `SOURCE_SUBPATH` = folder that contains `live_dashboard.py` (optional).
   - Secret: `SOURCE_REPO_TOKEN` = a fine-grained token with read-only
     **Contents** access to that private repository.
3. Push a release tag:

   ```bash
   git tag dashboard-v1.0.0
   git push origin dashboard-v1.0.0
   ```

The release job attaches every archive and its `.sha256` checksum to the GitHub
release. The private source token is used only inside the runner and is never
written to disk or to the release.

If `SOURCE_REPO` is not configured, the build stops with a clear error instead
of producing an incomplete release.

### Optional code signing

Signing is skipped automatically unless the following secrets exist.

| Secret | Purpose |
|---|---|
| `MACOS_CERTIFICATE_P12` | Developer ID certificate (Base64) |
| `MACOS_CERTIFICATE_PASSWORD` | Password for the `.p12` |
| `MACOS_SIGNING_IDENTITY` | e.g. `Developer ID Application: Name (TEAMID)` |
| `APPLE_ID` | Apple ID for notarization |
| `APPLE_TEAM_ID` | Apple Team ID |
| `APPLE_APP_PASSWORD` | App-specific password |
| `WINDOWS_CERTIFICATE_PFX` | Code-signing certificate (Base64) |
| `WINDOWS_CERTIFICATE_PASSWORD` | Password for the `.pfx` |

Never commit certificates, passwords or tokens to the repository.

---

## Security notes

- **Never commit** `sftp.evd`, `*.evd`, `.env`, `snapshot.json`, backups or any
  credential. The release folder's `.gitignore` covers the common cases.
- Binaries are distributed through **Releases**, not committed to the
  repository. The repository should contain only the build tooling.
- PyInstaller protects distribution, not the source itself. Python bytecode and
  frontend assets can be extracted from a frozen app. Use Nuitka/PyArmor or a
  native rewrite if stronger protection is required.
- Do not attach the private source archive to a release.

---

## Troubleshooting

| Problem | Fix |
|---|---|
| `PyInstaller is not installed` | `python -m pip install -r requirements-build.txt` |
| `source folder not found` | Pass the correct absolute path with `--source` |
| App opens but shows no data | Use `--file`, `MAPSIM_SNAPSHOT`, or the Link tab |
| Port already in use | Start again with `--port <free-port>` |
| macOS reports a damaged app | Download the build again; signed/notarized builds are recommended |
| Windows SmartScreen warning | Use a signed build, or **More info → Run anyway** |
| Linux: `Permission denied` | `chmod +x MapsimDashboard` |
| Runtime `certifi` / `paramiko` error | Rebuild with `requirements-build.txt` |

For a failed packaged run, attach the `dashboard.log` file from the per-user
folder. It never contains the SFTP password.

---

## License

See the `LICENSE` file in the repository root.
