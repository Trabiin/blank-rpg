#!/usr/bin/env python3
"""Free prop variants by palette swaps (Phase 8 step 3): each recipe maps style palette colours to other style
palette colours, optionally only on some pixels (moss on the upper, lit side). The result is a new
assets/props/<kind>_v<n>.png, which scripts/prop.gd picks up as another variant.

    python3 tools/recolor_prop.py       # writes every recipe below
"""
import os

import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PROPS = os.path.join(ROOT, "assets", "props")

GREY_TO_SAND = {"#1f2233": "#2a2019", "#2b3448": "#3a2a1c", "#2e3247": "#3a2a1c", "#3d4152": "#5a3e28",
                "#575b6b": "#8f8270", "#7a7d88": "#b5a68a", "#a3a3a6": "#d6cdba"}
IRON_TO_BRONZE = {"#2e3247": "#2a2019", "#3d4152": "#3a2a1c", "#575b6b": "#5a3e28", "#7a7d88": "#7d5836",
                  "#a3a3a6": "#a07a4e"}
WOOD_DARKER = {"#7d5836": "#6b4532", "#6b4532": "#5a3e28", "#b5a68a": "#8f8270"}
GREEN_DEEPER = {"#566b3a": "#3d5130", "#3d5130": "#2a3a22", "#2a3a22": "#1c2619"}
GREEN_SUNLIT = {"#566b3a": "#7d8c4c", "#3d5130": "#566b3a"}
MOSS = {"#7a7d88": "#566b3a", "#a3a3a6": "#7d8c4c", "#575b6b": "#3d5130"}

# (source, output, colour map, moss pass?)
RECIPES = [
    ("grave", "grave_v1", GREY_TO_SAND, False),
    ("grave", "grave_v2", {}, True),
    ("lamppost", "lamppost_v1", IRON_TO_BRONZE, False),
    ("barrels", "barrels_v3", WOOD_DARKER, False),
    ("bush", "bush_v1", GREEN_DEEPER, False),
    ("bush", "bush_v2", GREEN_SUNLIT, False),
]


def hexc(h):
    return tuple(int(h[i:i + 2], 16) for i in (1, 3, 5))


def recolor(src, cmap, moss, seed):
    a = np.array(Image.open(os.path.join(PROPS, src + ".png")).convert("RGBA"))
    out = a.copy()
    for f, t in cmap.items():
        m = (a[..., :3] == hexc(f)).all(-1)
        out[m, :3] = hexc(t)
    if moss:
        rng = np.random.default_rng(seed)
        h = a.shape[0]
        ys = np.arange(h)[:, None] / h
        # Moss collects on top and on the left (the lit side faces the sky); clumped by a coarse random field.
        coarse = np.kron(rng.random((h // 3 + 2, a.shape[1] // 3 + 2)), np.ones((3, 3)))[:h, :a.shape[1]]
        chance = (1.0 - ys) * 0.9 * coarse
        for f, t in MOSS.items():
            m = (a[..., :3] == hexc(f)).all(-1) & (rng.random(a.shape[:2]) < chance)
            out[m, :3] = hexc(t)
    return Image.fromarray(out, "RGBA")


if __name__ == "__main__":
    for i, (src, dst, cmap, moss) in enumerate(RECIPES):
        recolor(src, cmap, moss, 40 + i).save(os.path.join(PROPS, dst + ".png"))
        print("wrote", dst)
