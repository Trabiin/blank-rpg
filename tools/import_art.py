#!/usr/bin/env python3
"""Builds runtime art from the CC0 source packs in assets/source/.

- Paper-doll layers: every Puny Characters class sheet is diffed against the bare
  Character-Base sheet, so each outfit becomes its own transparent layer that the
  game stacks on the body and recolors in code.
- Tiles: the overworld sheet is copied as-is; the game picks tiles by grid position.

Run from the repo root:  python3 tools/import_art.py   (needs Pillow)
"""
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "assets" / "source"
CHAR = ROOT / "assets" / "characters"
TILES = ROOT / "assets" / "tiles"
T = 16


def outfit_layers():
    base = Image.open(SRC / "puny" / "Character-Base.png").convert("RGBA")
    base.save(CHAR / "body.png")
    bp = base.load()
    for src_name, out_name in [("Archer-Green", "archer"), ("Warrior-Blue", "warrior"),
                               ("Soldier-Blue", "soldier"), ("Mage-Cyan", "mage")]:
        im = Image.open(SRC / "puny" / f"{src_name}.png").convert("RGBA")
        p = im.load()
        out = Image.new("RGBA", im.size, (0, 0, 0, 0))
        op = out.load()
        palette = {}
        for y in range(im.height):
            for x in range(im.width):
                if p[x, y][3] and p[x, y] != bp[x, y]:
                    op[x, y] = p[x, y]
                    key = "%02x%02x%02x" % p[x, y][:3]
                    palette[key] = palette.get(key, 0) + 1
        out.save(CHAR / f"outfit_{out_name}.png")
        print(out_name, sorted(palette, key=lambda k: -palette[k]))
    Image.open(SRC / "puny" / "Slime.png").convert("RGBA").save(CHAR / "slime.png")


def tiles():
    Image.open(SRC / "zeldalike" / "Overworld.png").convert("RGBA").save(TILES / "overworld.png")


if __name__ == "__main__":
    CHAR.mkdir(parents=True, exist_ok=True)
    TILES.mkdir(parents=True, exist_ok=True)
    outfit_layers()
    tiles()
