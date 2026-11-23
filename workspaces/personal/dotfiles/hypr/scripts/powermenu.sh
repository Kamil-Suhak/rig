#!/usr/bin/env bash
set -euo pipefail

choice=$(printf "Lock\nSuspend\nLogout\nReboot\nShutdown" | "$HOME/.config/hypr/scripts/fuzzel-toggle.sh" --dmenu --prompt="Power: " --lines=5) || exit 0

case "$choice" in
  Lock) hyprlock ;;
  Suspend) systemctl suspend ;;
  Logout) hyprctl dispatch exit ;;
  Reboot) systemctl reboot ;;
  Shutdown) systemctl poweroff ;;
esac
