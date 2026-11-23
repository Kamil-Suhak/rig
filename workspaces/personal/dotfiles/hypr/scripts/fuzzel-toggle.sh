#!/usr/bin/env bash
set -euo pipefail

if pkill -x fuzzel; then
  exit 0
fi

exec fuzzel "$@"
