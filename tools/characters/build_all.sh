#!/usr/bin/env bash
# Bunny Beat Down — rebuild the whole character roster from the cached downloads.
#   tools/characters/build_all.sh [id ...]        (default: every id in roster.json)
# 1. download anything missing (needs ~/.config/sketchfab/token)
# 2. normalize -> assets/characters/<id>/<id>.glb + <id>.rig.json
# 3. preview.png per character, lineup.png for the roster
# 4. assets/credits/characters.json
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
BLENDER="${BLENDER:-/snap/bin/blender}"
cd "$ROOT"
if [ "$#" -gt 0 ]; then IDS=("$@"); else
  mapfile -t IDS < <(python3 -I -c "import json,sys; print('\n'.join(k for k in json.load(open(sys.argv[1])) if not k.startswith('_')))" "$HERE/roster.json")
fi
for id in "${IDS[@]}"; do
  uid=$(python3 -I -c "import json,sys; print(json.load(open(sys.argv[1]))[sys.argv[2]]['uid'])" "$HERE/roster.json" "$id")
  [ -f "tools/_cache/characters/$id/source.glb" ] || python3 -I "$HERE/sketchfab_fetch.py" fetch "$uid" "$id"
  "$BLENDER" --background --python "$HERE/normalize.py" -- "$id" 2>&1 | grep -E '^NORMALIZE|Error|Traceback' || true
  title=$(python3 -I -c "import json,sys; print(json.load(open(sys.argv[1]))['display_name'])" "assets/characters/$id/$id.rig.json")
  "$BLENDER" --background --python "$HERE/render_preview.py" -- "assets/characters/$id/$id.glb" \
      "assets/characters/$id/preview.png" --title "$title" --res 640 2>&1 | grep -E '^PREVIEW|Error' || true
done
"$BLENDER" --background --python "$HERE/render_lineup.py" -- assets/characters/lineup.png --res 2400 2>&1 | grep -E '^LINEUP|Error' || true
python3 -I "$HERE/write_credits.py"
