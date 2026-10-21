#!/usr/bin/env bash
# Launch Bunny Beat Down with a local Godot 4.6 binary.
# Uses $GODOT if set, otherwise godot4 / godot on PATH or in the usual places.
# When started from a desktop launcher (no terminal) output goes to a log file.
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"
find_godot() {
  for c in "${GODOT:-}" "$(command -v godot4 || true)" "$(command -v godot || true)" \
           "$HOME/bin/godot4" "$HOME/.local/bin/godot4" /snap/bin/godot4 /usr/local/bin/godot4; do
    if [ -n "$c" ] && [ -x "$c" ]; then echo "$c"; return; fi
  done
}
GODOT="$(find_godot)"
if [ -z "$GODOT" ]; then
  echo "Godot 4.6 not found — install it or set GODOT=/path/to/godot" >&2
  exit 1
fi
if [ ! -t 1 ]; then
  exec >>"${TMPDIR:-/tmp}/bunny-beat-down.log" 2>&1
  echo "--- $(date) --- $GODOT"
fi
if [ ! -d .godot ]; then
  echo "First run: importing assets (about a minute)…"
  "$GODOT" --headless --path . --import >/dev/null 2>&1 || true
fi
exec "$GODOT" --path . "$@"
