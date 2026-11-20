#!/usr/bin/env python3
"""Art audit (Phase 8 polish): checks the art against docs/ART_STYLE.md and redraws the comparison images, so each
polish step can be judged against the same yardstick.

    python3 tools/audit_art.py [out_dir]            # report + lineup.png + heads.png
    python3 tools/audit_art.py out_dir --shots      # also re-shoot the fixed screenshot set (needs Godot, ~6 min)

Checks:
  characters  figure height (measured) and head box (from tools/art_audit.json, measured by eye) against the
              body class bands
  props       sprite height against the prop scale table
  maps        identical twins: the same prop sprite (same variant) placed within 3 tiles of itself
"""
import json
import os
import re
import subprocess
import sys

from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SPEC = json.load(open(os.path.join(ROOT, "tools", "art_audit.json")))
SPRITES = json.load(open(os.path.join(ROOT, "data", "sprites.json")))["sprites"]
BUILTIN_PROPS = {"T": "bush", "t": "shrub", "r": "rock", "R": "rock_big", "S": "stump", "o": "pond", "b": "bones", "k": "skull"}
TWIN_RADIUS = 3

# The fixed screenshot set every step is compared on: name, then tools/shot.gd arguments.
SHOTS = [
    ("town_wide", "scene=town zoom=1"),
    ("town_lv3", "scene=town zoom=1 levels=3"),
    ("night", "scene=town zoom=1 day=0.9"),
    ("meadow_fight", "scene=mission mission=meadow_patrol kinds=nibbler,spitter,moth at=30,20 spread=1"),
    ("gutterwoods_wide", "scene=mission mission=meadow_patrol map=gutterwoods zoom=1"),
    ("saltreed_wide", "scene=mission mission=meadow_patrol map=saltreed zoom=1"),
    ("oldmill_wide", "scene=mission mission=meadow_patrol map=oldmill zoom=1"),
    ("lampwick_wide", "scene=mission mission=meadow_patrol map=lampwick zoom=1"),
    ("tithe_road_wide", "scene=mission mission=meadow_patrol map=tithe_road zoom=1"),
    ("tollgate", "scene=mission mission=auditor_duel zoom=1"),
    ("taxoffice", "scene=mission mission=ch1_breakout zoom=1"),
    ("enemies", "scene=mission mission=meadow_patrol kinds=enforcer,reedling,scarecrow,sellsword at=30,20 spread=1"),
    ("command", "scene=town act=call:_open_table"),
    ("title", "scene=title"),
    ("dialogue", "scene=town act=call:dialogue_box.play:quill_first"),
]


def figure(sid):
    s = SPRITES[sid]
    im = Image.open(os.path.join(ROOT, "assets", "sprites", sid, "rot_south.png")).convert("RGBA")
    im = im.crop((0, 0, s["size"][0], s["size"][1]))
    bb = im.getchannel("A").point(lambda v: 255 if v > 128 else 0).getbbox()
    return im.crop(bb), bb


def check_characters():
    rows, issues = [], []
    for sid in SPRITES:
        if not os.path.exists(os.path.join(ROOT, "assets", "sprites", sid, "rot_south.png")):
            continue
        img, bb = figure(sid)
        entry = SPEC["characters"].get(sid)
        if entry is None:
            issues.append(f"{sid}: no class in tools/art_audit.json")
            rows.append((sid, img, "?", []))
            continue
        cls = SPEC["classes"][entry[0]]
        bad = []
        h = img.height
        if not cls["height"][0] <= h <= cls["height"][1]:
            bad.append(f"height {h} (want {cls['height'][0]}-{cls['height'][1]})")
        if "head_w" in cls and len(entry) >= 3:
            hw, hh = entry[1], entry[2]
            if not cls["head_w"][0] <= hw <= cls["head_w"][1] or not cls["head_h"][0] <= hh <= cls["head_h"][1]:
                bad.append(f"head {hw}x{hh} (want {cls['head_w'][0]}-{cls['head_w'][1]} x {cls['head_h'][0]}-{cls['head_h'][1]})")
        for b in bad:
            issues.append(f"{sid} [{entry[0]}]: {b}")
        rows.append((sid, img, entry[0], bad))
    return rows, issues


def check_props():
    issues = []
    for kind, limit in SPEC["props"].items():
        p = os.path.join(ROOT, "assets", "props", kind + ".png")
        if os.path.exists(p):
            h = Image.open(p).height
            if h > limit:
                issues.append(f"prop {kind}: {h} px tall (max {limit})")
    return issues


def variants(kind):
    base = os.path.join(ROOT, "assets", "props", kind + ".png")
    if not os.path.exists(base):
        return 1
    n = 1
    while os.path.exists(base.replace(".png", f"_v{n}.png")):
        n += 1
    return n


def check_maps():
    issues = []
    for name in sorted(os.listdir(os.path.join(ROOT, "maps"))):
        text = open(os.path.join(ROOT, "maps", name)).read().split("\n")
        chars = dict(BUILTIN_PROPS)
        for line in text:
            m = re.match(r"@prop(.) ([a-z_0-9]+)", line)
            if m:
                chars[m.group(1)] = m.group(2)
        grid = text[text.index("---") + 1:] if "---" in text else []
        placed = []
        for y, row in enumerate(grid):
            for x, ch in enumerate(row):
                if ch in chars:
                    kind = chars[ch]
                    seed = x * 31 + y
                    n = variants(kind)
                    placed.append((x, y, kind, (seed * 7 + seed // 5) % n))
        twins = {}
        for i, a in enumerate(placed):
            for b in placed[i + 1:]:
                if a[2:] == b[2:] and abs(a[0] - b[0]) <= TWIN_RADIUS and abs(a[1] - b[1]) <= TWIN_RADIUS:
                    twins[a[2]] = twins.get(a[2], 0) + 1
        if twins:
            top = ", ".join(f"{k} {v}" for k, v in sorted(twins.items(), key=lambda kv: -kv[1])[:4])
            issues.append(f"map {name}: {sum(twins.values())} identical prop pairs within {TWIN_RADIUS} tiles ({top})")
    return issues


def lineup(rows, out):
    S, pad = 4, 6
    rows = sorted(rows, key=lambda r: -r[1].height)
    W = sum(r[1].width + pad for r in rows) + pad
    H = max(r[1].height for r in rows) + 30
    L = Image.new("RGBA", (W * S, H * S), (52, 56, 66, 255))
    d = ImageDraw.Draw(L)
    base = (H - 12) * S
    for y in range(0, H * S, 16 * S):
        d.line([0, base - y, W * S, base - y], fill=(80, 86, 100, 255))
    x = pad
    for sid, img, cls, bad in rows:
        L.alpha_composite(img.resize((img.width * S, img.height * S), Image.NEAREST), (x * S, base - img.height * S))
        d.text((x * S, base + 8), sid[:10], fill=(255, 120, 110, 255) if bad else (255, 255, 255, 255))
        d.text((x * S, base + 24), f"{img.height}px {cls}", fill=(255, 220, 120, 255))
        x += img.width + pad
    L.save(out)


def heads(rows, out):
    S, cw, ch, cols = 8, 34, 18, 8
    rows = [r for r in rows if SPEC["classes"].get(r[2], {}).get("head_w")]
    L = Image.new("RGBA", (cols * cw * S, ((len(rows) + cols - 1) // cols) * (ch * S + 14)), (70, 74, 86, 255))
    d = ImageDraw.Draw(L)
    for i, (sid, img, cls, bad) in enumerate(rows):
        cx = img.width // 2
        crop = img.crop((cx - cw // 2, 0, cx + cw // 2, ch)).resize((cw * S, ch * S), Image.NEAREST)
        X, Y = (i % cols) * cw * S, (i // cols) * (ch * S + 14)
        L.alpha_composite(crop, (X, Y))
        for y in range(0, ch + 1, 2):
            d.line([X, Y + y * S, X + 6, Y + y * S], fill=(255, 255, 0, 255))
            if y % 4 == 0:
                d.text((X + 8, Y + y * S - 5), str(y), fill=(255, 255, 0, 255))
        d.text((X + 40, Y + ch * S + 2), f"{sid} ({img.height}px)", fill=(255, 120, 110, 255) if bad else (255, 255, 255, 255))
    L.save(out)


def shots(out):
    godot = os.path.expanduser("~/godot/Godot_v4.3-stable_linux.x86_64")
    for name, args in SHOTS:
        cmd = ["timeout", "150", "xvfb-run", "-a", godot, "--path", ROOT, "--resolution", "1280x720", "-s", "tools/shot.gd",
               "--", f"out={out}/{name}.png", "frames=110", "party=ash,bran,gristle", "day=0.45"] + args.split()
        if "day=0.9" in args:
            cmd.remove("day=0.45")
        subprocess.run(cmd, cwd=ROOT, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        print("shot", name)


def main():
    out = sys.argv[1] if len(sys.argv) > 1 and not sys.argv[1].startswith("--") else "/tmp/art_audit"
    os.makedirs(out, exist_ok=True)
    rows, issues = check_characters()
    issues += check_props() + check_maps()
    lineup(rows, os.path.join(out, "lineup.png"))
    heads(rows, os.path.join(out, "heads.png"))
    report = "\n".join(issues) or "no issues"
    open(os.path.join(out, "report.txt"), "w").write(report + "\n")
    print(report)
    print(f"{len(issues)} issues; images in {out}")
    if "--shots" in sys.argv:
        shots(out)


if __name__ == "__main__":
    main()
