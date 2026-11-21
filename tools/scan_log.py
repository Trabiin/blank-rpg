"""Fails (exit 1) on any SCRIPT ERROR, ERROR or WARNING line in a Godot log, unless a test
announced it first with a line "##allow <regex>". Shared by tools/run_tests.sh (editor test run)
and tools/smoke_build.sh (exported desktop builds, issue #145).

Usage: python3 tools/scan_log.py <log file>
"""
import re
import sys

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
