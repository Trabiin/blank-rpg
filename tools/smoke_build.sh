#!/usr/bin/env bash
# Smoke test for an exported desktop build (issue #145), run by .github/workflows/desktop.yml on
# Windows, macOS and Linux. Two runs of the real exported binary:
#   1. a plain headless boot to the title screen and a few seconds of it;
#   2. the same binary running a subset of the automated tests from a test pack
#      (the export with tests/ left in), so the shipped engine, scripts and imported assets are
#      what gets tested, not the editor.
# Fails on a non-zero exit code, a failed test, or any error/warning in the log (tools/scan_log.py).
#
# Usage: tools/smoke_build.sh <game binary> <test pack .pck> [test filters...]
#        default filters: scenes saves display
set -uo pipefail
cd "$(dirname "$0")/.."
BIN="$1"
PACK="$2"
shift 2
FILTERS=("$@")
[ ${#FILTERS[@]} -eq 0 ] && FILTERS=(scenes saves display)
PY="$(command -v python3 || command -v python)"
# macOS has no `timeout` unless coreutils is installed.
TIMEOUT=()
if command -v timeout >/dev/null; then TIMEOUT=(timeout 900)
elif command -v gtimeout >/dev/null; then TIMEOUT=(gtimeout 900)
fi

# Godot also writes everything to user://logs/godot.log. A Windows GUI .exe may print nothing
# to a pipe, so that file is the log we read when there is one.
case "$(uname -s)" in
	Darwin) USERDIR="$HOME/Library/Application Support/Last Ink" ;;
	MINGW*|MSYS*|CYGWIN*) USERDIR="$(cygpath -u "$APPDATA")/Last Ink" ;;
	*) USERDIR="${XDG_DATA_HOME:-$HOME/.local/share}/Last Ink" ;;
esac
OUT="$(mktemp -d)"
fail=0

run() {  # run <name> <args...>
	local name="$1"
	shift
	rm -rf "$USERDIR/logs"
	echo "::group::$name"
	${TIMEOUT[@]+"${TIMEOUT[@]}"} "$BIN" --headless --audio-driver Dummy "$@" >"$OUT/$name.out" 2>&1
	local code=$?
	local log="$OUT/$name.out"
	if [ -s "$USERDIR/logs/godot.log" ]; then
		log="$USERDIR/logs/godot.log"
	fi
	cat "$log"
	echo "::endgroup::"
	if [ "$code" -ne 0 ]; then
		echo "FAILED: $name exited with code $code"
		fail=1
	fi
	if ! "$PY" tools/scan_log.py "$log"; then
		echo "FAILED: $name has errors or warnings in its log"
		fail=1
	fi
	if [ "$name" = "boot" ] && ! grep -q "Godot Engine" "$log"; then
		echo "FAILED: the build never started the engine"
		fail=1
	fi
	echo "$name: exit $code"
}

run boot --quit-after 600
for f in "${FILTERS[@]}"; do
	run "tests-$f" --main-pack "$PACK" -s res://tests/run.gd -- "$f"
	log="$USERDIR/logs/godot.log"
	[ -s "$log" ] || log="$OUT/tests-$f.out"
	if ! grep -qE "^[1-9][0-9]* passed, 0 failed" "$log"; then
		echo "FAILED: tests matching '$f' did not all pass (or none ran)"
		fail=1
	fi
done
rm -rf "$OUT"
if [ "$fail" -ne 0 ]; then
	echo "Smoke test FAILED for $BIN"
	exit 1
fi
echo "Smoke test passed for $BIN"
