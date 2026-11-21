"""Draws the Last Ink app icon (issue #145) as 32x32 pixel art in the style palette and writes it
scaled up with nearest-neighbour, so it stays crisp on every platform:

  assets/icon/icon.png      256x256  project icon (window, taskbar, web favicon, Windows .exe)
  assets/icon/icon_1024.png 1024x1024 macOS (Godot turns it into the .icns)
  assets/icon/icon_32.png   32x32    the source pixels

A drop of ink on old paper, its upper right corner being eaten by the Blank (paper white, the one
colour reserved for it). Run: python3 tools/make_icon.py
"""
import os
from PIL import Image

INK = (0x12, 0x14, 0x1f, 255)
SHADOW = (0x1f, 0x22, 0x33, 255)
SLATE = (0x2e, 0x32, 0x47, 255)
BLUE = (0x3a, 0x5f, 0x9e, 255)
GLOW = (0x7f, 0xa8, 0xec, 255)
BONE = (0xd6, 0xcd, 0xba, 255)
PLASTER = (0xb5, 0xa6, 0x8a, 255)
PSHADOW = (0x8f, 0x82, 0x70, 255)
STRAW = (0xc9, 0xa9, 0x7a, 255)
BLANK = (0xf3, 0xee, 0xe2, 255)
CLEAR = (0, 0, 0, 0)

N = 32
img = Image.new("RGBA", (N, N), CLEAR)
px = img.load()

# Rounded paper tile, 1px ink outline.
def inside_tile(x, y, r=5):
    lo, hi = 1, N - 2
    if x < lo or x > hi or y < lo or y > hi:
        return False
    cx = min(max(x, lo + r), hi - r)
    cy = min(max(y, lo + r), hi - r)
    return (x - cx) ** 2 + (y - cy) ** 2 <= r * r + 1

for y in range(N):
    for x in range(N):
        if inside_tile(x, y):
            px[x, y] = BONE
for y in range(N):
    for x in range(N):
        if px[x, y] == BONE:
            edge = any(not inside_tile(x + dx, y + dy) for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)))
            if edge:
                px[x, y] = INK
# Paper grain: shade the lower left, a few fibres.
for y in range(N):
    for x in range(N):
        if px[x, y] == BONE and (x + (N - y)) < 16:
            px[x, y] = PLASTER
for (x, y) in [(6, 22), (7, 22), (24, 25), (25, 25), (9, 8), (21, 27), (5, 14)]:
    if px[x, y] in (BONE, PLASTER):
        px[x, y] = PLASTER if px[x, y] == BONE else PSHADOW

# The Blank eating the top right corner: ragged edge, paper white inside, ink motes flaking off.
bite = {}
edge_y = [0, 0, 1, 1, 2, 3, 3, 4, 5, 5, 6, 8, 8, 9, 10, 12]  # bite depth per column from the right edge
for i, d in enumerate(edge_y[::-1]):
    x = N - 2 - i
    for y in range(1, 2 + d + (1 if i % 4 == 1 else 0)):
        bite[(x, y)] = True
for (x, y) in bite:
    if px[x, y] != CLEAR:
        px[x, y] = BLANK
for (x, y) in list(bite):
    if px[x, y] == BLANK:
        for dx, dy in ((-1, 0), (0, 1)):
            q = (x + dx, y + dy)
            if q not in bite and 0 <= q[0] < N and 0 <= q[1] < N and px[q] in (BONE, PLASTER):
                px[q] = PSHADOW
for (x, y) in [(15, 3), (16, 6), (18, 9), (14, 1)]:
    if px[x, y] in (BONE, PLASTER, PSHADOW):
        px[x, y] = SLATE

# The ink drop: point at the top, round belly, sitting a little low and left of centre.
cx, cy, r = 14.5, 19.5, 7.6
for y in range(N):
    for x in range(N):
        fx, fy = x + 0.5, y + 0.5
        in_belly = (fx - cx) ** 2 + (fy - cy) ** 2 <= r * r
        # Taper from the belly up to a point at y=5.
        in_tip = False
        if 5 <= fy <= cy:
            t = (fy - 5) / (cy - 5)
            half = r * (t ** 1.05)
            in_tip = abs(fx - cx) <= half
        if in_belly or in_tip:
            px[x, y] = INK
# Body shading: a deep blue core reflecting the Ink, a rim of shadow, glints top left.
for y in range(N):
    for x in range(N):
        if px[x, y] != INK:
            continue
        fx, fy = x + 0.5, y + 0.5
        # Reflected light from the paper on the lower right rim, inside the outline.
        d_out = ((fx - cx) ** 2 + (fy - cy) ** 2) ** 0.5
        d_in = ((fx - (cx - 1.8)) ** 2 + (fy - (cy - 1.8)) ** 2) ** 0.5
        if d_out < r - 1.0 and d_in > r - 1.2 and fy > cy - 2:
            px[x, y] = SHADOW
        if d_out < r - 1.2 and d_in > r + 0.4 and fy > cy:
            px[x, y] = SLATE
for (x, y) in [(10, 17), (10, 18), (10, 19), (11, 16), (12, 15), (11, 20)]:
    px[x, y] = BLUE
for (x, y) in [(10, 18), (11, 17)]:
    px[x, y] = GLOW
for (x, y) in [(13, 10), (13, 11), (12, 13)]:
    px[x, y] = SHADOW
# Drop shadow on the paper, to the right (light from the top left, as in the game).
for y in range(int(cy) - 1, N):
    for x in range(N - 1, 0, -1):
        if px[x - 1, y] in (INK, SHADOW, SLATE) and px[x, y] in (BONE, PLASTER):
            px[x, y] = PSHADOW
for x in range(9, 22):
    if px[x, 28] in (BONE, PLASTER) and px[x, 27] in (INK, SHADOW, SLATE, PSHADOW):
        px[x, 28] = PSHADOW
# A small splash beside the drop.
for (x, y) in [(23, 24), (24, 24), (23, 25), (25, 21)]:
    px[x, y] = INK

out = os.path.join(os.path.dirname(__file__), "..", "assets", "icon")
os.makedirs(out, exist_ok=True)
img.save(os.path.join(out, "icon_32.png"))
img.resize((256, 256), Image.NEAREST).save(os.path.join(out, "icon.png"))
img.resize((1024, 1024), Image.NEAREST).save(os.path.join(out, "icon_1024.png"))
print("wrote", os.path.abspath(out))
