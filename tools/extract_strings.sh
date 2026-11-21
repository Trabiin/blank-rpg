#!/usr/bin/env bash
# Writes locale/messages.pot (every player-facing string) for translators. Issue #143,
# docs/LOCALIZATION.md. Usage: tools/extract_strings.sh [out.pot]   GODOT=/path/to/godot to pick the binary.
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-$(command -v godot || echo "$HOME/godot/godot")}"
timeout 600 "$GODOT" --headless --import >/dev/null 2>&1 || true
timeout 300 "$GODOT" --headless --audio-driver Dummy --path . -s tools/extract_strings.gd -- "${1:-res://locale/messages.pot}"
