#!/bin/sh
# Mapsim Live Dashboard - installer bootstrap for macOS and Linux.
#
# This file only downloads the Mapsim BOT control center (mapsim-menu.sh) and
# runs it. All real work (install, start/stop, service, uninstall, menu) lives
# in mapsim-menu.sh so the interactive command 'Mapsim_BOT' behaves exactly
# like the installer.
#
# Install and start:
#   curl -fsSL https://raw.githubusercontent.com/MAPSIM-co/Mapsim_Assistance_Bot/main/Dashboard_Release/install.sh | sh
#
# Options (passed through to the control center):
#   --public          allow remote access: bind 0.0.0.0, sign in with the license
#   --service         also install a background service that starts at boot/login
#   --remove-service  stop and remove the background service (keeps the app)
#   --uninstall       stop the app and the service, then remove everything
#   --no-launch       install only, do not start the app
#   --version=dashboard-vX.Y.Z  install a specific release
set -eu

REPO="MAPSIM-co/Mapsim_Assistance_Bot"
MENU_URL="https://raw.githubusercontent.com/$REPO/main/Dashboard_Release/mapsim-menu.sh"

need() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "error: '$1' is required but was not found." >&2
    exit 1
  fi
}
need curl
need uname

os=$(uname -s)
case "$os" in
  Darwin|Linux) ;;
  *) echo "error: unsupported operating system: $os (on Windows run install.ps1 instead)" >&2; exit 1 ;;
esac

# If the control center is already installed, run the local copy (works offline).
case "${1:-}" in
  --remove-service|--uninstall)
    m="$HOME/.local/share/MapsimBOT/mapsim-menu.sh"
    if [ ! -f "$m" ]; then
      m="$HOME/.local/share/MapsimDashboard/mapsim-menu.sh"
    fi
    if [ -f "$m" ]; then
      echo "Mapsim BOT control center (installed copy)"
      exec sh "$m" --bootstrap "$@"
    fi
    ;;
esac

echo "Mapsim BOT control center bootstrap"
echo "  downloading the control center ..."
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT INT TERM
curl -fsSL --retry 3 --retry-delay 2 -o "$tmp/mapsim-menu.sh" "$MENU_URL"
chmod +x "$tmp/mapsim-menu.sh"
exec sh "$tmp/mapsim-menu.sh" --bootstrap "$@"
