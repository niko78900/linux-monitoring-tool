#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if command -v python >/dev/null 2>&1; then
  PYTHON_BIN=(python)
elif command -v python.exe >/dev/null 2>&1; then
  PYTHON_BIN=(python.exe)
elif command -v python3 >/dev/null 2>&1; then
  PYTHON_BIN=(python3)
elif command -v py >/dev/null 2>&1; then
  PYTHON_BIN=(py -3)
elif command -v py.exe >/dev/null 2>&1; then
  PYTHON_BIN=(py.exe -3)
else
  echo "Python was not found in PATH. Install Python or activate the project environment, then rerun this script." >&2
  exit 127
fi

echo "== backend =="
cd "$ROOT_DIR/backend"
"${PYTHON_BIN[@]}" -m pytest -q

echo "== control_agent =="
cd "$ROOT_DIR/control_agent"
"${PYTHON_BIN[@]}" -m pytest -q

echo "== mobile =="
cd "$ROOT_DIR/mobile"
flutter analyze
flutter test

echo "Core checks passed."
