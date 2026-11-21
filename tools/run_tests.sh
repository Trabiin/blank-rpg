#!/usr/bin/env bash
# Runs the automated tests (tests/run.gd) headless and fails on:
#   - any failed test (the runner's exit code),
#   - any SCRIPT ERROR, ERROR or WARNING line in the log, unless a test announced it with
#     "##allow <regex>" (for errors a test triggers on purpose, like a corrupt save).
# Usage: tools/run_tests.sh [filter]     GODOT=/path/to/godot to pick the binary (default: godot, then ~/godot/godot).
set -uo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-$(command -v godot || echo "$HOME/godot/godot")}"
LOG="$(mktemp)"
trap 'rm -f "$LOG"' EXIT

# Import first: textures, and the class_name list a new script joins (quick when nothing changed).
timeout 600 "$GODOT" --headless --import >/dev/null 2>&1 || true

timeout 900 "$GODOT" --headless --audio-driver Dummy --path . -s tests/run.gd -- "${1:-}" 2>&1 | tee "$LOG"
code=${PIPESTATUS[0]}

python3 tools/scan_log.py "$LOG"
scan=$?
if [ "$code" -ne 0 ]; then
	echo "Tests failed (exit code $code)."
	exit 1
fi
if [ "$scan" -ne 0 ]; then
	echo "Tests passed but the log has script errors or warnings (see above)."
	exit 1
fi
echo "All tests passed, log clean."
