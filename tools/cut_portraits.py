#!/usr/bin/env python3
"""Turn the raw AI portraits (1024x1536, flat light-grey background) into game portraits.

Usage: python3 tools/cut_portraits.py SRC_DIR [OUT_DIR]
Reads SRC_DIR/<id>-v2.png (or <id>.png), flood-fills the grey background from the edges to
transparent, feathers the edge a little, and writes OUT_DIR/<id>.png at 512x768.
Expression variants follow the same naming: <id>_<expr>-v2.png -> <id>_<expr>.png.
"""
import sys, os, glob
from collections import deque
from PIL import Image, ImageFilter

TOL = 22  # how far (max channel diff) from the background grey still counts as background
SIZE = (512, 768)
POCKET = 40  # enclosed background blobs bigger than this (in source pixels) are cleared too
# Characters whose own colours sit close to the background grey (Ilse's pale hair) only lose big pockets.
POCKET_FOR = {"ilse": 1500}


def cut(path: str, pocket: int = POCKET) -> Image.Image:
    im = Image.open(path).convert("RGB")
    w, h = im.size
    px = im.load()
    corners = [px[2, 2], px[w - 3, 2], px[2, h // 2], px[w - 3, h // 2], px[w // 2, 2]]
    bg = tuple(sorted(c[i] for c in corners)[len(corners) // 2] for i in range(3))

    def is_bg(p):
        # the grey itself, or the paper-white "erased" flecks that touch it (they read as holes in the
        # art, so on a dark background they should be see-through too)
        if max(p) - min(p) >= 16:
            return False
        if min(p) >= bg[0] - TOL // 2 and max(p) > bg[0]:
            return True
        return max(abs(p[0] - bg[0]), abs(p[1] - bg[1]), abs(p[2] - bg[2])) <= TOL

    def near(p):
        return max(abs(p[0] - bg[0]), abs(p[1] - bg[1]), abs(p[2] - bg[2])) <= 9

    mask = Image.new("L", (w, h), 255)
    m = mask.load()
    q = deque()
    for x in range(w):
        q.append((x, 0)); q.append((x, h - 1))
    for y in range(h):
        q.append((0, y)); q.append((w - 1, y))
    while q:
        x, y = q.popleft()
        if m[x, y] == 0 or not is_bg(px[x, y]):
            continue
        m[x, y] = 0
        if x > 0: q.append((x - 1, y))
        if x < w - 1: q.append((x + 1, y))
        if y > 0: q.append((x, y - 1))
        if y < h - 1: q.append((x, y + 1))
    # Pockets of background enclosed by the figure (between an axe and a head, say): clear any
    # big blob that is almost exactly the background grey.
    seen = bytearray(w * h)
    for sy in range(0, h, 2):
        for sx in range(0, w, 2):
            if seen[sy * w + sx] or m[sx, sy] == 0 or not near(px[sx, sy]):
                continue
            blob, q2 = [], deque([(sx, sy)])
            seen[sy * w + sx] = 1
            while q2:
                x, y = q2.popleft()
                blob.append((x, y))
                for nx, ny in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
                    if 0 <= nx < w and 0 <= ny < h and not seen[ny * w + nx] and m[nx, ny] and near(px[nx, ny]):
                        seen[ny * w + nx] = 1
                        q2.append((nx, ny))
            if len(blob) > pocket:
                for x, y in blob:
                    m[x, y] = 0
    # shave the grey fringe and soften the edge
    mask = mask.filter(ImageFilter.MinFilter(3)).filter(ImageFilter.GaussianBlur(1.2))
    out = im.convert("RGBA")
    out.putalpha(mask)
    return out.resize(SIZE, Image.LANCZOS)


def main():
    src = sys.argv[1]
    dst = sys.argv[2] if len(sys.argv) > 2 else os.path.join(os.path.dirname(__file__), "..", "assets", "portraits")
    os.makedirs(dst, exist_ok=True)
    for f in sorted(glob.glob(os.path.join(src, "*.png"))):
        name = os.path.basename(f)[:-4]
        if name.endswith("-test1"):
            continue
        pid = name[:-3] if name.endswith("-v2") else name
        cut(f, POCKET_FOR.get(pid.split("_")[0], POCKET)).save(os.path.join(dst, pid + ".png"), optimize=True)
        print("wrote", pid)


if __name__ == "__main__":
    main()
