#!/usr/bin/env bash
set -euo pipefail

RAW_DIR="$HOME/notes/raw"
if [ ! -d "$RAW_DIR" ]; then
  notify-send "note-picker" "No raw notes directory at $RAW_DIR"
  exit 1
fi

mapfile -t files < <(ls -t "$RAW_DIR"/*.md 2>/dev/null || true)
if [ "${#files[@]}" -eq 0 ]; then
  notify-send "note-picker" "No raw notes found."
  exit 1
fi

menu=""
for f in "${files[@]}"; do
  base="$(basename "$f" .md)"
  preview="$(grep -m1 -v '^[[:space:]]*$' "$f" 2>/dev/null | sed 's/^[#*-]*[[:space:]]*//' | cut -c1-55 || true)"
  if [ -n "$preview" ]; then
    menu+="${base}  —  ${preview}"$'\n'
  else
    menu+="${base}"$'\n'
  fi
done

idx=$(printf '%s' "$menu" | "$HOME/.config/hypr/scripts/rofi-toggle.sh" -dmenu -format i -i -p "raw> " -theme-str "window { width: 760px; }") || exit 0
[ -n "$idx" ] || exit 0

chosen="$(basename "${files[$idx]}" .md)"
exec xdg-open "obsidian://open?vault=notes&file=raw%2F${chosen}"
