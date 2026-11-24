#!/usr/bin/env bash
set -euo pipefail

choice=$(printf "Lock\nSuspend\nLogout\nReboot\nShutdown" | \
  "$HOME/.config/hypr/scripts/rofi-toggle.sh" -dmenu -i -p "Power: " -l 5 -theme-str "window { width: 320px; }") || exit 0

case "$choice" in
  Lock)     hyprlock ;;
  Suspend)  systemctl suspend ;;
  Logout)   hyprctl dispatch exit ;;
  Reboot)   systemctl reboot ;;
  Shutdown) systemctl poweroff ;;
esac
