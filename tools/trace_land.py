#!/usr/bin/env python3
"""Traces land and sea from the painted territory map (issue #53).

    python3 tools/trace_land.py [assets/ui/map_painted.jpg] [assets/map/land_mask.png]

The painted map's open sea is smooth parchment and its land is busy with ink detail, so a local
contrast threshold separates them. Lakes inside the land (and the ink lake under the Velvet
Causeway) count as land, so the provinces round them can hold them. The result is the 450x300
mask that scripts/territory.gd lays the provinces over (white = land, black = open sea).

After a new painting, run this, then check the overlay it writes next to the mask (red = sea).
"""
import sys
from collections import deque
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

SRC = sys.argv[1] if len(sys.argv) > 1 else "assets/ui/map_painted.jpg"
OUT = sys.argv[2] if len(sys.argv) > 2 else "assets/map/land_mask.png"
GRID = (450, 300)  # Empire.MAP_CELLS
# Hand fixes, in painting pixels (1536x1024): water that belongs to provinces.
LAKES = [
    (255, 575, 815, 800),  # the ink lake round the Velvet Causeway
    (760, 90, 990, 300),  # Candleford's lake
]


def box(a, r):
    k = 2 * r + 1
    c = np.cumsum(np.cumsum(np.pad(a, ((r + 1, r), (r + 1, r)), mode="edge"), 0), 1)
    return (c[k:, k:] - c[:-k, k:] - c[k:, :-k] + c[:-k, :-k]) / (k * k)


def main():
    paint = Image.open(SRC).convert("RGB")
    lum = np.asarray(paint.convert("L")).astype(float)
    m = box(lum, 6)
    contrast = box(np.sqrt(np.maximum(box(lum * lum, 6) - m * m, 0)), 8)
    land = Image.fromarray((contrast > 15.5).astype(np.uint8) * 255)
    d = ImageDraw.Draw(land)
    for e in LAKES:
        d.ellipse(e, fill=255)
    land = land.filter(ImageFilter.MaxFilter(9)).filter(ImageFilter.MinFilter(9))  # close gaps
    land = land.filter(ImageFilter.MinFilter(5)).filter(ImageFilter.MaxFilter(5))  # drop specks
    small = np.asarray(land.resize(GRID, Image.BILINEAR).point(lambda v: 255 if v > 127 else 0)).copy()
    # Water that never reaches the map's edge is a lake: land.
    h, w = small.shape
    sea = np.zeros_like(small, bool)
    q = deque()
    for x in range(w):
        for y in (0, h - 1):
            if small[y, x] == 0 and not sea[y, x]:
                sea[y, x] = True
                q.append((y, x))
    for y in range(h):
        for x in (0, w - 1):
            if small[y, x] == 0 and not sea[y, x]:
                sea[y, x] = True
                q.append((y, x))
    while q:
        y, x = q.popleft()
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            ny, nx = y + dy, x + dx
            if 0 <= ny < h and 0 <= nx < w and not sea[ny, nx] and small[ny, nx] == 0:
                sea[ny, nx] = True
                q.append((ny, nx))
    small[(small == 0) & (~sea)] = 255
    Image.fromarray(small).save(OUT)
    over = Image.fromarray(small).resize(paint.size, Image.NEAREST)
    red = Image.blend(paint, Image.new("RGB", paint.size, (255, 0, 0)), 0.45)
    Image.composite(paint, red, over).save(OUT.replace(".png", "_overlay.png"))
    print("wrote", OUT)


if __name__ == "__main__":
    main()
