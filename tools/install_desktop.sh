#!/usr/bin/env bash
# Install Bunny Beat Down as a desktop application (Linux, freedesktop.org).
# Adds an entry to the applications menu and a launcher on the Desktop, with
# Bun (in the acorn helmet, holding a carrot gun) as the icon.
#   ./tools/install_desktop.sh            install
#   ./tools/install_desktop.sh --remove   uninstall
# The launcher runs the standalone build in build/linux/ when one exists,
# otherwise play.sh (which runs the project through a local Godot 4.6).
set -euo pipefail
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
APPS="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
ICONS="${XDG_DATA_HOME:-$HOME/.local/share}/icons/hicolor/512x512/apps"
DESKTOP_DIR="$(xdg-user-dir DESKTOP 2>/dev/null || echo "$HOME/Desktop")"
ENTRY="bunny-beat-down.desktop"
SCRIPTS="${XDG_DATA_HOME:-$HOME/.local/share}/nautilus/scripts"
UPDATER="$ROOT/tools/installer/update-linux.sh"

if [ "${1:-}" = "--remove" ]; then
  rm -f "$APPS/$ENTRY" "$DESKTOP_DIR/$ENTRY" "$ICONS/bunny-beat-down.png" "$SCRIPTS/Update Bunny Beat Down"
  echo "Removed Bunny Beat Down from the menu and desktop."
  exit 0
fi

EXEC="$ROOT/play.sh"
if [ -x "$ROOT/build/linux/BunnyBeatDown.x86_64" ]; then
  EXEC="$ROOT/build/linux/BunnyBeatDown.x86_64"
fi

mkdir -p "$APPS" "$ICONS"
cp "$ROOT/icon.png" "$ICONS/bunny-beat-down.png"
cat > "$APPS/$ENTRY" <<DESK
[Desktop Entry]
Type=Application
Version=1.0
Name=Bunny Beat Down
GenericName=Battle Royale Game
Comment=A bunny in an acorn helmet vs. AI woodland critters, with carrot guns
Exec="$EXEC"
Path=$(dirname "$EXEC")
Icon=bunny-beat-down
Terminal=false
Categories=Game;ActionGame;
Keywords=bunny;battle royale;godot;carrot;
StartupNotify=true
StartupWMClass=Bunny Beat Down
Actions=update;

[Desktop Action update]
Name=Update Bunny Beat Down
Exec="$UPDATER" "$(dirname "$EXEC")"
DESK
chmod +x "$APPS/$ENTRY"
# right-click "Update Bunny Beat Down": in the menu and the dock (the launcher's
# action above) and, on the GNOME desktop, under Scripts
mkdir -p "$SCRIPTS"
cat > "$SCRIPTS/Update Bunny Beat Down" <<SCRIPT
#!/usr/bin/env bash
exec "$UPDATER" "$(dirname "$EXEC")"
SCRIPT
chmod +x "$SCRIPTS/Update Bunny Beat Down"
if [ -d "$DESKTOP_DIR" ]; then
  cp "$APPS/$ENTRY" "$DESKTOP_DIR/$ENTRY"
  chmod +x "$DESKTOP_DIR/$ENTRY"
  # GNOME only launches desktop icons that are marked trusted
  gio set "$DESKTOP_DIR/$ENTRY" metadata::trusted true 2>/dev/null || true
fi
update-desktop-database "$APPS" 2>/dev/null || true
gtk-update-icon-cache "${ICONS%/512x512/apps}" 2>/dev/null || true
echo "Installed Bunny Beat Down → $EXEC"
