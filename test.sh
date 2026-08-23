#!/usr/bin/env bash
# Run unit tests. There is nothing to compile: QML is loaded by omarchy-shell,
# and the mail helper is a Python 3 script.
set -euo pipefail
root="$(cd "$(dirname "$0")" && pwd)"
helper="$root/bin/omarchy-mail-helper"
chmod +x "$helper"
python3 "$helper" --test

# Arch/Omarchy: /usr/bin/qmltestrunner is Qt 5 and fails silently on Qt 6 QML.
# The Qt 6 runner lives under /usr/lib/qt6/bin (package qt6-declarative).
find_qmltestrunner() {
  if [[ -n "${QMLTESTRUNNER:-}" && -x "${QMLTESTRUNNER}" ]]; then
    printf '%s\n' "$QMLTESTRUNNER"
    return 0
  fi
  local candidate
  for candidate in /usr/lib/qt6/bin/qmltestrunner /usr/lib64/qt6/bin/qmltestrunner; do
    if [[ -x "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  return 1
}

if runner="$(find_qmltestrunner)"; then
  QT_QPA_PLATFORM="${QT_QPA_PLATFORM:-offscreen}" \
    "$runner" -input "$root/tests" -o -,txt
else
  echo "qmltestrunner (Qt 6) not found; skip QML tests"
  echo "Install qt6-declarative, or set QMLTESTRUNNER to /usr/lib/qt6/bin/qmltestrunner"
fi
echo "Tests passed."
