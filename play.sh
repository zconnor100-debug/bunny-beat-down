#!/usr/bin/env bash
# Launch Bunny Beat Down with a local Godot 4.6 binary.
# Uses $GODOT if set, otherwise the first of godot4 / godot found on PATH.
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"
GODOT="${GODOT:-$(command -v godot4 || command -v godot || true)}"
if [ -z "$GODOT" ]; then
  echo "Godot 4.6 not found — install it or set GODOT=/path/to/godot" >&2
  exit 1
fi
if [ ! -d .godot ]; then
  echo "First run: importing assets (about a minute)…"
  "$GODOT" --headless --path . --import >/dev/null 2>&1 || true
fi
exec "$GODOT" --path . "$@"
