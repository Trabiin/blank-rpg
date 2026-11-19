#!/usr/bin/env python3
"""Palette lock and cleanup for generated pixel art (docs/ART_ROADMAP.md 1.3 and section 4).

clean(img):  hard alpha (no half-transparent fringe), outline pixels set to Ink black, and the
             reserved Blank paper white pushed down to bone so only the Blank uses it.
snap(img):   additionally maps every colour to the nearest master palette colour (tools/master_palette.hex),
             measured in a perceptual (OKLab) space. Used for tiles and props so different days match.

    python3 tools/palette_lock.py in.png out.png [--snap] [--blank]
"""
import os
import sys

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
INK = (18, 20, 31)          # #12141f, outlines and Ink itself (matches scripts: INK)
PAPER = (243, 238, 226)     # #f3eee2, reserved for the Blank
BONE = (214, 205, 186)      # #d6cdba, what non-Blank whites become


def _lin(c):
    c = c / 255.0
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def oklab(rgb):
    r, g, b = (_lin(v) for v in rgb[:3])
    l_ = (0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b) ** (1 / 3)
    m_ = (0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b) ** (1 / 3)
    s_ = (0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b) ** (1 / 3)
    return (0.2104542553 * l_ + 0.7936177850 * m_ - 0.0040720468 * s_,
            1.9779984951 * l_ - 2.4285922050 * m_ + 0.4505937099 * s_,
            0.0259040371 * l_ + 0.7827717662 * m_ - 0.8086757660 * s_)


def load_palette(path=os.path.join(HERE, "master_palette.hex")):
    cols = []
    for line in open(path):
        tok = line.strip().split()
        if tok and not tok[0].startswith(";"):
            hx = tok[0].lstrip("#")
            if len(hx) == 6:
                cols.append(tuple(int(hx[i:i + 2], 16) for i in (0, 2, 4)))
    return cols


def clean(img, blank=False, outline=True):
    img = img.convert("RGBA")
    w, h = img.size
    px = img.load()
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            px[x, y] = (r, g, b, 255) if a >= 128 else (0, 0, 0, 0)
    if outline:
        out = img.copy()
        opx = out.load()
        for y in range(h):
            for x in range(w):
                r, g, b, a = px[x, y]
                if a == 0:
                    continue
                edge = any(not (0 <= x + dx < w and 0 <= y + dy < h) or px[x + dx, y + dy][3] == 0
                           for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)))
                # Only near-black edge pixels are outline; coloured edges (selective outline) stay.
                if edge and max(r, g, b) < 70:
                    opx[x, y] = INK + (255,)
        img = out
        px = img.load()
    img = drop_specks(img)
    px = img.load()
    if not blank:
        for y in range(h):
            for x in range(w):
                r, g, b, a = px[x, y]
                if a and min(r, g, b) > 228:
                    px[x, y] = BONE + (255,)
    return img


def drop_specks(img, min_size=10):
    """Removes small detached pixel islands (stray lines and sparkles the generator leaves around a sprite).
    The game draws its own FX, so loose bits only read as noise."""
    w, h = img.size
    px = img.load()
    seen = set()
    for y in range(h):
        for x in range(w):
            if px[x, y][3] == 0 or (x, y) in seen:
                continue
            comp, stack = [], [(x, y)]
            seen.add((x, y))
            while stack:
                cx, cy = stack.pop()
                comp.append((cx, cy))
                for dx in (-1, 0, 1):
                    for dy in (-1, 0, 1):
                        nx, ny = cx + dx, cy + dy
                        if 0 <= nx < w and 0 <= ny < h and (nx, ny) not in seen and px[nx, ny][3]:
                            seen.add((nx, ny))
                            stack.append((nx, ny))
            if len(comp) < min_size:
                for cx, cy in comp:
                    px[cx, cy] = (0, 0, 0, 0)
    return img


def snap(img, palette=None, blank=False):
    palette = palette or load_palette()
    labs = [oklab(c) for c in palette]
    img = clean(img, blank=blank)
    px = img.load()
    cache = {}
    for y in range(img.size[1]):
        for x in range(img.size[0]):
            r, g, b, a = px[x, y]
            if not a:
                continue
            key = (r, g, b)
            if key not in cache:
                L = oklab(key)
                best = min(range(len(labs)), key=lambda i: sum((L[k] - labs[i][k]) ** 2 for k in range(3)))
                cache[key] = palette[best]
            px[x, y] = cache[key] + (255,)
    return img


if __name__ == "__main__":
    if len(sys.argv) < 3:
        print(__doc__)
        sys.exit(1)
    im = Image.open(sys.argv[1])
    bl = "--blank" in sys.argv
    out = snap(im, blank=bl) if "--snap" in sys.argv else clean(im, blank=bl)
    out.save(sys.argv[2])
