#!/usr/bin/env python3
"""Packs raw PixelLab frames into game sprite strips (docs/ART_ROADMAP.md section 4).

Input: a raw folder as written by tools/pixellab.py fetch_character():
    <dir>.png                 rotations (8 or fewer)
    <anim>_<dir>_<i>.png      animation frames
Output:
    assets/sprites/<id>/<anim>_<dir>.png   one horizontal strip per animation and direction
    assets/sprites/<id>/rot_<dir>.png      rotations, as a 1-frame "rot" animation
    data/sprites.json                      entry for <id> (size, feet line, fps, loop, frames, dirs)

Only the right-hand directions are kept by default (south, south-east, east, north-east, north):
the game mirrors the left side (scripts/sprite_set.gd). Pass --all-dirs to keep all eight.

Every frame goes through palette_lock.clean() (stray alpha, outline colour) unless --raw.

    python3 tools/import_sprites.py RAW_DIR ID --anim idle:6:loop --anim attack:14:once ...
"""
import argparse
import glob
import json
import os
import re
import sys

from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import palette_lock  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RIGHT = ["south", "south-east", "east", "north-east", "north"]
ALL = RIGHT + ["north-west", "west", "south-west"]


def feet_line(img):
    """Lowest row with a solid pixel, and the horizontal centre of the solid pixels in the bottom rows."""
    w, h = img.size
    px = img.load()
    bottom = 0
    for y in range(h):
        for x in range(w):
            if px[x, y][3] > 128:
                bottom = y
    xs = [x for y in range(max(0, bottom - 3), bottom + 1) for x in range(w) if px[x, y][3] > 128]
    cx = (min(xs) + max(xs) + 1) / 2 if xs else w / 2
    return int(round(cx)), bottom


def dump(data):
    """JSON with one line per sprite field and per animation, so diffs stay readable."""
    out = ["{", '\t"_comment": ' + json.dumps(data["_comment"]) + ",", '\t"sprites": {']
    ids = list(data["sprites"])
    for n, sid in enumerate(ids):
        e = data["sprites"][sid]
        out.append(f'\t\t{json.dumps(sid)}: {{')
        keys = [k for k in e if k != "anims"]
        for k in keys:
            out.append(f'\t\t\t{json.dumps(k)}: {json.dumps(e[k])},')
        out.append('\t\t\t"anims": {')
        an = list(e.get("anims", {}))
        for i, a in enumerate(an):
            out.append(f'\t\t\t\t{json.dumps(a)}: {json.dumps(e["anims"][a])}' + ("," if i < len(an) - 1 else ""))
        out.append("\t\t\t}")
        out.append("\t\t}" + ("," if n < len(ids) - 1 else ""))
    out += ["\t}", "}", ""]
    return "\n".join(out)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("raw")
    ap.add_argument("id")
    ap.add_argument("--anim", action="append", default=[], help="name:fps:loop|once[:src_name][:dirs=a,b]")
    ap.add_argument("--all-dirs", action="store_true")
    ap.add_argument("--raw-pixels", action="store_true")
    ap.add_argument("--blank", action="store_true", help="a creature of the Blank: keeps the reserved paper white")
    ap.add_argument("--size", type=int, default=44, help="frame size; 44 fits v3 animation canvases around a 32 px character")
    args = ap.parse_args()

    out_dir = os.path.join(ROOT, "assets", "sprites", args.id)
    os.makedirs(out_dir, exist_ok=True)
    for old in glob.glob(os.path.join(out_dir, "*.png")):
        os.remove(old)
    keep = ALL if args.all_dirs else RIGHT
    size = args.size

    def prep(path):
        im = Image.open(path).convert("RGBA")
        if im.size != (size, size):
            # Rotations come on the 32 px canvas, v3 animations on a padded 44 px canvas with the
            # figure at the same scale and centre: pad or crop around the centre so every frame lines up.
            w, h = im.size
            canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
            canvas.paste(im, ((size - w) // 2, (size - h) // 2))
            im = canvas
        return im if args.raw_pixels else palette_lock.clean(im, blank=args.blank)

    entry = {"size": [size, size], "anims": {}}
    # Rotations
    rot_dirs = []
    for d in keep:
        p = os.path.join(args.raw, f"{d}.png")
        if os.path.exists(p):
            prep(p).save(os.path.join(out_dir, f"rot_{d}.png"))
            rot_dirs.append(d)
    if rot_dirs:
        entry["anims"]["rot"] = {"fps": 1, "loop": True, "frames": 1, "dirs": rot_dirs}
        south = Image.open(os.path.join(out_dir, f"rot_{rot_dirs[0]}.png"))
        fx, fy = feet_line(south)
        entry["feet"] = [fx, fy]
        # HUD face icon: a 20x20 window on the head of the south-facing rotation.
        top = min((y for y in range(size) for x in range(size) if south.getpixel((x, y))[3] > 128), default=0)
        entry["face"] = [max(0, min(size - 20, fx - 10)), max(0, top - 1), 20, 20]

    for spec in args.anim:
        parts = spec.split(":")
        name, fps, mode = parts[0], float(parts[1]), parts[2]
        src = name
        only = None
        for extra in parts[3:]:
            if extra.startswith("dirs="):
                only = extra[5:].split(",")
            else:
                src = extra
        dirs = []
        nframes = None
        for d in keep:
            if only and d not in only:
                continue
            frames = sorted(glob.glob(os.path.join(args.raw, f"{src}_{d}_*.png")),
                            key=lambda p: int(re.search(r"_(\d+)\.png$", p).group(1)))
            if not frames:
                continue
            ims = [prep(p) for p in frames]
            strip = Image.new("RGBA", (size * len(ims), size), (0, 0, 0, 0))
            for i, im in enumerate(ims):
                strip.paste(im, (i * size, 0))
            strip.save(os.path.join(out_dir, f"{name}_{d}.png"))
            dirs.append(d)
            nframes = len(ims) if nframes is None else min(nframes, len(ims))
        if dirs:
            entry["anims"][name] = {"fps": fps, "loop": mode == "loop", "frames": nframes, "dirs": dirs}
        else:
            print(f"warning: no frames for {name} ({src})", file=sys.stderr)

    data_path = os.path.join(ROOT, "data", "sprites.json")
    data = json.load(open(data_path)) if os.path.exists(data_path) else {
        "_comment": "Art pass sprite sets (scripts/sprite_set.gd). Written by tools/import_sprites.py; one entry per character id. "
                    "size: frame size; feet: the pixel that stands on the actor's origin; anims: fps, loop, frames, drawn dirs "
                    "(left-hand dirs are mirrored in game).",
        "sprites": {}}
    data["sprites"][args.id] = entry
    with open(data_path, "w") as f:
        f.write(dump(data))
    print(json.dumps(entry))


if __name__ == "__main__":
    main()
