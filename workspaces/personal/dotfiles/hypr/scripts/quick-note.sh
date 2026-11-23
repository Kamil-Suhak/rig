#!/usr/bin/env bash
set -euo pipefail

text=$("$HOME/.config/hypr/scripts/fuzzel-toggle.sh" --dmenu --prompt-only="Note: " --width=60) || exit 0
[ -n "${text// }" ] || exit 0

if out=$("$HOME/code/projects/rig/configs/bin/note" -a "$text" 2>&1); then
  notify-send "Note saved" "$out"
else
  notify-send -u critical "Note failed" "$out"
fi
