#!/usr/bin/env bash
set -euo pipefail

choice=$(printf "Python\nTypst\nRust\nC++\nFlutter\n.NET\nWeb" | "$HOME/.config/hypr/scripts/fuzzel-toggle.sh" --dmenu --prompt="VS Code: " --lines=7) || exit 0
[ -n "$choice" ] && exec code --profile "$choice"
