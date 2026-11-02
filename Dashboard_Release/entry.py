#!/usr/bin/env python3
"""Frozen-app entry point for the Mapsim dashboard.

The dashboard code is used exactly as-is. This wrapper only:
  * redirects stdout/stderr to a log file in windowed builds (they are None there),
  * logs a fatal traceback instead of dying silently,
  * lets a packaged build read snapshot.json from its per-user data folder
    when the app is started with no arguments.
"""

from __future__ import annotations

import os
import subprocess
import sys
import traceback
from pathlib import Path

APP_NAME = "MapsimDashboard"


def data_dir() -> Path:
    if sys.platform == "darwin":
        return Path.home() / "Library" / "Application Support" / APP_NAME
    if os.name == "nt":
        return Path(os.environ.get("APPDATA") or Path.home()) / APP_NAME
    return Path(os.environ.get("XDG_DATA_HOME") or (Path.home() / ".local" / "share")) / APP_NAME


def safe_streams() -> Path | None:
    if sys.stdout is not None and sys.stderr is not None:
        return None
    log_path = data_dir() / "dashboard.log"
    try:
        log_path.parent.mkdir(parents=True, exist_ok=True)
        stream = log_path.open("a", encoding="utf-8", buffering=1)
    except OSError:
        stream = open(os.devnull, "w", encoding="utf-8")
        log_path = None
    if sys.stdout is None:
        sys.stdout = stream
    if sys.stderr is None:
        sys.stderr = stream
    return log_path


def apply_data_dir_default(argv: list[str]) -> list[str]:
    if len(argv) > 1 or os.environ.get("MAPSIM_SNAPSHOT"):
        return argv
    candidate = data_dir() / "snapshot.json"
    if candidate.is_file():
        return [*argv, "--file", str(candidate)]
    return argv


def notify(message: str) -> None:
    try:
        if os.name == "nt":
            import ctypes

            ctypes.windll.user32.MessageBoxW(0, message, APP_NAME, 0x10)
        elif sys.platform == "darwin":
            safe = message.replace("\\", "\\\\").replace('"', '\\"')
            subprocess.run(
                ["osascript", "-e", f'display alert "{APP_NAME}" message "{safe}" as critical'],
                check=False,
                timeout=20,
            )
        else:
            sys.stderr.write(message + "\n")
    except Exception:
        pass


def run() -> int:
    log_path = safe_streams()
    try:
        from live_dashboard import main as dashboard_main

        sys.argv = apply_data_dir_default(sys.argv)
        return int(dashboard_main() or 0)
    except SystemExit as exc:
        return int(exc.code or 0)
    except KeyboardInterrupt:
        return 0
    except BaseException:
        details = traceback.format_exc()
        sys.stderr.write(details)
        where = f"\n\nLog: {log_path}" if log_path else ""
        notify(f"The dashboard could not start.\n\n{details.strip().splitlines()[-1]}{where}")
        return 1


if __name__ == "__main__":
    raise SystemExit(run())
