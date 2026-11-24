#!/usr/bin/env bash
set -euo pipefail

case "${1:-}" in
  close)
    if [[ "$(hyprctl monitors -j | jq length)" -gt 1 ]]; then
      hyprctl keyword monitor "eDP-1, disable"
    else
      hyprctl dispatch dpms off
    fi
    ;;
  open)
    hyprctl keyword monitor "eDP-1, 1920x1080@60, 384x1152, 1.5"
    hyprctl dispatch dpms on
    ;;
esac
