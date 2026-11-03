#!/bin/sh
# Mapsim BOT control center - interactive management menu for macOS and Linux.
#
# This script is the single source of truth for installing, starting, stopping,
# servicing and removing the Mapsim Live Dashboard. The installer (install.sh)
# only downloads this file and runs it; the Mapsim_BOT command is a symlink to
# it.
#
# Usage:
#   Mapsim_BOT                open the interactive menu
#   Mapsim_BOT --bootstrap    non-interactive install (used by install.sh)
#
set -u

REPO="MAPSIM-co/Mapsim_Assistance_Bot"
FALLBACK_VERSION="dashboard-v1.0.1"
APP_NAME="MapsimDashboard"
MENU_CMD="Mapsim_BOT"
CONFIG_DIR="$HOME/.config/mapsim-dashboard"
ENV_FILE="$CONFIG_DIR/mapsim-dashboard.env"
PID_FILE="$CONFIG_DIR/dashboard.pid"
LOG_FILE="$CONFIG_DIR/dashboard.log"
WRAPPER="$HOME/.local/bin/mapsim-dashboard"
SERVICE_NAME="mapsim-dashboard.service"
LABEL="com.mapsim.dashboard"

OS=$(uname -s)
ARCH=$(uname -m)

case "$OS" in
  Darwin)
    APP_ROOT="$HOME/Applications/MapsimDashboard.app"
    BINARY="$APP_ROOT/Contents/MacOS/MapsimDashboard"
    ;;
  Linux)
    APP_ROOT="$HOME/.local/share/MapsimDashboard"
    BINARY="$APP_ROOT/MapsimDashboard"
    ;;
  *)
    echo "error: unsupported operating system: $OS (on Windows run install.ps1 instead)" >&2
    exit 1
    ;;
esac

MENU_DEST="$HOME/.local/share/MapsimDashboard/mapsim-menu.sh"

# ---------------------------------------------------------------- utilities

need() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "error: '$1' is required but was not found." >&2
    exit 1
  fi
}

is_installed() { [ -x "$BINARY" ]; }

gen_password() {
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -hex 16
  else
    LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 32
    echo
  fi
}

# HTTP status of the dashboard on a port: prints 000 when nothing answers.
http_code() {
  curl -s -m 2 -o /dev/null -w '%{http_code}' "http://127.0.0.1:$1/healthz" 2>/dev/null || echo 000
}

# True when a port has a listener (anything at all).
port_listening() {
  if command -v ss >/dev/null 2>&1; then
    ss -ltn 2>/dev/null | grep -q ":$1 "
  elif command -v netstat >/dev/null 2>&1; then
    netstat -ltn 2>/dev/null | grep -qE "\.$1[[:space:]]"
  elif command -v lsof >/dev/null 2>&1; then
    lsof -iTCP:"$1" -sTCP:LISTEN >/dev/null 2>&1
  else
    [ "$(http_code "$1")" != "000" ]
  fi
}

# True when OUR dashboard answers on the port (200 local, 401 public).
dashboard_up() {
  code=$(http_code "$1")
  [ "$code" = "200" ] || [ "$code" = "401" ]
}

# PID of our dashboard process, or empty.
dashboard_pid() {
  if [ -f "$PID_FILE" ]; then
    pid=$(cat "$PID_FILE" 2>/dev/null || true)
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
      echo "$pid"
      return
    fi
  fi
  pgrep -f "$BINARY" 2>/dev/null | head -n 1 || true
}

current_bind() {
  [ -f "$ENV_FILE" ] && grep -E '^MAPSIM_DASHBOARD_BIND=' "$ENV_FILE" | tail -n 1 | cut -d= -f2 || true
}

current_password() {
  [ -f "$ENV_FILE" ] && grep -E '^MAPSIM_DASHBOARD_PASSWORD=' "$ENV_FILE" | tail -n 1 | cut -d= -f2 || true
}

# Prompts go to stderr so callers can capture the answer with $(ask ...).
ask() {
  printf '%s' "$1 " >&2
  if ! IFS= read -r ans; then
    exit 0
  fi
  echo "$ans"
}

# ---------------------------------------------------------------- env/wrapper

write_env_file() {
  bind="$1"
  password="$2"
  mkdir -p "$CONFIG_DIR"
  chmod 700 "$CONFIG_DIR"
  {
    echo "MAPSIM_DASHBOARD_BIND=$bind"
    echo "MAPSIM_DASHBOARD_PASSWORD=$password"
  } > "$ENV_FILE"
  chmod 600 "$ENV_FILE"
}

write_wrapper() {
  mkdir -p "$HOME/.local/bin"
  cat > "$WRAPPER" <<EOF
#!/bin/sh
# Mapsim Live Dashboard launcher - loads $ENV_FILE if present.
if [ -f "\$HOME/.config/mapsim-dashboard/mapsim-dashboard.env" ]; then
  set -a
  . "\$HOME/.config/mapsim-dashboard/mapsim-dashboard.env"
  set +a
fi
exec "$BINARY" --bind "\${MAPSIM_DASHBOARD_BIND:-127.0.0.1}" "\$@"
EOF
  chmod +x "$WRAPPER"
}

install_command_link() {
  # Make commands available even when ~/.local/bin is not on PATH (e.g. root
  # on many VPS images). Only link into directories we can write without sudo.
  LINKS=""
  for dir in /usr/local/bin /usr/bin; do
    if [ -d "$dir" ] && [ -w "$dir" ]; then
      ln -sf "$WRAPPER" "$dir/mapsim-dashboard"
      ln -sf "$MENU_DEST" "$dir/$MENU_CMD"
      LINKS="$dir"
      break
    fi
  done
  if [ -z "$LINKS" ] && ! printf '%s' ":$PATH:" | grep -q ":$HOME/.local/bin:"; then
    echo "note: add $HOME/.local/bin to your PATH to use the 'mapsim-dashboard'"
    echo "      and '$MENU_CMD' commands:  export PATH=\"\$HOME/.local/bin:\$PATH\""
  fi
}

remove_command_link() {
  for dir in /usr/local/bin /usr/bin; do
    [ -L "$dir/mapsim-dashboard" ] && rm -f "$dir/mapsim-dashboard"
    [ -L "$dir/$MENU_CMD" ] && rm -f "$dir/$MENU_CMD"
  done
}

install_self() {
  # Persist this script outside the app bundle so the Mapsim_BOT symlink
  # survives app updates/reinstalls.
  mkdir -p "$(dirname "$MENU_DEST")"
  cp "$0" "$MENU_DEST"
  chmod +x "$MENU_DEST"
}

# ---------------------------------------------------------------- install

detect_version() {
  if [ -n "${WANT_VERSION:-}" ]; then
    printf '%s\n' "$WANT_VERSION"
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

asset_name() {
  case "$OS" in
    Darwin)
      case "$ARCH" in
        arm64) echo "MapsimDashboard-macos-arm64.zip" ;;
        x86_64) echo "MapsimDashboard-macos-x64.zip" ;;
        *) echo "" ;;
      esac
      ;;
    Linux)
      case "$ARCH" in
        x86_64|amd64) echo "MapsimDashboard-linux-x64.tar.gz" ;;
        *) echo "" ;;
      esac
      ;;
  esac
}

download_and_install() {
  asset=$(asset_name)
  if [ -z "$asset" ]; then
    echo "error: unsupported system: $OS $ARCH" >&2
    return 1
  fi
  version=$(detect_version)
  base="https://github.com/$REPO/releases/download/$version"
  echo "installing $version ($asset) ..."
  tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' INT TERM
  curl -fsSL --retry 3 --retry-delay 2 -o "$tmp/$asset" "$base/$asset" || { rm -rf "$tmp"; return 1; }
  curl -fsSL --retry 3 --retry-delay 2 -o "$tmp/$asset.sha256" "$base/$asset.sha256" || { rm -rf "$tmp"; return 1; }
  if command -v sha256sum >/dev/null 2>&1; then
    (cd "$tmp" && sha256sum -c "$asset.sha256") || { rm -rf "$tmp"; return 1; }
  else
    (cd "$tmp" && shasum -a 256 -c "$asset.sha256") || { rm -rf "$tmp"; return 1; }
  fi
  stop_dashboard >/dev/null 2>&1 || true
  if [ "$OS" = "Darwin" ]; then
    mkdir -p "$HOME/Applications"
    rm -rf "$APP_ROOT"
    unzip -q "$tmp/$asset" -d "$HOME/Applications"
    xattr -dr com.apple.quarantine "$APP_ROOT" 2>/dev/null || true
  else
    rm -rf "$APP_ROOT"
    mkdir -p "$APP_ROOT"
    tar -xzf "$tmp/$asset" -C "$APP_ROOT"
    chmod +x "$BINARY"
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
  fi
  rm -rf "$tmp"
  trap - INT TERM
  write_wrapper
  install_self
  install_command_link
  echo "installed: $APP_ROOT"
}

# ---------------------------------------------------------------- service

service_installed() {
  case "$OS" in
    Darwin) [ -f "$HOME/Library/LaunchAgents/$LABEL.plist" ] ;;
    Linux)
      if [ "$(id -u)" -eq 0 ]; then
        [ -f "/etc/systemd/system/$SERVICE_NAME" ]
      else
        [ -f "$HOME/.config/systemd/user/$SERVICE_NAME" ]
      fi
      ;;
  esac
}

service_active() {
  case "$OS" in
    Darwin)
      launchctl print "gui/$(id -u)/$LABEL" >/dev/null 2>&1
      ;;
    Linux)
      if [ "$(id -u)" -eq 0 ]; then
        systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null
      else
        systemctl --user is-active --quiet "$SERVICE_NAME" 2>/dev/null
      fi
      ;;
  esac
}

service_install() {
  case "$OS" in
    Darwin)
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
      ;;
    Linux)
      unit_head="[Unit]
Description=Mapsim Live Dashboard (read-only MT5 dashboard)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
EnvironmentFile=-$ENV_FILE
ExecStart=$WRAPPER --no-browser
Restart=on-failure
RestartSec=5

[Install]"
      if [ "$(id -u)" -eq 0 ]; then
        unit="/etc/systemd/system/$SERVICE_NAME"
        printf '%s\nWantedBy=multi-user.target\n' "$unit_head" > "$unit"
        systemctl daemon-reload
        systemctl enable --now "$SERVICE_NAME"
      else
        unit="$HOME/.config/systemd/user/$SERVICE_NAME"
        mkdir -p "$HOME/.config/systemd/user"
        printf '%s\nWantedBy=default.target\n' "$unit_head" > "$unit"
        systemctl --user daemon-reload
        systemctl --user enable --now "$SERVICE_NAME"
        loginctl enable-linger "$USER" >/dev/null 2>&1 || \
          echo "note: run 'sudo loginctl enable-linger $USER' so the service survives logout"
      fi
      ;;
  esac
}

service_remove() {
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
        fi
      else
        unit="$HOME/.config/systemd/user/$SERVICE_NAME"
        if [ -f "$unit" ]; then
          systemctl --user disable --now "$SERVICE_NAME" 2>/dev/null || true
          rm -f "$unit"
          systemctl --user daemon-reload
        fi
      fi
      ;;
  esac
}

# ---------------------------------------------------------------- dashboard

stop_dashboard() {
  pid=$(dashboard_pid)
  if [ -z "$pid" ]; then
    echo "the dashboard is not running."
    rm -f "$PID_FILE"
    return 0
  fi
  kill "$pid" 2>/dev/null || true
  i=0
  while kill -0 "$pid" 2>/dev/null && [ "$i" -lt 10 ]; do
    sleep 1
    i=$((i + 1))
  done
  kill -9 "$pid" 2>/dev/null || true
  rm -f "$PID_FILE"
  echo "dashboard stopped (pid $pid)."
}

# start_dashboard <bind> <password> <port>
start_dashboard() {
  bind="$1"
  password="$2"
  port="$3"
  if [ -n "$(dashboard_pid)" ]; then
    echo "the dashboard is already running (pid $(dashboard_pid))."
    return 0
  fi
  if port_listening "$port"; then
    echo "error: port $port is already used by another program." >&2
    return 1
  fi
  write_env_file "$bind" "$password"
  mkdir -p "$CONFIG_DIR"
  nohup "$WRAPPER" --no-browser --port "$port" >>"$LOG_FILE" 2>&1 &
  echo $! > "$PID_FILE"
  i=0
  while [ "$i" -lt 20 ]; do
    if [ -n "$(dashboard_pid)" ] && dashboard_up "$port"; then
      echo "dashboard is up:"
      echo "  local   : http://127.0.0.1:$port/"
      if [ "$bind" = "0.0.0.0" ]; then
        if [ "$OS" = "Linux" ]; then
          ip=$(hostname -I 2>/dev/null | awk '{print $1}')
          [ -n "$ip" ] && echo "  remote  : http://$ip:$port/ (open the port in your firewall first)"
        else
          echo "  remote  : http://<this-computer-ip>:$port/ (allow the port through your firewall)"
        fi
        echo "  access  : user 'mapsim' / password '$password'"
      fi
      return 0
    fi
    sleep 1
    i=$((i + 1))
  done
  echo "error: the dashboard did not answer on port $port; see $LOG_FILE" >&2
  return 1
}

show_status() {
  echo "system    : $OS $ARCH"
  if is_installed; then
    echo "app       : installed ($APP_ROOT)"
  else
    echo "app       : not installed"
  fi
  pid=$(dashboard_pid)
  if [ -n "$pid" ]; then
    echo "dashboard : RUNNING (pid $pid)"
  else
    echo "dashboard : stopped"
  fi
  for p in 8765; do
    if dashboard_up "$p"; then
      echo "port $p   : dashboard answering (HTTP $(http_code "$p"))"
    elif port_listening "$p"; then
      echo "port $p   : busy (another program)"
    else
      echo "port $p   : free"
    fi
  done
  bind=$(current_bind)
  [ -n "$bind" ] && echo "bind      : $bind" || echo "bind      : 127.0.0.1 (default)"
  if service_installed; then
    if service_active; then
      echo "service   : installed, ACTIVE"
    else
      echo "service   : installed, not active"
    fi
  else
    echo "service   : not installed"
  fi
}

ask_default() {
  # ask_default <default> <prompt>
  d="$1"; p="$2"
  a=$(ask "$p [$d]")
  [ -n "$a" ] && echo "$a" || echo "$d"
}

# ---------------------------------------------------------------- expert advisor

EA_STATE="$CONFIG_DIR/ea-state.env"

ea_latest_version() {
  tags=$(curl -fsSL "https://api.github.com/repos/$REPO/tags?per_page=100" 2>/dev/null \
    | grep -o '"name": *"v[0-9][^"]*"' | sed 's/.*"name": *"\([^"]*\)"/\1/') || true
  if [ -z "$tags" ]; then
    echo ""
    return
  fi
  echo "$tags" | sed 's/^v//' | sort -t. -k1,1n -k2,2n -k3,3n | tail -n 1 | sed 's/^/v/'
}

ea_installed_version() {
  [ -f "$EA_STATE" ] && grep -E '^EA_VERSION=' "$EA_STATE" | tail -n 1 | cut -d= -f2- || true
}

ea_installed_path() {
  [ -f "$EA_STATE" ] && grep -E '^EA_MQL5=' "$EA_STATE" | tail -n 1 | cut -d= -f2- || true
}

# Print detected MT5 MQL5 folders, one per line.
ea_find_mql5() {
  case "$OS" in
    Darwin)
      base="$HOME/Library/Application Support/net.metaquotes.wine.metatrader5/drive_c"
      ;;
    Linux)
      base="$HOME/.wine/drive_c"
      ;;
  esac
  if [ -n "${base:-}" ] && [ -d "$base" ]; then
    find "$base" -maxdepth 6 -type d -name MQL5 2>/dev/null
  fi
}

# Pick the right .ex5 for this OS from the extracted package root.
ea_pick_expert() {
  src="$1"
  case "$OS" in
    Darwin) pref="mcos" ;;
    *) pref="win" ;;
  esac
  all=$(find "$src" -name '*.ex5' 2>/dev/null | sort)
  if [ -z "$all" ]; then
    echo ""
    return
  fi
  picked=$(printf '%s\n' "$all" | grep -i "$pref" | head -n 1 || true)
  if [ -z "$picked" ]; then
    picked=$(printf '%s\n' "$all" | head -n 1)
    echo "note: no '$pref' build found - using $(basename "$picked")" >&2
  fi
  echo "$picked"
}

ea_install() {
  if ! command -v unzip >/dev/null 2>&1; then
    echo "error: 'unzip' is required but was not found." >&2
    return 1
  fi
  version="${1:-}"
  if [ -z "$version" ]; then
    version=$(ea_latest_version)
  fi
  if [ -z "$version" ]; then
    echo "error: could not determine the latest Expert version - check your internet connection." >&2
    return 1
  fi

  current=$(ea_installed_version)
  mql5_list=$(ea_find_mql5)
  if [ -z "$mql5_list" ]; then
    echo "error: no MetaTrader 5 data folder (MQL5) was found." >&2
    case "$OS" in
      Darwin) echo "hint: install MT5 for macOS, run it once, then retry." >&2 ;;
      Linux) echo "hint: install MT5 under Wine (default: ~/.wine/drive_c/Program Files/MetaTrader 5), run it once, then retry." >&2 ;;
    esac
    return 1
  fi

  echo "latest Expert version: $version"
  [ -n "$current" ] && echo "installed version    : $current"
  echo "MQL5 folders found:"
  n=1
  old_ifs=$IFS
  IFS='
'
  for d in $mql5_list; do
    echo "  $n) $d"
    n=$((n + 1))
  done
  IFS=$old_ifs
  total=$((n - 1))
  if [ "$total" -gt 1 ]; then
    sel=$(ask_default "1" "choose 1-$total (or 'a' for all)")
  else
    sel="1"
  fi

  echo "downloading Expert $version ..."
  tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' INT TERM
  if ! curl -fsSL --retry 3 --retry-delay 2 -o "$tmp/ea.zip" "https://github.com/$REPO/archive/refs/tags/$version.zip"; then
    rm -rf "$tmp"
    echo "error: download failed." >&2
    return 1
  fi
  unzip -q "$tmp/ea.zip" -d "$tmp/src"
  root=$(find "$tmp/src" -maxdepth 1 -mindepth 1 -type d | head -n 1)
  pkg="$root/Expert/Meta_trader_5"
  if [ ! -d "$pkg" ]; then
    rm -rf "$tmp"
    echo "error: the $version package has no Expert folder." >&2
    return 1
  fi
  ex5=$(ea_pick_expert "$pkg")
  if [ -z "$ex5" ]; then
    rm -rf "$tmp"
    echo "error: no .ex5 Expert file in the $version package." >&2
    return 1
  fi
  include_zip=$(find "$pkg" -path '*/Include/*' -name '*.zip' | head -n 1 || true)

  installed_to=""
  n=1
  old_ifs=$IFS
  IFS='
'
  for d in $mql5_list; do
    if [ "$sel" != "a" ] && [ "$sel" != "A" ] && [ "$sel" != "$n" ]; then
      n=$((n + 1))
      continue
    fi
    n=$((n + 1))
    mkdir -p "$d/Experts" "$d/Libraries" "$d/Include" "$d/Files/Mapsim_Assistance_Bot/Sounds"
    cp -f "$ex5" "$d/Experts/"
    [ -f "$pkg/Libraries/sqlite3.dll" ] && cp -f "$pkg/Libraries/sqlite3.dll" "$d/Libraries/"
    if [ -n "$include_zip" ]; then
      unzip -o -q "$include_zip" -d "$d/Include/"
    fi
    if [ -d "$pkg/Sounds/Mapsim_Assistance_Bot/Sounds" ]; then
      cp -f "$pkg/Sounds/Mapsim_Assistance_Bot/Sounds/"*.wav "$d/Files/Mapsim_Assistance_Bot/Sounds/" 2>/dev/null || true
    fi
    installed_to="$installed_to $d"
  done
  IFS=$old_ifs
  rm -rf "$tmp"
  trap - INT TERM

  mkdir -p "$CONFIG_DIR"
  {
    echo "EA_VERSION=$version"
    echo "EA_FILE=$(basename "$ex5")"
    echo "EA_MQL5=$installed_to"
    echo "EA_UPDATED=$(date +%F)"
  } > "$EA_STATE"
  echo "installed: $(basename "$ex5") ($version) ->$installed_to"
  echo "next steps in MetaTrader 5:"
  echo "  1) restart MetaTrader 5"
  echo "  2) allow DLL imports in the EA options"
  echo "  3) attach the Mapsim Assistance Bot Expert to your chart"
  echo "  4) enter your license (from the Mapsim Bot in Telegram)"
}

menu_ea_install() {
  latest=$(ea_latest_version)
  if [ -z "$latest" ]; then
    echo "error: could not reach GitHub to find the latest Expert version." >&2
    return
  fi
  cur=$(ea_installed_version)
  if [ -n "$cur" ] && [ "$cur" = "$latest" ]; then
    a=$(ask_default "y" "version $cur is already installed - reinstall? (y/n)")
    [ "$a" != "y" ] && [ "$a" != "Y" ] && return
  fi
  ea_install "$latest"
}

menu_ea_status() {
  cur=$(ea_installed_version)
  latest=$(ea_latest_version)
  if [ -z "$cur" ]; then
    echo "Expert Advisor: not installed through $MENU_CMD"
  else
    echo "installed version : $cur"
    p=$(ea_installed_path)
    [ -n "$p" ] && echo "installed into    :$p"
    [ -f "$EA_STATE" ] && grep -E '^EA_UPDATED=' "$EA_STATE" | sed 's/^EA_/last /'
  fi
  if [ -n "$latest" ]; then
    echo "latest version    : $latest"
    if [ -n "$cur" ] && [ "$cur" != "$latest" ]; then
      a=$(ask_default "y" "a newer version is available - install it now? (y/n)")
      if [ "$a" = "y" ] || [ "$a" = "Y" ]; then
        ea_install "$latest"
      fi
    fi
  else
    echo "latest version    : (could not check - no internet?)"
  fi
}

# ---------------------------------------------------------------- uninstall

uninstall_everything() {
  service_remove
  remove_command_link
  stop_dashboard >/dev/null 2>&1 || true
  case "$OS" in
    Darwin)
      rm -rf "$APP_ROOT"
      rm -rf "$HOME/Library/Application Support/MapsimDashboard"
      ;;
    Linux)
      rm -rf "$APP_ROOT"
      rm -f "$HOME/.local/share/applications/mapsim-dashboard.desktop"
      ;;
  esac
  rm -f "$WRAPPER"
  rm -f "$MENU_DEST"
  rmdir "$HOME/.local/share/MapsimDashboard" 2>/dev/null || true
  rm -rf "$CONFIG_DIR"
  echo "Mapsim Live Dashboard removed completely (MT5 and the EA were not touched)."
}

# ---------------------------------------------------------------- interactive

prompt_password() {
  # Reuse existing password on empty input; otherwise require 8+ chars twice.
  existing=$(current_password)
  while true; do
    if [ -n "$existing" ]; then
      printf 'password (press Enter to keep the current one): ' >&2
    else
      printf 'password (min 8 characters): ' >&2
    fi
    stty -echo 2>/dev/null || true
    IFS= read -r p1 || p1=""
    stty echo 2>/dev/null || true
    echo "" >&2
    if [ -z "$p1" ] && [ -n "$existing" ]; then
      echo "$existing"
      return
    fi
    if [ -z "$p1" ]; then
      p1=$(gen_password)
      echo "generated password: $p1" >&2
      echo "$p1"
      return
    fi
    if [ "${#p1}" -lt 8 ]; then
      echo "too short - at least 8 characters." >&2
      continue
    fi
    printf 'repeat password: ' >&2
    stty -echo 2>/dev/null || true
    IFS= read -r p2 || p2=""
    stty echo 2>/dev/null || true
    echo "" >&2
    if [ "$p1" != "$p2" ]; then
      echo "passwords do not match, try again." >&2
      continue
    fi
    echo "$p1"
    return
  done
}

choose_port() {
  p=$(ask_default "8765" "port")
  while true; do
    if ! port_listening "$p"; then
      echo "$p"
      return
    fi
    echo "port $p is busy." >&2
    p=$(ask_default "$((p + 1))" "choose another port")
  done
}

menu_start() {
  if ! is_installed; then
    echo "the dashboard is not installed yet - install it first (menu 4)."
    return
  fi
  echo "how should the dashboard be reachable?"
  echo "  1) local only   (this computer, http://127.0.0.1)"
  echo "  2) internet     (any device, protected by a password)"
  m=$(ask_default "1" "choose 1 or 2")
  port=$(choose_port)
  if [ "$m" = "2" ]; then
    password=$(prompt_password)
    start_dashboard "0.0.0.0" "$password" "$port"
  else
    start_dashboard "127.0.0.1" "$(current_password || echo "")" "$port"
  fi
}

menu_configure() {
  if ! is_installed; then
    echo "the dashboard is not installed yet - install it first (menu 4)."
    return
  fi
  echo "current bind: $(current_bind || echo 127.0.0.1)"
  echo "  1) local only"
  echo "  2) internet (password required)"
  m=$(ask_default "1" "choose 1 or 2")
  running=""
  [ -n "$(dashboard_pid)" ] && running=1
  if [ "$m" = "2" ]; then
    password=$(prompt_password)
    write_env_file "0.0.0.0" "$password"
    echo "saved. access: user 'mapsim' / password '$password'"
  else
    write_env_file "127.0.0.1" "$(current_password || echo "$(gen_password)")"
    echo "saved: local only."
  fi
  if [ -n "$running" ]; then
    a=$(ask_default "y" "restart the dashboard now? (y/n)")
    if [ "$a" = "y" ] || [ "$a" = "Y" ]; then
      stop_dashboard
      port=$(choose_port)
      start_dashboard "$(current_bind)" "$(current_password)" "$port"
    fi
  fi
}

menu_service_install() {
  if ! is_installed; then
    echo "the dashboard is not installed yet - install it first (menu 4)."
    return
  fi
  service_install
  echo "service installed: the dashboard now starts automatically at boot/login."
}

menu_service_remove() {
  if ! service_installed; then
    echo "no service is installed."
    return
  fi
  a=$(ask_default "y" "remove the auto-start service? (y/n)")
  if [ "$a" = "y" ] || [ "$a" = "Y" ]; then
    service_remove
    echo "service removed (the app itself stays installed)."
  fi
}

menu_uninstall() {
  echo "this removes the dashboard app, config, service and commands."
  echo "nothing is changed in MetaTrader 5 or in the Expert Advisor."
  a=$(ask_default "n" "are you sure? type y to confirm")
  if [ "$a" = "y" ] || [ "$a" = "Y" ]; then
    uninstall_everything
  else
    echo "cancelled."
  fi
}

menu_main() {
  while true; do
    echo ""
    echo "=== Mapsim BOT control center ==="
    pid=$(dashboard_pid)
    if [ -n "$pid" ]; then st="running (pid $pid)"; else st="stopped"; fi
    if is_installed; then app="installed"; else app="not installed"; fi
    echo "dashboard: $st   app: $app"
    echo ""
    echo "  1) Status"
    echo "  2) Start dashboard"
    echo "  3) Stop dashboard"
    echo "  4) Install / update dashboard"
    echo "  5) Enable auto-start service"
    echo "  6) Remove auto-start service"
    echo "  7) Access mode / password"
    echo "  8) Uninstall everything"
    echo "  9) Expert Advisor: install / update"
    echo " 10) Expert Advisor: version check"
    echo " 11) Exit"
    echo ""
    printf 'choose 1-11: '
    if ! IFS= read -r c; then
      echo ""
      echo "bye."
      exit 0
    fi
    case "$c" in
      1) show_status ;;
      2) menu_start ;;
      3) stop_dashboard ;;
      4) download_and_install ;;
      5) menu_service_install ;;
      6) menu_service_remove ;;
      7) menu_configure ;;
      8) menu_uninstall ;;
      9) menu_ea_install ;;
      10) menu_ea_status ;;
      11) echo "bye."; exit 0 ;;
      *) echo "please choose 1-11." ;;
    esac
  done
}

# ---------------------------------------------------------------- bootstrap

bootstrap() {
  public=0
  service=0
  launch=1
  for arg in "$@"; do
    case "$arg" in
      --public) public=1 ;;
      --service) service=1 ;;
      --no-launch) launch=0 ;;
      --version=*) WANT_VERSION="${arg#--version=}" ;;
      --remove-service) service_remove; echo "service removed."; exit 0 ;;
      --uninstall) uninstall_everything; exit 0 ;;
      *) echo "error: unknown option: $arg" >&2; exit 2 ;;
    esac
  done

  need curl
  need uname
  if ! is_installed; then
    download_and_install || exit 1
  else
    write_wrapper
    install_self
    install_command_link
  fi

  if [ "$public" -eq 1 ]; then
    if [ -n "${WANT_PASSWORD:-}" ]; then password="$WANT_PASSWORD";
    elif [ -n "${MAPSIM_DASHBOARD_PASSWORD:-}" ]; then password="$MAPSIM_DASHBOARD_PASSWORD";
    else password=$(gen_password); fi
    write_env_file "0.0.0.0" "$password"
    echo "public access:"
    echo "  user     : mapsim"
    echo "  password : $password"
    echo "  saved in : $ENV_FILE"
  fi

  if [ "$service" -eq 1 ]; then
    service_install
    echo "service installed: starts automatically at boot/login."
  elif [ "$launch" -eq 1 ]; then
    if [ -z "$(dashboard_pid)" ]; then
      echo ""
      echo "starting the dashboard (local mode) ..."
      port=8765
      if port_listening "$port" && ! dashboard_up "$port"; then
        port=8766
        echo "note: port 8765 is busy, using $port."
      fi
      bind=$(current_bind); [ -z "$bind" ] && bind="127.0.0.1"
      password=$(current_password); [ -z "$password" ] && password=$(gen_password)
      start_dashboard "$bind" "$password" "$port"
    else
      echo "the dashboard is already running (pid $(dashboard_pid))."
    fi
  fi

  echo ""
  echo "done. From now on manage everything with:  $MENU_CMD"
}

# ---------------------------------------------------------------- entrypoint

case "${1:-}" in
  --bootstrap)
    shift
    bootstrap "$@"
    ;;
  --status)
    show_status
    ;;
  --stop)
    stop_dashboard
    ;;
  ""|-i|--menu)
    menu_main
    ;;
  *)
    echo "usage: $MENU_CMD [--bootstrap ...] [--status] [--stop]" >&2
    exit 2
    ;;
esac
