#!/usr/bin/env bash
set -euo pipefail

if pkill -x rofi; then
  exit 0
fi

exec rofi "$@"
