#!/usr/bin/env python3
"""Builds a group sprite from separate PixelLab figures (Phase 8: the Merrow Three are three children, not one
blob). Each member's frames are anchored on their frame-0 feet, shrunk to a child's height without blur
(tools/resize_prop.shrink), and set side by side on one canvas, back row first. Writes a raw folder in the
fetch_character layout for tools/import_sprites.py.

    python3 tools/compose_group.py OUT_RAW SCALE MEMBER_RAW:DX:DY [...]
"""
import glob
import os
import re
import sys

from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from resize_prop import shrink  # noqa: E402

W, H, FEET = 64, 44, 37


def anchor(im):
    bb = im.getchannel("A").point(lambda v: 255 if v > 128 else 0).getbbox()
    return (bb[0] + bb[2]) // 2, bb[3]


def frames(raw):
    """{(anim, dir): [paths in frame order]}, with rotations as anim 'rot'."""
    out = {}
    for p in glob.glob(os.path.join(raw, "*.png")):
        n = os.path.basename(p)[:-4]
        m = re.match(r"(.+)_((?:south|north)(?:-east|-west)?|east|west)_(\d+)$", n)
        if m:
            out.setdefault((m.group(1), m.group(2)), []).append((int(m.group(3)), p))
        else:
            out.setdefault(("rot", n), []).append((0, p))
    return {k: [p for _, p in sorted(v)] for k, v in out.items()}


def main():
    out, scale = sys.argv[1], float(sys.argv[2])
    members = []
    for arg in sys.argv[3:]:
        raw, dx, dy = arg.split(":")
        members.append((frames(raw), int(dx), int(dy)))
    os.makedirs(out, exist_ok=True)
    keys = set.intersection(*[set(m[0]) for m in members])
    for anim, d in sorted(keys):
        n = min(len(m[0][(anim, d)]) for m in members)
        for i in range(n):
            canvas = Image.new("RGBA", (W, H))
            for fr, dx, dy in sorted(members, key=lambda m: m[2]):  # back row (smaller dy) first
                paths = fr[(anim, d)]
                first = Image.open(paths[0]).convert("RGBA")
                ax, ay = anchor(first)
                im = Image.open(paths[i]).convert("RGBA")
                small = shrink(im, max(1, round(im.height * scale)))
                sx, sy = round(ax * scale), round(ay * scale)
                canvas.alpha_composite(small, (W // 2 + dx - sx, FEET + dy - sy))
            name = f"{d}.png" if anim == "rot" else f"{anim}_{d}_{i}.png"
            canvas.save(os.path.join(out, name))
    print("wrote", out)


if __name__ == "__main__":
    main()
