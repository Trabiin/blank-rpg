#!/usr/bin/env python3
"""Shrink an art-pass prop to the prop scale table (docs/ART_STYLE.md, tools/art_audit.json "props") without
blurring it: area-average at the new size, then snap every pixel back to the sprite's own colours and alpha back
to on/off, and keep a dark rim where the original had its outline.

    python3 tools/resize_prop.py crates            # every variant of assets/props/crates*.png to the table height
    python3 tools/resize_prop.py crates 14         # to 14 px instead
    python3 tools/resize_prop.py all               # every prop the checker flags as too tall
Originals are kept as assets/props/_orig/<name>.png (not imported by Godot) so a resize can be redone.
"""
import glob
import json
import os
import shutil
import sys

import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PROPS = os.path.join(ROOT, "assets", "props")
ORIG = os.path.join(PROPS, "_orig")
LIMITS = json.load(open(os.path.join(ROOT, "tools", "art_audit.json")))["props"]


def shrink(im, h):
    a = np.asarray(im.convert("RGBA")).astype(float)
    alpha = a[..., 3:] / 255.0
    pal = np.unique(a[a[..., 3] > 128][:, :3], axis=0)
    w = max(1, round(im.width * h / im.height))
    pm = Image.fromarray(np.concatenate([a[..., :3] * alpha, a[..., 3:]], -1).astype(np.uint8), "RGBA")
    small = np.asarray(pm.resize((w, h), Image.BOX)).astype(float)
    sa = small[..., 3]
    rgb = small[..., :3] / np.maximum(sa[..., None] / 255.0, 1e-6)
    # Snap to the nearest of the sprite's own colours, so no new in-between colours appear.
    d = ((rgb[..., None, :] - pal[None, None]) ** 2).sum(-1)
    out = pal[d.argmin(-1)]
    on = sa > 110
    # Outline: original sprites have a dark rim; keep it on the shrunken silhouette's edge.
    lum = pal @ np.array([0.299, 0.587, 0.114])
    dark = pal[lum.argmin()]
    pad = np.pad(on, 1)
    edge = on & ~(pad[:-2, 1:-1] & pad[2:, 1:-1] & pad[1:-1, :-2] & pad[1:-1, 2:])
    edge_lum = (out @ np.array([0.299, 0.587, 0.114]))
    rim = edge & (edge_lum > lum.min() + 40) & (np.roll(on, 1, 1) == 0)  # left/bottom-ish rim only where it was lost
    out[rim] = dark
    res = np.zeros((h, w, 4), np.uint8)
    res[..., :3] = out.astype(np.uint8)
    res[..., 3] = on * 255
    return Image.fromarray(res, "RGBA")


def run(kind, h=None):
    h = h or LIMITS[kind]
    os.makedirs(ORIG, exist_ok=True)
    for p in sorted(glob.glob(os.path.join(PROPS, kind + ".png")) + glob.glob(os.path.join(PROPS, kind + "_v*.png"))):
        name = os.path.basename(p)
        src = os.path.join(ORIG, name)
        if not os.path.exists(src):
            shutil.copy(p, src)
        im = Image.open(src)
        if im.height <= h:
            continue
        shrink(im, h).save(p)
        print("resized", name, im.size, "->", Image.open(p).size)


if __name__ == "__main__":
    if sys.argv[1] == "all":
        for k, lim in LIMITS.items():
            p = os.path.join(PROPS, k + ".png")
            if os.path.exists(p) and Image.open(p).height > lim:
                run(k)
    else:
        run(sys.argv[1], int(sys.argv[2]) if len(sys.argv) > 2 else None)
