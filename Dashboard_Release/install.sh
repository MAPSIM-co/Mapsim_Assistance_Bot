#!/bin/sh
# Mapsim Live Dashboard - installer / service manager for macOS and Linux.
#
# Install and start:
#   curl -fsSL https://raw.githubusercontent.com/MAPSIM-co/Mapsim_Assistance_Bot/main/Dashboard_Release/install.sh | sh
#
# Options (run the file directly to pass options, e.g. `sh install.sh --public`):
#   --public          allow remote access: bind 0.0.0.0 with a generated password
#   --service         also install a background service that starts at boot/login
#   --remove-service  stop and remove the background service (keeps the app)
#   --uninstall       stop the app and the service, then remove everything
#   --no-launch       install only, do not start the app
#   --version=dashboard-vX.Y.Z  install a specific release
set -eu

REPO="MAPSIM-co/Mapsim_Assistance_Bot"
FALLBACK_VERSION="dashboard-v1.0.1"
APP_DIR_NAME="MapsimDashboard"
CONFIG_DIR="$HOME/.config/mapsim-dashboard"
ENV_FILE="$CONFIG_DIR/mapsim-dashboard.env"
SERVICE_NAME="mapsim-dashboard.service"
LABEL="com.mapsim.dashboard"
WRAPPER="$HOME/.local/bin/mapsim-dashboard"

PUBLIC=0
SERVICE=0
REMOVE_SERVICE=0
UNINSTALL=0
LAUNCH=1

for arg in "$@"; do
  case "$arg" in
    --public) PUBLIC=1 ;;
    --service) SERVICE=1 ;;
    --remove-service) REMOVE_SERVICE=1 ;;
    --uninstall) UNINSTALL=1 ;;
    --no-launch) LAUNCH=0 ;;
    --version=*) MAPSIM_DASHBOARD_VERSION="${arg#--version=}" ;;
    -h|--help)
      sed -n '2,19p' "$0" | sed 's/^# \{0,1\}//'
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

gen_password() {
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -hex 16
  else
    LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 32
    echo
  fi
}

write_env_file() {
  mkdir -p "$CONFIG_DIR"
  chmod 700 "$CONFIG_DIR"
  if [ -n "${MAPSIM_DASHBOARD_PASSWORD:-}" ]; then
    password="$MAPSIM_DASHBOARD_PASSWORD"
  else
    password="$(gen_password)"
  fi
  {
    echo "MAPSIM_DASHBOARD_BIND=0.0.0.0"
    echo "MAPSIM_DASHBOARD_PASSWORD=$password"
  } > "$ENV_FILE"
  chmod 600 "$ENV_FILE"
  printf '%s\n' "$password"
}

write_wrapper() {
  case "$OS" in
    Darwin) exec_target="$HOME/Applications/MapsimDashboard.app/Contents/MacOS/MapsimDashboard" ;;
    *) exec_target="$HOME/.local/share/MapsimDashboard/MapsimDashboard" ;;
  esac
  mkdir -p "$HOME/.local/bin"
  cat > "$WRAPPER" <<EOF
#!/bin/sh
# Mapsim Live Dashboard launcher - loads $ENV_FILE if present.
if [ -f "\$HOME/.config/mapsim-dashboard/mapsim-dashboard.env" ]; then
  set -a
  . "\$HOME/.config/mapsim-dashboard/mapsim-dashboard.env"
  set +a
fi
exec "$exec_target" --bind "\${MAPSIM_DASHBOARD_BIND:-127.0.0.1}" "\$@"
EOF
  chmod +x "$WRAPPER"
}

install_service_linux_root() {
  unit="/etc/systemd/system/$SERVICE_NAME"
  cat > "$unit" <<EOF
[Unit]
Description=Mapsim Live Dashboard (read-only MT5 dashboard)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
EnvironmentFile=-$ENV_FILE
ExecStart=$WRAPPER --no-browser
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable --now "$SERVICE_NAME"
}

install_service_linux_user() {
  unit="$HOME/.config/systemd/user/$SERVICE_NAME"
  mkdir -p "$HOME/.config/systemd/user"
  cat > "$unit" <<EOF
[Unit]
Description=Mapsim Live Dashboard (read-only MT5 dashboard)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
EnvironmentFile=-$ENV_FILE
ExecStart=$WRAPPER --no-browser
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
EOF
  systemctl --user daemon-reload
  systemctl --user enable --now "$SERVICE_NAME"
  loginctl enable-linger "$USER" >/dev/null 2>&1 || \
    echo "note: run 'sudo loginctl enable-linger $USER' so the service survives logout"
}

install_service_macos() {
  plist="$HOME/Library/LaunchAgents/$LABEL.plist"
  mkdir -p "$HOME/Library/LaunchAgents"
  cat > "$plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>$WRAPPER</string>
    <string>--no-browser</string>
  </array>
  <key>EnvironmentVariables</key>
  <dict>
    <key>HOME</key>
    <string>$HOME</string>
  </dict>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>WorkingDirectory</key>
  <string>$HOME</string>
</dict>
</plist>
EOF
  launchctl bootout "gui/$(id -u)" "$plist" 2>/dev/null || true
  launchctl bootstrap "gui/$(id -u)" "$plist"
}

install_service() {
  case "$OS" in
    Darwin) install_service_macos ;;
    Linux)
      if [ "$(id -u)" -eq 0 ]; then
        install_service_linux_root
      else
        install_service_linux_user
      fi
      ;;
  esac
  echo "service installed: starts automatically at boot/login"
}

remove_service() {
  case "$OS" in
    Darwin)
      plist="$HOME/Library/LaunchAgents/$LABEL.plist"
      launchctl bootout "gui/$(id -u)" "$plist" 2>/dev/null || true
      rm -f "$plist"
      ;;
    Linux)
      if [ "$(id -u)" -eq 0 ]; then
        if [ -f "/etc/systemd/system/$SERVICE_NAME" ]; then
          systemctl disable --now "$SERVICE_NAME" 2>/dev/null || true
          rm -f "/etc/systemd/system/$SERVICE_NAME"
          systemctl daemon-reload
        else
          echo "note: no system service installed"
        fi
      else
        unit="$HOME/.config/systemd/user/$SERVICE_NAME"
        if [ -f "$unit" ]; then
          systemctl --user disable --now "$SERVICE_NAME" 2>/dev/null || true
          rm -f "$unit"
          systemctl --user daemon-reload
        else
          echo "note: no user service installed"
        fi
      fi
      ;;
  esac
  echo "service removed."
}

stop_app() {
  pkill -f "$APP_DIR_NAME" 2>/dev/null || true
}

uninstall_everything() {
  remove_service
  stop_app
  case "$OS" in
    Darwin)
      rm -rf "$HOME/Applications/MapsimDashboard.app"
      rm -rf "$HOME/Library/Application Support/MapsimDashboard"
      ;;
    Linux)
      rm -rf "$HOME/.local/share/MapsimDashboard"
      rm -f "$HOME/.local/share/applications/mapsim-dashboard.desktop"
      ;;
  esac
  rm -f "$WRAPPER"
  rm -rf "$CONFIG_DIR"
  echo "Mapsim Live Dashboard removed completely."
}

if [ "$UNINSTALL" -eq 1 ]; then
  uninstall_everything
  exit 0
fi

if [ "$REMOVE_SERVICE" -eq 1 ]; then
  remove_service
  exit 0
fi

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
[ "$PUBLIC" -eq 1 ] && echo "  mode   : public (bind 0.0.0.0, password required)"
[ "$SERVICE" -eq 1 ] && echo "  service: will install and enable at boot/login"

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
  xattr -dr com.apple.quarantine "$DEST" 2>/dev/null || true
  echo "installed: $DEST"
else
  DEST="$HOME/.local/share/MapsimDashboard"
  rm -rf "$DEST"
  mkdir -p "$DEST"
  tar -xzf "$TMP/$ASSET" -C "$DEST"
  chmod +x "$DEST/MapsimDashboard"
  mkdir -p "$HOME/.local/share/applications"
  cat > "$HOME/.local/share/applications/mapsim-dashboard.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Mapsim Live Dashboard
Comment=Read-only MetaTrader 5 dashboard
Exec=$WRAPPER
Terminal=false
Categories=Finance;
EOF
  echo "installed: $DEST"
fi

PASSWORD=""
if [ "$PUBLIC" -eq 1 ]; then
  PASSWORD="$(write_env_file)"
  echo "public access:"
  echo "  user     : mapsim"
  echo "  password : $PASSWORD"
  echo "  saved in : $ENV_FILE"
  if [ "$OS" = "Linux" ]; then
    ip=$(hostname -I 2>/dev/null | awk '{print $1}')
    [ -n "$ip" ] && echo "  remote   : http://$ip:8765/ (open port 8765 in your firewall first)"
  else
    echo "  remote   : http://<this-mac-ip>:8765/ (allow port 8765 through your firewall)"
  fi
fi

write_wrapper
echo "command  : mapsim-dashboard (loads $ENV_FILE)"

if [ "$SERVICE" -eq 1 ]; then
  install_service
elif [ "$LAUNCH" -eq 1 ]; then
  if [ "$OS" = "Darwin" ]; then
    echo "starting the dashboard; your browser will open at http://127.0.0.1:8765/"
    open "$DEST"
  else
    echo "starting the dashboard; your browser will open at http://127.0.0.1:8765/"
    nohup "$WRAPPER" --no-browser >/dev/null 2>&1 &
    sleep 1
  fi
else
  echo "run with: mapsim-dashboard"
fi

echo "done."
