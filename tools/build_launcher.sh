#!/usr/bin/env bash
# Build the Linux game for the desktop launcher (build/linux, see
# tools/install_desktop.sh), stamped with its version the way the release
# workflow stamps downloads, so the game's own update check and update.sh
# agree on what's installed.
#   tools/build_launcher.sh [version]   (default: what this commit releases as,
#                                        or the latest release if it's unchanged)
# Exports into build/linux_next, smoke-tests it, and moves it into build/linux
# once the game isn't running (the previous build kept as build/linux_v<its
# version>; nothing is deleted).
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")/.."
GODOT="${GODOT:-$HOME/bin/godot4}"
git fetch -q --tags 2>/dev/null || true
V="${1:-}"
if [ -z "$V" ]; then
  out="$(python3 tools/release_version.py)"
  if grep -q "^release=yes" <<<"$out"; then
    V="$(sed -n 's/^version=//p' <<<"$out")"
  else
    V="$(git tag -l 'v*' --sort=-v:refname | head -n 1 | sed 's/^v//')"
  fi
fi
echo "building $V"
# (stamped for the export only: project.godot keeps the release line)
cp project.godot build/project.godot.unstamped
trap 'cp build/project.godot.unstamped project.godot && rm -f build/project.godot.unstamped' EXIT
python3 tools/release_version.py --stamp "$V"
rm -rf build/linux_next
mkdir -p build/linux_next
"$GODOT" --headless --path . --export-release "Linux" build/linux_next/BunnyBeatDown.x86_64 > build/linux_next.log 2>&1
echo "$V" > build/linux_next/version.txt
BBD_TEST=1 timeout 300 build/linux_next/BunnyBeatDown.x86_64 --headless -- --smoke-test --map island 2>&1 \
  | grep "SMOKE TEST PASS" || { echo "smoke test failed: build/linux_next not swapped in" >&2; exit 1; }
end=$(( $(date +%s) + 43200 ))
while pidof BunnyBeatDown.x86_64 > /dev/null; do
  [ "$(date +%s)" -gt "$end" ] && { echo "the game was open for 12 h: the new build waits in build/linux_next" >&2; exit 1; }
  sleep 15
done
keep=""
if [ -d build/linux ]; then
  keep="build/linux_v$(cat build/linux/version.txt 2>/dev/null || echo unknown)"
  [ -e "$keep" ] && keep="$keep-$(date +%Y%m%d-%H%M%S)"
  mv build/linux "$keep"
fi
mv build/linux_next build/linux
echo "build/linux is now $V${keep:+ (the previous build is in $keep)}"
