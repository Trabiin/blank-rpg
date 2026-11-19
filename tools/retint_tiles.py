#!/usr/bin/env python3
"""Gives each Act 1 biome its own grass inside the style palette (docs/ART_STYLE.md), so the biomes read apart
while sharing one tileset style. Each recipe maps palette colours to palette colours, some only for a share
of the pixels (a fixed-seed dither), so the result stays palette-locked and the tiles stay seamless.

    python3 tools/retint_tiles.py        # meadow -> marsh, hills; town -> road; forest from its original in tools/art_src
"""
import glob
import os
import random

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)

# biome -> (source folder, [(from, to, share)]) applied in order; share < 1 dithers.
RECIPES = {
    # Uplands: sun-dried, yellow-green grass with straw tufts.
    "hills": ("assets/tiles/meadow", [
        ("3d5130", "7d8c4c", 0.75), ("2a3a22", "566b3a", 0.8), ("1c2619", "3d5130", 1.0),
        ("566b3a", "a07a4e", 0.15)]),
    # The Concord road: verges trampled to dust and mud by carts and boots.
    "road": ("assets/tiles/town", [
        ("3d5130", "7d5836", 0.4), ("2a3a22", "5a3e28", 0.35), ("1c2619", "3a2a1c", 0.4)]),
    # Marsh: cold, wet, blue-black under the green.
    "marsh": ("assets/tiles/meadow", [
        ("3d5130", "2a3a22", 0.7), ("1c2619", "1f2233", 0.45), ("2a3a22", "2e3247", 0.25)]),
    # Deep forest: darker floor, a few near-black hollows.
    "forest": ("tools/art_src/assets/tiles/forest", [
        ("3d5130", "2a3a22", 0.6), ("2a3a22", "1c2619", 0.35), ("1c2619", "12141f", 0.12)]),
}


def c(h):
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def main():
    for biome, (src, steps) in RECIPES.items():
        for path in sorted(glob.glob(os.path.join(ROOT, src, "????.png"))):
            name = os.path.basename(path)
            im = Image.open(path).convert("RGBA")
            px = im.load()
            # The same seed per tile name keeps seams matching between tiles that share edges.
            rnd = random.Random(biome)
            for f, t, share in steps:
                f, t = c(f), c(t)
                for y in range(im.height):
                    for x in range(im.width):
                        r = rnd.random()
                        if px[x, y][:3] == f and px[x, y][3] and r < share:
                            px[x, y] = t + (px[x, y][3],)
            os.makedirs(os.path.join(ROOT, "assets/tiles", biome), exist_ok=True)
            im.save(os.path.join(ROOT, "assets/tiles", biome, name))
        print("retinted", biome)


if __name__ == "__main__":
    main()
