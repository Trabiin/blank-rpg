#!/usr/bin/env python3
"""AI artefact audit (issue #166): scans the pixel art for the small tells that make generated art read as
"AI slop", so each chapter can be checked with the same yardstick before it ships.

    python3 tools/ai_audit.py                 # report on every sprite, prop, building, icon and tile
    python3 tools/ai_audit.py --fix           # also repair what is safe to repair in code (see below)
    python3 tools/ai_audit.py --json out.json # machine-readable report

Checks, per frame:
  soft     half-transparent pixels (pixel art uses hard alpha; soft fringes are generator leftovers)
  specks   loose pixel islands smaller than SPECK that float free of the figure (stray noise pixels)
  feet     idle/walk frames whose lowest row jumps more than FEET_JITTER from the strip's usual baseline
           (the sprite bobs or sinks in a way the animation did not intend)
  pop      frames whose filled area is more than POP off the strip median (a detail appears or melts away)
  outline  frames whose share of dark outline round the silhouette differs from the strip by more than
           OUTLINE (outline thickness changing between frames)
  palette  share of pixels outside tools/style_palette.hex (reported, not an error: the hero sprites predate
           the palette lock; see docs/ART_STYLE.md)

--fix repairs only the first two (hard alpha and speck removal) because they never change what a sprite
is meant to look like. Everything else is listed for a person to judge; see docs/AI_AUDIT.md.
"""
import json
import os
import sys

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)
import palette_lock  # noqa: E402

SPECK = 4          # islands smaller than this (8-connected) are noise
FEET_JITTER = 1    # pixels
POP = 0.22         # share of the median filled area
OUTLINE = 0.25     # share of the silhouette edge
SPRITES = json.load(open(os.path.join(ROOT, "data", "sprites.json")))["sprites"]
STEADY = ("rot", "idle", "walk")  # strips whose frames should keep one silhouette
# Islands that are meant to float: projectiles and FX drawn into the strip (checked by eye, see docs/AI_AUDIT.md).
LOOSE_OK = {
    "spitter/attack": "spit glob leaves the mouth",
    "moth/attack": "dust puff",
    "enforcer/death": "body breaks into ink",
    "auditor/death": "body breaks into ink",
    "auditor/phase": "torn paper scraps",
    "auditor/sweep": "quill-blade ink trail",
}


def _palette():
    return {tuple(c[:3]) for c in palette_lock.load_palette()}


def components(im):
    """8-connected islands of opaque pixels, largest first, as lists of (x, y)."""
    w, h = im.size
    a = im.getchannel("A").load()
    seen = bytearray(w * h)
    out = []
    for y in range(h):
        for x in range(w):
            if a[x, y] == 0 or seen[y * w + x]:
                continue
            comp, stack = [], [(x, y)]
            seen[y * w + x] = 1
            while stack:
                cx, cy = stack.pop()
                comp.append((cx, cy))
                for dx in (-1, 0, 1):
                    for dy in (-1, 0, 1):
                        nx, ny = cx + dx, cy + dy
                        if 0 <= nx < w and 0 <= ny < h and not seen[ny * w + nx] and a[nx, ny]:
                            seen[ny * w + nx] = 1
                            stack.append((nx, ny))
            out.append(comp)
    out.sort(key=len, reverse=True)
    return out


def _luma(p):
    return 0.299 * p[0] + 0.587 * p[1] + 0.114 * p[2]


def frame_stats(im, pal):
    w, h = im.size
    px = im.load()
    soft = filled = off = edge = dark_edge = 0
    bottom = -1
    for y in range(h):
        for x in range(w):
            p = px[x, y]
            if p[3] == 0:
                continue
            filled += 1
            bottom = max(bottom, y)
            if p[3] != 255:
                soft += 1
            if p[:3] not in pal:
                off += 1
            if any(not (0 <= x + dx < w and 0 <= y + dy < h) or px[x + dx, y + dy][3] == 0
                   for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))):
                edge += 1
                if _luma(p) < 60:
                    dark_edge += 1
    comps = components(im) if filled else []
    specks = [c for c in comps[1:] if len(c) < SPECK]
    return {
        "soft": soft, "filled": filled, "off": off, "bottom": bottom,
        "outline": dark_edge / edge if edge else 0.0,
        "specks": sum(len(c) for c in specks), "speck_cells": [p for c in specks for p in c],
    }


def frames(path, size):
    im = Image.open(path).convert("RGBA")
    fw, fh = size
    if im.size[1] != fh or im.size[0] % fw:
        fw, fh = im.size[1], im.size[1]
    return im, [(i * fw, 0, fw, fh) for i in range(im.size[0] // fw)]


def median(v):
    s = sorted(v)
    return s[len(s) // 2] if s else 0


def audit_sprite_strip(sid, name, path, pal, fix):
    size = SPRITES.get(sid, {}).get("size", [44, 44])
    im, rects = frames(path, size)
    anim = name.split("_")[0]
    key = "%s/%s" % (sid, anim)
    stats = [frame_stats(im.crop((x, y, x + w, y + h)), pal) for x, y, w, h in rects]
    issues = []
    for i, s in enumerate(stats):
        if s["soft"]:
            issues.append(("soft", i, "%d half-transparent px" % s["soft"]))
        if s["specks"] and key not in LOOSE_OK:
            issues.append(("specks", i, "%d loose px" % s["specks"]))
    live = [s for s in stats if s["filled"]]
    if anim in STEADY and len(live) > 1:
        base = median([s["bottom"] for s in live])
        area = median([s["filled"] for s in live])
        line = median([s["outline"] for s in live])
        for i, s in enumerate(stats):
            if not s["filled"]:
                continue
            if abs(s["bottom"] - base) > FEET_JITTER:
                issues.append(("feet", i, "baseline %+d px" % (s["bottom"] - base)))
            if area and abs(s["filled"] - area) / area > POP:
                issues.append(("pop", i, "area %+d%%" % round(100 * (s["filled"] - area) / area)))
            if abs(s["outline"] - line) > OUTLINE:
                issues.append(("outline", i, "dark edge %d%% vs %d%%" % (100 * s["outline"], 100 * line)))
    if fix and any(k in ("soft", "specks") for k, _, _ in issues):
        _repair(im, rects, stats, key)
        im.save(path)
    off = sum(s["off"] for s in stats)
    tot = sum(s["filled"] for s in stats) or 1
    return issues, off / tot


def _repair(im, rects, stats, key):
    px = im.load()
    for (fx, fy, _, _), s in zip(rects, stats):
        if key not in LOOSE_OK:
            for x, y in s["speck_cells"]:
                px[fx + x, fy + y] = (0, 0, 0, 0)
    w, h = im.size
    for y in range(h):
        for x in range(w):
            p = px[x, y]
            if 0 < p[3] < 255:
                px[x, y] = p[:3] + (255,) if p[3] >= 128 else (0, 0, 0, 0)


def audit_flat(path, pal, fix):
    im = Image.open(path).convert("RGBA")
    s = frame_stats(im, pal)
    issues = []
    if s["soft"]:
        issues.append(("soft", 0, "%d half-transparent px" % s["soft"]))
    if s["specks"]:
        issues.append(("specks", 0, "%d loose px" % s["specks"]))
    if fix and issues:
        _repair(im, [(0, 0) + im.size], [s], "")
        im.save(path)
    return issues, s["off"] / (s["filled"] or 1)


def walk(fix=False):
    pal = _palette()
    report = []
    sp = os.path.join(ROOT, "assets", "sprites")
    for sid in sorted(os.listdir(sp)):
        if sid.startswith("_") or not os.path.isdir(os.path.join(sp, sid)):
            continue
        for f in sorted(os.listdir(os.path.join(sp, sid))):
            if f.endswith(".png"):
                iss, off = audit_sprite_strip(sid, f[:-4], os.path.join(sp, sid, f), pal, fix)
                report.append({"file": "assets/sprites/%s/%s" % (sid, f), "issues": iss, "off_palette": off})
    for group in ("props", "buildings", "icons"):
        d = os.path.join(ROOT, "assets", group)
        for f in sorted(os.listdir(d)):
            if f.endswith(".png"):
                iss, off = audit_flat(os.path.join(d, f), pal, fix)
                report.append({"file": "assets/%s/%s" % (group, f), "issues": iss, "off_palette": off})
    return report


def main(argv):
    fix = "--fix" in argv
    report = walk(fix)
    counts = {}
    for r in report:
        for k, i, msg in r["issues"]:
            counts[k] = counts.get(k, 0) + 1
            if k not in ("soft", "specks") or not fix:
                print("%-48s %-8s frame %-2d %s" % (r["file"], k, i, msg))
    print("\n%d files, issues by kind: %s%s" % (len(report), counts or "none", " (soft/specks repaired)" if fix else ""))
    if "--json" in argv:
        json.dump(report, open(argv[argv.index("--json") + 1], "w"), indent=1)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
