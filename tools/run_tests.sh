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

python3 - "$LOG" <<'PY'
import re, sys
lines = open(sys.argv[1], errors="replace").read().splitlines()
allowed = [re.compile(l[len("##allow "):]) for l in lines if l.startswith("##allow ")]
# Engine noise at shutdown and on machines without a sound card: not the game's doing.
allowed += [re.compile(p) for p in [
	r"ObjectDB instances leaked at exit",
	r"resources? still in use at exit",
	r"All audio drivers failed",
]]
bad = []
i = 0
while i < len(lines):
	l = lines[i]
	if re.match(r"\s*(SCRIPT ERROR|ERROR|WARNING|USER ERROR|USER WARNING|USER SCRIPT ERROR):", l):
		block = [l]
		while i + 1 < len(lines) and re.match(r"\s+(at:|GDScript backtrace|\[\d+\])", lines[i + 1]):
			i += 1
			block.append(lines[i])
		if not any(a.search(l) for a in allowed):
			bad.append("\n".join(block))
	i += 1
if bad:
	print("\n%d unexpected error/warning line(s) in the log:" % len(bad))
	for b in bad:
		print(b)
	sys.exit(1)
PY
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
