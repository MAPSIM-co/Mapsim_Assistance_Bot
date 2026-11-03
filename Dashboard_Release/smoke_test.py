#!/usr/bin/env python3
"""Start a built dashboard in demo mode on a free port and verify /api/snapshot."""

from __future__ import annotations

import argparse
import base64
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


def read_auth(path: Path | None) -> str:
    """Basic Auth header from a two-line username/password file ('' when absent)."""
    if path is None:
        return ""
    lines = path.read_text(encoding="utf-8").splitlines()
    if len(lines) < 2:
        raise SystemExit(f"auth file needs a username and a password line: {path}")
    token = base64.b64encode(f"{lines[0].strip()}:{lines[1]}".encode("utf-8")).decode("ascii")
    return "Basic " + token


def fetch(url: str, authorization: str = "", limit: int = 400_000) -> bytes:
    request = urllib.request.Request(url)
    if authorization:
        request.add_header("Authorization", authorization)
    with urllib.request.urlopen(request, timeout=5) as response:
        if response.status != 200:
            raise RuntimeError(f"{url} returned HTTP {response.status}")
        return response.read(limit)


def check_assets(base: str, authorization: str = "") -> None:
    page = fetch(base + "/", authorization).decode("utf-8", errors="replace")
    if "<!doctype html" not in page.lower() or "app.js" not in page:
        raise SystemExit("bundled web/index.html is missing or incomplete")
    fetch(base + "/styles.css", authorization)
    fetch(base + "/app.js", authorization)
    fetch(base + "/logo/app_icon.png", authorization)


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
    parser.add_argument("--license-file", required=True, help="license file for the app (it refuses to start without one)")
    parser.add_argument("--auth-file", required=True, help="username/password file used to sign in")
    args = parser.parse_args()

    executable = resolve_executable(Path(args.artifact).expanduser().resolve())
    license_file = Path(args.license_file).expanduser().resolve()
    auth_file = Path(args.auth_file).expanduser().resolve()
    if not license_file.is_file():
        raise SystemExit(f"license file not found: {license_file}")
    authorization = read_auth(auth_file)

    port = free_port()
    env = os.environ.copy()
    env.pop("MAPSIM_SNAPSHOT", None)
    env["PYTHONUNBUFFERED"] = "1"

    command = [
        str(executable),
        "--demo",
        "--no-browser",
        "--port",
        str(port),
        "--license-file",
        str(license_file),
        "--auth-file",
        str(auth_file),
    ]
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
                request = urllib.request.Request(url)
                request.add_header("Authorization", authorization)
                with urllib.request.urlopen(request, timeout=2) as response:
                    payload = json.loads(response.read().decode("utf-8"))
                snapshot = payload.get("payload")
                if isinstance(snapshot, dict) and isinstance(snapshot.get("account"), dict):
                    check_assets(f"http://127.0.0.1:{port}", authorization)
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
