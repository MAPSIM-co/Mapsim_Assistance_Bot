#!/usr/bin/env python3
"""Start a built dashboard in demo mode on a free port and verify /api/snapshot."""

from __future__ import annotations

import argparse
import json
import os
import signal
import socket
import subprocess
import sys
import time
import urllib.request
from pathlib import Path


def resolve_executable(artifact: Path) -> Path:
    if artifact.is_dir() and artifact.suffix == ".app":
        executable = artifact / "Contents" / "MacOS" / artifact.stem
        if executable.is_file():
            return executable
    if artifact.is_file():
        return artifact
    raise SystemExit(f"artifact not found: {artifact}")


def free_port() -> int:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.bind(("127.0.0.1", 0))
        return int(sock.getsockname()[1])


def fetch(url: str, limit: int = 400_000) -> bytes:
    with urllib.request.urlopen(url, timeout=5) as response:
        if response.status != 200:
            raise RuntimeError(f"{url} returned HTTP {response.status}")
        return response.read(limit)


def check_assets(base: str) -> None:
    page = fetch(base + "/").decode("utf-8", errors="replace")
    if "<!doctype html" not in page.lower() or "app.js" not in page:
        raise SystemExit("bundled web/index.html is missing or incomplete")
    fetch(base + "/styles.css")
    fetch(base + "/app.js")
    fetch(base + "/logo/app_icon.png")


def port_is_closed(port: int, attempts: int = 20) -> bool:
    for _ in range(attempts):
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
            sock.settimeout(0.5)
            if sock.connect_ex(("127.0.0.1", port)) != 0:
                return True
        time.sleep(0.25)
    return False


def stop_tree(process: subprocess.Popen) -> None:
    if process.poll() is not None:
        return
    if os.name == "nt":
        subprocess.run(
            ["taskkill", "/T", "/F", "/PID", str(process.pid)],
            capture_output=True,
            check=False,
        )
    else:
        try:
            os.killpg(os.getpgid(process.pid), signal.SIGTERM)
        except ProcessLookupError:
            pass
    try:
        process.wait(timeout=10)
    except subprocess.TimeoutExpired:
        if os.name == "nt":
            process.kill()
        else:
            try:
                os.killpg(os.getpgid(process.pid), signal.SIGKILL)
            except ProcessLookupError:
                pass
        process.wait(timeout=5)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--artifact", required=True, help="built .app, .exe or executable")
    parser.add_argument("--timeout", type=float, default=90.0, help="seconds to wait for the API")
    args = parser.parse_args()

    executable = resolve_executable(Path(args.artifact).expanduser().resolve())
    port = free_port()
    env = os.environ.copy()
    env.pop("MAPSIM_SNAPSHOT", None)
    env["PYTHONUNBUFFERED"] = "1"

    command = [str(executable), "--demo", "--no-browser", "--port", str(port)]
    print("starting:", " ".join(command))
    process = subprocess.Popen(
        command,
        cwd=str(executable.parent),
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        env=env,
        text=True,
        start_new_session=(os.name != "nt"),
    )

    url = f"http://127.0.0.1:{port}/api/snapshot"
    deadline = time.time() + args.timeout
    last_error = ""
    try:
        while time.time() < deadline:
            if process.poll() is not None:
                output = (process.stdout.read() if process.stdout else "") or ""
                print(output[-4000:])
                raise SystemExit(f"dashboard exited early with code {process.returncode}")
            try:
                with urllib.request.urlopen(url, timeout=2) as response:
                    payload = json.loads(response.read().decode("utf-8"))
                snapshot = payload.get("payload")
                if isinstance(snapshot, dict) and isinstance(snapshot.get("account"), dict):
                    check_assets(f"http://127.0.0.1:{port}")
                    print(f"smoke test ok: {url} -> account payload ready")
                    return 0
                last_error = "snapshot payload is not ready yet"
            except Exception as exc:  # noqa: BLE001 - startup races are expected
                last_error = f"{type(exc).__name__}: {exc}"
            time.sleep(0.5)
        raise SystemExit(f"timed out waiting for {url} ({last_error})")
    finally:
        stop_tree(process)
        if not port_is_closed(port):
            raise SystemExit(f"the dashboard left port {port} open after shutdown")


if __name__ == "__main__":
    raise SystemExit(main())
