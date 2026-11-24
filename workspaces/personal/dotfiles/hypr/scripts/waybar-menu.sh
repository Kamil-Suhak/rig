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
    tmp_cfg="$(mktemp)"
    sed "s|rofi -dmenu|rofi -dmenu -theme-str '${theme_override}'|" "$HOME/.config/networkmanager-dmenu/config.ini" > "$tmp_cfg"
    networkmanager_dmenu --config "$tmp_cfg"
    rm -f "$tmp_cfg"
    ;;
  bluetooth)
    bzmenu -l custom --launcher-command "rofi -dmenu -theme ~/.config/rofi/dropdown.rasi -i -p '󰂯  ' -theme-str '${theme_override}'"
    ;;
esac
