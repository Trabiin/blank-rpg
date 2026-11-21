#!/usr/bin/env python3
"""Character consistency sheets for the AI artefact audit (issue #166): for each character, the dialogue
portrait, every expression (assets/portraits/<id>_<expr>.png), every CG they are listed in, and the field
sprite's five rotations side by side, so face, hair, eye colour, outfit and signature weapon can be compared
at a glance.

    python3 tools/character_sheet.py out_dir            # one sheet per character + all.png overview
    python3 tools/character_sheet.py out_dir ash bran   # only these

CGs: any image under assets/cg/ whose name contains the character id (for #117, once CGs exist).
"""
import os
import sys

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PORTRAITS = os.path.join(ROOT, "assets", "portraits")
SPRITES = os.path.join(ROOT, "assets", "sprites")
CGS = os.path.join(ROOT, "assets", "cg")
DIRS = ["south", "south-east", "east", "north-east", "north"]
BG = (38, 36, 44)
FG = (230, 224, 210)
SPRITE_SCALE = 4
H = 336


def _font(size):
    try:
        return ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", size)
    except OSError:
        return ImageFont.load_default()


def characters():
    ids = {f[:-4].split("_")[0] for f in os.listdir(PORTRAITS) if f.endswith(".png")}
    ids |= {d for d in os.listdir(SPRITES) if os.path.isfile(os.path.join(SPRITES, d, "rot_south.png"))}
    return sorted(ids)


def pieces(cid):
    out = []
    p = os.path.join(PORTRAITS, cid + ".png")
    if os.path.exists(p):
        out.append(("portrait", Image.open(p).convert("RGBA")))
    for f in sorted(os.listdir(PORTRAITS)):
        if f.startswith(cid + "_") and f.endswith(".png"):
            out.append((f[len(cid) + 1:-4], Image.open(os.path.join(PORTRAITS, f)).convert("RGBA")))
    if os.path.isdir(CGS):
        for f in sorted(os.listdir(CGS)):
            if cid in f and f.lower().endswith((".png", ".jpg")):
                im = Image.open(os.path.join(CGS, f)).convert("RGBA")
                out.append(("cg " + f[:-4], im.resize((im.size[0] * H // im.size[1], H))))
    for d in DIRS:
        p = os.path.join(SPRITES, cid, "rot_%s.png" % d)
        if os.path.exists(p):
            im = Image.open(p).convert("RGBA")
            im = im.crop((0, 0, im.size[1], im.size[1]))
            out.append((d, im.resize((im.size[0] * SPRITE_SCALE, im.size[1] * SPRITE_SCALE), Image.NEAREST)))
    return out


def sheet(cid):
    ps = pieces(cid)
    if not ps:
        return None
    pad, top = 8, 28
    w = sum(im.size[0] for _, im in ps) + pad * (len(ps) + 1)
    h = max(im.size[1] for _, im in ps) + top + pad
    out = Image.new("RGBA", (w, h), BG + (255,))
    d = ImageDraw.Draw(out)
    d.text((pad, 6), cid, fill=FG, font=_font(16))
    x = pad
    for label, im in ps:
        out.alpha_composite(im, (x, top + (h - top - pad - im.size[1])))
        d.text((x, top - 2 + h - top - pad - im.size[1] - 14), label, fill=FG, font=_font(11))
        x += im.size[0] + pad
    return out


def main(argv):
    if not argv:
        print(__doc__)
        return 1
    out_dir = argv[0]
    os.makedirs(out_dir, exist_ok=True)
    ids = argv[1:] or characters()
    made = []
    for cid in ids:
        s = sheet(cid)
        if s:
            s.save(os.path.join(out_dir, cid + ".png"))
            made.append(s)
    if len(ids) > 1 and made:
        W = max(s.size[0] for s in made)
        allim = Image.new("RGBA", (W, sum(s.size[1] for s in made)), BG + (255,))
        y = 0
        for s in made:
            allim.alpha_composite(s, (0, y))
            y += s.size[1]
        allim.save(os.path.join(out_dir, "all.png"))
    print("%d sheets in %s" % (len(made), out_dir))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
