#!/usr/bin/env python3
"""Icons for issue #112 (consumables, materials, tier 1-6 weapons, armour, trinkets, satchel upgrades, statuses,
Forge and Market), made the way Phase 6 made the first 80 (docs/ART_STYLE.md, "Icons"): PixelLab Pro
generate-image-v2 at 32x32 anchored to an existing icon, one call per 8 concepts ("A..H, one per image"),
64 options back, picked by eye, then palette-snapped into assets/icons/<id>.png.

    python3 tools/make_item_icons.py gen 0            # batch 0 -> /tmp/claude-0/icons/b0_<k>.png + b0_sheet.png
    python3 tools/make_item_icons.py gen all          # every batch not generated yet
    python3 tools/make_item_icons.py pick 0 3 17 ...  # option index per concept, in order -> assets/icons

Spend goes to tools/art_spend_items.jsonl."""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import pixellab  # noqa: E402

pixellab.LEDGER = os.path.join(HERE, "art_spend_items.jsonl")
OUT = os.environ.get("ICON_OUT", "/tmp/claude-0/icons")
ROOT = os.path.join(HERE, "..")
STYLE = ("Pixel art inventory icon for a dark fantasy RPG, 32x32, one object centred on a transparent background, "
         "chunky dark outline, soft top-left light, muted earthy palette like the reference icon, no text, no frame. "
         "Eight different icons, one per image, in this order: ")

CONCEPTS = [
    [("marrow_broth", "a steaming clay bowl of bone broth with a marrow bone in it"),
     ("wormwood", "a bundle of grey-green wormwood herb tied with string"),
     ("fresh_ink", "a small glass bottle of glowing black ink with a cork, a drop running down"),
     ("clean_sheet", "a crisp folded sheet of white paper with a wax seal"),
     ("iron_tea", "a dented iron tea cup with dark tea and steam"),
     ("gutter_gin", "a squat green glass gin bottle with a torn label"),
     ("courier_snuff", "a small round brass snuff tin, lid open, brown snuff inside"),
     ("oil_flask", "a glass flask of lamp oil with a burning rag stuffed in the neck")],
    [("flash_powder", "a little paper twist of white flash powder throwing sparks"),
     ("ward_candle", "a thick tallow candle with a bright warm flame and wax drips, ward runes on it"),
     ("oilcloth_satchel", "a waxed brown oilcloth satchel with a buckle strap"),
     ("brass_bandolier", "a leather bandolier with little brass vial holders"),
     ("velvet_harness", "a deep red velvet shoulder harness with pouches and gold clasps"),
     ("forge", "a blacksmith's anvil with a hammer resting on it and orange sparks"),
     ("market", "a market stall awning, red and cream stripes, with a crate of apples under it"),
     ("status_burn", "a bold orange flame symbol")],
    [("status_erase", "a torn scrap of paper with its words half erased to white, a pale blank hole in the middle"),
     ("status_might", "a clenched fist with a red upward arrow"),
     ("status_guard", "a round iron shield, blue rim"),
     ("status_ward", "a glowing pale gold candle flame inside a ring"),
     ("blank_pith", "a lump of chalky white pith, faintly glowing, like a blank hole in the world"),
     ("scrap_iron", "a small pile of rusty scrap iron: nails, a bent hinge, a broken blade"),
     ("moth_silk", "a skein of pale grey moth silk thread with a tiny moth wing"),
     ("oak_gall", "three brown round oak galls on a leafy twig")],
    [("tithe_wax", "a slab of red sealing wax with a stamped tithe seal"),
     ("lamp_brass", "a curved piece of polished brass lamp casing with a screw"),
     ("relic_silver", "a small silver reliquary fragment, ornate, with a tiny cross pattern"),
     ("bell_bronze", "a cracked shard of a bronze bell, green patina at the edges"),
     ("ink_pearl", "a single glossy black pearl with a faint purple shine"),
     ("velvet_cord", "a coil of rich red velvet cord with gold tassels"),
     ("saltglass", "a jagged shard of pale blue-white frozen sea glass, crystal"),
     ("wreck_oak", "a dark waterlogged plank of ship oak with an iron rivet and barnacles")],
    [("spire_leaf", "a thin sheet of gold leaf curling at the edges"),
     ("ledger_steel", "a bar of grey blued steel stamped with ledger lines and numbers"),
     ("vespers_nib", "a silver dip pen with an ornate abbey nib and a little cross"),
     ("inkpearl_quill", "a black quill pen with a black pearl set in the barrel"),
     ("the_last_word", "a magnificent gold-leaf pen with a pale blue icy glass nib"),
    ],
    [
     ("abbots_headsman", "an executioner's broad axe with an abbey cross engraved on the blade"),
     ("velvet_guillotine", "a heavy axe with a slanted guillotine blade and red velvet wrapped grip"),
     ("final_notice", "a huge cleaver of blued steel shelving, engraved numbers on the blade"),
     ("censer_ladle", "a silver church censer ladle on a chain trailing smoke")],
    [("banquet_spoon", "an ornate silver banquet serving spoon with a pearl handle"),
     ("ladle_of_last_rites", "a golden ladle with a glowing bowl and holy symbols"),
     ("belltower_halberd", "a halberd with a small bronze bell hanging from the axe head and a bell rope"),
     ("causeway_glaive", "a long elegant glaive with a curved blade and a pearl inlay"),
     ("spire_breaker", "a massive war pick with a long spike made of blued ledger steel and gold")],
    [("brass_knuckles", "a set of brass knuckles"),
     ("door_knocker", "a heavy iron door knocker ring worn as a knuckle duster"),
     ("bouncers_gauntlets", "a pair of thick studded leather gauntlets"),
     ("bellclapper_fists", "two bronze bell clappers riveted into knuckle dusters"),
     ("last_warning", "an iron gauntlet wrapped in red velvet"),
     ("closing_time", "a gold plated gauntlet, fist clenched"),
     ("hook_knives", "two short hooked knives crossed"),
     ("moonless_pair", "two black daggers crossed, a crescent moon on the pommel")],
    [("tide_and_tithe", "two wavy kris daggers crossed, one with a coin pommel"),
     ("vigil_knives", "two silver candle snuffer knives crossed"),
     ("pearl_divers_pair", "two short black blades crossed with a pearl between them"),
     ("nothing_declared", "two translucent pale blue glass knives crossed"),
     ("iron_ledger", "an iron-bound account ledger book with a clasp"),
     ("assessors_seal", "a heavy brass seal stamp with a red wax impression"),
     ("book_of_arrears", "a thick red leather book with a chain and padlock"),
     ("penitents_tally", "a black iron-bound book with a broken chain dangling")],
    [("masquerade_register", "a purple velvet book with a gold masquerade mask on the cover"),
     ("index_of_the_ledger", "a huge gilded index book with many coloured tab markers"),
     ("stage_rapier", "a simple rapier with a cup guard, theatrical"),
     ("courtiers_smallsword", "an elegant thin smallsword with a gold shell guard"),
     ("crimson_encore", "a rapier with a crimson ribbon tied at the guard and a red blade sheen"),
     ("matins_foil", "a slender silver fencing foil with a chased silver guard"),
     ("masked_ball", "a rapier with a black pearl in the swept guard and a tiny mask charm"),
     ("standing_ovation", "a regal rapier of blued steel with gold leaf and a pale glass edge")],
    [("mothsilk_shawl", "a pale grey silk shawl with faint written words in the weave"),
     ("tollkeepers_coat", "a long brown toll keeper's coat with brass buttons and a coin pouch"),
     ("chapel_hauberk", "a shirt of silver-washed chain mail with an abbey cross"),
     ("penitents_cassock", "a black wool cassock with small bells along the hem"),
     ("masquers_brigandine", "a red velvet brigandine vest with rows of brass rivets"),
     ("pearlscale_coat", "a coat of black pearl-shell scales with a purple shimmer"),
     ("ledgerplate", "a gilded steel breastplate engraved with ledger lines"),
     ("saltglass_mantle", "a hooded cloak of pale blue crystal glass shards over dark wood")],
    [("wormwood_sachet", "a small cloth pouch tied with string, a sprig of wormwood poking out"),
     ("smiths_patch", "a square scorched leather patch with stitched edges"),
     ("leech_locket", "an oval silver locket, open, a dark red leech inside"),
     ("gamblers_die", "a single bone six-sided die showing six"),
     ("inkblot_brooch", "a brooch of black glass shaped like an ink blot in a silver setting"),
     ("gilt_tooth", "a gold tooth hanging on a leather cord"),
     ("thornwire_bracelet", "a bracelet of twisted barbed wire"),
     ("widows_ribbon", "a black silk ribbon tied in a bow")],
    [("steady_bell", "a tiny bronze hand bell"),
     ("bellringers_clapper", "a bronze bell clapper on a leather thong"),
     ("clockwork_heart", "a brass clockwork heart with gears and a pearl in the middle"),
     ("saltglass_eye", "a pale blue glass eyeball, crystal"),
     ("second_signature", "a gilt-edged card with two signatures in black ink"),
    ],
]
CONCEPTS_FLAT = [c for group in CONCEPTS for c in group]  # grouped by kind above, generated 8 at a time
BATCHES = [CONCEPTS_FLAT[i:i + 8] for i in range(0, len(CONCEPTS_FLAT), 8)]
STYLE_REF = os.path.join(ROOT, "assets/icons/tonic.png")


def gen(b):
    pl = pixellab.PL(phase="112")
    os.makedirs(OUT, exist_ok=True)
    concepts = BATCHES[b]
    desc = STYLE + " ".join("%s) %s." % ("ABCDEFGH"[i], c[1]) for i, c in enumerate(concepts))
    before = pl.balance()
    job = pixellab.generate_styled(pl, desc, (32, 32), STYLE_REF, seed=40 + b)
    done = pl.wait_jobs([job], what="icons batch %d" % b)
    after = pl.balance()
    files = pixellab.save_styled(done[job], os.path.join(OUT, "b%d" % b))
    sheet(b, files)
    print("batch %d: %d options, cost $%.4f (balance %.4f -> %.4f)" % (b, len(files), before - after, before, after))


def sheet(b, files):
    """8x8 contact sheet at 4x with each option's index, for picking by eye."""
    from PIL import Image, ImageDraw
    cols = 8
    rows = (len(files) + cols - 1) // cols
    W = Image.new("RGBA", (cols * 140, rows * 150), (40, 38, 50, 255))
    d = ImageDraw.Draw(W)
    for k, f in enumerate(files):
        im = Image.open(f).convert("RGBA").resize((128, 128), Image.NEAREST)
        x, y = (k % cols) * 140 + 6, (k // cols) * 150 + 16
        W.alpha_composite(im, (x, y))
        d.text((x, y - 13), str(k), fill=(255, 230, 120, 255))
    W.save(os.path.join(OUT, "b%d_sheet.png" % b))


def pick(b, idx):
    from PIL import Image
    import palette_lock
    for (icon_id, _), k in zip(BATCHES[b], idx):
        im = Image.open(os.path.join(OUT, "b%d_%d.png" % (b, k))).convert("RGBA")
        im = palette_lock.drop_specks(palette_lock.snap(im), 4)
        im.save(os.path.join(ROOT, "assets/icons/%s.png" % icon_id))
        print(icon_id, "<-", k)


if __name__ == "__main__":
    if sys.argv[1] == "gen":
        todo = range(len(BATCHES)) if sys.argv[2] == "all" else [int(sys.argv[2])]
        for b in todo:
            if sys.argv[2] == "all" and os.path.exists(os.path.join(OUT, "b%d_sheet.png" % b)):
                continue
            gen(b)
    elif sys.argv[1] == "pick":
        pick(int(sys.argv[2]), [int(a) for a in sys.argv[3:]])
    elif sys.argv[1] == "list":
        print(json.dumps([c[0] for bt in BATCHES for c in bt]))
