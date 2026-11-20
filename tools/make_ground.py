#!/usr/bin/env python3
"""Procedural seamless ground textures in the style palette (docs/ART_STYLE.md), 256 px so they repeat only every
16 tiles. The paving layer of a ground set is its cobbles.png, painted over the grass by
shaders/ground_blend.gdshader with ragged edges; the grass itself is its grass.png, drawn under everything.

    python3 tools/make_ground.py mud     assets/tiles/marsh/cobbles.png    # marsh: wet earth, puddles, reeds
    python3 tools/make_ground.py gravel  assets/tiles/hills/cobbles.png    # hills: scree, pebbles lit top left
    python3 tools/make_ground.py trail   assets/tiles/meadow/cobbles.png   # meadow: trodden earth path
    python3 tools/make_ground.py leaves  assets/tiles/forest/cobbles.png   # forest: earth path with leaf litter
    python3 tools/make_ground.py grass   assets/tiles/meadow/grass.png assets/tiles/meadow/GGGG.png
    python3 tools/make_ground.py all                                       # every texture the ground sets use

Shapes come from domain-warped fractal noise (several octaves, warped by more noise), so patches are organic
instead of the square blobs plain value noise gives. Colours are only ever picked from the palette, never mixed.
"""
import os
import sys

import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def hexc(h):
    return np.array([int(h[i:i + 2], 16) for i in (1, 3, 5)], dtype=np.uint8)


def tnoise(size, cells, rng):
    """Tileable value noise with `cells` grid points per side."""
    g = rng.random((cells, cells))
    x = np.arange(size) / size * cells
    x0 = np.floor(x).astype(int)
    t = x - x0
    t = t * t * (3 - 2 * t)
    x0 %= cells
    x1 = (x0 + 1) % cells
    ty, tx = t[:, None], t[None, :]
    a, b = g[np.ix_(x0, x0)], g[np.ix_(x0, x1)]
    c, d = g[np.ix_(x1, x0)], g[np.ix_(x1, x1)]
    return (a * (1 - tx) + b * tx) * (1 - ty) + (c * (1 - tx) + d * tx) * ty


def fbm(size, cells, octaves, rng, gain=0.5):
    out, amp, tot = np.zeros((size, size)), 1.0, 0.0
    for o in range(octaves):
        out += tnoise(size, cells * 2 ** o, rng) * amp
        tot += amp
        amp *= gain
    out /= tot
    return (out - out.min()) / (out.max() - out.min() + 1e-9)


def sample(field, yy, xx):
    """Bilinear sample with wrap-around (keeps the texture seamless)."""
    n = field.shape[0]
    y0, x0 = np.floor(yy).astype(int), np.floor(xx).astype(int)
    ty, tx = yy - y0, xx - x0
    y0, x0 = y0 % n, x0 % n
    y1, x1 = (y0 + 1) % n, (x0 + 1) % n
    return ((field[y0, x0] * (1 - tx) + field[y0, x1] * tx) * (1 - ty)
            + (field[y1, x0] * (1 - tx) + field[y1, x1] * tx) * ty)


def warped(size, cells, octaves, rng, strength=18.0):
    base = fbm(size, cells, octaves, rng)
    wx, wy = fbm(size, 3, 3, rng) - 0.5, fbm(size, 3, 3, rng) - 0.5
    yy, xx = np.mgrid[0:size, 0:size].astype(float)
    return sample(base, yy + wy * strength * 2, xx + wx * strength * 2)


def ramp(field, cols, cuts):
    """Index into a colour ramp by thresholds: cols[i] where field passes cuts[i-1]."""
    idx = np.zeros(field.shape, dtype=int)
    for c in cuts:
        idx += field > c
    return np.array(cols)[idx]


def stroke(img, x, y, length, col, shadow=None):
    """A grass blade or reed: a vertical run of pixels, optionally with a dark root pixel."""
    n = img.shape[0]
    for i in range(length):
        img[(y - i) % n, x % n] = col
    if shadow is not None:
        img[(y + 1) % n, x % n] = shadow


def pebble(img, x, y, w, h, body, hi, sh, rng):
    n = img.shape[0]
    for dy in range(h):
        for dx in range(w):
            if (dx in (0, w - 1)) and (dy in (0, h - 1)) and w > 2 and h > 2:
                continue  # round the corners
            img[(y + dy) % n, (x + dx) % n] = body
    img[y % n, (x + (1 if w > 2 else 0)) % n] = hi
    if w > 3:
        img[(y + 1) % n, (x + 1) % n] = hi
    img[(y + h) % n, (x + w // 2) % n] = sh
    img[(y + h - 1) % n, (x + w) % n] = sh


def mud(size, rng):
    earth = [hexc("#2a2019"), hexc("#3a2a1c"), hexc("#5a3e28")]
    water, water_hi, water_dk = hexc("#2b3448"), hexc("#3f4c66"), hexc("#1f2233")
    reed, reed_hi, stone, stone_hi = hexc("#3d5130"), hexc("#566b3a"), hexc("#575b6b"), hexc("#7a7d88")
    soil = warped(size, 4, 5, rng) * 0.8 + fbm(size, 48, 2, rng) * 0.2
    img = ramp(soil, earth[:2], [0.5])
    fine = fbm(size, 64, 2, rng)
    img[(fine > 0.72) & (soil > 0.45)] = earth[2]  # drier crusts on the higher ground
    pud = warped(size, 3, 4, rng, 24.0)
    wet = pud > 0.66
    img[wet] = water
    img[pud > 0.74] = water_dk
    above = np.roll(wet, 1, axis=0)
    below = np.roll(wet, -1, axis=0)
    img[wet & ~above] = water_hi  # the far bank catches the light
    img[~wet & above & (soil > 0.3)] = earth[0]  # near bank: a dark lip under the earth
    glint = wet & (rng.random((size, size)) < 0.01)
    img[glint] = water_hi
    for _ in range(size * size // 90):  # reeds round the water's edge
        x, y = rng.integers(size), rng.integers(size)
        if 0.58 < pud[y, x] < 0.66:
            stroke(img, x, y, int(rng.integers(2, 5)), reed_hi if rng.random() < 0.4 else reed, earth[0])
    for _ in range(size * size // 700):
        x, y = rng.integers(size), rng.integers(size)
        if not wet[y, x]:
            pebble(img, x, y, 2, 1, stone, stone_hi, earth[0], rng)
    return img


def gravel(size, rng):
    base = [hexc("#2e3247"), hexc("#3d4152"), hexc("#575b6b")]
    peb, peb_hi, peb_sh = hexc("#7a7d88"), hexc("#a3a3a6"), hexc("#1f2233")
    grass = [hexc("#566b3a"), hexc("#7d8c4c")]
    soil = warped(size, 4, 5, rng) * 0.6 + fbm(size, 48, 2, rng) * 0.4
    img = ramp(soil, base, [0.38, 0.62])
    dens = warped(size, 3, 3, rng)
    for _ in range(size * size // 40):
        x, y = rng.integers(size), rng.integers(size)
        if rng.random() < dens[y, x] * 1.4:
            w = int(rng.choice([2, 2, 3, 3, 4, 5]))
            h = max(1, w - int(rng.integers(1, 3)))
            pebble(img, x, y, w, h, peb if rng.random() < 0.8 else base[2], peb_hi, peb_sh, rng)
    for _ in range(size * size // 160):  # grass in the hollows
        x, y = rng.integers(size), rng.integers(size)
        if dens[y, x] < 0.3:
            stroke(img, x, y, int(rng.integers(2, 4)), grass[int(rng.random() < 0.35)], base[0])
    return img


def trail(size, rng, leaves=False):
    earth = [hexc("#2a2019"), hexc("#3a2a1c"), hexc("#5a3e28"), hexc("#7d5836")]
    stone, stone_hi = hexc("#575b6b"), hexc("#7a7d88")
    soil = warped(size, 4, 5, rng) * 0.65 + fbm(size, 40, 2, rng) * 0.35
    img = ramp(soil, earth, [0.25, 0.50, 0.78])
    for _ in range(size * size // 260):
        x, y = rng.integers(size), rng.integers(size)
        pebble(img, x, y, int(rng.choice([1, 2, 2, 3])), 1, stone, stone_hi, earth[0], rng)
    if leaves:
        litter = [hexc("#7d5836"), hexc("#a07a4e"), hexc("#566b3a"), hexc("#85402f")]
        dens = warped(size, 3, 3, rng)
        for _ in range(size * size // 30):
            x, y = rng.integers(size), rng.integers(size)
            if rng.random() < dens[y, x]:
                c = litter[int(rng.integers(len(litter)))]
                img[y, x] = c
                if rng.random() < 0.5:
                    img[y, (x + 1) % size] = c
    return img


def grass(size, rng, tile_path):
    """Grass from a ground set's own grass tile colours, without the 16 px repeat of the tile. The green colours
    make the lawn, in the proportions the tile uses them; other colours (marsh water, road earth) only speckle it."""
    tile = np.array(Image.open(tile_path).convert("RGB")).reshape(-1, 3)
    cols, counts = np.unique(tile, axis=0, return_counts=True)
    keep = counts >= 3
    cols, counts = cols[keep], counts[keep]
    order = np.argsort(cols @ np.array([0.299, 0.587, 0.114]))  # dark to light
    cols, counts = cols[order], counts[order]
    green = (cols[:, 1].astype(int) >= cols[:, 2]) & (cols[:, 1].astype(int) >= cols[:, 0])
    lo, lo_n = cols[green], counts[green]
    hi = lo[max(1, len(lo) // 2):]  # blades and tips
    body = warped(size, 4, 4, rng, 22.0) * 0.6 + fbm(size, 32, 2, rng) * 0.3 + rng.random((size, size)) * 0.1
    share = np.cumsum(lo_n)[:-1] / lo_n.sum()
    cuts = list(np.quantile(body, share))
    img = ramp(body, list(lo), cuts)
    fine = fbm(size, 64, 1, rng)
    for c, n in zip(cols[~green], counts[~green]):  # speckles of the odd colours, a fraction of their tile share
        frac = n / counts.sum() * 0.35
        mask = (fine > np.quantile(fine, 1 - frac)) & (rng.random((size, size)) < 0.6)
        img[mask] = c
        fine = np.roll(fine, (37, 53), axis=(0, 1))
    dens = warped(size, 3, 3, rng)
    for _ in range(size * size // 45):  # tufts of 2-3 blades, clumped where the density field is high
        x, y = rng.integers(size), rng.integers(size)
        if rng.random() < dens[y, x] ** 2 * 1.6:
            c = hi[int(rng.integers(len(hi)))]
            for dx in range(int(rng.integers(2, 4))):
                stroke(img, x + dx * 2 - 2, y - (dx % 2), int(rng.choice([2, 3])), c, lo[0])
    return img


def save(img, out):
    Image.fromarray(img.astype(np.uint8), "RGB").save(out)
    print("wrote", out)


def main():
    kind = sys.argv[1]
    if kind == "all":
        t = os.path.join(ROOT, "assets", "tiles")
        jobs = [("mud", "marsh/cobbles.png", 5), ("gravel", "hills/cobbles.png", 6), ("trail", "meadow/cobbles.png", 7),
                ("leaves", "forest/cobbles.png", 8)]
        for k, out, seed in jobs:
            rng = np.random.default_rng(seed)
            save(trail(256, rng, True) if k == "leaves" else {"mud": mud, "gravel": gravel, "trail": trail}[k](256, rng),
                 os.path.join(t, out))
        for i, s in enumerate(["meadow", "forest", "marsh", "hills", "town", "road"]):
            src = os.path.join(t, s, "GGGG.png")
            save(grass(256, np.random.default_rng(20 + i), src), os.path.join(t, s, "grass.png"))
        return
    out = sys.argv[2]
    rng = np.random.default_rng(int(sys.argv[4]) if len(sys.argv) > 4 else 5)
    if kind == "grass":
        save(grass(256, rng, sys.argv[3]), out)
    elif kind == "leaves":
        save(trail(256, rng, True), out)
    else:
        save({"mud": mud, "gravel": gravel, "trail": trail}[kind](256, rng), out)


if __name__ == "__main__":
    main()
