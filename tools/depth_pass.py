#!/usr/bin/env python3
"""Depth pass and cheap variants for art pass sprites (docs/ART_STYLE.md, "Sitting in the world").

Generated sprites come out front-on and evenly lit, so they look pasted onto the ground. This pass adds,
in palette colours only (each darkening is one step down the material's own ramp):
  - eave shadow: the wall right under a roof edge drops 2 steps for a row, then 1 step for 2 more rows
  - contact shade: the bottom rows of every column drop 1 step, so the sprite sits on the ground
  - side shade: the rightmost wall column drops 1 step (light comes from the top left)
Variants recolour one material ramp into another (slate roof -> clay roof, wood -> darker wood) and can
sprinkle moss on a roof. Houses no longer need them: each style-locked call returns 4 different houses.

Originals live in tools/art_src/ (copied there on the first run), so rerunning never darkens twice:
    python3 tools/depth_pass.py
"""
import os
import random
import shutil

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
SRC = os.path.join(HERE, "art_src")


def _c(hx):
    hx = hx.lstrip("#")
    return tuple(int(hx[i:i + 2], 16) for i in (0, 2, 4))


# Material ramps, dark -> light. A colour darkens to its left neighbour.
RAMPS = {
    "stone": ["12141f", "1f2233", "2e3247", "3d4152", "575b6b", "7a7d88", "a3a3a6"],
    "wood": ["12141f", "2a2019", "3a2a1c", "5a3e28", "7d5836", "a07a4e", "c9a97a"],
    "plaster": ["3a2a1c", "8f8270", "b5a68a", "d6cdba"],
    "foliage": ["12141f", "1c2619", "2a3a22", "3d5130", "566b3a", "7d8c4c", "a3a865"],
    "slate": ["12141f", "1f2233", "2b3448", "3f4c66", "5b6b85"],
    "clay": ["2a2019", "5c2a26", "85402f", "a85d3e"],
    "skin": ["3a2a1c", "6b4532", "a06a4c", "d19c7c"],
    "glow": ["3a5f9e", "7fa8ec"],
    "lamp": ["c2622d", "e8c65a", "f2c25c"],
    "red": ["5c2a26", "a3243b"],
}
DARKER = {}
for ramp in RAMPS.values():
    for i in range(1, len(ramp)):
        DARKER.setdefault(_c(ramp[i]), _c(ramp[i - 1]))
ROOF = {_c(h) for h in RAMPS["slate"][1:] + RAMPS["clay"][1:] + RAMPS["stone"][1:]}
INK = _c("12141f")
# Roof recolours: generated roofs use the stone ramp, so these map stone onto clay or blue slate.
ROOF_TO = {
    "clay": {"1f2233": "5c2a26", "2e3247": "5c2a26", "2b3448": "5c2a26", "3d4152": "85402f",
             "575b6b": "a85d3e", "7a7d88": "a85d3e"},
    "slate": {"3d4152": "3f4c66", "575b6b": "5b6b85", "2e3247": "2b3448", "7a7d88": "5b6b85"},
}


def roof_mask(img):
    """The roof: roof/stone coloured pixels above the eave line, the first row (from the top) where
    they stop being most of the row. Returns a set of (x, y)."""
    px = img.load()
    eave = 0
    seen = False
    for y in range(img.height):
        row = [px[x, y][:3] for x in range(img.width) if px[x, y][3] and px[x, y][:3] != INK]
        if not row:
            continue
        frac = sum(1 for c in row if c in ROOF) / len(row)
        if frac > 0.5:
            seen = True
        elif seen and frac < 0.3:
            eave = y
            break
    return {(x, y) for y in range(eave) for x in range(img.width)
            if px[x, y][3] and px[x, y][:3] in ROOF}


def darken(rgb, n=1):
    for _ in range(n):
        rgb = DARKER.get(rgb, rgb)
    return rgb


def recolour(img, src, dst):
    """Maps ramp src onto ramp dst by position (both dark -> light)."""
    a, b = RAMPS[src], RAMPS[dst]
    table = {}
    for i, hx in enumerate(a):
        j = round(i * (len(b) - 1) / max(len(a) - 1, 1))
        table[_c(hx)] = _c(b[j])
    table.pop(INK, None)
    px = img.load()
    for y in range(img.height):
        for x in range(img.width):
            r, g, bb, al = px[x, y]
            if al and (r, g, bb) in table:
                px[x, y] = table[(r, g, bb)] + (al,)
    return img


def recolour_roof(img, to):
    table = {_c(a): _c(b) for a, b in ROOF_TO[to].items()}
    px = img.load()
    for x, y in roof_mask(img):
        c = px[x, y][:3]
        if c in table:
            px[x, y] = table[c] + (255,)
    return img


def shift_ramp(img, ramp, steps):
    """Moves every colour of one ramp up (+) or down (-) a few steps, outline excluded."""
    cols = [_c(h) for h in RAMPS[ramp]]
    px = img.load()
    for y in range(img.height):
        for x in range(img.width):
            r, g, b, a = px[x, y]
            if a and (r, g, b) in cols and (r, g, b) != INK:
                i = max(1, min(len(cols) - 1, cols.index((r, g, b)) + steps))
                px[x, y] = cols[i] + (a,)
    return img


def moss_roof(img, seed, amount=0.16):
    """Moss creeps over the roof: roof pixels next to the eave or in noisy patches turn foliage."""
    rng = random.Random(seed)
    px = img.load()
    moss = [_c("2a3a22"), _c("3d5130"), _c("566b3a")]
    mask = roof_mask(img)
    bottom = {}
    for x, y in mask:
        bottom[x] = max(bottom.get(x, 0), y)
    # A few patches grow out from random seeds; the eave row is mossiest.
    seeds = [(rng.randrange(img.width), rng.randrange(max(bottom.values(), default=1) + 1)) for _ in range(4)]
    for x, y in mask:
        r, g, b = px[x, y][:3]
        near = min(((x - sx) ** 2 + (y - sy) ** 2) ** 0.5 for sx, sy in seeds)
        chance = amount * (3.0 if y >= bottom[x] - 1 else 0.3) + (0.55 if near < 4 else 0.25 if near < 7 else 0)
        if rng.random() < chance:
            lum = r + g + b
            px[x, y] = moss[0 if lum < 120 else 1 if lum < 200 else 2] + (255,)
    return img


def depth(img, eaves=True, contact=2, side=True):
    img = img.convert("RGBA")
    w, h = img.size
    mask = roof_mask(img) if eaves else set()
    src = img.copy().load()
    px = img.load()
    for x in range(w):
        col = [src[x, y] for y in range(h)]
        ys = [y for y in range(h) if (x, y) in mask]
        if ys:
            # Under the eave: skip the roof's outline, then the wall falls into the roof's shadow.
            y = ys[-1] + 1
            while y < h and col[y][3] and col[y][:3] == INK:
                y += 1
            for n in (2, 2, 1, 1):
                if y < h and col[y][3] and (x, y) not in mask:
                    if col[y][:3] != INK:
                        px[x, y] = darken(px[x, y][:3], n) + (255,)
                    y += 1
        if contact:
            ys = [y for y in range(h) if col[y][3]]
            if ys:
                for y in range(ys[-1], max(ys[-1] - contact - 1, -1), -1):
                    if col[y][3] and col[y][:3] != INK:
                        px[x, y] = darken(px[x, y][:3], 1) + (255,)
    if side:
        for y in range(h):
            xs = [x for x in range(w) if src[x, y][3] and src[x, y][:3] != INK]
            if len(xs) > 6 and (xs[-1], y) not in mask:
                px[xs[-1], y] = darken(px[xs[-1], y][:3], 1) + (255,)
    return img


# Which sprites get which pass, and the variants to write next to them (name suffix -> recipe).
PROPS = ["house", "house_v1", "house_v2", "house_v3", "house_v4", "house_a", "house_b", "house_c", "house_d",
         "house_e", "house_f", "house_g", "house_h", "fence", "fence_v1", "tree", "tree_v1", "tree_v2", "tree_v3",
         "tavern", "townhall", "stores", "stall", "well", "cart", "crates", "barrels",
         "produce", "noticeboard", "bench", "fountain", "command_table"]
VARIANTS = {
    "crates": {"_v1": [("shift", "wood", -1)], "_v2": [("shift", "wood", 1)]},
    "barrels": {"_v1": [("shift", "wood", -1)], "_v2": [("shift", "wood", 1)]},
    "stall": {"_v1": [("shift", "wood", -1)]},
}


def apply_recipe(img, recipe):
    for step in recipe:
        if step[0] == "roof":
            recolour_roof(img, step[1])
        elif step[0] == "recolour":
            recolour(img, step[1], step[2])
        elif step[0] == "shift":
            shift_ramp(img, step[1], step[2])
        elif step[0] == "moss":
            moss_roof(img, step[1])
    return img


def process(rel, variants=None):
    dst = os.path.join(ROOT, rel)
    src = os.path.join(SRC, rel)
    if not os.path.exists(src):
        os.makedirs(os.path.dirname(src), exist_ok=True)
        shutil.copy(dst, src)
    base = Image.open(src).convert("RGBA")
    depth(base.copy()).save(dst)
    for suffix, recipe in (variants or {}).items():
        v = apply_recipe(base.copy(), recipe)
        depth(v).save(dst.replace(".png", suffix + ".png"))


def main():
    for k in PROPS:
        process("assets/props/%s.png" % k, VARIANTS.get(k))
    bdir = os.path.join(ROOT, "assets/buildings")
    for f in sorted(os.listdir(bdir)):
        if f.endswith(".png"):
            process("assets/buildings/" + f)
    print("depth pass done")


if __name__ == "__main__":
    main()
