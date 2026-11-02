#!/usr/bin/env python3
"""Build a standalone Mapsim dashboard binary from a whitelist copy.

The dashboard project is never modified: files are copied into a staging
folder, packaged with PyInstaller, then verified. Secrets and live exports
(sftp.evd, runtime/snapshot.json, backups) are deliberately excluded.
"""

from __future__ import annotations

import argparse
import hashlib
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent

SOURCE_FILES = ("live_dashboard.py", "market_engine.py", "mock_feed.py", "news_feed.py")
SOURCE_DIRS = ("web", "Logo")
SOURCE_EXTRA = ("runtime/candles_sampled.json",)
ENTRY_FILE = HERE / "entry.py"

WEB_EXTENSIONS = {".html", ".js", ".mjs", ".css", ".svg", ".png", ".jpg", ".jpeg", ".ico", ".webp", ".woff", ".woff2"}
LOGO_EXTENSIONS = {".png", ".jpg", ".jpeg", ".gif", ".webp", ".svg", ".ico", ".icns"}

# Anything matching this must never reach the staging folder or the binary.
BANNED_PATTERN = re.compile(
    r"(^sftp\.evd$|\.evd$|^snapshot\.json$|^\.env(\.|$)|\.p12$|\.pfx$|\.key$|\.pem$|^backup_|\.DS_Store$)",
    re.IGNORECASE,
)

SECRET_KEYS = ("sftp_password", "password", "mapsim_sftp_password", "pass")


class BuildError(RuntimeError):
    pass


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def source_manifest(source: Path) -> list[Path]:
    files: list[Path] = []
    for name in SOURCE_FILES:
        files.append(source / name)
    for name in SOURCE_DIRS:
        folder = source / name
        if folder.is_dir():
            files.extend(sorted(p for p in folder.rglob("*") if p.is_file()))
    for name in SOURCE_EXTRA:
        files.append(source / name)
    return files


def validate_source(source: Path) -> None:
    if not source.is_dir():
        raise BuildError(f"source folder not found: {source}")
    missing = [str(path.relative_to(source)) for path in source_manifest(source) if not path.is_file()]
    if missing:
        raise BuildError(
            "source is missing required files:\n  " + "\n  ".join(sorted(missing))
        )


def snapshot_hashes(source: Path) -> dict[str, str]:
    return {
        str(path.relative_to(source)): sha256_file(path)
        for path in source_manifest(source)
    }


def is_allowed_asset(path: Path, allowed: set[str]) -> bool:
    if path.name.startswith("."):
        return False
    if BANNED_PATTERN.search(path.name):
        return False
    return path.suffix.lower() in allowed


def copy_whitelist(source: Path, stage: Path) -> None:
    stage.mkdir(parents=True, exist_ok=True)

    for name in SOURCE_FILES:
        shutil.copy2(source / name, stage / name)
    shutil.copy2(ENTRY_FILE, stage / "entry.py")

    for name, allowed in (("web", WEB_EXTENSIONS), ("Logo", LOGO_EXTENSIONS)):
        folder = source / name
        for path in sorted(folder.rglob("*")):
            if not path.is_file() or not is_allowed_asset(path, allowed):
                continue
            target = stage / name / path.relative_to(folder)
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(path, target)

    runtime = stage / "runtime"
    runtime.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source / "runtime" / "candles_sampled.json", runtime / "candles_sampled.json")


def assert_clean(folder: Path) -> None:
    leaked = [
        str(path.relative_to(folder))
        for path in folder.rglob("*")
        if path.is_file() and BANNED_PATTERN.search(path.name)
    ]
    if leaked:
        raise BuildError("refusing to continue, excluded files reached the build folder: " + ", ".join(sorted(leaked)))


def secret_values(source: Path) -> list[bytes]:
    values: list[str] = []
    secrets_file = source / "sftp.evd"
    if secrets_file.is_file():
        for raw in secrets_file.read_text(encoding="utf-8-sig", errors="ignore").splitlines():
            line = raw.strip()
            if not line or line.startswith(("#", ";", "//")):
                continue
            if line.lower().startswith("export "):
                line = line[7:].strip()
            if "=" not in line:
                continue
            key, value = line.split("=", 1)
            value = value.strip().strip("\"'")
            if key.strip().lower() in SECRET_KEYS and len(value) >= 6:
                values.append(value)
    for key in ("MAPSIM_SFTP_PASSWORD", "SFTP_PASSWORD"):
        value = os.environ.get(key)
        if value and len(value) >= 6:
            values.append(value)
    encoded: list[bytes] = []
    for value in values:
        encoded.append(value.encode("utf-8"))
        encoded.append(value.encode("utf-16-le"))
    return encoded


def scan_artifact(artifact: Path, needles: list[bytes]) -> None:
    if not needles:
        return
    targets = [artifact] if artifact.is_file() else [p for p in artifact.rglob("*") if p.is_file()]
    for path in targets:
        payload = path.read_bytes()
        for needle in needles:
            if needle in payload:
                raise BuildError(
                    "the built artifact contains a secret value; refusing to keep it "
                    f"({path.name}, value redacted). Delete the output and call the maintainer."
                )


def resolve_artifact(dist: Path, name: str) -> tuple[Path, Path]:
    if sys.platform == "darwin":
        bundle = dist / f"{name}.app"
        executable = bundle / "Contents" / "MacOS" / name
        if bundle.is_dir() and executable.is_file():
            return bundle, executable
    if os.name == "nt":
        executable = dist / f"{name}.exe"
        if executable.is_file():
            return executable, executable
    executable = dist / name
    if executable.is_file():
        return executable, executable
    raise BuildError(f"build finished but no artifact was found in {dist}")


def run_pyinstaller(source: Path, stage: Path, dist: Path, work: Path, name: str, console: bool, icon: Path | None) -> None:
    separator = os.pathsep
    command = [
        sys.executable,
        "-m",
        "PyInstaller",
        "--noconfirm",
        "--clean",
        "--onefile",
        "--name",
        name,
        "--distpath",
        str(dist),
        "--workpath",
        str(work),
        "--specpath",
        str(work),
        "--paths",
        str(stage),
        "--hidden-import",
        "paramiko",
        "--hidden-import",
        "certifi",
        "--hidden-import",
        "tzdata",
        "--collect-submodules",
        "paramiko",
        "--collect-data",
        "certifi",
        "--collect-data",
        "tzdata",
        "--add-data",
        f"{stage / 'web'}{separator}web",
        "--add-data",
        f"{stage / 'Logo'}{separator}Logo",
        "--add-data",
        f"{stage / 'runtime' / 'candles_sampled.json'}{separator}runtime",
    ]
    if not console:
        command.append("--windowed")
    if icon is not None:
        command.extend(["--icon", str(icon)])
    identity = os.environ.get("MAPSIM_CODESIGN_IDENTITY", "").strip()
    if identity:
        command.extend(["--codesign-identity", identity])
    command.append(str(stage / "entry.py"))

    env = os.environ.copy()
    env["PYTHONDONTWRITEBYTECODE"] = "1"
    print("running:", " ".join(command))
    subprocess.run(command, check=True, env=env)


def main() -> int:
    parser = argparse.ArgumentParser(description="Package the read-only Mapsim dashboard as a standalone app.")
    parser.add_argument("--source", required=True, help="path to the private dashboard source folder")
    parser.add_argument("--out", default=str(HERE / "dist"), help="output folder (default: ./dist)")
    parser.add_argument("--name", default="MapsimDashboard", help="artifact name")
    parser.add_argument("--console", action="store_true", help="keep the console window (debugging only)")
    parser.add_argument("--icon", default=None, help="optional .ico/.icns/.png icon")
    parser.add_argument("--keep-stage", action="store_true", help="keep the staging folder for inspection")
    parser.add_argument("--skip-secret-scan", action="store_true", help="skip scanning the binary for sftp.evd values")
    args = parser.parse_args()

    if shutil.which("pyinstaller") is None:
        try:
            import PyInstaller  # noqa: F401
        except ImportError as exc:
            raise BuildError("PyInstaller is not installed; run: python -m pip install -r requirements-build.txt") from exc

    source = Path(args.source).expanduser().resolve()
    dist = Path(args.out).expanduser().resolve()
    build_root = HERE / ".build"
    stage = build_root / "stage"
    work = build_root / "work"

    validate_source(source)
    before = snapshot_hashes(source)

    if (source / "sftp.evd").exists():
        print("note: sftp.evd is present in the source and will NOT be bundled")
    if (source / "runtime" / "snapshot.json").exists():
        print("note: runtime/snapshot.json is live data and will NOT be bundled")

    shutil.rmtree(build_root, ignore_errors=True)
    dist.mkdir(parents=True, exist_ok=True)

    try:
        copy_whitelist(source, stage)
        assert_clean(stage)
        print(f"staged {sum(1 for _ in stage.rglob('*') if _.is_file())} files in {stage}")

        icon = Path(args.icon).expanduser().resolve() if args.icon else source / "Logo" / "app_icon.png"
        if not icon.is_file():
            print(f"note: icon not found at {icon}; building with the default icon")
            icon = None

        run_pyinstaller(source, stage, dist, work, args.name, args.console, icon)

        artifact, executable = resolve_artifact(dist, args.name)
        assert_clean(artifact if artifact.is_dir() else dist)
        if not args.skip_secret_scan:
            scan_artifact(artifact, secret_values(source))
            print("secret scan: no credential values found in the artifact")

        digest = sha256_file(executable)
        (dist / "SHA256SUMS").write_text(f"{digest}  {executable.name}\n", encoding="utf-8")

        after = snapshot_hashes(source)
        if before != after:
            changed = sorted(name for name in before if before[name] != after.get(name))
            raise BuildError("source files changed during the build: " + ", ".join(changed))
        print("source check: all whitelisted source files are byte-identical")

        print(f"built: {artifact}")
        print(f"sha256: {digest}")
        return 0
    finally:
        if not args.keep_stage:
            shutil.rmtree(build_root, ignore_errors=True)


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except BuildError as error:
        print(f"build failed: {error}", file=sys.stderr)
        raise SystemExit(1)
    except subprocess.CalledProcessError as error:
        print(f"PyInstaller failed with exit code {error.returncode}", file=sys.stderr)
        raise SystemExit(error.returncode or 1)
