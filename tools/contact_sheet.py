#!/usr/bin/env python3
"""Contact sheets for art review: rows of sprites blown up with nearest-neighbour, labelled.

    python3 tools/contact_sheet.py out.png --scale 4 --row "Label" a.png b.png ... --row "Label 2" ...
A strip (wider than tall, width a multiple of its height) is split into its frames.
"""
import sys

from PIL import Image, ImageDraw, ImageFont

BG = (38, 36, 44)
FG = (230, 224, 210)
GRASS = (86, 120, 70)


def frames_of(path):
    im = Image.open(path).convert("RGBA")
    w, h = im.size
    if w > h and w % h == 0:
        return [im.crop((i * h, 0, (i + 1) * h, h)) for i in range(w // h)]
    return [im]


def build(rows, scale=4, pad=6, label_w=150, ground=False):
    cells = [(label, [f for p in paths for f in frames_of(p)]) for label, paths in rows]
    cw = max(f.size[0] for _, fs in cells for f in fs) * scale
    ch = max(f.size[1] for _, fs in cells for f in fs) * scale
    ncol = max(len(fs) for _, fs in cells)
    W = label_w + ncol * (cw + pad) + pad
    H = len(cells) * (ch + pad) + pad
    sheet = Image.new("RGBA", (W, H), BG + (255,))
    d = ImageDraw.Draw(sheet)
    try:
        font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 13)
    except OSError:
        font = ImageFont.load_default()
    for r, (label, fs) in enumerate(cells):
        y = pad + r * (ch + pad)
        d.text((8, y + ch // 2 - 8), label, fill=FG, font=font)
        for c, f in enumerate(fs):
            x = label_w + pad + c * (cw + pad)
            if ground:
                d.rectangle([x, y, x + cw - 1, y + ch - 1], fill=GRASS + (255,))
            big = f.resize((f.size[0] * scale, f.size[1] * scale), Image.NEAREST)
            sheet.alpha_composite(big, (x + (cw - big.size[0]) // 2, y + (ch - big.size[1]) // 2))
    return sheet


if __name__ == "__main__":
    out = sys.argv[1]
    scale = 4
    ground = "--ground" in sys.argv
    rows = []
    args = [a for a in sys.argv[2:] if a != "--ground"]
    i = 0
    while i < len(args):
        if args[i] == "--scale":
            scale = int(args[i + 1])
            i += 2
        elif args[i] == "--row":
            rows.append((args[i + 1], []))
            i += 2
        else:
            rows[-1][1].append(args[i])
            i += 1
    build(rows, scale, ground=ground).save(out)
