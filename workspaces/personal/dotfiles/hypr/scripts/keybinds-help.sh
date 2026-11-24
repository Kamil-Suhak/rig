#!/usr/bin/env bash
set -euo pipefail

CONF="$HOME/.config/hypr/keybinds.lua"
[ -f "$CONF" ] || exit 1

list=$(python3 - "$CONF" <<'PY'
import re
import sys
from pathlib import Path

text = Path(sys.argv[1]).read_text(encoding="utf-8", errors="replace")
pat = re.compile(
    r'hl\.bind\(\s*(?:mainMod\s*\.\.\s*"\s*\+\s*([^"]+)"|"([^"]+)")\s*,\s*(.+?)\)\s*(?:--\s*(.*))?$'
)
for line in text.splitlines():
    m = pat.search(line.strip())
    if not m:
        continue
    key = f"SUPER + {m.group(1)}" if m.group(1) else m.group(2)
    comment = (m.group(4) or "").strip()
    if comment:
        desc = comment
    else:
        desc = re.sub(r'^hl\.dsp\.exec_cmd\((.*)\)$', r'\1', m.group(3).strip()).strip('"\'')
    print(f"{key:<24}  {desc}")
PY
)

printf '%s\n' "$list" | "$HOME/.config/hypr/scripts/rofi-toggle.sh" -dmenu -i -p "keys> " -theme-str "window { width: 820px; }" >/dev/null || true
