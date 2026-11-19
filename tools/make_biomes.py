#!/usr/bin/env python3
"""Builds the Act 1 biome mission maps (docs/ART_ROADMAP.md phase 4): one 80 x 60 map per biome, laid out
like maps/frayed_meadow.txt so the Defense / Reclaim / Rescue spots in scripts/mission_types.gd (wardstone,
Blot, rescue spots, the Blank's wall at tile 69) fall on open ground in every one of them.

Each biome is a recipe: a ground set, a winding road from the party start to the Blot, side trails to the
rescue spots and spawn clearings, a dense border, and props scattered by noise so they clump into groves,
reed beds or rock fields instead of an even sprinkle. Free-standing prop chars sit at their bottom-centre
tile (scripts/prop.gd). Edit the recipes and rerun:
    python3 tools/make_biomes.py
"""
import math
import os
import random

W, H = 80, 60
HERE = os.path.dirname(os.path.abspath(__file__))
MAPS = os.path.join(HERE, "..", "maps")

START = (12, 31)
BLANK = 69
WARD = (50, 31)
BLOT = (64, 30)
RESCUE = [(60, 9), (60, 50), (59, 22)]
SPAWNS = [(31, 10), (58, 24), (40, 26), (52, 33), (60, 38), (36, 40), (47, 44)]
SIGN_AT = (14, 28)

# Prop sizes in tiles (width, height) for spacing: from the sprites, rounded up.
SIZE = {"fortree": (3, 4), "tree": (3, 4), "fungus": (2, 2), "log": (2, 2), "fern": (3, 2), "roots": (3, 3),
        "totem": (2, 3), "reeds": (2, 2), "marshstump": (2, 2), "lilypad": (2, 1), "planks": (3, 2),
        "boulder": (2, 2), "outcrop": (2, 2), "inkspring": (2, 2), "roadlamp": (1, 2), "drygrass": (2, 2),
        "taxbanner": (1, 3), "milestone": (2, 3), "barricade": (3, 3), "seized": (3, 3), "dock": (4, 3),
        "mill": (6, 6), "tollbooth": (6, 6), "fence": (3, 2), "crates": (2, 2), "barrels": (2, 2)}

BIOMES = {
    "gutterwoods": {
        "name": "The Gutterwoods", "mood": "grade=0.80,0.93,0.86 mist=1.3 motes=0.75,0.95,0.6", "ground": "forest", "seed": 11,
        "sign": "GUTTERWOODS|Letters left here are delivered.|Eventually.",
        "props": {"F": "fortree", "U": "fungus", "L": "log", "N": "fern", "O": "roots", "Q": "totem"},
        "border": ["F"],
        "scatter": [("F", 0.10, 0.55), ("N", 0.05, 0.35), ("U", 0.03, 0.4), ("L", 0.015, 0.2),
                    ("O", 0.015, 0.45), ("Q", 0.004, 0.0)],
        "path_r": 1.2,
        "landmarks": [("Q", (20, 26)), ("Q", (44, 18)), ("O", (33, 33))],
    },
    "saltreed": {
        "name": "Saltreed Marsh", "mood": "grade=0.82,0.88,0.96 mist=2.0 motes=0.55,0.6,0.5", "ground": "marsh", "seed": 23,
        "sign": "SALTREED|Mind the water.|The water minds you.",
        "props": {"D": "reeds", "M": "marshstump", "Y": "lilypad", "K": "planks", "F": "fortree", "N": "fern"},
        "border": ["D", "F"],
        "scatter": [("D", 0.11, 0.3), ("Y", 0.04, 0.5), ("M", 0.025, 0.3), ("F", 0.02, 0.6), ("N", 0.02, 0.4)],
        "path_r": 1.3, "patches": (7, 0.58),
        "landmarks": [("K", (24, 30)), ("K", (38, 28)), ("K", (56, 31))],
    },
    "oldmill": {
        "name": "Old Mill Crossing", "mood": "grade=0.92,0.92,0.95 mist=1.5 motes=1.0,0.95,0.8", "ground": "marsh", "seed": 37,
        "sign": "OLD MILL CROSSING|Flour: none.|Miller: also none.",
        "props": {"D": "reeds", "M": "marshstump", "Y": "lilypad", "K": "planks", "J": "dock", "W": "mill",
                  "X": "crates", "B": "barrels", "E": "fence", "F": "tree", "Z": "drygrass"},
        "border": ["F", "D"],
        "scatter": [("D", 0.06, 0.35), ("Z", 0.05, 0.3), ("F", 0.03, 0.55), ("M", 0.015, 0.3), ("Y", 0.02, 0.55)],
        "path_r": 1.6, "patches": (8, 0.66),
        "landmarks": [("W", (30, 24)), ("J", (36, 40)), ("X", (25, 26)), ("B", (34, 27)), ("E", (22, 35)),
                      ("E", (26, 36)), ("K", (44, 36))],
    },
    "lampwick": {
        "name": "Lampwick Hills", "mood": "grade=1.04,0.98,0.86 mist=0.5 motes=1.0,0.9,0.55", "ground": "hills", "seed": 41,
        "sign": "LAMPWICK HILLS|Ink spring ahead.|Do not drink. Do not write.",
        "props": {"P": "boulder", "C": "outcrop", "I": "inkspring", "A": "roadlamp", "Z": "drygrass", "F": "tree"},
        "border": ["C", "P", "F"],
        "scatter": [("Z", 0.08, 0.3), ("P", 0.04, 0.45), ("C", 0.03, 0.55), ("F", 0.015, 0.6)],
        "path_r": 1.3, "patches": (6, 0.72),
        "landmarks": [("I", (40, 20)), ("I", (30, 38)), ("A", (22, 30)), ("A", (36, 30)), ("A", (46, 28))],
    },
    "tithe_road": {
        "name": "The Tithe Road", "mood": "grade=1.02,0.96,0.89 mist=0.7 motes=0.9,0.85,0.75", "ground": "town", "seed": 53,
        "sign": "THE TITHE ROAD|Concord property.|Tolls are not optional.",
        "props": {"V": "taxbanner", "G": "milestone", "B": "barricade", "H": "seized", "A": "roadlamp",
                  "W": "tollbooth", "F": "tree", "P": "boulder", "Z": "drygrass"},
        "border": ["F", "P"],
        "scatter": [("Z", 0.06, 0.3), ("F", 0.04, 0.55), ("P", 0.02, 0.4)],
        "path_r": 2.0,
        "landmarks": [("W", (32, 26)), ("V", (28, 28)), ("V", (40, 28)), ("G", (20, 29)), ("G", (46, 34)),
                      ("B", (44, 30)), ("H", (56, 27)), ("H", (38, 36)), ("A", (24, 34)), ("A", (52, 28))],
    },
}


def value_noise(seed, cell):
    rnd = random.Random(seed)
    grid = {}

    def g(ix, iy):
        if (ix, iy) not in grid:
            grid[(ix, iy)] = rnd.random()
        return grid[(ix, iy)]

    def f(x, y):
        gx, gy = x / cell, y / cell
        x0, y0 = math.floor(gx), math.floor(gy)
        tx, ty = gx - x0, gy - y0
        tx, ty = tx * tx * (3 - 2 * tx), ty * ty * (3 - 2 * ty)
        a = g(x0, y0) + (g(x0 + 1, y0) - g(x0, y0)) * tx
        b = g(x0, y0 + 1) + (g(x0 + 1, y0 + 1) - g(x0, y0 + 1)) * tx
        return a + (b - a) * ty
    return f


def build(bid, b):
    rnd = random.Random(b["seed"])
    g = [['.' for _ in range(W)] for _ in range(H)]
    taken = set()  # tiles a prop or a clearing already holds

    def disc(cx, cy, r):
        for y in range(max(0, int(cy - r - 1)), min(H, int(cy + r + 2))):
            for x in range(max(0, int(cx - r - 1)), min(W, int(cx + r + 2))):
                if (x - cx) ** 2 + ((y - cy) / 0.85) ** 2 <= r * r:
                    g[y][x] = ':'

    def road(a, c, r, wiggle=3.0):
        # A wandering line: midpoints pushed sideways, then sampled densely.
        pts = [a]
        n = max(2, int(math.dist(a, c) / 8))
        for i in range(1, n):
            t = i / n
            pts.append((a[0] + (c[0] - a[0]) * t + rnd.uniform(-wiggle, wiggle),
                        a[1] + (c[1] - a[1]) * t + rnd.uniform(-wiggle, wiggle)))
        pts.append(c)
        for p, q in zip(pts, pts[1:]):
            steps = int(math.dist(p, q) * 3) + 1
            for i in range(steps + 1):
                t = i / steps
                disc(p[0] + (q[0] - p[0]) * t, p[1] + (q[1] - p[1]) * t, r)

    def clear(cx, cy, r):
        for y in range(H):
            for x in range(W):
                if (x - cx) ** 2 + (y - cy) ** 2 <= r * r:
                    taken.add((x, y))

    r = b["path_r"]
    road(START, WARD, r)
    road(WARD, BLOT, r, 2.0)
    for p in RESCUE:
        road(WARD if p[1] > 30 else (44, 28), p, r * 0.8)
    for s in SPAWNS:
        if rnd.random() < 0.6:
            disc(s[0], s[1], 2.2)
    if "patches" in b:  # open ground of the biome's own floor: bog in the marsh, scree on the hills
        cell, cut = b["patches"]
        pn = value_noise(b["seed"] * 7 + 1, cell)
        for y in range(H):
            for x in range(W):
                if pn(x, y) > cut:
                    g[y][x] = ':'
    disc(START[0], START[1], 2.5)
    disc(BLOT[0], BLOT[1], 3.0)
    for x in range(W):  # paths stay a little ragged
        for y in range(H):
            if g[y][x] == ':' and rnd.random() < 0.04:
                g[y][x] = '.'
    # What must stay open: the start, the wardstone, the Blot, rescue spots, spawn points, the road itself.
    for p, rr in [(START, 4), (WARD, 4), (BLOT, 4), (SIGN_AT, 2)] + [(p, 3) for p in RESCUE] + [(s, 2) for s in SPAWNS]:
        clear(p[0], p[1], rr)
    for y in range(H):
        for x in range(W):
            if g[y][x] == ':':
                taken.add((x, y))

    props = b["props"]
    chars = {k: k for k in props}
    assert not set(chars) & set("TtrRSobkfe@:0123456789"), "prop chars clash with the map legend"

    def place(key, x, y):
        kind = props[key]
        w, h = SIZE.get(kind, (2, 2))
        cells = {(xx, yy) for yy in range(y - h + 1, y + 1) for xx in range(x - w // 2, x - w // 2 + w)}
        if any(not (0 <= cx < W and 0 <= cy < H) for cx, cy in cells):
            return False
        if cells & taken:
            return False
        taken.update(cells)
        g[y][x] = chars[key]
        return True

    for key, at in b.get("landmarks", []):
        if not place(key, at[0], at[1]):
            # nudge a landmark until it fits next to the road
            for d in range(1, 6):
                if any(place(key, at[0] + dx, at[1] + dy) for dx, dy in ((d, 0), (-d, 0), (0, d), (0, -d))):
                    break

    # Border: a thick ragged band of the biome's blockers.
    for y in range(0, H, 2):
        for x in range(0, W, 2):
            edge = min(x, y, W - 1 - x, H - 1 - y)
            if edge <= 3 or (edge <= 6 and rnd.random() < 0.4):
                key = rnd.choice(b["border"])
                h = SIZE.get(props[key], (2, 2))[1]
                place(key, min(W - 2, x + rnd.randint(0, 1)), min(H - 1, y + h - 1 + rnd.randint(0, 1)))

    # Scatter: each prop thinned by its own noise field so they clump.
    for key, dens, clump in b["scatter"]:
        noise = value_noise(b["seed"] * 31 + ord(key[0]), 9)
        for y in range(H):
            for x in range(W):
                n = noise(x, y)
                chance = dens * (1.0 - clump + clump * 3.0 * max(0.0, n - 0.45))
                if x >= BLANK - 1:
                    chance *= 0.5  # the Blank's side is emptier
                if rnd.random() < chance:
                    place(key, x, y)
    # Flowers / ground scraps on open grass
    for y in range(H):
        for x in range(W):
            if g[y][x] == '.' and (x, y) not in taken and rnd.random() < 0.03:
                g[y][x] = 'f'

    for s in SPAWNS:
        g[s[1]][s[0]] = 'e'
    g[START[1]][START[0]] = '@'
    g[SIGN_AT[1]][SIGN_AT[0]] = '1'

    head = ["# Last Ink map: %s (80 x 60 tiles of 16px). Generated by tools/make_biomes.py: edit that script, not this file." % b["name"],
            "# Same legend as frayed_meadow.txt; the @prop lines below name this biome's props (free-standing, placed at",
            "# their bottom-centre tile). Same open spots as the meadow, so Defense / Reclaim / Rescue missions fit.",
            "@name " + b["name"], "@blank %d" % BLANK, "@ground " + b["ground"], "@mood " + b["mood"]]
    for k, kind in props.items():
        head.append("@prop%s %s" % (chars[k], kind))
    head.append("@sign1 " + b["sign"])
    head.append("---")
    path = os.path.join(MAPS, bid + ".txt")
    with open(path, "w") as f:
        f.write("\n".join(head) + "\n" + "\n".join("".join(row) for row in g) + "\n")
    print("wrote", path)


if __name__ == "__main__":
    for bid, b in BIOMES.items():
        build(bid, b)
