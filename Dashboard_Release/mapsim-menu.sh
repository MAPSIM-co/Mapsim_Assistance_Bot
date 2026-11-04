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
PORT_FILE="$CONFIG_DIR/dashboard.port"
LOG_FILE="$CONFIG_DIR/dashboard.log"
# Logs are capped so a long-running dashboard never fills the disk: past this
# size only the newest lines are kept. 256 KB holds thousands of startup lines.
LOG_MAX_BYTES=262144
LOG_KEEP_LINES=200
WRAPPER="$HOME/.local/bin/mapsim-dashboard"
LICENSE_DIR="$HOME/.mapsim"
LICENSE_FILE="$LICENSE_DIR/dashboard.license"
LICENSE_AUTH_FILE="$LICENSE_DIR/dashboard.auth"
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

# ---------------------------------------------------------------- ui (colors, boxes, title)

ESC=$(printf '\033')
RED="$ESC[0;31m"
GREEN="$ESC[0;32m"
YELLOW="$ESC[1;33m"
BLUE="$ESC[0;34m"
CYAN="$ESC[0;36m"
MAGENTA="$ESC[0;35m"
WHITE="$ESC[1;37m"
NC="$ESC[0m"

msg_ok()   { printf '%b\n' "${GREEN}✓ $*${NC}"; }
msg_info() { printf '%b\n' "${BLUE}ℹ $*${NC}"; }
msg_warn() { printf '%b\n' "${YELLOW}⚠ $*${NC}"; }
msg_err()  { printf '%b\n' "${RED}✗ $*${NC}"; }

disk_summary() {
  df -h "$HOME" 2>/dev/null | awk 'NR==2 {print $4 " free of " $2 " (" $5 " used)"}'
}

disk_usage_pct() {
  df -Pk "$HOME" 2>/dev/null | awk 'NR==2 {gsub("%", "", $5); print $5}'
}

hline() {
  n=$1
  out=''
  while [ "$n" -gt 0 ]; do out="${out}─"; n=$((n - 1)); done
  printf '%s' "$out"
}

ui_top()    { printf '%s┌%s┐%s\n' "$CYAN" "$(hline 79)" "$NC"; }
ui_sep()    { printf '%s├%s┤%s\n' "$CYAN" "$(hline 79)" "$NC"; }
ui_bottom() { printf '%s└%s┘%s\n' "$CYAN" "$(hline 79)" "$NC"; }

# ui_row LABEL PLAIN [COLORED]  -> one boxed row; PLAIN is the color-stripped
# text used only to compute padding so the right border stays aligned.
ui_row() {
  label=$1
  plain=$2
  colored=${3:-"$2"}
  body=$(printf '%-10s: %s' "$label" "$colored")
  plainbody=$(printf '%-10s: %s' "$label" "$plain")
  pad=$((79 - 2 - ${#plainbody}))
  [ "$pad" -lt 0 ] && pad=0
  printf '%s│%s  %s%*s%s│%s\n' "$CYAN" "$NC" "$body" "$pad" '' "$CYAN" "$NC"
}

ui_item() {
  num=$1
  text=$2
  printf '%s│%s   %s%2s%s - %s%-71s%s%s│%s\n' "$CYAN" "$NC" "$MAGENTA" "$num" "$NC" "$WHITE" "$text" "$NC" "$CYAN" "$NC"
}

show_title() {
  printf '\n%b\n' "${MAGENTA}    ██   ██  █████  ██████   ██████ ███████ ██   ██   █████   █████  ███████${NC}"
  printf '%b\n'   "${MAGENTA}    ███ ███ ██   ██ ██   ██ ██      ██      ███ ███  ██   ██ ██   ██   ███  ${NC}"
  printf '%b\n'   "${MAGENTA}    ██ █ ██ ███████ ██████   █████  ███████ ██ █ ██  ██████  ██   ██   ███  ${NC}"
  printf '%b\n'   "${MAGENTA}    ██   ██ ██   ██ ██           ██ ██      ██   ██  ██   ██ ██   ██   ███  ${NC}"
  printf '%b\n'   "${MAGENTA}    ██   ██ ██   ██ ██      ██████  ███████ ██   ██  ██████   █████    ███  ${NC}"
}

is_installed() { [ -x "$BINARY" ]; }

# The dashboard login is the license username/password, so the old generated
# access password is gone. The encoder lives in the app, not in this menu.

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

# True when the process is still running. A process started by this menu is
# our child, so after it exits it stays a zombie until the shell reaps it and
# "kill -0" keeps answering yes; the stat check avoids a pointless 10s wait.
process_alive() {
  [ -n "$1" ] || return 1
  st=$(ps -o stat= -p "$1" 2>/dev/null | tr -d ' ')
  case "$st" in
    ''|*Z*) return 1 ;;
  esac
  return 0
}

# PID of our dashboard process, or empty.
dashboard_pid() {
  if [ -f "$PID_FILE" ]; then
    pid=$(cat "$PID_FILE" 2>/dev/null || true)
    if process_alive "$pid"; then
      echo "$pid"
      return
    fi
  fi
  pgrep -f "$BINARY" 2>/dev/null | head -n 1 || true
}

# Every process of our dashboard: the pid file first, then anything running the
# installed binary. PyInstaller --onefile runs a bootloader parent plus a child,
# so stopping a single pid can leave an orphan holding the port.
dashboard_pids() {
  seen=""
  if [ -f "$PID_FILE" ]; then
    p=$(cat "$PID_FILE" 2>/dev/null || true)
    case "$p" in
      ''|*[!0-9]*) : ;;
      *)
        if process_alive "$p"; then
          seen="$p"
          printf '%s\n' "$p"
        fi
        ;;
    esac
  fi
  for p in $(pgrep -f "$BINARY" 2>/dev/null || true); do
    [ "$p" = "$$" ] && continue
    case " $seen " in *" $p "*) continue ;; esac
    process_alive "$p" || continue
    seen="$seen $p"
    printf '%s\n' "$p"
  done
}

# Log that the packaged app writes itself when it runs without a console
# (macOS .app double-click / Windows). The menu log is separate.
app_log_file() {
  case "$OS" in
    Darwin) printf '%s\n' "$HOME/Library/Application Support/MapsimDashboard/dashboard.log" ;;
    *) printf '%s\n' "$HOME/.local/share/MapsimDashboard/dashboard.log" ;;
  esac
}

# Keep logs useful but small: past LOG_MAX_BYTES only the last lines survive.
trim_log() {
  f=$1
  [ -f "$f" ] || return 0
  bytes=$(wc -c <"$f" 2>/dev/null | tr -d ' ')
  case "$bytes" in ''|*[!0-9]*) return 0 ;; esac
  if [ "$bytes" -gt "$LOG_MAX_BYTES" ]; then
    tail -n "$LOG_KEEP_LINES" "$f" > "$f.mapsim-tmp" 2>/dev/null && mv "$f.mapsim-tmp" "$f"
  fi
  return 0
}

trim_logs() {
  trim_log "$LOG_FILE"
  trim_log "$LOG_FILE.err"
  trim_log "$(app_log_file)"
}

# wait_dashboard <port> [seconds] - wait until our dashboard answers.
wait_dashboard() {
  wport=$1
  wleft=${2:-20}
  wi=0
  while [ "$wi" -lt "$wleft" ]; do
    if dashboard_up "$wport"; then return 0; fi
    wi=$((wi + 1))
    sleep 1
  done
  return 1
}

current_bind() {
  [ -f "$ENV_FILE" ] && grep -E '^MAPSIM_DASHBOARD_BIND=' "$ENV_FILE" | tail -n 1 | cut -d= -f2 || true
}

current_port() {
  if [ -f "$PORT_FILE" ]; then
    p=$(tail -n 1 "$PORT_FILE")
    case "$p" in
      ''|*[!0-9]*) : ;;
      *) echo "$p"; return ;;
    esac
  fi
  echo "8765"
}

# Address of this machine that a browser on another device can reach.
host_ip() {
  case "$OS" in
    Darwin)
      for i in en0 en1 en2; do
        ip=$(ipconfig getifaddr "$i" 2>/dev/null || true)
        [ -n "$ip" ] && { printf '%s\n' "$ip"; return; }
      done
      ;;
    *)
      ips=$(hostname -I 2>/dev/null | tr ' ' '\n' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | grep -v '^127\.' || true)
      # Prefer a public address over docker/private interfaces.
      ip=$(printf '%s\n' "$ips" | grep -vE '^(10\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[01])\.)' | head -n 1 || true)
      [ -z "$ip" ] && ip=$(printf '%s\n' "$ips" | head -n 1 || true)
      if [ -z "$ip" ]; then
        ip=$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for (i = 1; i <= NF; i++) if ($i == "src") { print $(i + 1); exit }}')
      fi
      [ -n "$ip" ] && printf '%s\n' "$ip"
      ;;
  esac
}

# URL to open in a browser for the current bind/port.
access_url() {
  port=$(current_port)
  if [ "$(current_bind)" = "0.0.0.0" ]; then
    ip=$(host_ip)
    if [ -n "$ip" ]; then
      printf 'http://%s:%s/\n' "$ip" "$port"
    else
      printf 'http://<this-pc-ip>:%s/\n' "$port"
    fi
  else
    printf 'http://127.0.0.1:%s/\n' "$port"
  fi
}

current_snapshot() {
  v=$([ -f "$ENV_FILE" ] && grep -E '^MAPSIM_SNAPSHOT=' "$ENV_FILE" | tail -n 1 | cut -d= -f2- || true)
  case "$v" in
    \'*\') v=${v#\'}; v=${v%\'} ;;
  esac
  printf '%s\n' "$v"
}

# Wine prefixes where MetaTrader 5 can live, one per line.
mt5_bases() {
  case "$OS" in
    Darwin)
      [ -d "$HOME/Library/Application Support/net.metaquotes.wine.metatrader5/drive_c" ] \
        && echo "$HOME/Library/Application Support/net.metaquotes.wine.metatrader5/drive_c"
      ;;
    Linux)
      [ -d "$HOME/.wine/drive_c" ] && echo "$HOME/.wine/drive_c"
      [ -d "$HOME/.var/app/net.metaquotes.wine.metatrader5/drive_c" ] && echo "$HOME/.var/app/net.metaquotes.wine.metatrader5/drive_c"
      for d in "$HOME"/*/drive_c; do
        [ -d "$d" ] && echo "$d"
      done
      ;;
  esac
}

# Newest MapsimLive/snapshot.json across the detected MT5 data folders.
# A stored MAPSIM_SNAPSHOT value wins while the file it points at still exists.
find_snapshot() {
  stored=$(current_snapshot)
  if [ -n "$stored" ] && [ -f "$stored" ]; then
    echo "$stored"
    return
  fi
  list=$(ea_find_mql5 2>/dev/null)
  [ -z "$list" ] && return
  best=""
  best_t=-1
  old_ifs=$IFS
  IFS='
'
  for d in $list; do
    cand="$d/Files/MapsimLive/snapshot.json"
    if [ -f "$cand" ]; then
      t=$(stat -c %Y "$cand" 2>/dev/null || stat -f %m "$cand" 2>/dev/null || echo 0)
      case "$t" in ''|*[!0-9]*) t=0 ;; esac
      if [ "$t" -gt "$best_t" ]; then
        best="$cand"
        best_t=$t
      fi
    fi
  done
  IFS=$old_ifs
  [ -n "$best" ] && echo "$best"
}

file_age() {
  t=$(stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null || echo 0)
  case "$t" in ''|*[!0-9]*) t=0 ;; esac
  [ "$t" -le 0 ] && { echo "unknown age"; return; }
  now=$(date +%s)
  d=$((now - t))
  [ "$d" -lt 0 ] && d=0
  if [ "$d" -lt 90 ]; then
    echo "${d}s ago"
  elif [ "$d" -lt 5400 ]; then
    echo "$((d / 60))m ago"
  else
    echo "$((d / 3600))h ago"
  fi
}

# Pick the Wine prefix that holds a Windows path.
# $1 = optional path relative to drive_c; used to choose between prefixes.
pick_wine_prefix() {
  rel=${1:-}
  list=$(mt5_bases 2>/dev/null | sed 's#/drive_c/*$##' || true)
  if [ -n "$rel" ] && [ -n "$list" ]; then
    matches=""
    old_ifs=$IFS
    IFS='
'
    for d in $list; do
      if [ -e "$d/drive_c/$rel" ]; then
        matches="${matches}${d}
"
      fi
    done
    IFS=$old_ifs
    if [ -n "$matches" ]; then
      list=$(printf '%s' "$matches")
    fi
  fi
  count=$(printf '%s\n' "$list" | grep -c .)
  if [ "$count" -eq 1 ]; then
    printf '%s\n' "$list"
    return 0
  fi
  if [ "$count" -gt 1 ]; then
    msg_info "Wine prefixes found:" >&2
    i=1
    old_ifs=$IFS
    IFS='
'
    for d in $list; do
      printf '  %s) %s\n' "$i" "$d" >&2
      i=$((i + 1))
    done
    IFS=$old_ifs
    printf 'choose 1-%s (0 = back): ' "$count" >&2
    IFS= read -r pick || return 1
    if wants_back "$pick"; then
      return 1
    fi
    i=1
    old_ifs=$IFS
    IFS='
'
    for d in $list; do
      if [ "$i" = "$pick" ]; then
        IFS=$old_ifs
        printf '%s\n' "$d"
        return 0
      fi
      i=$((i + 1))
    done
    IFS=$old_ifs
    echo "error: invalid choice." >&2
    return 1
  fi
  printf 'Wine prefix folder that contains drive_c, e.g. ~/mt5 (0 = back): ' >&2
  IFS= read -r dir || return 1
  dir=$(printf '%s' "$dir" | sed "s/^'//; s/'$//")
  if wants_back "$dir"; then
    return 1
  fi
  if [ ! -d "$dir/drive_c" ]; then
    echo "error: no drive_c inside: $dir" >&2
    return 1
  fi
  printf '%s\n' "$dir"
}

# Turn what the user typed into the snapshot.json path. Accepts the file
# itself, an MT5 folder (native or Windows style like C:\Program Files\MetaTrader 5),
# an MQL5 folder, a drive_c folder or a whole Wine prefix.
resolve_snapshot_input() {
  raw=$1
  raw=$(printf '%s' "$raw" | sed "s/^[[:space:]]*//; s/[[:space:]]*$//; s/^'//; s/'$//; s/^\"//; s/\"$//")
  [ -z "$raw" ] && return 1
  case "$raw" in
    [A-Za-z]:[\\/]*|[A-Za-z]:)
      drive=$(printf '%s' "$raw" | cut -c1 | tr 'A-Z' 'a-z')
      rest=$(printf '%s' "$raw" | cut -c3- | sed 's#\\#/#g; s#^/##')
      prefix=$(pick_wine_prefix "$rest") || return 1
      base="$prefix/drive_$drive"
      [ -n "$rest" ] && base="$base/$rest"
      ;;
    *)
      base=$raw
      ;;
  esac
  base=$(printf '%s' "$base" | sed 's#/*$##')
  if [ -f "$base" ]; then
    printf '%s\n' "$base"
    return 0
  fi
  if [ -d "$base" ]; then
    found=$(find "$base" -maxdepth 9 -type f -path '*/MapsimLive/snapshot.json' 2>/dev/null | head -n 1)
    if [ -n "$found" ]; then
      printf '%s\n' "$found"
      return 0
    fi
    case "$base" in
      */MQL5)
        cand="$base/Files/MapsimLive/snapshot.json"
        ;;
      *)
        if [ -d "$base/MQL5" ]; then
          cand="$base/MQL5/Files/MapsimLive/snapshot.json"
        elif [ -d "$base/drive_c" ]; then
          cand="$base/drive_c/Program Files/MetaTrader 5/MQL5/Files/MapsimLive/snapshot.json"
        else
          cand="$base/MQL5/Files/MapsimLive/snapshot.json"
        fi
        ;;
    esac
    printf '%s\n' "$cand"
    return 0
  fi
  printf '%s\n' "$base"
  return 0
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

# write_env_file <bind> [snapshot]
# snapshot omitted -> keep the stored path or auto-detect it; "" -> no path.
write_env_file() {
  bind="$1"
  snap=${2-__auto__}
  if [ "$snap" = "__auto__" ]; then
    snap=$(current_snapshot)
    if [ -z "$snap" ] || [ ! -f "$snap" ]; then
      snap=$(find_snapshot)
    fi
  fi
  mkdir -p "$CONFIG_DIR"
  chmod 700 "$CONFIG_DIR"
  {
    echo "MAPSIM_DASHBOARD_BIND=$bind"
    if [ -n "$snap" ]; then
      # quoted: MT5 paths contain spaces, and the launcher sources this file
      echo "MAPSIM_SNAPSHOT='$snap'"
    fi
  } > "$ENV_FILE"
  chmod 600 "$ENV_FILE"
}

# ---------------------------------------------------------------- license

license_saved() {
  [ -s "$LICENSE_FILE" ] && [ -s "$LICENSE_AUTH_FILE" ]
}

# 0600 temp file for one license check; prints its path.
license_tmp() {
  f=$(mktemp "${TMPDIR:-/tmp}/mapsim-license.XXXXXX") || return 1
  chmod 600 "$f" 2>/dev/null || true
  printf '%s\n' "$f"
}

# The check result goes to a file, not stdout: windowed builds (Windows) have
# no console, so the menu could never read a printed answer there.
# license_run <license-file> <auth-file> <out-file>
license_run() {
  snap=$(current_snapshot)
  [ -z "$snap" ] && snap=$(find_snapshot)
  if [ -n "$snap" ] && [ -f "$snap" ]; then
    "$BINARY" --license-check --license-file "$1" --auth-file "$2" \
      --file "$snap" --no-browser --license-out "$3" >/dev/null 2>&1
  else
    "$BINARY" --license-check --license-file "$1" --auth-file "$2" \
      --no-browser --license-out "$3" >/dev/null 2>&1
  fi
  return 0
}

# The installed build must know --license-check (older builds do not).
license_supported() {
  [ -x "$BINARY" ] || return 1
  out=$(license_tmp) || return 1
  "$BINARY" --license-check --license-file "/nonexistent/mapsim.license" \
    --auth-file "/nonexistent/mapsim.auth" --no-browser --license-out "$out" \
    >/dev/null 2>&1 || true
  found=0
  grep -q '^status=' "$out" 2>/dev/null && found=1
  rm -f "$out"
  [ "$found" -eq 1 ]
}

license_check_saved() {
  out=$(license_tmp) || return 1
  license_run "$LICENSE_FILE" "$LICENSE_AUTH_FILE" "$out"
  cat "$out" 2>/dev/null
  rm -f "$out"
  return 0
}

# Validate values before they are written anywhere; the password only touches
# a 0600 temp file, never the process list.
# license_check_values <license> <username> <password>
license_check_values() {
  lic=$(license_tmp) || return 1
  auth=$(license_tmp) || { rm -f "$lic"; return 1; }
  out=$(license_tmp) || { rm -f "$lic" "$auth"; return 1; }
  printf '%s\n' "$1" > "$lic"
  printf '%s\n%s\n' "$2" "$3" > "$auth"
  license_run "$lic" "$auth" "$out"
  cat "$out" 2>/dev/null
  rm -f "$lic" "$auth" "$out"
  return 0
}

license_field() {
  printf '%s\n' "$1" | grep "^$2=" | head -n 1 | cut -d= -f2-
}

license_save() {
  mkdir -p "$LICENSE_DIR"
  chmod 700 "$LICENSE_DIR"
  printf '%s\n' "$1" > "$LICENSE_FILE"
  chmod 600 "$LICENSE_FILE"
  printf '%s\n%s\n' "$2" "$3" > "$LICENSE_AUTH_FILE"
  chmod 600 "$LICENSE_AUTH_FILE"
}

license_show_result() {
  # $1 = raw --license-check output
  status=$(license_field "$1" status)
  msg=$(license_field "$1" message)
  user=$(license_field "$1" user)
  account=$(license_field "$1" account)
  expiry=$(license_field "$1" expiry)
  days=$(license_field "$1" days_left)
  warning=$(license_field "$1" warning)
  [ -n "$user" ] && echo "  user    : $user"
  [ -n "$account" ] && echo "  account : $account"
  [ -n "$expiry" ] && echo "  expires : $expiry ($days day(s) left)"
  [ -n "$msg" ] && echo "  status  : $status - $msg"
  [ -n "$warning" ] && echo "  warning : $warning"
  return 0
}

# Interactive gate for anything that starts the dashboard. Offers to enter a
# license when none is saved, and refuses when the license is invalid.
license_prepare() {
  if ! license_supported; then
    echo "the installed dashboard build does not support the license yet."
    echo "update it from menu 4 (Install / update dashboard), then enter the license (menu 13)."
    return 1
  fi
  if ! license_saved; then
    echo "a valid Mapsim license is required to run the dashboard."
    a=$(ask_default "y" "enter the license now? (y/n, 0 = back)")
    if wants_back "$a"; then
      return 1
    fi
    if [ "$a" != "y" ] && [ "$a" != "Y" ]; then
      echo "the dashboard was not started - the license is required (menu 13)."
      return 1
    fi
    menu_license_enter || return 1
  fi
  out=$(license_check_saved)
  if [ "$(license_field "$out" status)" != "ACTIVE" ]; then
    echo "the license check failed:"
    license_show_result "$out"
    echo "the dashboard was not started. Fix the license in menu 13."
    return 1
  fi
  warning=$(license_field "$out" warning)
  if [ -n "$warning" ]; then
    echo "warning: $warning"
  fi
  return 0
}

# Non-interactive variant used by start_dashboard itself.
license_ready() {
  license_supported || return 1
  license_saved || return 1
  out=$(license_check_saved)
  [ "$(license_field "$out" status)" = "ACTIVE" ]
}

menu_license_enter() {
  if ! license_supported; then
    echo "the installed dashboard build does not support the license yet."
    echo "update it from menu 4 (Install / update dashboard), then try again."
    return 1
  fi
  printf 'paste your license (0 = back): ' >&2
  IFS= read -r lic || return 1
  if wants_back "$lic"; then
    echo "back."
    return 1
  fi
  if [ -z "$lic" ]; then
    echo "no license entered."
    return 1
  fi
  printf 'license username (0 = back): ' >&2
  IFS= read -r user || return 1
  if wants_back "$user"; then
    echo "back."
    return 1
  fi
  printf 'license password (0 = back): ' >&2
  stty -echo 2>/dev/null || true
  IFS= read -r pass || pass=""
  stty echo 2>/dev/null || true
  echo "" >&2
  if wants_back "$pass"; then
    echo "back."
    return 1
  fi
  if [ -z "$user" ] || [ -z "$pass" ]; then
    echo "the username and password must not be empty."
    return 1
  fi
  out=$(license_check_values "$lic" "$user" "$pass")
  if [ "$(license_field "$out" status)" != "ACTIVE" ]; then
    echo "this license was rejected:"
    license_show_result "$out"
    echo "nothing was saved."
    return 1
  fi
  license_save "$lic" "$user" "$pass"
  echo "license saved:"
  license_show_result "$out"
  days=$(license_field "$out" days_left)
  case "$days" in
    ''|*[!0-9]*) ;;
    *)
      if [ "$days" -le 7 ]; then
        echo "warning: this license expires in $days day(s) - renew it soon."
      fi
      ;;
  esac
  return 0
}

menu_license_status() {
  if ! license_supported; then
    echo "the installed dashboard build does not support the license yet."
    echo "update it from menu 4 (Install / update dashboard)."
    return
  fi
  if ! license_saved; then
    echo "license : not set (choose 1 to enter it)"
    return
  fi
  echo "license files:"
  echo "  $LICENSE_FILE"
  echo "  $LICENSE_AUTH_FILE"
  out=$(license_check_saved)
  license_show_result "$out"
  if [ "$(license_field "$out" status)" = "ACTIVE" ]; then
    echo "license : ACTIVE"
  else
    echo "license : NOT ACTIVE - the dashboard will not start (choose 1 to fix it)"
  fi
}

menu_license_remove() {
  if ! license_saved; then
    echo "no license is saved."
    return
  fi
  a=$(ask_default "n" "remove the saved license? the dashboard will not start without it (y/n, 0 = back)")
  if wants_back "$a"; then
    return
  fi
  case "$a" in
    y|Y) ;;
    *) echo "cancelled."; return ;;
  esac
  rm -f "$LICENSE_FILE" "$LICENSE_AUTH_FILE"
  rmdir "$LICENSE_DIR" 2>/dev/null || true
  echo "license removed."
}

menu_license() {
  while true; do
    if [ -t 1 ]; then clear; fi
    show_title
    echo "License"
    echo "  dashboard login uses the license username/password"
    if license_saved; then
      echo "  saved: yes ($LICENSE_FILE)"
    else
      echo "  saved: no"
    fi
    echo ""
    echo "  1) Enter / update license"
    echo "  2) Show license status"
    echo "  3) Remove saved license"
    echo "  0) Back to the main menu"
    printf '\n%s' "${CYAN}choose 1-3 (0 = back):${NC} "
    if ! IFS= read -r c; then
      echo ""
      exit 0
    fi
    case "$c" in
      0|b|B|back|q|Q|quit) return ;;
      1) menu_license_enter ;;
      2) menu_license_status ;;
      3) menu_license_remove ;;
      *) echo "please choose 1-3." ;;
    esac
    printf '%s' "${CYAN}Press Enter to continue...${NC}"
    IFS= read -r _ || { echo ""; exit 0; }
  done
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

# Commands live in ~/.local/bin (always writable, no sudo). The PATH block
# below keeps that directory on PATH for future terminals; without it a
# non-root user gets "Mapsim_BOT: command not found".
LOCAL_BIN="$HOME/.local/bin"
PATH_MARKER="# Mapsim BOT: put ~/.local/bin on PATH"

path_has_local_bin() {
  printf '%s' ":$PATH:" | grep -q ":$LOCAL_BIN:"
}

ensure_path() {
  touched=0
  for f in "$HOME/.profile" "$HOME/.bash_profile" "$HOME/.bashrc" "$HOME/.zprofile" "$HOME/.zshrc"; do
    [ -f "$f" ] || continue
    touched=1
    if grep -qF "$PATH_MARKER" "$f" 2>/dev/null; then
      continue
    fi
    {
      echo ""
      echo "$PATH_MARKER"
      echo 'case ":$PATH:" in'
      echo '  *":$HOME/.local/bin:"*) ;;'
      echo '  *) PATH="$HOME/.local/bin:$PATH"; export PATH ;;'
      echo 'esac'
    } >> "$f"
  done
  if [ "$touched" -eq 0 ]; then
    {
      echo "$PATH_MARKER"
      echo 'case ":$PATH:" in'
      echo '  *":$HOME/.local/bin:"*) ;;'
      echo '  *) PATH="$HOME/.local/bin:$PATH"; export PATH ;;'
      echo 'esac'
    } > "$HOME/.profile"
  fi
}

remove_path_block() {
  for f in "$HOME/.profile" "$HOME/.bash_profile" "$HOME/.bashrc" "$HOME/.zprofile" "$HOME/.zshrc"; do
    [ -f "$f" ] || continue
    grep -qF "$PATH_MARKER" "$f" 2>/dev/null || continue
    awk -v m="$PATH_MARKER" '
      $0 == m { skip = 1; next }
      skip == 1 && $0 ~ /^[ \t]*esac[ \t]*$/ { skip = 0; next }
      skip == 1 { next }
      { print }
    ' "$f" > "$f.mapsim-tmp" && mv "$f.mapsim-tmp" "$f"
  done
}

install_command_link() {
  # mapsim-dashboard already lives in ~/.local/bin (write_wrapper); only the
  # Mapsim_BOT command has to be linked there.
  mkdir -p "$LOCAL_BIN"
  ln -sf "$MENU_DEST" "$LOCAL_BIN/$MENU_CMD"
  LINKS=""
  for dir in /usr/local/bin /usr/bin; do
    if [ -d "$dir" ] && [ -w "$dir" ]; then
      ln -sf "$WRAPPER" "$dir/mapsim-dashboard"
      ln -sf "$MENU_DEST" "$dir/$MENU_CMD"
      LINKS="$dir"
      break
    fi
  done
  if [ -z "$LINKS" ]; then
    ensure_path
    if path_has_local_bin; then
      msg_info "commands ready: $MENU_CMD and mapsim-dashboard"
    else
      echo "commands installed in $LOCAL_BIN ($MENU_CMD, mapsim-dashboard)"
      echo "this terminal:  export PATH=\"\$HOME/.local/bin:\$PATH\""
      echo "new terminals already find them."
    fi
  fi
}

remove_command_link() {
  for dir in /usr/local/bin /usr/bin "$LOCAL_BIN"; do
    [ -L "$dir/mapsim-dashboard" ] && rm -f "$dir/mapsim-dashboard"
    [ -L "$dir/$MENU_CMD" ] && rm -f "$dir/$MENU_CMD"
  done
  remove_path_block
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
  had_service=0
  if service_installed && service_active; then had_service=1; fi
  stop_dashboard --force >/dev/null 2>&1 || true
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
  if [ "$had_service" -eq 1 ]; then
    service_start
    echo "auto-start service restarted with the new version."
  fi
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
      unit_cmd is-active --quiet 2>/dev/null
      ;;
  esac
}

# Run a systemctl action against the dashboard unit, as root or as the user.
unit_cmd() {
  if [ "$(id -u)" -eq 0 ]; then
    systemctl "$@" "$SERVICE_NAME"
  else
    systemctl --user "$@" "$SERVICE_NAME"
  fi
}

# True when the service currently has a live process (for display).
service_running() {
  case "$OS" in
    Darwin) launchctl print "gui/$(id -u)/$LABEL" 2>/dev/null | grep -q 'state = running' ;;
    Linux) unit_cmd is-active --quiet 2>/dev/null ;;
  esac
}

# Will the service start by itself at the next boot/login?
service_enabled() {
  case "$OS" in
    Darwin)
      [ -f "$HOME/Library/LaunchAgents/$LABEL.plist" ] || return 1
      if launchctl print-disabled "gui/$(id -u)" 2>/dev/null | grep -q "\"$LABEL\" => disabled"; then
        return 1
      fi
      return 0
      ;;
    Linux)
      unit_cmd is-enabled --quiet 2>/dev/null
      ;;
  esac
}

service_start() {
  case "$OS" in
    Darwin)
      if launchctl print "gui/$(id -u)/$LABEL" >/dev/null 2>&1; then
        launchctl kickstart "gui/$(id -u)/$LABEL" >/dev/null 2>&1
      else
        launchctl bootstrap "gui/$(id -u)" "$HOME/Library/LaunchAgents/$LABEL.plist" >/dev/null 2>&1
      fi
      ;;
    Linux)
      unit_cmd start
      ;;
  esac
}

# Stop for now, keep the unit/task/agent installed so it returns at boot/login.
service_stop() {
  case "$OS" in
    Darwin)
      launchctl bootout "gui/$(id -u)" "$HOME/Library/LaunchAgents/$LABEL.plist" >/dev/null 2>&1 || true
      ;;
    Linux)
      unit_cmd stop
      ;;
  esac
}

service_restart() {
  case "$OS" in
    Darwin)
      launchctl kickstart -k "gui/$(id -u)/$LABEL" >/dev/null 2>&1
      ;;
    Linux)
      unit_cmd restart
      ;;
  esac
}

service_enable() {
  case "$OS" in
    Darwin)
      launchctl enable "gui/$(id -u)/$LABEL" >/dev/null 2>&1
      ;;
    Linux)
      unit_cmd enable
      ;;
  esac
}

service_disable() {
  case "$OS" in
    Darwin)
      launchctl disable "gui/$(id -u)/$LABEL" >/dev/null 2>&1
      ;;
    Linux)
      unit_cmd disable
      ;;
  esac
}

service_manager_label() {
  case "$OS" in
    Darwin) echo "launchd LaunchAgent ($HOME/Library/LaunchAgents/$LABEL.plist), restarts on failure" ;;
    Linux)
      if [ "$(id -u)" -eq 0 ]; then
        echo "systemd unit /etc/systemd/system/$SERVICE_NAME, restarts on failure (5s)"
      else
        echo "systemd user unit ~/.config/systemd/user/$SERVICE_NAME, restarts on failure (5s)"
      fi
      ;;
  esac
}

service_install() {
  # One dashboard only: the unit/task starts immediately, so a manually started
  # instance would fight for the port.
  if [ -n "$(dashboard_pid)" ] && ! service_active; then
    echo "stopping the manually started dashboard - the service will run it."
    stop_dashboard --force >/dev/null 2>&1 || true
  fi
  svc_port=$(current_port)
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
    <string>--port</string>
    <string>$svc_port</string>
  </array>
  <key>EnvironmentVariables</key>
  <dict>
    <key>HOME</key>
    <string>$HOME</string>
  </dict>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <dict>
    <key>SuccessfulExit</key>
    <false/>
  </dict>
  <key>ThrottleInterval</key>
  <integer>10</integer>
  <key>StandardOutPath</key>
  <string>$LOG_FILE</string>
  <key>StandardErrorPath</key>
  <string>$LOG_FILE</string>
  <key>WorkingDirectory</key>
  <string>$HOME</string>
</dict>
</plist>
EOF
      launchctl bootout "gui/$(id -u)" "$plist" 2>/dev/null || true
      launchctl enable "gui/$(id -u)/$LABEL" 2>/dev/null || true
      launchctl bootstrap "gui/$(id -u)" "$plist"
      ;;
    Linux)
      unit_head="[Unit]
Description=Mapsim Live Dashboard (read-only MT5 dashboard)
After=network-online.target
Wants=network-online.target
# Automatic restarts are capped; the service never spins forever.
StartLimitIntervalSec=60
StartLimitBurst=5

[Service]
Type=simple
EnvironmentFile=-$ENV_FILE
ExecStart=$WRAPPER --no-browser --port $svc_port
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
  mkdir -p "$CONFIG_DIR"
  echo "$svc_port" > "$PORT_FILE"
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

# stop_dashboard [ask|--force]
# Stops every process of the dashboard (bootloader parent and child). When the
# auto-start service is running it is stopped too, otherwise systemd/launchd
# would start the dashboard again seconds later. "ask" (the menu 3 default)
# asks first; --force is used by --stop, updates and restarts.
stop_dashboard() {
  mode=${1:-ask}
  managed=0
  if service_installed && service_active; then managed=1; fi
  if [ "$managed" -eq 1 ] && [ "$mode" != "--force" ]; then
    a=$(ask_default "y" "the dashboard runs from the auto-start service - stop the service too? (y/n)")
    if [ "$a" != "y" ] && [ "$a" != "Y" ]; then
      echo "cancelled - the dashboard was not stopped."
      return 1
    fi
  fi
  if [ "$managed" -eq 1 ]; then
    service_stop
    echo "auto-start service stopped (it starts again at the next boot/login; menu 6 removes it)."
  fi
  pids=$(dashboard_pids)
  if [ -z "$pids" ]; then
    rm -f "$PID_FILE"
    [ "$managed" -eq 0 ] && echo "the dashboard is not running."
    trim_logs
    return 0
  fi
  pid_list=""
  for p in $pids; do
    pid_list="$pid_list $p"
    kill "$p" 2>/dev/null || true
  done
  i=0
  while [ "$i" -lt 10 ]; do
    alive=""
    for p in $pids; do
      process_alive "$p" && alive="$alive $p"
    done
    [ -z "$alive" ] && break
    sleep 1
    i=$((i + 1))
  done
  # Escalate, and re-scan in case the bootloader left a fresh child behind.
  for p in $pids $(dashboard_pids); do
    process_alive "$p" && kill -9 "$p" 2>/dev/null || true
  done
  rm -f "$PID_FILE"
  port=$(current_port)
  i=0
  while port_listening "$port" && [ "$i" -lt 5 ]; do
    sleep 1
    i=$((i + 1))
  done
  echo "dashboard stopped (pids:$pid_list)."
  if port_listening "$port"; then
    echo "note: port $port is still used by another program."
  fi
  trim_logs
  return 0
}

# start_dashboard <bind> <port>
start_dashboard() {
  bind="$1"
  port="$2"
  if [ -n "$(dashboard_pid)" ]; then
    echo "the dashboard is already running (pid $(dashboard_pid))."
    return 0
  fi
  if ! license_ready; then
    echo "error: a valid Mapsim license is required - the dashboard was not started." >&2
    echo "open menu 13 (License) and enter or fix the license." >&2
    return 1
  fi
  if service_installed; then
    if service_active; then
      # A loaded service whose process is gone: stop it so it cannot race us.
      service_stop
      echo "note: the auto-start service was stopped for this manual start (it starts again at the next boot/login)."
    else
      echo "note: the auto-start service is installed and will start the dashboard again at the next boot/login (menu 6 removes it)."
    fi
  fi
  if port_listening "$port"; then
    echo "error: port $port is already used by another program." >&2
    return 1
  fi
  write_env_file "$bind"
  snap=$(current_snapshot)
  if [ -z "$snap" ] || [ ! -f "$snap" ]; then
    echo "warning: no Mapsim snapshot was found in any MT5 folder."
    echo "         start MT5 with the Expert loaded, or set the file in menu 12."
  fi
  mkdir -p "$CONFIG_DIR"
  # Keep the log small: only the newest startup lines are worth keeping.
  trim_logs
  nohup "$WRAPPER" --no-browser --port "$port" >>"$LOG_FILE" 2>&1 &
  echo $! > "$PID_FILE"
  i=0
  while [ "$i" -lt 20 ]; do
    if [ -n "$(dashboard_pid)" ] && dashboard_up "$port"; then
      echo "$port" > "$PORT_FILE"
      echo "dashboard is up:"
      echo "  local   : http://127.0.0.1:$port/"
      if [ "$bind" = "0.0.0.0" ]; then
        ip=$(host_ip)
        if [ -n "$ip" ]; then
          echo "  remote  : http://$ip:$port/ (open the port in your firewall first)"
        else
          echo "  remote  : http://<this-computer-ip>:$port/ (allow the port through your firewall)"
        fi
        echo "  access  : the license username and password (menu 13)"
      fi
      return 0
    fi
    sleep 1
    i=$((i + 1))
  done
  echo "error: the dashboard did not answer on port $port; see $LOG_FILE" >&2
  tail -n 5 "$LOG_FILE" 2>/dev/null | sed 's/^/  /' >&2
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
  p=$(current_port)
  if dashboard_up "$p"; then
    echo "port $p   : dashboard answering (HTTP $(http_code "$p"))"
  elif port_listening "$p"; then
    echo "port $p   : busy (another program)"
  else
    echo "port $p   : free"
  fi
  bind=$(current_bind)
  [ -n "$bind" ] && echo "bind      : $bind" || echo "bind      : 127.0.0.1 (default)"
  echo "url       : $(access_url)"
  if service_installed; then
    if service_enabled; then sen="enabled"; else sen="disabled"; fi
    if service_running; then
      echo "service   : installed, $sen, RUNNING"
    else
      echo "service   : installed, $sen, stopped"
    fi
  else
    echo "service   : not installed"
  fi
  echo "disk      : $(disk_summary)"
  snap=$(current_snapshot)
  [ -z "$snap" ] && snap=$(find_snapshot)
  if [ -n "$snap" ]; then
    if [ -f "$snap" ]; then
      echo "snapshot  : $snap ($(file_age "$snap"))"
    else
      echo "snapshot  : $snap (MISSING - menu 12 to change)"
    fi
  else
    echo "snapshot  : not found (no MQL5/Files/MapsimLive/snapshot.json - menu 12)"
  fi
  if ! license_saved; then
    echo "license   : not set (menu 13 - required to start)"
  elif ! license_supported; then
    echo "license   : saved (the installed build is too old - menu 4)"
  else
    out=$(license_check_saved)
    lstatus=$(license_field "$out" status)
    luser=$(license_field "$out" user)
    lexp=$(license_field "$out" expiry)
    if [ "$lstatus" = "ACTIVE" ]; then
      echo "license   : ACTIVE - $luser, expires $lexp"
    else
      echo "license   : $lstatus ($(license_field "$out" message)) - dashboard will not start"
    fi
  fi
}

ask_default() {
  # ask_default <default> <prompt>
  d="$1"; p="$2"
  a=$(ask "$p [$d]")
  [ -n "$a" ] && echo "$a" || echo "$d"
}

# Every submenu prompt accepts 0 (or b/back/q) to leave the submenu and go
# back to the main menu without changing anything.
wants_back() {
  case "$1" in
    0|0\)|b|B|back|BACK|Back|q|Q|quit|QUIT) return 0 ;;
  esac
  return 1
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
  mt5_bases | while IFS= read -r base; do
    [ -d "$base" ] || continue
    find "$base" -maxdepth 9 -type d -name MQL5 2>/dev/null
  done | awk '!seen[$0]++'
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
    while true; do
      sel=$(ask_default "1" "choose 1-$total (or 'a' for all, 0 = back)")
      if wants_back "$sel"; then
        echo "back to the main menu."
        return 1
      fi
      case "$sel" in
        a|A) break ;;
        ''|*[!0-9]*)
          echo "error: choose a number between 1 and $total (or 'a')." >&2
          ;;
        *)
          if [ "$sel" -ge 1 ] && [ "$sel" -le "$total" ]; then
            break
          fi
          echo "error: choose a number between 1 and $total (or 'a')." >&2
          ;;
      esac
    done
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
    a=$(ask_default "y" "version $cur is already installed - reinstall? (y/n, 0 = back)")
    if wants_back "$a"; then
      echo "back to the main menu."
      return
    fi
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
      a=$(ask_default "y" "a newer version is available - install it now? (y/n, 0 = back)")
      if wants_back "$a"; then
        echo "back to the main menu."
        return
      fi
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
  stop_dashboard --force >/dev/null 2>&1 || true
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
  rm -rf "$LICENSE_DIR"
  echo "Mapsim Live Dashboard removed completely (MT5 and the EA were not touched)."
}

# ---------------------------------------------------------------- interactive

choose_port() {
  p=$(ask_default "8765" "port (0 = back)")
  while true; do
    if wants_back "$p"; then
      return 1
    fi
    case "$p" in
      ''|*[!0-9]*)
        echo "error: port must be a number between 1 and 65535." >&2
        p=$(ask_default "8765" "port (0 = back)")
        continue
        ;;
    esac
    if [ "$p" -lt 1 ] || [ "$p" -gt 65535 ]; then
      echo "error: port must be between 1 and 65535." >&2
      p=$(ask_default "8765" "port (0 = back)")
      continue
    fi
    # Our own running dashboard already owns its port; switching to it needs
    # no "busy" complaint.
    if [ "$p" = "$(current_port)" ] && [ -n "$(dashboard_pid)" ]; then
      echo "$p"
      return 0
    fi
    if ! port_listening "$p"; then
      echo "$p"
      return 0
    fi
    echo "port $p is busy." >&2
    p=$(ask_default "$((p + 1))" "choose another port (0 = back)")
  done
}

menu_start() {
  if ! is_installed; then
    echo "the dashboard is not installed yet - install it first (menu 4)."
    return
  fi
  if ! license_prepare; then
    return
  fi
  echo "how should the dashboard be reachable?"
  echo "  1) local only   (this computer, http://127.0.0.1)"
  echo "  2) internet     (any device + this computer, sign in with the license)"
  m=$(ask_default "1" "choose 1 or 2 (0 = back)")
  if wants_back "$m"; then
    echo "back to the main menu."
    return
  fi
  if [ "$m" = "2" ]; then
    bind="0.0.0.0"
  else
    bind="127.0.0.1"
  fi
  if ! port=$(choose_port); then
    echo "back to the main menu."
    return
  fi
  old_pid=$(dashboard_pid)
  if [ -n "$old_pid" ]; then
    echo "the dashboard is already running (pid $old_pid, port $(current_port), bind $(current_bind || echo 127.0.0.1))."
    a=$(ask_default "y" "stop it and restart with the new settings? (y/n, 0 = back)")
    if wants_back "$a"; then
      echo "back to the main menu."
      return
    fi
    if [ "$a" != "y" ] && [ "$a" != "Y" ]; then
      echo "cancelled - the running dashboard was not changed."
      return
    fi
    stop_dashboard --force
  fi
  start_dashboard "$bind" "$port"
}

menu_disk() {
  echo "server disk usage:"
  df -h / "$HOME" 2>/dev/null | awk 'NR==1 || !seen[$1]++'
  echo ""
  echo "dashboard folders:"
  for d in "$APP_ROOT" "$CONFIG_DIR"; do
    if [ -e "$d" ]; then
      du -sh "$d" 2>/dev/null || true
    fi
  done
  for f in "$LOG_FILE" "$LOG_FILE.err" "$(app_log_file)"; do
    if [ -f "$f" ]; then
      echo "log file: $(du -h "$f" 2>/dev/null | awk '{print $1}') ($f)"
    fi
  done
  echo "logs are trimmed automatically above 256 KB (the newest lines are kept)."
  bases=$(mt5_bases 2>/dev/null || true)
  if [ -n "$bases" ]; then
    echo ""
    echo "MetaTrader (Wine) drives:"
    old_ifs=$IFS
    IFS='
'
    for d in $bases; do
      echo "  $(du -sh "$d" 2>/dev/null | awk '{print $1}')  $d"
    done
    IFS=$old_ifs
  fi
}

menu_snapshot() {
  if ! is_installed; then
    echo "the dashboard is not installed yet - install it first (menu 4)."
    return
  fi
  cur=$(current_snapshot)
  det=$(find_snapshot)
  if [ -n "$cur" ]; then
    if [ -f "$cur" ]; then
      echo "saved snapshot : $cur ($(file_age "$cur"))"
    else
      echo "saved snapshot : $cur (missing)"
    fi
  else
    echo "saved snapshot : not set (auto-detect is used)"
  fi
  if [ -n "$det" ]; then
    echo "detected       : $det ($(file_age "$det"))"
  else
    echo "detected       : nothing (no MQL5/Files/MapsimLive/snapshot.json yet)"
  fi
  echo "  1) use the detected file"
  printf '  2) enter a path (snapshot.json, MT5 folder, or C:\\Program Files\\MetaTrader 5)\n'
  echo "  3) clear (let the dashboard search by itself)"
  m=$(ask_default "1" "choose 1, 2 or 3 (0 = back)")
  if wants_back "$m"; then
    echo "back to the main menu."
    return
  fi
  case "$m" in
    1)
      if [ -z "$det" ]; then
        echo "nothing was detected - the saved value was not changed."
        return
      fi
      new="$det"
      ;;
    2)
      printf '%s' 'path (0 = back): ' >&2
      IFS= read -r typed || typed=""
      if wants_back "$typed"; then
        echo "back to the main menu."
        return
      fi
      if [ -z "$typed" ]; then
        echo "cancelled."
        return
      fi
      new=$(resolve_snapshot_input "$typed")
      if [ -z "$new" ]; then
        echo "cancelled."
        return
      fi
      if [ ! -f "$new" ]; then
        echo "not found yet: $new"
        a=$(ask_default "y" "save this path anyway? (y/n, 0 = back)")
        if wants_back "$a"; then
          echo "back to the main menu."
          return
        fi
        if [ "$a" != "y" ] && [ "$a" != "Y" ]; then
          echo "cancelled."
          return
        fi
      fi
      ;;
    3)
      new=""
      ;;
    *)
      echo "cancelled."
      return
      ;;
  esac
  bind=$(current_bind); [ -z "$bind" ] && bind="127.0.0.1"
  write_env_file "$bind" "$new"
  if [ -n "$new" ]; then
    echo "saved: snapshot = $new"
  else
    echo "saved: snapshot = auto-detect"
  fi
  if [ -n "$(dashboard_pid)" ]; then
    a=$(ask_default "y" "restart the dashboard now? (y/n, 0 = back)")
    if wants_back "$a"; then
      echo "back to the main menu."
      return
    fi
    if [ "$a" = "y" ] || [ "$a" = "Y" ]; then
      if ! port=$(choose_port); then
        echo "the dashboard was not restarted (menu 2 to start it later)."
        return
      fi
      if ! license_prepare; then
        echo "the dashboard was not restarted."
        return
      fi
      stop_dashboard --force
      start_dashboard "$bind" "$port"
    fi
  fi
}

menu_configure() {
  if ! is_installed; then
    echo "the dashboard is not installed yet - install it first (menu 4)."
    return
  fi
  echo "current bind: $(current_bind || echo 127.0.0.1)"
  echo "sign-in is always the license username and password (menu 13)."
  echo "  1) local only"
  echo "  2) internet (any device on your network / the internet)"
  m=$(ask_default "1" "choose 1 or 2 (0 = back)")
  if wants_back "$m"; then
    echo "back to the main menu."
    return
  fi
  running=""
  [ -n "$(dashboard_pid)" ] && running=1
  if [ "$m" = "2" ]; then
    write_env_file "0.0.0.0"
    echo "saved: internet access on 0.0.0.0."
  else
    write_env_file "127.0.0.1"
    echo "saved: local only."
  fi
  if [ -n "$running" ]; then
    a=$(ask_default "y" "restart the dashboard now? (y/n, 0 = back)")
    if wants_back "$a"; then
      echo "back to the main menu."
      return
    fi
    if [ "$a" = "y" ] || [ "$a" = "Y" ]; then
      if ! port=$(choose_port); then
        echo "the dashboard was not restarted (menu 2 to start it later)."
        return
      fi
      if ! license_prepare; then
        echo "the dashboard was not restarted."
        return
      fi
      stop_dashboard --force
      start_dashboard "$(current_bind)" "$port"
    fi
  fi
}

menu_service_install() {
  if ! is_installed; then
    echo "the dashboard is not installed yet - install it first (menu 4)."
    return
  fi
  if ! license_prepare; then
    echo "the service was not installed."
    return
  fi
  service_install
  echo "service installed and enabled: the dashboard starts now and at every boot/login."
}

service_log_hint() {
  case "$OS" in
    Darwin) echo "$LOG_FILE and the macOS unified log (log show --last 1h --predicate 'process == \"MapsimDashboard\"')" ;;
    Linux)
      if [ "$(id -u)" -eq 0 ]; then
        echo "$LOG_FILE and journalctl -u $SERVICE_NAME -n 50"
      else
        echo "$LOG_FILE and journalctl --user -u $SERVICE_NAME -n 50"
      fi
      ;;
  esac
}

service_status() {
  echo "auto-start service:"
  if service_installed; then
    echo "  installed : yes"
    echo "  manager   : $(service_manager_label)"
    if service_enabled; then
      echo "  enabled   : yes (starts at the next boot/login)"
    else
      echo "  enabled   : no (choose 6 to enable it)"
    fi
    if service_running; then
      echo "  running   : yes (pid $(dashboard_pid || echo '?'))"
    else
      echo "  running   : no"
    fi
  else
    echo "  installed : no (choose 2 to install it)"
    echo "  enabled   : -"
    echo "  running   : -"
  fi
  pid=$(dashboard_pid)
  port=$(current_port)
  if [ -n "$pid" ]; then
    echo "  dashboard : pid $pid, port $port"
    echo "  url       : $(access_url)"
  else
    echo "  dashboard : not running"
  fi
  echo "  logs      : $(service_log_hint)"
}

# One service action from the submenu; asks nothing, prints what it did.
menu_service_action() {
  action=$1
  if ! is_installed; then
    echo "the dashboard is not installed yet - install it first (menu 4)."
    return
  fi
  if ! service_installed; then
    echo "the auto-start service is not installed - choose 2 first."
    return
  fi
  port=$(current_port)
  case "$action" in
    start|restart)
      if [ "$OS" = "Darwin" ] && ! service_enabled; then
        echo "the service is disabled - choose 6 to enable it first."
        return
      fi
      if ! license_prepare; then
        echo "the service was not $action-ed."
        return
      fi
      ;;
  esac
  case "$action" in
    start)
      service_start
      echo "start requested."
      if wait_dashboard "$port" 15; then
        echo "dashboard is up: $(access_url)"
      else
        echo "it did not answer on port $port - see status (1) and the service logs."
      fi
      ;;
    stop)
      service_stop
      # Kill anything the manager left behind (bootloader child, manual copy).
      stop_dashboard --force >/dev/null 2>&1 || true
      echo "service stopped. It starts again at the next boot/login while it is enabled."
      ;;
    restart)
      service_restart
      echo "restart requested."
      if wait_dashboard "$port" 15; then
        echo "dashboard is up: $(access_url)"
      else
        echo "it did not answer on port $port - see status (1) and the service logs."
      fi
      ;;
    enable)
      service_enable
      echo "enabled: the dashboard starts automatically at the next boot/login."
      ;;
    disable)
      service_disable
      echo "disabled: it will not start automatically any more. The running dashboard keeps running until you stop it (4)."
      ;;
  esac
}

menu_service() {
  while true; do
    if [ -t 1 ]; then clear; fi
    echo ""
    echo "auto-start service"
    if service_installed; then
      if service_enabled; then se="enabled"; else se="disabled"; fi
      if service_running; then sr="running"; else sr="stopped"; fi
      echo "  installed, $se, $sr (port $(current_port))"
    else
      echo "  not installed"
    fi
    echo ""
    echo "  1) Status / details"
    echo "  2) Install and enable (start now and at every boot/login)"
    echo "  3) Start now"
    echo "  4) Stop now"
    echo "  5) Restart now"
    echo "  6) Enable at boot/login"
    echo "  7) Disable at boot/login"
    m=$(ask_default "1" "choose 1-7 (0 = back)")
    if wants_back "$m"; then
      echo "back to the main menu."
      return
    fi
    case "$m" in
      1) service_status ;;
      2) menu_service_install ;;
      3) menu_service_action start ;;
      4) menu_service_action stop ;;
      5) menu_service_action restart ;;
      6) menu_service_action enable ;;
      7) menu_service_action disable ;;
      *) echo "please choose 1-7." ;;
    esac
    printf '%s' "press Enter to continue..."
    IFS= read -r _ || { echo ""; return; }
  done
}

menu_service_remove() {
  if ! service_installed; then
    echo "no service is installed."
    return
  fi
  a=$(ask_default "y" "remove the auto-start service? (y/n, 0 = back)")
  if wants_back "$a"; then
    echo "back to the main menu."
    return
  fi
  if [ "$a" = "y" ] || [ "$a" = "Y" ]; then
    service_remove
    echo "service removed (the app itself stays installed)."
  fi
}

menu_uninstall() {
  echo "this removes the dashboard app, config, service and commands."
  echo "nothing is changed in MetaTrader 5 or in the Expert Advisor."
  a=$(ask_default "n" "are you sure? type y to confirm (0 = back)")
  if wants_back "$a"; then
    echo "back to the main menu."
    return
  fi
  if [ "$a" = "y" ] || [ "$a" = "Y" ]; then
    uninstall_everything
  else
    echo "cancelled."
  fi
}

menu_main() {
  while true; do
    if [ -t 1 ]; then clear; fi
    pid=$(dashboard_pid)
    if [ -n "$pid" ]; then
      st_plain="running (pid $pid)"
      st="${GREEN}$st_plain${NC}"
    else
      st_plain="stopped"
      st="${RED}$st_plain${NC}"
    fi
    if is_installed; then
      app_plain="installed"
      app="${GREEN}$app_plain${NC}"
    else
      app_plain="not installed"
      app="${RED}$app_plain${NC}"
    fi
    ea=$(ea_installed_version)
    if [ -n "$ea" ]; then
      ea_plain="$ea"
      ea="${GREEN}$ea${NC}"
    else
      ea_plain="not installed"
      ea="${YELLOW}$ea_plain${NC}"
    fi
    bind=$(current_bind)
    port=$(current_port)
    if [ "$bind" = "0.0.0.0" ]; then
      acc="internet (0.0.0.0) - port $port"
    else
      acc="local only - port $port"
    fi
    disk=$(disk_summary)
    [ -z "$disk" ] && disk="unknown"
    pct=$(disk_usage_pct)
    case "$pct" in
      ''|*[!0-9]*) pct=0 ;;
    esac
    if [ "$pct" -ge 90 ]; then
      disk_col="$RED"
    elif [ "$pct" -ge 75 ]; then
      disk_col="$YELLOW"
    else
      disk_col="$GREEN"
    fi
    snap=$(current_snapshot)
    [ -z "$snap" ] && snap=$(find_snapshot)
    if [ -n "$snap" ] && [ -f "$snap" ]; then
      snap_plain="ok ($(file_age "$snap"))"
      snap_col="${GREEN}$snap_plain${NC}"
    elif [ -n "$snap" ]; then
      snap_plain="missing"
      snap_col="${RED}$snap_plain${NC}"
    else
      snap_plain="not found"
      snap_col="${RED}$snap_plain${NC}"
    fi
    if license_saved; then
      lic_plain="saved"
      lic_col="${GREEN}$lic_plain${NC}"
    else
      lic_plain="not set"
      lic_col="${RED}$lic_plain${NC}"
    fi

    show_title
    ui_top
    ui_row "Dashboard" "$st_plain" "$st"
    ui_row "App" "$app_plain" "$app"
    ui_row "Expert" "$ea_plain" "$ea"
    ui_row "License" "$lic_plain" "$lic_col"
    ui_row "Access" "$acc" "${CYAN}$acc${NC}"
    ui_row "URL" "$(access_url)"
    ui_row "Snapshot" "$snap_plain" "$snap_col"
    ui_row "Disk" "$disk" "${disk_col}$disk${NC}"
    ui_sep
    ui_item "1" "Status"
    ui_item "2" "Start dashboard"
    ui_item "3" "Stop dashboard"
    ui_item "4" "Install / update dashboard"
    ui_item "5" "Service management (start/stop/restart/enable/disable)"
    ui_item "6" "Remove auto-start service"
    ui_item "7" "Access mode (local / internet)"
    ui_item "8" "Uninstall everything"
    ui_item "9" "Expert Advisor: install / update"
    ui_item "10" "Expert Advisor: version check"
    ui_item "11" "Disk space / server storage"
    ui_item "12" "Snapshot file / data source"
    ui_item "13" "License (dashboard login)"
    ui_item "14" "Exit"
    ui_bottom
    printf '%s\n' "${CYAN}tip: type 0 inside any option to return to this menu.${NC}"
    printf '\n%s' "${CYAN}Enter Number Of List:${NC} "
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
      5) menu_service ;;
      6) menu_service_remove ;;
      7) menu_configure ;;
      8) menu_uninstall ;;
      9) menu_ea_install ;;
      10) menu_ea_status ;;
      11) menu_disk ;;
      12) menu_snapshot ;;
      13) menu_license ;;
      14) echo "bye."; exit 0 ;;
      *) msg_warn "please choose 1-14." ;;
    esac
    printf '%s' "${CYAN}Press Enter to continue...${NC}"
    IFS= read -r _ || { echo ""; exit 0; }
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
    write_env_file "0.0.0.0"
    echo "public access: reachable from other devices on 0.0.0.0."
    echo "  sign in with the license username and password (menu 13)."
  fi

  if [ "$service" -eq 1 ]; then
    service_install
    echo "service installed: starts automatically at boot/login."
    if ! license_ready; then
      echo "note: the dashboard needs a valid Mapsim license before it runs."
      echo "      open $MENU_CMD and choose 13 (License)."
    fi
  elif [ "$launch" -eq 1 ]; then
    if [ -z "$(dashboard_pid)" ]; then
      echo ""
      if ! license_ready; then
        echo "the dashboard was not started: a valid Mapsim license is required."
        echo "open the control center and choose 13 (License):  $MENU_CMD"
      else
        echo "starting the dashboard (local mode) ..."
        port=8765
        if port_listening "$port" && ! dashboard_up "$port"; then
          port=8766
          echo "note: port 8765 is busy, using $port."
        fi
        bind=$(current_bind); [ -z "$bind" ] && bind="127.0.0.1"
        start_dashboard "$bind" "$port"
      fi
    else
      echo "the dashboard is already running (pid $(dashboard_pid))."
    fi
  fi

  echo ""
  if path_has_local_bin; then
    echo "done. From now on manage everything with:  $MENU_CMD"
  else
    echo "done. Manage everything with:  $LOCAL_BIN/$MENU_CMD"
    echo "this terminal needs:  export PATH=\"\$HOME/.local/bin:\$PATH\""
    echo "new terminals find $MENU_CMD automatically."
  fi
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
    stop_dashboard --force
    ;;
  ""|-i|--menu)
    trim_logs
    menu_main
    ;;
  *)
    echo "usage: $MENU_CMD [--bootstrap ...] [--status] [--stop]" >&2
    exit 2
    ;;
esac
