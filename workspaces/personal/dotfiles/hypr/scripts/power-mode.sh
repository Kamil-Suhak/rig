#!/usr/bin/env bash
set -euo pipefail

STATE_FILE="/tmp/power-mode"
PID_FILE="/tmp/power-mode-inhibit.pid"

is_on_ac() {
  local f
  for f in /sys/class/power_supply/A*/online; do
    if [[ -r "$f" ]] && [[ "$(cat "$f")" == "1" ]]; then
      return 0
    fi
  done
  return 1
}

stop_inhibit() {
  if [[ -f "$PID_FILE" ]]; then
    local pid
    pid="$(cat "$PID_FILE" 2>/dev/null || true)"
    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
      kill "$pid" 2>/dev/null || true
    fi
    rm -f "$PID_FILE"
  fi
}

start_inhibit() {
  if [[ -f "$PID_FILE" ]]; then
    local pid
    pid="$(cat "$PID_FILE" 2>/dev/null || true)"
    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
      return 0
    fi
  fi
  systemd-inhibit --what=sleep:handle-lid-switch --who="power-mode" --why="Server/AFK mode" sleep infinity >/dev/null 2>&1 &
  echo $! > "$PID_FILE"
}

get_mode() {
  if [[ -f "$STATE_FILE" ]]; then
    cat "$STATE_FILE"
  else
    echo "auto"
  fi
}

apply_mode() {
  local mode="$1"
  echo "$mode" > "$STATE_FILE"
  case "$mode" in
    auto)
      stop_inhibit
      if is_on_ac; then
        powerprofilesctl set balanced >/dev/null 2>&1 || true
      else
        powerprofilesctl set power-saver >/dev/null 2>&1 || true
      fi
      ;;
    low)
      stop_inhibit
      powerprofilesctl set power-saver >/dev/null 2>&1 || true
      ;;
    high)
      stop_inhibit
      powerprofilesctl set performance >/dev/null 2>&1 || powerprofilesctl set balanced >/dev/null 2>&1 || true
      ;;
    server)
      powerprofilesctl set power-saver >/dev/null 2>&1 || true
      start_inhibit
      ;;
  esac
}

cmd_status() {
  local mode ac_label profile text cls tooltip
  mode="$(get_mode)"

  if is_on_ac; then
    ac_label="AC"
  else
    ac_label="Battery"
  fi

  if [[ "$mode" == "auto" ]]; then
    if is_on_ac; then
      powerprofilesctl set balanced >/dev/null 2>&1 || true
      text="󰚥 Auto"
      cls="auto"
    else
      powerprofilesctl set power-saver >/dev/null 2>&1 || true
      text="󰌪 Auto"
      cls="low"
    fi
  elif [[ "$mode" == "low" ]]; then
    text="󰌪 Low"
    cls="low"
  elif [[ "$mode" == "high" ]]; then
    text="󰗑 High"
    cls="high"
  else
    text="󰒍 Server"
    cls="server"
  fi

  profile="$(powerprofilesctl get 2>/dev/null || echo unknown)"
  if [[ "$mode" == "server" ]]; then
    tooltip="Mode: Server / AFK (${ac_label}) | Profile: ${profile} | Sleep and lid-suspend blocked"
  else
    tooltip="Mode: ${mode} (${ac_label}) | Profile: ${profile} | Click to switch"
  fi

  printf '{"text":"%s","tooltip":"%s","class":"%s"}\n' "$text" "$tooltip" "$cls"
}

cmd_menu() {
  local font_opt="${1:-JetBrainsMono Nerd Font:size=15}"
  local choice
  choice=$(printf "Auto (AC/Battery)\nLow Power\nHigh Power\nServer / AFK" | \
    fuzzel --dmenu --anchor=top-right --x-margin=12 --y-margin=8 --width=32 --lines=4 --font="$font_opt" --prompt="Power: ") || exit 0

  case "$choice" in
    "Auto (AC/Battery)") apply_mode "auto" ;;
    "Low Power")         apply_mode "low" ;;
    "High Power")        apply_mode "high" ;;
    "Server / AFK")      apply_mode "server" ;;
    *) exit 0 ;;
  esac

  pkill -RTMIN+8 waybar 2>/dev/null || true
}

case "${1:-status}" in
  status) cmd_status ;;
  menu)   cmd_menu "${2:-}" ;;
  set)    apply_mode "${2:-auto}"; pkill -RTMIN+8 waybar 2>/dev/null || true ;;
esac
