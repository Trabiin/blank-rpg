"""Writes export_presets.cfg with tests/ kept in every preset, so CI can export a test pack
(godot --export-pack <preset> smoke.pck) for tools/smoke_build.sh (issue #145). CI only: the
presets in the repository always leave tests out.

Usage: python3 tools/smoke_pack.py   (rewrites export_presets.cfg in place)
"""
import re

p = "export_presets.cfg"
s = open(p).read()
s = re.sub(r'(exclude_filter="[^"]*?)(, )?tests/\*', r"\1", s)
open(p, "w").write(s)
