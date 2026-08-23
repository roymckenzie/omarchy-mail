#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")" && pwd)"
helper="$root/bin/omarchy-mail-helper"
chmod +x "$helper"
python3 "$helper" --test
echo "Python helper is ready at $helper (no compile step)."
