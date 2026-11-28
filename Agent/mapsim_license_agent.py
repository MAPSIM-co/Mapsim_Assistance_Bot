#!/usr/bin/env python3
"""MAPSIM licence Agent: the only component on the customer machine that talks
to the network.

Commands (frozen: the control center ``mapsim-menu.ps1`` / ``mapsim-menu.sh``
calls these names; the customer has no second menu):

    activate --serial <s>   first activation, writes lease.json
    refresh [--force]       new lease, redistributes to every terminal
    verify [--json]         local verification only, no network
    status                  key=value block for the menu
    link-terminal           record the MQL5 folder(s) the lease must reach
    uninstall               remove local state, keep the server record
    device-info             dev, os, arch, dongle (support use)

Exit codes (architecture 9.2):
    0 ok · 10 serial invalid · 11 serial consumed · 12 device unidentifiable
    13 network · 14 server reject · 15 revoked/suspended · 16 device mismatch
    20 any denial code from ``verify``

Ground rules this file must keep:

* Standard library only. No Python on the customer machine: this module is
  frozen into ``mapsim-license-agent[.exe]``, so an import that is not in the
  stdlib becomes a packaging failure on three platforms.
* Ed25519 verification is implemented here (RFC 8032) instead of pulling in
  ``cryptography``: one fewer native dependency, identical bytes everywhere.
* The Agent never decides an entitlement. It verifies what the server signed,
  writes it, and copies it into the terminals. A network failure is never an
  error the customer has to act on before ``exp``.

Spec: Document BOT\\MAPSIM_LICENSE_ARCHITECTURE.md sections 5, 7, 8 and 9.
"""

from __future__ import annotations

import argparse
import base64
import glob
import hashlib
import hmac
import json
import os
import platform
import secrets
import subprocess
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any

AGENT_VERSION = "2.0.1"
AGENT_NAME = "mapsim-license-agent"

# Architecture 3.3 / 5.5: the EA enforces the span, the Agent writes inside it.
MAX_LEASE_SPAN = 8 * 24 * 3600
CLOCK_SKEW = 300
REFRESH_INTERVAL = 6 * 3600
LEASE_FILE_MAX = 8192
LOCK_STALE_SECONDS = 120

STATE_DIR_NAME = ".mapsim"
LEASE_NAME = "lease.json"
DEVICE_NAME = "device.json"
KEY_NAME = "device.key"
KEYRING_NAME = "keyring.json"
KEYRING_STAMP = "keyring_at.json"
LOG_NAME = "agent.log"
TERMINAL_LIST_NAME = "ea_mql5.txt"
ENV_FILE_NAME = "ea-state.env"
LOCK_NAME = "lease.json.lock"

# Where the EA reads its copies, relative to the MQL5 folder (5.4).
MQL5_SUBDIR = ("Files", "MapsimLive")
LEASE_COPY_NAME = "license_lease.json"
GUARD_COPY_NAME = "license_guard.dat"

DEFAULT_API = "https://license.mapsimfx.sbs"

EXIT_OK = 0
EXIT_SERIAL_INVALID = 10
EXIT_SERIAL_CONSUMED = 11
EXIT_DEVICE = 12
EXIT_NETWORK = 13
EXIT_REJECT = 14
EXIT_REVOKED = 15
EXIT_MISMATCH = 16
EXIT_DENIED = 20



# =====================================================================
# small helpers
# =====================================================================
def now_ts() -> int:
    return int(time.time())


def utc_text(stamp: int) -> str:
    if stamp <= 0:
        return "-"
    return time.strftime("%Y-%m-%d %H:%M", time.gmtime(stamp))


def state_dir() -> Path:
    override = os.environ.get("MAPSIM_STATE_DIR", "").strip()
    if override:
        return Path(override).expanduser()
    return Path(os.path.expanduser("~")) / STATE_DIR_NAME


def _secure_dir(path: Path) -> Path:
    path.mkdir(parents=True, exist_ok=True)
    if os.name != "nt":
        try:
            os.chmod(path, 0o700)
        except OSError:
            pass
    return path


def _secure_file(path: Path) -> None:
    if os.name != "nt":
        try:
            os.chmod(path, 0o600)
        except OSError:
            pass


def write_atomic(path: Path, payload: bytes) -> None:
    """``.tmp`` in the same directory, fsync, then replace (9.7)."""
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(path.name + ".tmp")
    with open(tmp, "wb") as handle:
        handle.write(payload)
        handle.flush()
        os.fsync(handle.fileno())
    os.replace(tmp, path)
    _secure_file(path)


def read_json(path: Path) -> dict[str, Any] | None:
    try:
        raw = path.read_text(encoding="utf-8")
    except OSError:
        return None
    try:
        value = json.loads(raw)
    except ValueError:
        return None
    return value if isinstance(value, dict) else None


def log_line(message: str) -> None:
    """Rotating, owner-only log: 256 KB, last 200 lines (9.3)."""
    directory = state_dir()
    try:
        _secure_dir(directory)
        path = directory / LOG_NAME
        line = f"{time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())} {message}\n"
        with open(path, "a", encoding="utf-8") as handle:
            handle.write(line)
        if path.stat().st_size > 256 * 1024:
            kept = path.read_text(encoding="utf-8", errors="replace").splitlines()[-200:]
            write_atomic(path, ("\n".join(kept) + "\n").encode("utf-8"))
    except OSError:
        pass


class AgentError(Exception):
    """A refusal with an exit code attached."""

    def __init__(self, message: str, code: str = "", exit_code: int = EXIT_REJECT) -> None:
        super().__init__(message)
        self.code = code
        self.exit_code = exit_code


# =====================================================================
# Ed25519 verification (RFC 8032) - verify only, no signing
# =====================================================================
_P = 2**255 - 19
_L = 2**252 + 27742317777372353535851937790883648493
_D = (-121665 * pow(121666, _P - 2, _P)) % _P
_I = pow(2, (_P - 1) // 4, _P)
_BASE_ENCODING = bytes.fromhex("5866666666666666666666666666666666666666666666666666666666666666")


def _point_add(left: tuple[int, int, int, int], right: tuple[int, int, int, int]) -> tuple[int, int, int, int]:
    x1, y1, z1, t1 = left
    x2, y2, z2, t2 = right
    a = (y1 - x1) * (y2 - x2) % _P
    b = (y1 + x1) * (y2 + x2) % _P
    c = t1 * 2 * _D * t2 % _P
    d = z1 * 2 * z2 % _P
    e, f, g, h = b - a, d - c, d + c, b + a
    return (e * f % _P, g * h % _P, f * g % _P, e * h % _P)


def _point_mul(scalar: int, point: tuple[int, int, int, int]) -> tuple[int, int, int, int]:
    result = (0, 1, 1, 0)
    while scalar > 0:
        if scalar & 1:
            result = _point_add(result, point)
        point = _point_add(point, point)
        scalar >>= 1
    return result


def _recover_x(y: int, sign: int) -> int | None:
    if y >= _P:
        return None
    x2 = (y * y - 1) * pow(_D * y * y + 1, _P - 2, _P) % _P
    if x2 == 0:
        return None if sign else 0
    x = pow(x2, (_P + 3) // 8, _P)
    if (x * x - x2) % _P:
        x = x * _I % _P
    if (x * x - x2) % _P:
        return None
    if (x & 1) != sign:
        x = _P - x
    return x


def _decompress(encoded: bytes) -> tuple[int, int, int, int] | None:
    if len(encoded) != 32:
        return None
    value = int.from_bytes(encoded, "little")
    sign = value >> 255
    y = value & ((1 << 255) - 1)
    x = _recover_x(y, sign)
    if x is None:
        return None
    return (x, y, 1, x * y % _P)


def _same_point(left: tuple[int, int, int, int], right: tuple[int, int, int, int]) -> bool:
    x1, y1, z1, _ = left
    x2, y2, z2, _ = right
    return (x1 * z2 - x2 * z1) % _P == 0 and (y1 * z2 - y2 * z1) % _P == 0


def ed25519_verify(public: bytes, message: bytes, signature: bytes) -> bool:
    """True only for a valid signature by ``public`` over ``message``."""
    if len(public) != 32 or len(signature) != 64:
        return False
    r_point = _decompress(signature[:32])
    a_point = _decompress(public)
    base = _decompress(_BASE_ENCODING)
    if r_point is None or a_point is None or base is None:
        return False
    scalar = int.from_bytes(signature[32:], "little")
    if scalar >= _L:
        return False
    challenge = int.from_bytes(hashlib.sha512(signature[:32] + public + message).digest(), "little") % _L
    return _same_point(_point_mul(scalar, base), _point_add(r_point, _point_mul(challenge, a_point)))


# =====================================================================
# canonical JSON and sig_local
# =====================================================================
def canonical_json(payload: dict[str, Any]) -> str:
    return json.dumps(payload, sort_keys=True, separators=(",", ":"), ensure_ascii=False)


def canonical_bytes(payload: dict[str, Any]) -> bytes:
    return canonical_json(payload).encode("utf-8")


def sig_local(key: bytes, payload: dict[str, Any], signature: str) -> str:
    """HMAC integrity stamp (5.6). Not a security boundary, by design."""
    return hmac.new(key, canonical_bytes(payload) + signature.encode("ascii"), hashlib.sha256).hexdigest()


# =====================================================================
# key storage: DPAPI on Windows, 0600 file elsewhere
# =====================================================================
def _windows_dpapi(data: bytes, protect: bool) -> bytes | None:
    if os.name != "nt":
        return None
    try:
        import ctypes
        from ctypes import wintypes

        class Blob(ctypes.Structure):
            _fields_ = [("cbData", wintypes.DWORD), ("pbData", ctypes.POINTER(ctypes.c_char))]

        crypt32 = ctypes.windll.crypt32
        kernel32 = ctypes.windll.kernel32
        buffer = ctypes.create_string_buffer(data, len(data))
        source = Blob(len(data), ctypes.cast(buffer, ctypes.POINTER(ctypes.c_char)))
        target = Blob()
        function = crypt32.CryptProtectData if protect else crypt32.CryptUnprotectData
        # Without argtypes ctypes truncates the 64-bit pointers and the call
        # corrupts memory instead of failing, so every parameter is typed.
        function.argtypes = [
            ctypes.POINTER(Blob),
            wintypes.LPCWSTR,
            ctypes.POINTER(Blob),
            ctypes.c_void_p,
            ctypes.c_void_p,
            wintypes.DWORD,
            ctypes.POINTER(Blob),
        ]
        function.restype = wintypes.BOOL
        kernel32.LocalFree.argtypes = [ctypes.c_void_p]
        kernel32.LocalFree.restype = ctypes.c_void_p
        ok = function(ctypes.byref(source), None, None, None, None, 0, ctypes.byref(target))
        if not ok:
            return None
        try:
            return ctypes.string_at(target.pbData, target.cbData)
        finally:
            kernel32.LocalFree(target.pbData)
    except Exception:  # noqa: BLE001 - any ctypes gap falls back to the file
        return None


class KeyStore:
    """``K_local``/``K_dev``: DPAPI blob first, owner-only file second (9.6)."""

    def __init__(self, directory: Path) -> None:
        self.directory = directory
        self.file = directory / KEY_NAME
        self.dpapi_file = directory / (KEY_NAME + ".dpapi")

    def load(self) -> bytes | None:
        if self.dpapi_file.is_file():
            sealed = self.dpapi_file.read_bytes()
            plain = _windows_dpapi(sealed, protect=False)
            if plain and len(plain) == 32:
                return plain
        if self.file.is_file():
            raw = self.file.read_bytes().strip()
            try:
                return base64.b64decode(raw)
            except ValueError:
                return None
        return None

    def create(self) -> bytes:
        key = secrets.token_bytes(32)
        _secure_dir(self.directory)
        sealed = _windows_dpapi(key, protect=True)
        if sealed is not None:
            write_atomic(self.dpapi_file, sealed)
            return key
        write_atomic(self.file, base64.b64encode(key) + b"\n")
        if os.name == "nt":
            log_line("KEYSTORE_FALLBACK file (DPAPI refused); ACL limited to the user")
        else:
            log_line("KEYSTORE_FALLBACK file 0600")
        return key

    def get(self) -> bytes:
        return self.load() or self.create()

    def clear(self) -> None:
        for path in (self.file, self.dpapi_file):
            if path.exists():
                path.unlink()


def seal_text(store: KeyStore, text: str) -> str:
    """Store a secret (the serial) beside the key, sealed the same way."""
    raw = text.encode("utf-8")
    sealed = _windows_dpapi(raw, protect=True)
    if sealed is not None:
        return "dpapi:" + base64.b64encode(sealed).decode("ascii")
    return "b64:" + base64.b64encode(raw).decode("ascii")


def unseal_text(text: str) -> str:
    try:
        kind, _, body = text.partition(":")
        raw = base64.b64decode(body.encode("ascii"))
    except ValueError:
        return ""
    if kind == "dpapi":
        plain = _windows_dpapi(raw, protect=False)
        return plain.decode("utf-8") if plain else ""
    return raw.decode("utf-8")


# =====================================================================
# device identity (8.2)
# =====================================================================
def _run(command: list[str]) -> str:
    try:
        completed = subprocess.run(
            command,
            capture_output=True,
            text=True,
            timeout=12,
            creationflags=0x08000000 if os.name == "nt" else 0,
        )
    except (OSError, subprocess.SubprocessError):
        return ""
    if completed.returncode != 0:
        return ""
    return (completed.stdout or "").strip()


def _windows_components() -> list[str]:
    parts: list[str] = []
    try:
        import winreg

        with winreg.OpenKey(
            winreg.HKEY_LOCAL_MACHINE, r"SOFTWARE\Microsoft\Cryptography", 0, winreg.KEY_READ | winreg.KEY_WOW64_64KEY
        ) as key:
            parts.append(str(winreg.QueryValueEx(key, "MachineGuid")[0]))
    except OSError:
        pass
    board = _run(
        ["powershell", "-NoProfile", "-NonInteractive", "-Command",
         "(Get-CimInstance Win32_BaseBoard).SerialNumber"]
    )
    product = _run(
        ["powershell", "-NoProfile", "-NonInteractive", "-Command",
         "(Get-CimInstance Win32_ComputerSystemProduct).UUID"]
    )
    parts.extend([board, product])
    return parts


def _linux_component(path: str) -> str:
    try:
        return Path(path).read_text(encoding="utf-8", errors="replace").strip()
    except OSError:
        return ""


def _linux_components() -> list[str]:
    return [
        _linux_component("/etc/machine-id"),
        _linux_component("/sys/class/dmi/id/board_serial"),
        _linux_component("/sys/class/dmi/id/product_uuid"),
    ]


def _macos_components() -> list[str]:
    platform_uuid = ""
    for line in _run(["ioreg", "-rd1", "-c", "IOPlatformExpertDevice"]).splitlines():
        if "IOPlatformUUID" in line:
            platform_uuid = line.split("=")[-1].strip().strip('"')
            break
    serial = ""
    for line in _run(["system_profiler", "SPHardwareDataType"]).splitlines():
        if "Serial Number" in line:
            serial = line.split(":")[-1].strip()
            break
    volume = ""
    for line in _run(["diskutil", "info", "-plist", "/"]).splitlines():
        if "VolumeUUID" in line:
            volume = line.split("<string>")[-1].split("</string>")[0].strip()
            break
    return [platform_uuid, serial, volume]


def _normalise_component(value: str) -> str:
    return value.strip().strip("{}").replace(" ", "").lower()


def fingerprint() -> str:
    """``sha256:<hex>`` over three different components, best effort (8.2)."""
    system = platform.system().lower()
    if system == "windows":
        raw = _windows_components()
    elif system == "darwin":
        raw = _macos_components()
    else:
        raw = _linux_components()
    parts = [value for value in (_normalise_component(item) for item in raw) if value]
    parts = list(dict.fromkeys(parts))  # a duplicate source is a defect, not a component
    if not parts:
        raise AgentError("this machine exposes no device identifiers", code="DEVICE_UNIDENTIFIABLE", exit_code=EXIT_DEVICE)
    seed = "|".join(parts[:3]).encode("utf-8")
    return "sha256:" + hashlib.sha256(seed).hexdigest()


def device_record(directory: Path) -> dict[str, Any]:
    """Stable installation record. ``device_id`` never changes with hardware."""
    path = directory / DEVICE_NAME
    record = read_json(path) or {}
    changed = False
    if not record.get("device_id"):
        record["device_id"] = "dev-" + secrets.token_hex(8)
        record["created_at"] = now_ts()
        changed = True
    current = fingerprint()
    if record.get("fingerprint") != current:
        record["fingerprint"] = current
        record["fingerprint_at"] = now_ts()
        changed = True
    record.setdefault("seat", 1)
    if changed:
        write_atomic(path, json.dumps(record, sort_keys=True, indent=2).encode("utf-8"))
    return record


def device_id(directory: Path) -> str:
    return str(device_record(directory)["device_id"])


# =====================================================================
# key ring cache
# =====================================================================
class KeyRing:
    """kid -> raw public key, cached in the state dir and refreshed on demand."""

    def __init__(self, directory: Path, fetch: Any = None) -> None:
        self.file = directory / KEYRING_NAME
        self.fetch = fetch
        self.keys: dict[str, str] = {}
        stored = read_json(self.file) or {}
        for kid, value in (stored.get("keys") or {}).items():
            if isinstance(kid, str) and isinstance(value, str):
                self.keys[kid] = value

    def refresh(self) -> None:
        if self.fetch is None:
            return
        try:
            body = self.fetch()
        except AgentError:
            return
        keys = body.get("keys") if isinstance(body, dict) else None
        if not isinstance(keys, dict) or not keys:
            return
        clean = {str(k): str(v) for k, v in keys.items() if isinstance(v, str)}
        if clean == self.keys:
            return
        self.keys = clean
        write_atomic(
            self.file,
            json.dumps({"keys": clean, "current": body.get("current"), "at": now_ts()}, sort_keys=True, indent=2).encode("utf-8"),
        )

    def public_key(self, kid: str) -> bytes | None:
        value = self.keys.get(kid)
        if not value:
            return None
        try:
            return base64.b64decode(value.encode("ascii"))
        except ValueError:
            return None


# =====================================================================
# serials
#
# The server derives the device key from ``sha256(normalise(code))``, where
# ``normalise`` drops the prefix and every separator. Getting this byte-wise
# wrong is a permanent 401, so it is implemented once here.
# =====================================================================
SERIAL_PREFIX = "MAPSIM"
SERIAL_SYMBOLS = 16
SERIAL_ALPHABET = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"


def normalise_serial(text: str) -> str:
    cleaned = "".join(ch for ch in (text or "").upper() if ch.isalnum())
    if cleaned.startswith(SERIAL_PREFIX):
        cleaned = cleaned[len(SERIAL_PREFIX) :]
    return cleaned


def serial_ok(text: str) -> bool:
    body = normalise_serial(text)
    return len(body) == SERIAL_SYMBOLS and all(ch in SERIAL_ALPHABET for ch in body)


def pretty_serial(text: str) -> str:
    body = normalise_serial(text)
    return SERIAL_PREFIX + "-" + "-".join(body[i : i + 4] for i in range(0, len(body), 4))


def device_key(code: str, device: str) -> bytes:
    seed = hashlib.sha256(normalise_serial(code).encode("ascii")).digest()
    return hmac.new(seed, f"mapsim-kdev-v1|{device}".encode("utf-8"), hashlib.sha256).digest()


class Api:
    def __init__(self, base_url: str, code: str, device: str, timeout: int = 20) -> None:
        self.base = base_url.rstrip("/")
        self.code = normalise_serial(code)
        self.device = device
        self.timeout = timeout

    def _call(self, method: str, path: str, payload: dict[str, Any] | None, signed: bool) -> dict[str, Any]:
        body = b"" if payload is None else json.dumps(payload, separators=(",", ":"), sort_keys=True).encode("utf-8")
        headers = {"Accept": "application/json", "User-Agent": f"{AGENT_NAME}/{AGENT_VERSION}"}
        if body:
            headers["Content-Type"] = "application/json"
        if signed:
            stamp = str(now_ts())
            nonce = secrets.token_hex(8)
            base = f"{method.upper()}\n{path}\n{stamp}\n{nonce}\n{hashlib.sha256(body).hexdigest()}".encode("utf-8")
            headers.update(
                {
                    "X-License-Key": self.code,
                    "X-Device-Id": self.device,
                    "X-Timestamp": stamp,
                    "X-Nonce": nonce,
                    "X-Signature": hmac.new(device_key(self.code, self.device), base, hashlib.sha256).hexdigest(),
                }
            )
        request = urllib.request.Request(self.base + path, data=body if body else None, headers=headers, method=method.upper())
        try:
            with urllib.request.urlopen(request, timeout=self.timeout) as response:
                text = response.read().decode("utf-8", errors="replace")
        except urllib.error.HTTPError as exc:
            text = exc.read().decode("utf-8", errors="replace")
            raise _refusal(exc.code, text) from None
        except (urllib.error.URLError, OSError) as exc:
            raise AgentError(f"cannot reach the licence server: {exc}", code="NETWORK", exit_code=EXIT_NETWORK) from None
        try:
            value = json.loads(text)
        except ValueError:
            raise AgentError("the licence server answered something that is not JSON", code="BAD_RESPONSE", exit_code=EXIT_NETWORK) from None
        if not isinstance(value, dict):
            raise AgentError("unexpected answer from the licence server", code="BAD_RESPONSE", exit_code=EXIT_NETWORK)
        return value

    def post(self, path: str, payload: dict[str, Any]) -> dict[str, Any]:
        return self._call("POST", path, payload, True)

    def get(self, path: str) -> dict[str, Any]:
        return self._call("GET", path, None, True)

    def public_keys(self) -> dict[str, Any]:
        return self._call("GET", "/v1/keys", None, False)


def _refusal(status: int, text: str) -> AgentError:
    code = ""
    message = ""
    verdict = ""
    try:
        body = json.loads(text)
        error = body.get("error") if isinstance(body.get("error"), dict) else body
        code = str(error.get("code") or "")
        message = str(error.get("message") or "")
        verdict = str(error.get("verdict") or "")
    except ValueError:
        message = text[:160]
    code = code or verdict or f"HTTP_{status}"
    table = {
        401: EXIT_REJECT,
        403: EXIT_REVOKED,
        404: EXIT_SERIAL_INVALID,
        409: EXIT_MISMATCH,
        410: EXIT_SERIAL_CONSUMED,
        422: EXIT_REJECT,
        429: EXIT_NETWORK,
    }
    exit_code = table.get(status, EXIT_REJECT if status < 500 else EXIT_NETWORK)
    if code in ("DEVICE_MISMATCH",):
        exit_code = EXIT_MISMATCH
    if code in ("REVOKED", "SUSPENDED", "BANNED_SECURITY", "BANNED_ADMIN"):
        exit_code = EXIT_REVOKED
    if code in ("LICENSE_NOT_FOUND", "SERIAL_INVALID"):
        exit_code = EXIT_SERIAL_INVALID
    return AgentError(message or f"the licence server refused the request ({status})", code=code, exit_code=exit_code)


# =====================================================================
# lease file
# =====================================================================
def lease_path() -> Path:
    return state_dir() / LEASE_NAME


def load_lease(directory: Path | None = None) -> dict[str, Any] | None:
    path = (directory or state_dir()) / LEASE_NAME
    envelope = read_json(path)
    if envelope is None:
        return None
    if not isinstance(envelope.get("payload"), dict) or not isinstance(envelope.get("sig"), str):
        return None
    return envelope


def lease_body(stored: dict[str, Any]) -> bytes:
    """The exact bytes written to ``lease.json`` and to every terminal copy.

    ``ensure_ascii=False`` is mandatory, not cosmetic: the EA recomputes the
    integrity stamp over the *bytes it finds in the file*, while the Agent
    computed it over the canonical payload. A payload carrying a Persian
    label or account name would otherwise be written as ``\\uXXXX`` escapes
    and the stamp could never match, so every write goes through here.
    """
    return json.dumps(
        stored, sort_keys=True, separators=(",", ":"), ensure_ascii=False
    ).encode("utf-8")


def store_lease(directory: Path, envelope: dict[str, Any], key: bytes) -> dict[str, Any]:
    """Write the transport envelope with its integrity stamp (5.4 / 5.6)."""
    payload = envelope["payload"]
    signature = envelope["sig"]
    stored = {"payload": payload, "sig": signature, "sig_local": sig_local(key, payload, signature)}
    body = lease_body(stored)
    if len(canonical_bytes(payload)) > 4096 or len(body) > LEASE_FILE_MAX:
        raise AgentError("the server sent a lease larger than the protocol allows", code="LEASE_TOO_LARGE")
    write_atomic(directory / LEASE_NAME, body)
    return stored


def stored_sig_local(envelope: dict[str, Any], key: bytes) -> str:
    """Recompute the stamp over what is on disk and compare, in constant time."""
    payload = envelope.get("payload")
    signature = envelope.get("sig")
    if not isinstance(payload, dict) or not isinstance(signature, str):
        return ""
    return sig_local(key, payload, signature)


# =====================================================================
# verdicts (7.1 / 5.7)
# =====================================================================
ENTITLEMENTS = (
    "ENTRY_NORMAL",
    "ENTRY_RECOVERY",
    "MANAGE_POSITION",
    "PARTIAL",
    "BREAKEVEN",
    "RULES_APPLY",
    "STRUCTURE",
    "DASHBOARD",
)
MANAGEMENT_ALWAYS = ("MANAGE_POSITION", "PARTIAL", "BREAKEVEN")


def _as_int(value: Any, default: int = 0) -> int:
    try:
        return int(value)
    except (TypeError, ValueError):
        return default


class Verdict:
    def __init__(self, code: str, *, entries: bool, management: bool, payload: dict[str, Any] | None, note: str = "") -> None:
        self.code = code
        self.entries = entries
        self.management = management
        self.payload = payload or {}
        self.note = note

    @property
    def entitlements(self) -> list[str]:
        values = self.payload.get("ent")
        return [str(item) for item in values] if isinstance(values, list) else []

    def allowed(self, entitlement: str) -> bool:
        if entitlement in MANAGEMENT_ALWAYS:
            return self.management
        return self.entries and entitlement in self.entitlements

    @property
    def exp(self) -> int:
        return _as_int(self.payload.get("exp"))

    @property
    def grace_until(self) -> int:
        return _as_int(self.payload.get("grace_until"))

    @property
    def days_left(self) -> int:
        return max(0, (self.exp - now_ts()) // 86400)

    @property
    def key_hint(self) -> str:
        return str(self.payload.get("key") or "")

    def lines(self) -> list[str]:
        return [
            f"status={self.code}",
            f"code={self.code}",
            f"key={self.key_hint}",
            f"product={self.payload.get('prod', '')}",
            f"expiry={self.exp}",
            f"expiry_utc={utc_text(self.exp)}",
            f"days_left={self.days_left}",
            f"entitlements={','.join(self.entitlements)}",
            f"warning={self.note}",
            f"agent={AGENT_VERSION}",
        ]


def evaluate(
    envelope: dict[str, Any] | None,
    *,
    ring: KeyRing,
    key: bytes | None,
    device: str,
    product: str = "",
    last_seen: int = 0,
    now: int | None = None,
) -> Verdict:
    """The 5.7 order, one implementation for verify/status/refresh reporting."""
    now = now_ts() if now is None else now
    if envelope is None:
        return Verdict("NO_LEASE", entries=False, management=True, payload=None)
    payload = envelope.get("payload")
    signature = envelope.get("sig")
    if not isinstance(payload, dict) or not isinstance(signature, str):
        return Verdict("LEASE_MALFORMED", entries=False, management=True, payload=None)
    if _as_int(payload.get("v")) != 2:
        return Verdict("UNSUPPORTED_LEASE", entries=False, management=True, payload=payload)

    iat = _as_int(payload.get("iat"))
    nbf = _as_int(payload.get("nbf"), iat)
    exp = _as_int(payload.get("exp"))
    srv_time = _as_int(payload.get("srv_time"))
    now_eff = max(now, last_seen)

    if now < last_seen - CLOCK_SKEW:
        return Verdict("CLOCK_SKEW", entries=False, management=True, payload=payload, note="clock rolled back")
    if now_eff < nbf:
        return Verdict("NOT_YET_VALID", entries=False, management=True, payload=payload)
    if now_eff > exp:
        code = "GRACE" if now_eff <= _as_int(payload.get("grace_until")) else "EXPIRED"
        return Verdict(code, entries=False, management=True, payload=payload, note="refresh the licence")
    if exp - now_eff > MAX_LEASE_SPAN:
        return Verdict("LEASE_SPAN_VIOLATION", entries=False, management=True, payload=payload)

    if product and str(payload.get("prod") or "") != product:
        return Verdict("PRODUCT_MISMATCH", entries=False, management=True, payload=payload)

    # Signature before the stamp: a lease whose Ed25519 signature does not
    # verify is not ours, whatever its local stamp says.
    public = ring.public_key(str(payload.get("kid") or ""))
    if public is None:
        return Verdict("LEASE_TAMPERED", entries=False, management=True, payload=payload, note="unknown signing key")
    if not ed25519_verify(public, canonical_bytes(payload), _b64(signature)):
        return Verdict("LEASE_TAMPERED", entries=False, management=True, payload=payload, note="signature")

    if key is None or not hmac.compare_digest(stored_sig_local(envelope, key), str(envelope.get("sig_local") or "")):
        return Verdict("LEASE_TAMPERED", entries=False, management=True, payload=payload, note="integrity stamp")

    if device and str(payload.get("dev") or "") != device:
        return Verdict("DEVICE_MISMATCH", entries=False, management=True, payload=payload)

    note = ""
    if srv_time and now + CLOCK_SKEW < srv_time:
        note = "clock is behind the server"
    return Verdict("ACTIVE", entries=True, management=True, payload=payload, note=note)


def _b64(text: str) -> bytes:
    try:
        return base64.b64decode(text.encode("ascii"))
    except ValueError:
        return b""


# =====================================================================
# terminals and distribution (10.2)
# =====================================================================
def terminal_folders(directory: Path) -> list[Path]:
    """Every MQL5 folder the Menu recorded. The Agent never guesses.

    Order: ``EA_MQL5`` environment variable, ``ea_mql5.txt`` (one path per
    line), then ``ea-state.env`` (``EA_MQL5=`` lines written by the menu).
    Missing folders are skipped silently: a terminal may have been removed
    since the menu last ran.
    """
    values: list[str] = []
    env = os.environ.get("EA_MQL5", "").strip()
    if env:
        values.append(env)
    for name in (TERMINAL_LIST_NAME, ENV_FILE_NAME):
        path = directory / name
        try:
            lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
        except OSError:
            continue
        for line in lines:
            text = line.strip().strip('"')
            if not text or text.startswith("#"):
                continue
            if "=" in text:
                key, _, value = text.partition("=")
                if key.strip() != "EA_MQL5":
                    continue
                text = value.strip().strip('"')
            if text:
                values.append(text)
    folders: list[Path] = []
    for value in values:
        folder = Path(value).expanduser()
        if folder.is_dir() and folder not in folders:
            folders.append(folder)
    return folders


def guard_bytes(key: bytes, device: str) -> bytes:
    """``license_guard.dat``: version, K_local, device id. No expiry (5.6)."""
    return f"1\n{key.hex()}\n{device}\n".encode("ascii")


def distribute(directory: Path, stored: dict[str, Any], key: bytes, device: str) -> list[str]:
    """Copy the lease and the guard into every terminal the menu knows about."""
    written: list[str] = []
    body = lease_body(stored)
    guard = guard_bytes(key, device)
    for folder in terminal_folders(directory):
        target = folder.joinpath(*MQL5_SUBDIR)
        try:
            target.mkdir(parents=True, exist_ok=True)
            write_atomic(target / LEASE_COPY_NAME, body)
            write_atomic(target / GUARD_COPY_NAME, guard)
            written.append(str(target))
        except OSError as exc:
            log_line(f"DISTRIBUTE failed {target}: {exc}")
    if not written:
        log_line("NO_TERMINAL no MQL5 folder recorded; lease kept in the state dir")
    return written


def remove_terminal_copies(directory: Path) -> None:
    for folder in terminal_folders(directory):
        target = folder.joinpath(*MQL5_SUBDIR)
        for name in (LEASE_COPY_NAME, GUARD_COPY_NAME):
            path = target / name
            try:
                if path.exists():
                    path.unlink()
            except OSError:
                pass


def discover_terminals() -> list[Path]:
    """Every MQL5 folder this machine exposes, in a stable order (10.2).

    A guessed path is worse than no path: ``distribute`` copies the lease into
    ``<MQL5>/Files/MapsimLive`` and the EA reads it from there, so a wrong
    entry only produces a silent NO_LEASE. The patterns below are the default
    install locations per OS; ``link-terminal --path`` exists for everything
    else (portable installs, a Wine prefix outside the home directory).
    """
    system = platform.system().lower()
    patterns: list[str] = []
    home = Path(os.path.expanduser("~"))
    if system == "windows":
        roaming = os.environ.get("APPDATA", "").strip()
        if roaming:
            patterns.append(str(Path(roaming) / "MetaQuotes" / "Terminal" / "*" / "MQL5"))
    elif system == "darwin":
        base = home / "Library" / "Application Support"
        patterns.append(str(base / "*" / "MQL5"))
        patterns.append(str(base / "net.metaquotes.wine.metatrader5" / "drive_c" / "Program Files" / "*" / "MQL5"))
    else:
        drive = home / ".wine" / "drive_c"
        patterns.append(str(drive / "users" / "*" / "AppData" / "Roaming" / "MetaQuotes" / "Terminal" / "*" / "MQL5"))
        patterns.append(str(drive / "Program Files" / "*" / "MQL5"))
    found: list[Path] = []
    for pattern in patterns:
        for candidate in sorted(glob.glob(pattern)):
            folder = Path(candidate)
            if folder.is_dir() and folder not in found:
                found.append(folder)
    return found


def record_terminals(directory: Path, folders: list[Path]) -> list[Path]:
    """Merge ``folders`` into ``ea_mql5.txt``; returns the full known list."""
    path = directory / TERMINAL_LIST_NAME
    known = terminal_folders(directory)
    added = False
    for folder in folders:
        if folder not in known:
            known.append(folder)
            added = True
    if added or not path.exists():
        text = "\n".join(str(item) for item in known) + ("\n" if known else "")
        write_atomic(path, text.encode("utf-8"))
    return known


# =====================================================================
# single-run lock (9.5)
# =====================================================================
class LeaseLock:
    """Exclusive lock file; stale after 120 s or when its process is gone."""

    def __init__(self, directory: Path) -> None:
        self.path = directory / LOCK_NAME

    def __enter__(self) -> "LeaseLock":
        _secure_dir(self.path.parent)
        for _ in range(2):
            try:
                handle = os.open(str(self.path), os.O_CREAT | os.O_EXCL | os.O_WRONLY)
            except FileExistsError:
                if not self._stale():
                    raise AgentError("another refresh is already running", code="LOCKED", exit_code=EXIT_OK) from None
                try:
                    self.path.unlink()
                except OSError:
                    pass
                continue
            os.write(handle, str(os.getpid()).encode("ascii"))
            os.close(handle)
            return self
        raise AgentError("could not take the refresh lock", code="LOCKED", exit_code=EXIT_OK)

    def _stale(self) -> bool:
        try:
            age = now_ts() - int(self.path.stat().st_mtime)
        except OSError:
            return True
        if age > LOCK_STALE_SECONDS:
            return True
        try:
            pid = int(self.path.read_text(encoding="ascii").strip() or "0")
        except (OSError, ValueError):
            return False
        if pid <= 0 or os.name == "nt":
            return False
        try:
            os.kill(pid, 0)
        except OSError:
            return True
        return False

    def __exit__(self, *_exc: Any) -> None:
        try:
            self.path.unlink()
        except OSError:
            pass


# =====================================================================
# state
# =====================================================================
def remember(directory: Path, *, serial: str = "", last_seen: int = 0) -> None:
    path = directory / DEVICE_NAME
    record = read_json(path) or {}
    if serial:
        record["serial"] = seal_text(KeyStore(directory), pretty_serial(serial))
    if last_seen:
        record["last_seen_srv_time"] = max(int(record.get("last_seen_srv_time") or 0), int(last_seen))
    write_atomic(path, json.dumps(record, sort_keys=True, indent=2).encode("utf-8"))


def stored_serial(directory: Path) -> str:
    record = read_json(directory / DEVICE_NAME) or {}
    token = str(record.get("serial") or "")
    return unseal_text(token) if token else ""


def last_seen(directory: Path) -> int:
    record = read_json(directory / DEVICE_NAME) or {}
    return _as_int(record.get("last_seen_srv_time"))


def api_base(args: argparse.Namespace) -> str:
    return (
        getattr(args, "api", None)
        or os.environ.get("MAPSIM_API_URL", "").strip()
        or DEFAULT_API
    )


def current_verdict(directory: Path, product: str = "", *, fetch_keys: bool = False) -> Verdict:
    store = KeyStore(directory)
    key = store.load()
    ring = KeyRing(directory)
    if fetch_keys and store.load() is not None:
        serial = stored_serial(directory)
        if serial:
            ring.fetch = Api(api_base(_BlankArgs()), serial, device_id(directory)).public_keys
            ring.refresh()
    return evaluate(
        load_lease(directory),
        ring=ring,
        key=key,
        device=device_id(directory),
        product=product,
        last_seen=last_seen(directory),
    )


class _BlankArgs:
    api = None


# =====================================================================
# commands
# =====================================================================
def print_status(verdict: Verdict) -> None:
    for line in verdict.lines():
        print(line)


def cmd_activate(args: argparse.Namespace) -> int:
    directory = _secure_dir(state_dir())
    serial = args.serial or (sys.stdin.readline().strip() if not sys.stdin.isatty() else "")
    if not serial_ok(serial):
        print("error=serial_invalid")
        print("hint=the serial looks like MAPSIM-XXXX-XXXX-XXXX-XXXX")
        return EXIT_SERIAL_INVALID
    record = device_record(directory)
    store = KeyStore(directory)
    key = store.get()
    api = Api(api_base(args), serial, str(record["device_id"]))
    payload = {
        "device_id": record["device_id"],
        "fingerprint": record.get("fingerprint", ""),
        "product": args.product,
        "mode": "live",
        "os": platform.system().lower(),
        "arch": platform.machine().lower(),
        "agent_version": AGENT_VERSION,
        "broker": args.broker or "",
        "login": args.login or "",
        "account_type": args.account_type or "",
        "label": args.label or None,
    }
    with LeaseLock(directory):
        body = api.post("/v1/activate", payload)
    envelope = body.get("lease")
    if not isinstance(envelope, dict):
        raise AgentError("the server did not return a lease", code="NO_LEASE")
    stored = store_lease(directory, envelope, key)
    remember(directory, serial=serial, last_seen=_as_int((envelope.get("payload") or {}).get("srv_time")))
    ring = KeyRing(directory, fetch=api.public_keys)
    ring.refresh()
    written = distribute(directory, stored, key, str(record["device_id"]))
    verdict = evaluate(stored, ring=ring, key=key, device=str(record["device_id"]), product=args.product, last_seen=last_seen(directory))
    print_status(verdict)
    print(f"terminals={len(written)}")
    log_line(f"ACTIVATE ok device={record['device_id']} exp={verdict.exp} terminals={len(written)}")
    return EXIT_OK


def cmd_refresh(args: argparse.Namespace) -> int:
    directory = state_dir()
    serial = args.serial or stored_serial(directory)
    if not serial:
        print("error=not_activated")
        print("hint=run: " + AGENT_NAME + " activate --serial <serial>")
        return EXIT_SERIAL_INVALID
    record = device_record(directory)
    lease = load_lease(directory)
    if lease is None:
        raise AgentError("no lease on this machine; activate first", code="NO_LEASE", exit_code=EXIT_SERIAL_INVALID)
    payload = lease.get("payload") or {}
    verdict = current_verdict(directory, args.product)
    if not args.force and verdict.exp - now_ts() > REFRESH_INTERVAL and verdict.code in ("ACTIVE", "GRACE"):
        print_status(verdict)
        print("refreshed=no")
        return EXIT_OK

    store = KeyStore(directory)
    key = store.get()
    api = Api(api_base(args), serial, str(record["device_id"]))
    body = api.post(
        "/v1/refresh",
        {
            "device_id": record["device_id"],
            "lease_id": str(payload.get("lease_id") or ""),
            "fingerprint": record.get("fingerprint", ""),
        },
    )
    envelope = body.get("lease")
    if not isinstance(envelope, dict):
        raise AgentError("the server did not return a lease", code="NO_LEASE")
    with LeaseLock(directory):
        stored = store_lease(directory, envelope, key)
        remember(directory, last_seen=_as_int((envelope.get("payload") or {}).get("srv_time")))
    ring = KeyRing(directory, fetch=api.public_keys)
    ring.refresh()
    written = distribute(directory, stored, key, str(record["device_id"]))
    new_verdict = evaluate(stored, ring=ring, key=key, device=str(record["device_id"]), product=args.product, last_seen=last_seen(directory))
    print_status(new_verdict)
    print(f"terminals={len(written)}")
    print("refreshed=yes")
    log_line(f"REFRESH {new_verdict.code} exp={new_verdict.exp} terminals={len(written)}")
    return EXIT_OK


def cmd_verify(args: argparse.Namespace) -> int:
    directory = state_dir()
    verdict = current_verdict(directory, args.product)
    if args.json:
        print(
            json.dumps(
                {
                    "status": verdict.code,
                    "code": verdict.code,
                    "product": verdict.payload.get("prod", ""),
                    "expiry": verdict.exp,
                    "days_left": verdict.days_left,
                    "entries": verdict.entries,
                    "management": verdict.management,
                    "entitlements": verdict.entitlements,
                    "warning": verdict.note,
                },
                sort_keys=True,
            )
        )
    else:
        print_status(verdict)
    log_line(f"VERIFY {verdict.code} entries={int(verdict.entries)}")
    return EXIT_OK if verdict.code in ("ACTIVE", "GRACE") else EXIT_DENIED


def cmd_status(args: argparse.Namespace) -> int:
    directory = state_dir()
    verdict = current_verdict(directory, args.product)
    # The menu parses key=value; `user` is the licence hint, never the serial.
    print(f"user={verdict.key_hint or '-'}")
    print_status(verdict)
    print(f"device={device_id(directory) if (directory / DEVICE_NAME).exists() else '-'}")
    return EXIT_OK


def cmd_link_terminal(args: argparse.Namespace) -> int:
    """Record the MQL5 folder(s) so the lease reaches the EA (5.4 / 10.2).

    Without an entry here ``distribute`` has nowhere to copy and the EA only
    ever sees ``NO_LEASE``, which looks like a broken licence but is a missing
    path. When a lease already exists it is delivered immediately, so the
    customer never has to think about the order of these two steps.
    """
    directory = _secure_dir(state_dir())
    requested: list[Path] = []
    if args.path:
        candidate = Path(os.path.expanduser(args.path)).resolve()
        if not candidate.is_dir():
            raise AgentError(f"not a folder: {candidate}", code="TERMINAL_NOT_FOUND", exit_code=EXIT_REJECT)
        requested.append(candidate)
    if not requested:
        requested = discover_terminals()
    if not requested:
        print("terminals=0")
        print("hint=pass --path \"<MetaTrader 5 data folder>\\MQL5\"")
        return EXIT_REJECT
    known = record_terminals(directory, requested)
    for item in requested:
        print(f"terminal={item}")
    print(f"terminals={len(known)}")
    stored = load_lease(directory)
    key = KeyStore(directory).load()
    if stored is not None and key is not None:
        device = device_id(directory)
        written = distribute(directory, stored, key, device)
        print(f"delivered={len(written)}")
        log_line(f"LINK terminals={len(known)} delivered={len(written)}")
    else:
        print("delivered=0")
        log_line(f"LINK terminals={len(known)} no lease yet")
    return EXIT_OK


def cmd_uninstall(args: argparse.Namespace) -> int:
    directory = state_dir()
    remove_terminal_copies(directory)
    for name in (LEASE_NAME, DEVICE_NAME, KEYRING_NAME, KEYRING_STAMP, LOG_NAME, LOCK_NAME):
        path = directory / name
        try:
            if path.exists():
                path.unlink()
        except OSError:
            pass
    KeyStore(directory).clear()
    print("status=UNINSTALLED")
    return EXIT_OK


def cmd_device_info(args: argparse.Namespace) -> int:
    directory = _secure_dir(state_dir())
    record = device_record(directory)
    print(f"dev={record.get('fingerprint', '')}")
    print(f"device_id={record['device_id']}")
    print(f"os={platform.system().lower()}")
    print(f"arch={platform.machine().lower()}")
    print(f"dongle={_dongle_state()}")
    print(f"agent={AGENT_VERSION}")
    return EXIT_OK


def _dongle_state() -> str:
    """The Arduino dongle is a presence signal, never an identity (8.5)."""
    if os.name == "nt":
        return "unknown"
    try:
        for port in Path("/dev").glob("ttyACM*"):
            return "present"
    except OSError:
        pass
    return "unknown"


# =====================================================================
# CLI
# =====================================================================
def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog=AGENT_NAME, description="MAPSIM licence agent")
    parser.add_argument("--api", default=None, help=f"licence server base URL (default {DEFAULT_API})")
    parser.add_argument("--version", action="version", version=f"{AGENT_NAME} {AGENT_VERSION}")
    sub = parser.add_subparsers(dest="command", required=True)

    activate = sub.add_parser("activate", help="first activation, writes lease.json")
    activate.add_argument("--serial", default="", help="licence serial; read from stdin when omitted")
    # "" is the normal value: the serial decides the product (D-68), and one
    # control center serves both products without ever guessing which was bought.
    activate.add_argument("--product", default="", choices=("", "assist", "full"))
    activate.add_argument("--broker", default="")
    activate.add_argument("--login", default="")
    activate.add_argument("--account-type", dest="account_type", default="", choices=("", "demo", "real"))
    activate.add_argument("--label", default=None)
    activate.set_defaults(handler=cmd_activate)

    refresh = sub.add_parser("refresh", help="new lease, redistribute")
    refresh.add_argument("--force", action="store_true")
    refresh.add_argument("--serial", default="")
    # An assertion, not a default: empty means "whatever the lease says".
    refresh.add_argument("--product", default="", choices=("", "assist", "full"))
    refresh.set_defaults(handler=cmd_refresh)

    verify = sub.add_parser("verify", help="local verification only")
    verify.add_argument("--json", action="store_true")
    verify.add_argument("--product", default="", choices=("", "assist", "full"))
    verify.set_defaults(handler=cmd_verify)

    status = sub.add_parser("status", help="key=value block for the menu")
    status.add_argument("--product", default="", choices=("", "assist", "full"))
    status.set_defaults(handler=cmd_status)

    uninstall = sub.add_parser("uninstall", help="remove local state")
    uninstall.set_defaults(handler=cmd_uninstall)

    info = sub.add_parser("device-info", help="dev, os, arch, dongle")
    info.set_defaults(handler=cmd_device_info)

    link = sub.add_parser("link-terminal", help="record the MQL5 folder(s) the lease must reach")
    link.add_argument("--path", default="", help="MQL5 folder; auto-discovered when omitted")
    link.set_defaults(handler=cmd_link_terminal)

    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    try:
        return int(args.handler(args))
    except AgentError as exc:
        print(f"error={exc.code or 'error'}")
        print(f"message={exc}")
        log_line(f"ERROR {exc.code} {exc}")
        return exc.exit_code
    except KeyboardInterrupt:
        return EXIT_OK


if __name__ == "__main__":
    sys.exit(main())
