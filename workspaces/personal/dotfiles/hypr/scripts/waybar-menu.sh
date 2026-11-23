#!/usr/bin/env bash
set -euo pipefail

ACTIVE_FILE="/tmp/waybar-menu-active"
target="${1:-}"
[[ -n "$target" ]] || exit 1

if pgrep -x fuzzel >/dev/null 2>&1; then
  prev="$(cat "$ACTIVE_FILE" 2>/dev/null || true)"
  pkill -x fuzzel 2>/dev/null || true
  sleep 0.05
  if [[ "$prev" == "$target" ]]; then
    rm -f "$ACTIVE_FILE"
    exit 0
  fi
fi

font_size=15
focused_mon="$(hyprctl monitors -j 2>/dev/null | jq -r '.[] | select(.focused) | .name' || true)"
if [[ "$focused_mon" == "eDP-1" ]]; then
  font_size=13
fi
font_opt="JetBrainsMono Nerd Font:size=${font_size}"

echo "$target" > "$ACTIVE_FILE"
trap 'rm -f "$ACTIVE_FILE"' EXIT

case "$target" in
  power)
    "$HOME/.config/hypr/scripts/power-mode.sh" menu "$font_opt"
    ;;
  wifi)
    if [[ "$font_size" == "13" ]]; then
      tmp_cfg="$(mktemp)"
      sed "s|fuzzel --dmenu|fuzzel --dmenu --font=\"${font_opt}\"|" "$HOME/.config/networkmanager-dmenu/config.ini" > "$tmp_cfg"
      networkmanager_dmenu --config "$tmp_cfg"
      rm -f "$tmp_cfg"
    else
      networkmanager_dmenu
    fi
    ;;
  bluetooth)
    bzmenu -l custom --launcher-command "fuzzel --dmenu --anchor=top-right --x-margin=12 --y-margin=8 --width=38 --lines=10 --font='${font_opt}' --prompt='󰂯  '"
    ;;
esac
