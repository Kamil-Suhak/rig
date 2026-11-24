#!/usr/bin/env bash
set -euo pipefail

choice=$(printf "Python\nTypst\nRust\nC++\nFlutter\n.NET\nWeb" | "$HOME/.config/hypr/scripts/rofi-toggle.sh" -dmenu -i -p "VS Code: " -l 7 -theme-str "window { width: 320px; }") || exit 0
[ -n "$choice" ] && exec code --profile "$choice"
