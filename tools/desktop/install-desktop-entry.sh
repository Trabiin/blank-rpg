#!/usr/bin/env bash
# Adds Last Ink to your desktop's app menu (Linux). Run it from the folder you unpacked the game
# into; run it again if you move that folder. Remove with: ./install-desktop-entry.sh --remove
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
apps="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
icons="${XDG_DATA_HOME:-$HOME/.local/share}/icons/hicolor/256x256/apps"
if [ "${1:-}" = "--remove" ]; then
	rm -f "$apps/last-ink.desktop" "$icons/last-ink.png"
	echo "Removed Last Ink from the app menu."
	exit 0
fi
mkdir -p "$apps" "$icons"
cp "$here/last-ink.png" "$icons/last-ink.png"
cat > "$apps/last-ink.desktop" <<DESKTOP
[Desktop Entry]
Type=Application
Name=Last Ink
Comment=Reality is being eaten. You were spat back out.
Exec="$here/LastInk.x86_64"
Path=$here
Icon=last-ink
Terminal=false
Categories=Game;RolePlaying;ActionGame;
DESKTOP
chmod +x "$here/LastInk.x86_64"
command -v update-desktop-database >/dev/null && update-desktop-database "$apps" >/dev/null 2>&1 || true
echo "Last Ink is now in your app menu."
