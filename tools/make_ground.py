#!/usr/bin/env python3
"""Procedural seamless ground textures in the style palette (docs/ART_STYLE.md), painted over the grass by
shaders/ground_blend.gdshader like the town cobbles (the paving texture of a ground set is its cobbles.png).

    python3 tools/make_ground.py mud    assets/tiles/marsh/cobbles.png   # marsh: mud with puddles and reeds
    python3 tools/make_ground.py gravel assets/tiles/hills/cobbles.png   # hills: grey gravel and pebbles
"""
import math
import random
import sys

from PIL import Image


def hexc(h):
    return tuple(int(h[i:i + 2], 16) for i in (1, 3, 5))


def value_noise(size, cell, rnd):
    """Tileable value noise: a random grid of size/cell points on a torus, smoothly interpolated."""
    n = max(1, size // cell)
    grid = [[rnd.random() for _ in range(n)] for _ in range(n)]

    def f(x, y):
        gx, gy = x / cell, y / cell
        x0, y0 = int(math.floor(gx)) % n, int(math.floor(gy)) % n
        x1, y1 = (x0 + 1) % n, (y0 + 1) % n
        tx, ty = gx - math.floor(gx), gy - math.floor(gy)
        tx, ty = tx * tx * (3 - 2 * tx), ty * ty * (3 - 2 * ty)
        a = grid[y0][x0] + (grid[y0][x1] - grid[y0][x0]) * tx
        b = grid[y1][x0] + (grid[y1][x1] - grid[y1][x0]) * tx
        return a + (b - a) * ty
    return f


def mud(size, rnd):
    dark, mid, light = hexc("#2a2019"), hexc("#3a2a1c"), hexc("#5a3e28")
    water, water_hi, water_dk = hexc("#2b3448"), hexc("#3f4c66"), hexc("#1f2233")
    reed, reed_hi = hexc("#3d5130"), hexc("#566b3a")
    big = value_noise(size, 32, rnd)
    small = value_noise(size, 8, rnd)
    img = Image.new("RGB", (size, size))
    px = img.load()
    for y in range(size):
        for x in range(size):
            b = big(x, y) * 0.75 + small(x, y) * 0.25
            if b > 0.68:  # puddle: dark water, a lighter rim on the far (top) side, a few glints
                above = big(x, (y - 2) % size) * 0.75 + small(x, (y - 2) % size) * 0.25
                col = water_hi if above <= 0.68 else (water if b < 0.76 else water_dk)
                if rnd.random() < 0.012:
                    col = water_hi
            else:
                s = small(x, y) + rnd.uniform(-0.12, 0.12)
                col = light if s > 0.68 else (mid if s > 0.38 else dark)
                if 0.6 < b <= 0.68 and rnd.random() < 0.25:
                    col = reed if rnd.random() < 0.7 else reed_hi  # reeds round the puddles
            px[x, y] = col
    return img


def gravel(size, rnd):
    base = [hexc("#2e3247"), hexc("#3d4152"), hexc("#575b6b")]
    peb, peb_hi, peb_sh = hexc("#7a7d88"), hexc("#a3a3a6"), hexc("#1f2233")
    grass = [hexc("#566b3a"), hexc("#7d8c4c")]
    big = value_noise(size, 32, rnd)
    small = value_noise(size, 4, rnd)
    img = Image.new("RGB", (size, size))
    px = img.load()
    for y in range(size):
        for x in range(size):
            s = small(x, y) * 0.6 + big(x, y) * 0.4 + rnd.uniform(-0.1, 0.1)
            px[x, y] = base[2] if s > 0.6 else (base[1] if s > 0.3 else base[0])
            if big(x, y) < 0.22 and rnd.random() < 0.3:
                px[x, y] = grass[rnd.random() < 0.3]
    for _ in range(size * size // 110):  # pebbles: 2x2 or 3x2 stones lit from the top left
        x, y = rnd.randrange(size), rnd.randrange(size)
        w = rnd.choice([2, 2, 3])
        for dy in range(2):
            for dx in range(w):
                px[(x + dx) % size, (y + dy) % size] = peb_hi if (dx == 0 and dy == 0) else peb
        px[(x + w) % size, (y + 1) % size] = peb_sh
        px[x % size, (y + 2) % size] = peb_sh
    return img


def main():
    kind, out = sys.argv[1], sys.argv[2]
    rnd = random.Random(int(sys.argv[3]) if len(sys.argv) > 3 else 5)
    size = int(sys.argv[4]) if len(sys.argv) > 4 else 256  # 256 px = 16 tiles before it repeats
    {"mud": mud, "gravel": gravel}[kind](size, rnd).save(out)
    print("wrote", out)


if __name__ == "__main__":
    main()
