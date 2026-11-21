"""Checks that the exported Windows .exe carries the game's icon and version info, not Godot's
(rcedit ran during export). CI only (issue #145).

Usage: python tools/desktop/check_exe.py <LastInk.exe> <version>
"""
import sys

import pefile

exe, version = sys.argv[1], sys.argv[2]
pe = pefile.PE(exe, fast_load=True)
pe.parse_data_directories(directories=[pefile.DIRECTORY_ENTRY["IMAGE_DIRECTORY_ENTRY_RESOURCE"]])
info = {}
pe.parse_data_directories()
for fi in getattr(pe, "FileInfo", []):
	for entry in fi:
		for table in getattr(entry, "StringTable", []):
			for k, v in table.entries.items():
				info[k.decode(errors="replace")] = v.decode(errors="replace")
icons = [e for e in pe.DIRECTORY_ENTRY_RESOURCE.entries if e.struct.Id == pefile.RESOURCE_TYPE["RT_ICON"]]
problems = []
if info.get("ProductName") != "Last Ink":
	problems.append("ProductName is %r, want 'Last Ink'" % info.get("ProductName"))
if not str(info.get("FileVersion", "")).startswith(version):
	problems.append("FileVersion is %r, want %s" % (info.get("FileVersion"), version))
if not icons or len(icons[0].directory.entries) < 4:
	problems.append("icon missing or has too few sizes")
for k in sorted(info):
	print("%s = %s" % (k, info[k]))
if problems:
	print("\n".join("PROBLEM: " + p for p in problems))
	sys.exit(1)
print("exe metadata ok")
