#!/usr/bin/env bash
# Import-check the environment kit in a throwaway Godot project (never the real one).
#   tools/env/godot_check.sh [godot binary]
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
GODOT="${1:-$HOME/bin/godot4}"
CHECK=/tmp/bbd-envcheck

rm -rf "$CHECK"
mkdir -p "$CHECK/assets"
cp -r "$ROOT/assets/env" "$ROOT/assets/textures" "$ROOT/assets/sky" "$CHECK/assets/"
find "$CHECK" -name "*.import" -delete   # start from a clean import, not the real project's settings
cp "$ROOT/tools/env/godot_check.gd" "$CHECK/"
cat > "$CHECK/project.godot" <<'EOF'
config_version=5

[application]
config/name="bbd-envcheck"
EOF

"$GODOT" --headless --path "$CHECK" --import 2>&1 | grep -iE "error|warn|fail" | grep -v "^$" | head -40 || true
"$GODOT" --headless --path "$CHECK" -s res://godot_check.gd
