#!/bin/sh
# Mapsim Live Dashboard - one-line installer for macOS and Linux.
# Downloads the latest published build, verifies its SHA-256 checksum,
# installs it for the current user and starts it.
#
#   curl -fsSL https://raw.githubusercontent.com/MAPSIM-co/Mapsim_Assistance_Bot/main/Dashboard_Release/install.sh | sh
#
# Options when running the file directly:
#   --no-launch                 install only, do not start the dashboard
#   --version=dashboard-vX.Y.Z  install a specific release
set -eu

REPO="MAPSIM-co/Mapsim_Assistance_Bot"
FALLBACK_VERSION="dashboard-v1.0.0"
LAUNCH=1

for arg in "$@"; do
  case "$arg" in
    --no-launch) LAUNCH=0 ;;
    --version=*) MAPSIM_DASHBOARD_VERSION="${arg#--version=}" ;;
    -h|--help)
      cat <<'EOF'
Usage: install.sh [--no-launch] [--version=dashboard-vX.Y.Z]

  --no-launch                 install only, do not start the dashboard
  --version=dashboard-vX.Y.Z  install a specific release
EOF
      exit 0
      ;;
    *)
      echo "error: unknown option: $arg" >&2
      exit 2
      ;;
  esac
done

need() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "error: '$1' is required but was not found." >&2
    exit 1
  fi
}

need curl
need uname

OS=$(uname -s)
ARCH=$(uname -m)

case "$OS" in
  Darwin)
    case "$ARCH" in
      arm64) ASSET="MapsimDashboard-macos-arm64.zip" ;;
      x86_64) ASSET="MapsimDashboard-macos-x64.zip" ;;
      *)
        echo "error: unsupported macOS architecture: $ARCH" >&2
        exit 1
        ;;
    esac
    ;;
  Linux)
    case "$ARCH" in
      x86_64|amd64) ASSET="MapsimDashboard-linux-x64.tar.gz" ;;
      *)
        echo "error: unsupported Linux architecture: $ARCH (x86_64 is required)" >&2
        exit 1
        ;;
    esac
    ;;
  *)
    echo "error: unsupported operating system: $OS (on Windows run install.ps1 instead)" >&2
    exit 1
    ;;
esac

detect_version() {
  if [ -n "${MAPSIM_DASHBOARD_VERSION:-}" ]; then
    printf '%s\n' "$MAPSIM_DASHBOARD_VERSION"
    return
  fi
  latest=$(curl -fsSL "https://api.github.com/repos/$REPO/releases?per_page=50" 2>/dev/null \
    | grep -o '"tag_name": *"dashboard-v[^"]*"' \
    | head -n 1 \
    | sed 's/.*"\(dashboard-v[^"]*\)"/\1/') || true
  if [ -n "${latest:-}" ]; then
    printf '%s\n' "$latest"
  else
    printf '%s\n' "$FALLBACK_VERSION"
  fi
}

VERSION=$(detect_version)
BASE="https://github.com/$REPO/releases/download/$VERSION"

echo "Mapsim Live Dashboard installer"
echo "  system : $OS $ARCH"
echo "  version: $VERSION"

TMP=$(mktemp -d)
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT INT TERM

echo "downloading $ASSET ..."
curl -fL --retry 3 --retry-delay 2 -o "$TMP/$ASSET" "$BASE/$ASSET"
curl -fL --retry 3 --retry-delay 2 -o "$TMP/$ASSET.sha256" "$BASE/$ASSET.sha256"

echo "verifying checksum ..."
if command -v sha256sum >/dev/null 2>&1; then
  (cd "$TMP" && sha256sum -c "$ASSET.sha256")
else
  (cd "$TMP" && shasum -a 256 -c "$ASSET.sha256")
fi

if [ "$OS" = "Darwin" ]; then
  DEST="$HOME/Applications/MapsimDashboard.app"
  mkdir -p "$HOME/Applications"
  rm -rf "$DEST"
  unzip -q "$TMP/$ASSET" -d "$HOME/Applications"
  # Ad-hoc signed build: clear the quarantine flag so Gatekeeper can start it.
  xattr -dr com.apple.quarantine "$DEST" 2>/dev/null || true
  echo "installed: $DEST"
  if [ "$LAUNCH" -eq 1 ]; then
    echo "starting the dashboard; your browser will open at http://127.0.0.1:8765/"
    open "$DEST"
  else
    echo "run with: open \"$DEST\""
  fi
else
  DEST="$HOME/.local/share/MapsimDashboard"
  rm -rf "$DEST"
  mkdir -p "$DEST"
  tar -xzf "$TMP/$ASSET" -C "$DEST"
  chmod +x "$DEST/MapsimDashboard"
  mkdir -p "$HOME/.local/bin"
  ln -sf "$DEST/MapsimDashboard" "$HOME/.local/bin/mapsim-dashboard"
  mkdir -p "$HOME/.local/share/applications"
  cat > "$HOME/.local/share/applications/mapsim-dashboard.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Mapsim Live Dashboard
Comment=Read-only MetaTrader 5 dashboard
Exec=$DEST/MapsimDashboard
Terminal=false
Categories=Finance;
EOF
  echo "installed: $DEST"
  echo "command  : mapsim-dashboard (when ~/.local/bin is on PATH)"
  if [ "$LAUNCH" -eq 1 ]; then
    echo "starting the dashboard; your browser will open at http://127.0.0.1:8765/"
    nohup "$DEST/MapsimDashboard" >/dev/null 2>&1 &
    sleep 1
  else
    echo "run with: \"$DEST/MapsimDashboard\""
  fi
fi

echo "done."
