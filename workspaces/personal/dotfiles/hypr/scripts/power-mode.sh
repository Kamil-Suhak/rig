#!/usr/bin/env bash
set -euo pipefail

RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
STATE_FILE="${RUNTIME_DIR}/power-state"
LOCK_FILE="${RUNTIME_DIR}/power-mode.lock"
SERVER_FLAG="${RUNTIME_DIR}/server-mode"
INHIBIT_UNIT="rig-server-inhibit.service"

is_on_ac() {
  local f
  for f in /sys/class/power_supply/A*/online; do
    if [[ -r "$f" ]] && [[ "$(cat "$f")" == "1" ]]; then
      return 0
    fi
  done
  return 1
}

battery_info() {
  local bat cap status
  for bat in /sys/class/power_supply/BAT*; do
    [[ -r "$bat/capacity" && -r "$bat/status" ]] || continue
    cap="$(cat "$bat/capacity" 2>/dev/null || echo 100)"
    status="$(cat "$bat/status" 2>/dev/null || echo Unknown)"
    printf '%s %s\n' "$cap" "$status"
    return 0
  done
  printf '100 Unknown\n'
}

wifi_powersave_off() {
  command -v iw >/dev/null 2>&1 || return 0
  local iface
  iface="$(iw dev 2>/dev/null | awk '$1=="Interface"{print $2; exit}' || true)"
  [[ -n "$iface" ]] || return 0
  iw dev "$iface" set power_save off >/dev/null 2>&1 || sudo -n iw dev "$iface" set power_save off >/dev/null 2>&1 || true
}

start_inhibit() {
  if systemctl --user is-active --quiet "$INHIBIT_UNIT" 2>/dev/null; then
    return 0
  fi
  systemd-run --user --unit="$INHIBIT_UNIT" \
    --description="Rig Server Mode Sleep Inhibitor" \
    systemd-inhibit --what=idle:sleep:handle-lid-switch \
      --who="server-mode" --why="Server/AFK mode" --mode=block \
      sleep infinity >/dev/null 2>&1 || true
}

stop_inhibit() {
  systemctl --user stop "$INHIBIT_UNIT" >/dev/null 2>&1 || true
  systemctl --user reset-failed "$INHIBIT_UNIT" >/dev/null 2>&1 || true
}

read_state() {
  MODE="auto"
  MANUAL_TARGET="low"
  if [[ -f "$STATE_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$STATE_FILE" 2>/dev/null || true
  fi
}

write_state() {
  local mode="$1"
  local target="${2:-low}"
  mkdir -p "$RUNTIME_DIR"
  local tmp="${STATE_FILE}.tmp.$$"
  printf 'MODE=%q\nMANUAL_TARGET=%q\n' "$mode" "$target" > "$tmp"
  mv -f "$tmp" "$STATE_FILE"
}

reconcile_unlocked() {
  read_state
  local cap status
  read -r cap status < <(battery_info)

  # Critical battery failsafe (< 15% discharging drops server mode and suspends)
  if [[ "$MODE" == "server" && "$status" == "Discharging" && "$cap" -lt 15 ]]; then
    write_state "auto" "low"
    rm -f "$SERVER_FLAG"
    stop_inhibit
    powerprofilesctl set power-saver >/dev/null 2>&1 || true
    notify-send -u critical "Server Mode" "Battery at ${cap}% — dropping server mode and suspending." 2>/dev/null || true
    pkill -RTMIN+8 waybar 2>/dev/null || true
    systemctl suspend >/dev/null 2>&1 || true
    return 0
  fi

  case "$MODE" in
    auto)
      rm -f "$SERVER_FLAG"
      stop_inhibit
      if is_on_ac; then
        powerprofilesctl set balanced >/dev/null 2>&1 || true
      else
        powerprofilesctl set power-saver >/dev/null 2>&1 || true
      fi
      ;;
    manual)
      rm -f "$SERVER_FLAG"
      stop_inhibit
      if [[ "$MANUAL_TARGET" == "high" ]]; then
        powerprofilesctl set performance >/dev/null 2>&1 || powerprofilesctl set balanced >/dev/null 2>&1 || true
      else
        powerprofilesctl set power-saver >/dev/null 2>&1 || true
      fi
      ;;
    server)
      touch "$SERVER_FLAG"
      powerprofilesctl set power-saver >/dev/null 2>&1 || true
      start_inhibit
      wifi_powersave_off
      ;;
  esac
}

reconcile() {
  mkdir -p "$RUNTIME_DIR"
  (
    flock -x 9
    reconcile_unlocked
  ) 9>"$LOCK_FILE"
}

set_mode() {
  local req="$1"
  mkdir -p "$RUNTIME_DIR"
  (
    flock -x 9
    case "$req" in
      auto)   write_state "auto" "low" ;;
      low)    write_state "manual" "low" ;;
      high)   write_state "manual" "high" ;;
      server) write_state "server" "low" ;;
      *)      echo "Usage: power-mode.sh [status|reconcile|menu|set <auto|low|high|server>]" >&2; exit 2 ;;
    esac
    reconcile_unlocked
  ) 9>"$LOCK_FILE"
  pkill -RTMIN+8 waybar 2>/dev/null || true
}

cmd_status() {
  reconcile
  read_state
  local ac_label profile text cls tooltip
  if is_on_ac; then
    ac_label="AC"
  else
    ac_label="Battery"
  fi

  if [[ "$MODE" == "auto" ]]; then
    if is_on_ac; then
      text="󰚥 Auto"
      cls="auto"
    else
      text="󰌪 Auto"
      cls="low"
    fi
  elif [[ "$MODE" == "manual" && "$MANUAL_TARGET" == "high" ]]; then
    text="󰗑 High"
    cls="high"
  elif [[ "$MODE" == "manual" ]]; then
    text="󰌪 Low"
    cls="low"
  else
    text="󰒍 Server"
    cls="server"
  fi

  profile="$(powerprofilesctl get 2>/dev/null || echo unknown)"
  if [[ "$MODE" == "server" ]]; then
    tooltip="Mode: Server / AFK (${ac_label}) | Profile: ${profile} | Sleep & lid-suspend blocked | Peek re-blanks in 25s"
  else
    tooltip="Mode: ${MODE}${MODE:+ (${MANUAL_TARGET})} (${ac_label}) | Profile: ${profile} | Click to switch"
  fi

  printf '{"text":"%s","tooltip":"%s","class":"%s"}\n' "$text" "$tooltip" "$cls"
}

cmd_menu() {
  local font_size="${1:-15}"
  local choice confirm
  choice=$(printf "Auto (AC/Battery)\nLow Power\nHigh Power\nServer / AFK" | \
    "$HOME/.config/hypr/scripts/rofi-toggle.sh" -dmenu -theme "$HOME/.config/rofi/dropdown.rasi" -i -p "Power: " -l 4 \
      -theme-str "window { width: 280px; } * { font: \"JetBrainsMono Nerd Font ${font_size}\"; }") || exit 0

  case "$choice" in
    "Auto (AC/Battery)") set_mode "auto" ;;
    "Low Power")         set_mode "low" ;;
    "High Power")        set_mode "high" ;;
    "Server / AFK")
      confirm=$(printf "Yes\nNo" | \
        rofi -dmenu -theme "$HOME/.config/rofi/dropdown.rasi" -i -p "Enable Server/AFK? " -l 2 \
          -mesg "Caps CPU, blocks sleep/lid-suspend, Wi-Fi power-save OFF, debounced DPMS off (Peek re-blanks in 25s)." \
          -theme-str "window { width: 420px; } * { font: \"JetBrainsMono Nerd Font ${font_size}\"; }") || exit 0
      [[ "$confirm" == "Yes" ]] || exit 0
      set_mode "server"
      # Debounce so key-release doesn't immediately wake DPMS
      (sleep 0.7 && hyprctl dispatch dpms off >/dev/null 2>&1 || true) &
      return 0
      ;;
    *) exit 0 ;;
  esac
}

case "${1:-status}" in
  status)    cmd_status ;;
  reconcile) reconcile; pkill -RTMIN+8 waybar 2>/dev/null || true ;;
  menu)      cmd_menu "${2:-}" ;;
  set)       set_mode "${2:-auto}" ;;
esac
