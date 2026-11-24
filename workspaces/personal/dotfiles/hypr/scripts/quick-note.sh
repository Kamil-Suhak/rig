#!/usr/bin/env bash
set -euo pipefail

text=$("$HOME/.config/hypr/scripts/rofi-toggle.sh" -dmenu -p "Note: " -l 0 -theme-str 'window { width: 640px; } listview { enabled: false; } entry { placeholder: ""; }') || exit 0
[ -n "${text// }" ] || exit 0

if out=$("$HOME/code/projects/rig/configs/bin/note" -a "$text" 2>&1); then
  notify-send "Note saved" "$out"
else
  notify-send -u critical "Note failed" "$out"
fi
