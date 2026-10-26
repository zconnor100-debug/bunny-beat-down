#!/usr/bin/env bash
# Bunny Beat Down: update to the newest release. Packed into the Linux
# download as update.sh, and run from "Update Bunny Beat Down" when you
# right-click the launcher (in the applications menu and the dock; on the
# GNOME desktop under Scripts). It asks GitHub for the latest release, and if
# it's newer than the one in the game folder (version.txt), downloads it,
# puts the new game in place (saves and settings are never touched) and starts
# it.
#   update.sh [game folder]   (default: the folder this script is in)
#   update.sh --check [game folder]   just say whether there's something newer
set -euo pipefail
REPO="zconnor100-debug/bunny-beat-down"
ASSET="BunnyBeatDown-linux-x86_64.tar.xz"
CHECK=0
if [ "${1:-}" = "--check" ]; then CHECK=1; shift; fi
GAME="$(cd "${1:-$(dirname "$(readlink -f "$0")")}" && pwd)"
ICON="$GAME/bunny-beat-down.png"
[ -f "$ICON" ] || ICON="$(dirname "$(readlink -f "$0")")/../../icon.png"

say() {   # (a notification when there's a desktop, and the terminal either way)
  echo "$1"
  if [ "$CHECK" = 0 ]; then notify-send -i "$ICON" "Bunny Beat Down" "$1" 2>/dev/null || true; fi
}
newer() {   # is version $1 newer than $2?
  [ "$1" != "$2" ] && [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -n 1)" = "$1" ]
}

have="$(cat "$GAME/version.txt" 2>/dev/null || echo 0)"
json="$(curl -fsSL -H "User-Agent: BunnyBeatDown-updater" "https://api.github.com/repos/$REPO/releases/latest")" || {
  say "Couldn't reach GitHub to check for updates."; exit 1; }
latest="$(printf '%s' "$json" | grep -o '"tag_name": *"[^"]*"' | head -n 1 | sed 's/.*"v\{0,1\}\([^"]*\)"$/\1/')"
if ! newer "$latest" "$have"; then
  say "You have the newest version ($have). Have fun!"
  exit 0
fi
if [ "$CHECK" = 1 ]; then echo "Version $latest is out."; exit 0; fi
url="$(printf '%s' "$json" | grep -o "\"browser_download_url\": *\"[^\"]*/$ASSET\"" | head -n 1 | sed 's/.*"\(https[^"]*\)"$/\1/')"
if [ -z "$url" ]; then say "Version $latest has no Linux download yet: try again in a few minutes."; exit 1; fi
if pidof BunnyBeatDown.x86_64 > /dev/null; then
  say "Close Bunny Beat Down first, then update again."
  exit 1
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
say "Downloading version $latest..."
if command -v zenity > /dev/null && [ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]; then
  # (a progress window: curl's percentage, as zenity reads it)
  curl -fL --progress-bar -o "$tmp/$ASSET" "$url" 2>&1 \
    | stdbuf -oL tr '\r' '\n' | stdbuf -oL grep -o '[0-9]*\.[0-9]%' | stdbuf -oL tr -d '%' \
    | zenity --progress --title "Bunny Beat Down" --text "Downloading version $latest..." --auto-close --no-cancel 2>/dev/null || true
  [ -s "$tmp/$ASSET" ] || curl -fL -o "$tmp/$ASSET" "$url"
else
  curl -fL --progress-bar -o "$tmp/$ASSET" "$url"
fi
mkdir -p "$tmp/x"
tar -xJf "$tmp/$ASSET" -C "$tmp/x"
NEW="$tmp/x/BunnyBeatDown"
[ -d "$NEW" ] || NEW="$tmp/x"   # (older downloads had no folder)
# the new game, and the new scripts, into the game folder
cp -f "$NEW/BunnyBeatDown.x86_64" "$NEW/BunnyBeatDown.pck" "$GAME/"
for f in install.sh update.sh bunny-beat-down.png; do
  if [ -f "$GAME/$f" ] && [ -f "$NEW/$f" ]; then cp -f "$NEW/$f" "$GAME/$f"; fi
done
echo "$latest" > "$GAME/version.txt"
chmod +x "$GAME/BunnyBeatDown.x86_64"
say "Updated to version $latest. Starting the game..."
if [ "${BBD_TEST:-}" != "1" ]; then   # (automated runs just check the files)
  (cd "$GAME" && nohup ./BunnyBeatDown.x86_64 > /dev/null 2>&1 &)
fi
