#!/usr/bin/env python3
"""Procedural seamless cobblestone texture in the style palette (docs/ART_STYLE.md), matching the target plaza:
irregular stones a little wider than tall, lit from the top left, mossy cracks, a few darker and lighter stones.

    python3 tools/make_cobbles.py assets/tiles/town/cobbles.png [--size 128] [--seed 3]
"""
import math, random, sys
from PIL import Image

def hexc(h): return tuple(int(h[i:i + 2], 16) for i in (1, 3, 5))
STONE = [hexc(c) for c in ("#3d4152", "#575b6b", "#7a7d88")]   # dark, mid, light
HI = hexc("#a3a3a6")
SH = hexc("#2e3247")
CRACK = [hexc("#1c2619"), hexc("#2a3a22")]
MOSS = [hexc("#2a3a22"), hexc("#3d5130"), hexc("#566b3a")]

def main():
    out = sys.argv[1]
    size = int(sys.argv[sys.argv.index("--size") + 1]) if "--size" in sys.argv else 128
    seed = int(sys.argv[sys.argv.index("--seed") + 1]) if "--seed" in sys.argv else 3
    rnd = random.Random(seed)
    # Jittered grid of stone centres, offset every other row like laid cobbles; stones ~7x5 px.
    sx, sy = 9.0, 6.0
    pts = []
    rows = int(size / sy)
    cols = int(size / sx)
    for r in range(rows):
        for c in range(cols):
            x = (c + 0.5 + (0.5 if r % 2 else 0.0)) * size / cols + rnd.uniform(-1.6, 1.6)
            y = (r + 0.5) * size / rows + rnd.uniform(-1.0, 1.0)
            tone = rnd.choices([0, 1, 2], weights=[2, 9, 2])[0]
            pts.append((x % size, y % size, tone, rnd.random()))
    yscale = sx / sy
    def near(x, y):
        best = [(1e9, None), (1e9, None)]
        for p in pts:
            dx = (x - p[0] + size / 2) % size - size / 2
            dy = ((y - p[1] + size / 2) % size - size / 2) * yscale
            d = math.hypot(dx, dy)
            if d < best[0][0]:
                best = [(d, (p, dx, dy)), best[0]]
            elif d < best[1][0]:
                best[1] = (d, (p, dx, dy))
        return best
    # Low-frequency moss field (tileable: sum of sines with integer periods).
    ph = [rnd.uniform(0, 6.28) for _ in range(6)]
    def moss(x, y):
        t = 2 * math.pi / size
        return (math.sin(x * t * 2 + ph[0]) + math.sin(y * t * 3 + ph[1]) + math.sin((x + y) * t * 1 + ph[2])
                + 0.6 * math.sin((x - y) * t * 4 + ph[3])) / 3.6
    img = Image.new("RGB", (size, size))
    px = img.load()
    for y in range(size):
        for x in range(size):
            (d1, a), (d2, b) = near(x + 0.5, y + 0.5)
            edge = d2 - d1
            m = moss(x, y)
            p, dx, dy = a
            if edge < 1.5:
                col = CRACK[1] if m > -0.2 else CRACK[0]
                if m > 0.1 and rnd.random() < 0.7:
                    col = MOSS[1]
            else:
                col = STONE[p[2]]
                # Top-left light: the rim facing up-left is lit, the rim facing down-right is in shade.
                if edge < 2.4:
                    if dx < -0.5 and dy < 0.5 or dy < -1.2:
                        col = STONE[min(p[2] + 1, 2)]
                    elif dx > 0.5 or dy > 1.2:
                        col = SH if p[2] == 0 else STONE[max(p[2] - 1, 0)]
                # Moss creeping over stones in the mossy patches.
                if m > 0.35 and rnd.random() < (m - 0.35) * 1.8:
                    col = MOSS[2] if rnd.random() < 0.4 else MOSS[1]
            px[x, y] = col
    img.save(out)
    print("wrote", out, size)

if __name__ == "__main__":
    main()
