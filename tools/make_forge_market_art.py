#!/usr/bin/env python3
"""Forge and Market building sprites (issue #112), made the way the other plot buildings were (docs/ART_STYLE.md):
level 3 with PixelLab Pro generate-image-v2 anchored to the town's own buildings, then levels 1 and 2 edited down
from it with edit-images-v2 so shape, angle and size stay the same.

    python3 tools/make_forge_market_art.py gen forge      # 4 level-3 options -> /tmp/claude-0/art/forge3_<k>.png
    python3 tools/make_forge_market_art.py gen market
    python3 tools/make_forge_market_art.py levels forge_pick.png market_pick.png   # level 1 and 2 of both

Spend goes to tools/art_spend_items.jsonl (a ledger of its own so parallel branches never edit one file)."""
import base64
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import pixellab  # noqa: E402

pixellab.LEDGER = os.path.join(HERE, "art_spend_items.jsonl")
OUT = os.environ.get("ART_OUT", "/tmp/claude-0/art")
ROOT = os.path.join(HERE, "..")
CAMERA = ("Top-down 3/4 view pixel art building sprite for a top-down RPG town, seen from above at the same angle as "
          "the reference buildings: the roof is seen from above and recedes away from the viewer, large roof surface "
          "visible, the front facade faces the viewer, vertical walls stay vertical, no isometric corner view. ")
SUBJECTS = {
    "forge": ("A village blacksmith's forge: a two-storey timber-framed house with bone-white plaster over a grey "
              "stone ground floor and a slate blue roof, a tall red brick chimney breathing a little smoke, and an "
              "open-fronted smithy lean-to on one side under the same slate roof: a glowing orange hearth, an anvil, "
              "bellows, tongs and hammers on the wall, a water barrel. Sturdy, sooty, lived in. Same materials and "
              "palette as the reference buildings."),
    "market": ("A covered market hall for a small town: a long timber-framed hall on stout wooden posts with a dark "
               "red clay tile roof, open sides with market stalls under it, red and cream striped cloth awnings, crates "
               "of apples and cabbages, sacks, barrels, a hanging brass weighing scale and a painted wooden sign over "
               "the front. Busy and cheerful. Same materials and palette as the reference buildings."),
}
LEVEL_EDITS = {
    1: ("The same building at its humble beginning: a small, run-down, patched first version, rough planks and bare "
        "timber, patched roof, fewer details and goods, a little smaller and plainer. Keep the exact same angle, "
        "camera, outline style, footprint position and canvas size."),
    2: ("The same building a little less grand: a plainer, slightly worn middle version with fewer goods and "
        "decorations and some repairs visible. Keep the exact same shape, angle, camera, outline style, footprint and "
        "canvas size."),
}
SIZE = 96


def _b64(path):
    return base64.b64encode(open(path, "rb").read()).decode()


def gen(look):
    pl = pixellab.PL(phase="112")
    os.makedirs(OUT, exist_ok=True)
    refs = [os.path.join(ROOT, "assets/buildings/inkworks_3.png"), os.path.join(ROOT, "assets/buildings/barracks_3.png")]
    before = pl.balance()
    job = pixellab.generate_styled(pl, CAMERA + SUBJECTS[look], (SIZE, SIZE),
                                   os.path.join(ROOT, "assets/buildings/guildhall_3.png"), refs=refs, seed=11)
    done = pl.wait_jobs([job], what="%s level 3" % look)
    after = pl.balance()
    files = pixellab.save_styled(done[job], os.path.join(OUT, "%s3" % look))
    print("cost $%.4f (balance %.4f -> %.4f)" % (before - after, before, after))
    print("\n".join(files))


def levels(picks):
    """picks: {look: level-3 png}. One edit call per level, every look in it, so they age the same way."""
    pl = pixellab.PL(phase="112")
    os.makedirs(OUT, exist_ok=True)
    looks = list(picks)
    for lv in (1, 2):
        before = pl.balance()
        body = {"method": "edit_with_text", "description": LEVEL_EDITS[lv], "image_size": {"width": SIZE, "height": SIZE},
                "no_background": True, "seed": 7,
                "edit_images": [{"image": {"base64": _b64(picks[l])}, "width": SIZE, "height": SIZE} for l in looks]}
        job = pl._req("POST", "/edit-images-v2", body)["background_job_id"]
        done = pl.wait_jobs([job], what="levels %d (%s)" % (lv, ", ".join(looks)))
        after = pl.balance()
        ims = (done[job].get("last_response") or {}).get("images") or []
        for look, im in zip(looks, ims):
            data = im["base64"] if isinstance(im, dict) else im
            if data.startswith("data:"):
                data = data.split(",", 1)[1]
            path = os.path.join(OUT, "%s%d.png" % (look, lv))
            open(path, "wb").write(base64.b64decode(data))
            print(path)
        print("level %d cost $%.4f" % (lv, before - after))


if __name__ == "__main__":
    if sys.argv[1] == "gen":
        gen(sys.argv[2])
    elif sys.argv[1] == "levels":
        levels({"forge": sys.argv[2], "market": sys.argv[3]})
