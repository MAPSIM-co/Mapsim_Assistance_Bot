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
| `install.sh` | One-line installer for macOS and Linux (latest release, checksum-verified) |
| `install.ps1` | One-line installer for Windows 10/11 (latest release, checksum-verified) |
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

The installer detects your system, downloads the latest `dashboard-v*` release,
verifies its SHA-256 checksum, installs it for the current user and starts it:

| System | Installed to |
|---|---|
| macOS | `~/Applications/MapsimDashboard.app` |
| Linux | `~/.local/share/MapsimDashboard` (plus a `mapsim-dashboard` command and app-menu entry) |
| Windows | `%LOCALAPPDATA%\MapsimDashboard` (plus a Desktop shortcut) |

No Python installation is required. To install without starting the app, run
`install.sh --no-launch` (or `install.ps1 -NoLaunch`); to install a specific
release, pass `--version=dashboard-vX.Y.Z` (or set `MAPSIM_DASHBOARD_VERSION`).

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

```bash
# macOS
python smoke_test.py --artifact dist/MapsimDashboard.app

# Windows
python smoke_test.py --artifact dist/MapsimDashboard.exe

# Linux
python smoke_test.py --artifact dist/MapsimDashboard
```

The smoke test starts the app in demo mode on a free port, waits for
`/api/snapshot`, fetches the bundled page, stylesheet, script and logo, then
stops the whole process tree and confirms the port was released.

### What is bundled

Only these files are copied into the build:

- `live_dashboard.py`, `market_engine.py`, `mock_feed.py`, `news_feed.py`
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
