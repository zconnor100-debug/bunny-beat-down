#!/usr/bin/env bash
# Bunny Beat Down — import every character GLB into a throwaway Godot project and
# verify it (see godot_check.gd). Never runs Godot on the real project, so the
# editor's import cache there is left alone.
#   tools/characters/godot_check.sh [godot-binary]     (default: ~/bin/godot4)
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
GODOT="${1:-$HOME/bin/godot4}"
WORK="/tmp/bbd-charcheck"
rm -rf "$WORK/chars" "$WORK/.godot"
mkdir -p "$WORK/chars"
cat > "$WORK/project.godot" <<'PRJ'
; Throwaway project: import check for Bunny Beat Down character GLBs.
config_version=5

[application]
config/name="bbd-charcheck"
PRJ
cp "$HERE/godot_check.gd" "$WORK/check.gd"
for dir in "$ROOT"/assets/characters/*/; do
  id="$(basename "$dir")"
  [ -f "$dir/$id.glb" ] || continue
  mkdir -p "$WORK/chars/$id"
  cp "$dir/$id.glb" "$dir/$id.rig.json" "$WORK/chars/$id/"
  if [ -f "$dir/skins.json" ]; then
    cp "$dir/skins.json" "$WORK/chars/$id/"
    cp -r "$dir/skins" "$WORK/chars/$id/"
  fi
done
"$GODOT" --headless --path "$WORK" --import >/dev/null 2>&1
"$GODOT" --headless --path "$WORK" -s res://check.gd 2>&1 | grep -v '^Godot Engine' | grep -v '^$'
