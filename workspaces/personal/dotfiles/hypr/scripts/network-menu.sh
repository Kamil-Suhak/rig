#!/usr/bin/env bash
# Custom nmcli-backed Rofi network menu (Ethernet + Wi-Fi, no Bluetooth duplication).
set -euo pipefail

font_size="${1:-13}"
theme_override="* { font: \"JetBrainsMono Nerd Font ${font_size}\"; }"
rofi_cmd=(rofi -dmenu -theme "$HOME/.config/rofi/dropdown.rasi" -i -theme-str "$theme_override")

wifi_icon() {
  local sig="${1:-0}"
  if (( sig >= 75 )); then printf '󰤨'
  elif (( sig >= 50 )); then printf '󰤥'
  elif (( sig >= 25 )); then printf '󰤢'
  else printf '󰤟'
  fi
}

build_menu() {
  local entries=()

  # 1. Wired / Ethernet devices (always shown even if Wi-Fi is disabled)
  while IFS=: read -r dev state conn; do
    [[ -z "$dev" ]] && continue
    if [[ "$state" == "connected" ]]; then
      entries+=("󰈀  ${dev} (${conn:-wired})  ✓|eth-disconnect|${dev}")
    elif [[ "$state" == "disconnected" ]]; then
      entries+=("󰈀  Connect ${dev}|eth-connect|${dev}")
    else
      entries+=("󰈂  ${dev} (${state})|noop|${dev}")
    fi
  done < <(nmcli -t -f DEVICE,STATE,CONNECTION device status | awk -F: '$0 ~ /:ethernet:/ || $1 ~ /^(en|eth)/ { print $1 ":" $2 ":" $3 }' || true)

  # 2. Wi-Fi radio toggle (always shown)
  local wifi_state
  wifi_state="$(nmcli radio wifi 2>/dev/null || echo "disabled")"
  if [[ "$wifi_state" == "enabled" ]]; then
    entries+=("󰤭  Disable Wi-Fi|wifi-off|")
    entries+=("󰑐  Rescan Wi-Fi|wifi-rescan|")

    # 3. Deduplicated Wi-Fi networks sorted by signal strength
    declare -A seen_ssid=()
    while IFS=: read -r in_use ssid sec sig; do
      [[ -z "$ssid" ]] && continue
      [[ -n "${seen_ssid[$ssid]:-}" ]] && continue
      seen_ssid["$ssid"]=1
      local icon lock_icon active_mark
      icon="$(wifi_icon "${sig:-0}")"
      lock_icon=""
      [[ -n "$sec" && "$sec" != "--" ]] && lock_icon=" 󰌾"
      active_mark=""
      [[ "$in_use" == "*" ]] && active_mark="  ✓"
      entries+=("${icon}  ${ssid}${lock_icon}  (${sig}%)${active_mark}|wifi-connect|${ssid}|${sec}")
    done < <(nmcli -t -f IN-USE,SSID,SECURITY,SIGNAL device wifi list 2>/dev/null | sort -t: -k4 -rn || true)
  else
    entries+=("󰤨  Enable Wi-Fi|wifi-on|")
  fi

  printf '%s\n' "${entries[@]}"
}

mapfile -t raw_entries < <(build_menu)
[[ "${#raw_entries[@]}" -eq 0 ]] && exit 0

display_list=()
for row in "${raw_entries[@]}"; do
  display_list+=("${row%%|*}")
done

idx="$(printf '%s\n' "${display_list[@]}" | "${rofi_cmd[@]}" -format i -p "󰤨  " || true)"
[[ -z "$idx" ]] && exit 0

chosen="${raw_entries[$idx]}"
IFS='|' read -r _label action arg1 arg2 <<<"$chosen"

case "$action" in
  wifi-on)
    nmcli radio wifi on
    ;;
  wifi-off)
    nmcli radio wifi off
    ;;
  wifi-rescan)
    nmcli device wifi rescan 2>/dev/null || true
    exec "$0" "$font_size"
    ;;
  eth-connect)
    nmcli device connect "$arg1"
    ;;
  eth-disconnect)
    nmcli device disconnect "$arg1"
    ;;
  wifi-connect)
    ssid="$arg1"
    sec="${arg2:-}"
    if nmcli -t -f NAME connection show | grep -Fxq "$ssid"; then
      nmcli connection up "$ssid"
    elif [[ -n "$sec" && "$sec" != "--" ]]; then
      pass="$("${rofi_cmd[@]}" -password -p "󰌾  Password for ${ssid}: " </dev/null || true)"
      [[ -n "$pass" ]] && nmcli device wifi connect "$ssid" password "$pass"
    else
      nmcli device wifi connect "$ssid"
    fi
    ;;
  *)
    ;;
esac
