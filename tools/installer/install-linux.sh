#!/usr/bin/env bash
# Bunny Beat Down for Linux: put it in your applications menu and a launcher
# on your desktop (Bun in his acorn helmet as the icon). Packed into the Linux
# download by the release workflow; run it from the folder you extracted:
#   ./install.sh            add the menu entry and desktop launcher
#   ./install.sh --remove   take them away again (the game folder stays)
# Saves and settings live in ~/.local/share/godot and are never touched.
set -euo pipefail
HERE="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
APPS="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
ICONS="${XDG_DATA_HOME:-$HOME/.local/share}/icons/hicolor/512x512/apps"
DESKTOP_DIR="$(xdg-user-dir DESKTOP 2>/dev/null || echo "$HOME/Desktop")"
ENTRY="bunny-beat-down.desktop"

if [ "${1:-}" = "--remove" ]; then
  rm -f "$APPS/$ENTRY" "$DESKTOP_DIR/$ENTRY" "$ICONS/bunny-beat-down.png"
  echo "Removed Bunny Beat Down from the menu and the desktop."
  exit 0
fi

EXEC="$HERE/BunnyBeatDown.x86_64"
if [ ! -f "$EXEC" ]; then
  echo "BunnyBeatDown.x86_64 isn't next to this script: run it from the folder you extracted." >&2
  exit 1
fi
chmod +x "$EXEC"
mkdir -p "$APPS" "$ICONS"
cp "$HERE/bunny-beat-down.png" "$ICONS/bunny-beat-down.png"
cat > "$APPS/$ENTRY" <<DESK
[Desktop Entry]
Type=Application
Version=1.0
Name=Bunny Beat Down
GenericName=Survival Roguelike
Comment=A bunny in an acorn helmet against 49 woodland critters who remember you
Exec="$EXEC"
Path=$HERE
Icon=bunny-beat-down
Terminal=false
Categories=Game;ActionGame;
Keywords=bunny;roguelike;battle royale;carrot;
StartupNotify=true
StartupWMClass=Bunny Beat Down
DESK
chmod +x "$APPS/$ENTRY"
if [ -d "$DESKTOP_DIR" ]; then
  cp "$APPS/$ENTRY" "$DESKTOP_DIR/$ENTRY"
  chmod +x "$DESKTOP_DIR/$ENTRY"
  # (GNOME only starts desktop launchers marked as trusted)
  gio set "$DESKTOP_DIR/$ENTRY" metadata::trusted true 2>/dev/null || true
fi
update-desktop-database "$APPS" 2>/dev/null || true
gtk-update-icon-cache "${ICONS%/512x512/apps}" 2>/dev/null || true
echo "Bunny Beat Down is in your applications menu and on your desktop."
