#!/usr/bin/env bash
set -euo pipefail

ACTIVE_FILE="/tmp/waybar-menu-active"
target="${1:-}"
[[ -n "$target" ]] || exit 1

if pgrep -x rofi >/dev/null 2>&1; then
  prev="$(cat "$ACTIVE_FILE" 2>/dev/null || true)"
  pkill -x rofi 2>/dev/null || true
  sleep 0.05
  if [[ "$prev" == "$target" ]]; then
    rm -f "$ACTIVE_FILE"
    exit 0
  fi
fi

font_size=13
cursor_json="$(hyprctl cursorpos -j 2>/dev/null || true)"
if [[ -n "$cursor_json" ]]; then
  hover_mon="$(hyprctl monitors -j 2>/dev/null | jq -r --argjson c "$cursor_json" \
    '.[] | select($c.x >= .x and $c.x < (.x + (.width / .scale)) and $c.y >= .y and $c.y < (.y + (.height / .scale))) | .name' | head -n1 || true)"
else
  hover_mon="$(hyprctl monitors -j 2>/dev/null | jq -r '.[] | select(.focused) | .name' || true)"
fi
if [[ "$hover_mon" == "eDP-1" ]]; then
  font_size=10
fi
theme_override="* { font: \"JetBrainsMono Nerd Font ${font_size}\"; }"

echo "$target" > "$ACTIVE_FILE"
trap 'rm -f "$ACTIVE_FILE"' EXIT

case "$target" in
  power)
    "$HOME/.config/hypr/scripts/power-mode.sh" menu "$font_size"
    ;;
  wifi)
    "$HOME/.config/hypr/scripts/network-menu.sh" "$font_size"
    ;;
  bluetooth)
    bzmenu -l custom --launcher-command "rofi -dmenu -theme ~/.config/rofi/dropdown.rasi -i -p '󰂯  ' -theme-str '${theme_override}'"
    ;;
  audio)
    if command -v wiremix >/dev/null 2>&1; then
      exec ghostty --class=com.audio.tui -e wiremix
    elif command -v pulsemixer >/dev/null 2>&1; then
      exec ghostty --class=com.audio.tui -e pulsemixer
    else
      exec pavucontrol
    fi
    ;;
esac
