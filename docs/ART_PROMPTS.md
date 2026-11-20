# Last Ink: Art Prompts and Settings

The fixed prompt blocks and generator settings for the art pass (docs/ART_ROADMAP.md 1.6). Every new asset starts
from these so sprites made on different days still match. Claude runs the generators through the APIs with
`tools/pixellab.py` (PixelLab) and the OpenAI image API; spend is logged per call (see "Spend tracking" below).

## PixelLab settings (characters and enemies)

| Setting | Value | Notes |
|---|---|---|
| Endpoint | `POST /v2/create-character-v3` (from text) | ~$0.03 per 8-direction character at 32 px |
| Canvas | **32x32** for every human and small enemy; 48x48 for large enemies; bosses up to 128 | Option A (ART_ROADMAP 1.1b). Never generate big and shrink |
| View | `high top-down` | |
| Outline | `single color black outline` | `tools/palette_lock.py` then sets every outline pixel to Ink black `#12141f` |
| Detail | `medium detail` | |
| Background | transparent (`no_background`) | |
| Candidates | 3 per character, best one kept | Picks are shown on a contact sheet in the phase PR |

**Character prompt shape** (description field, no style words needed: the model and settings carry the style):

```
[build and age] [hair] [face detail], [main garment] with [accent colour] [accent item], [secondary garment],
[signature weapon] held in one hand, [one silhouette detail]
```

Rules that worked in Phase 1:
- Name the accent colour on one clear item (Bran's rust-orange sash, Daro's brass-yellow scarf, Gristle's glowing
  poison-green bottles). It survives the 32 px canvas and keeps the cast readable at a glance.
- One weapon, held in the hand, named simply ("heavy single-bladed cleaver axe", "long steel pike"). No gear
  swaps on sprites (decided 2026-11-19).
- Small creatures and children: keep the 32 px canvas and say "small creature" / "small and short".

## PixelLab settings (animations)

`POST /v2/characters/animations` in **v3 mode** with an action text, `keep_first_frame: false`.
At 32 px every direction costs one generation (about $0.008). Only the five right-hand directions are generated
(south, south-east, east, north-east, north); the game mirrors the other three.

| Animation | Directions | Frames | Action text (weapon filled in per hero) |
|---|---|---|---|
| idle | 5 | 4 | `standing idle, breathing gently, holding [weapon] ready` |
| walk | 5 | 6 | `walking` (Ash's walk is the template walk from the detail trial, 8 directions) |
| attack | 5 | 6 | per weapon: `slashing quickly with a shortsword in a wide horizontal arc`, `swinging a heavy axe down in a big overhead chop`, `swinging a wooden staff in a short sweeping strike`, `thrusting a long pike forward in a powerful stab` |
| cast | 5 | 6 | `raising one hand forward and casting a spell` (all abilities share it; colour and FX are code) |
| tech | 5 | 8 | `crouching low to gather power, then lunging forward in a mighty strike with [weapon]` (first half = wind-up loop, second half = release) |
| hurt | 3 (S, E, N) | 4 | `recoiling backward from being hit` |
| ko | 1 (S) | 6 | `collapsing and falling to the ground, lying knocked out` |
| victory | 1 (S) | 6 | `raising [weapon] triumphantly in victory` |

## Character descriptions used (Phase 1)

| Id | PixelLab character | Description |
|---|---|---|
| ash | `Ash trial 32` (detail trial, approved) | young swordsman with messy black hair and pale skin, tattered charcoal-grey hooded cloak with frayed white edges and deep ink-blue lining, dark leather vest, steel shortsword at his hip, ink stains on his hands |
| bran | `bran base 1` | broad-shouldered bald mercenary man in his 40s, scarred jaw, grey stubble, dented grey plate pauldron on one shoulder over a stained brown padded gambeson, rust-orange sash at the waist, heavy single-bladed cleaver axe held in one hand, sturdy boots |
| gristle | `gristle base 1` | hunched sturdy old woman herbalist, wild grey hair tied back, hooked nose, patched brown shawl over a dark apron hung with small glass bottles of glowing poison-green liquid, gnarled wooden staff wrapped in dried herbs, short and stooped |
| ninefingers (Daro) | `daro base 1` | lean wiry deserter soldier man in his 30s, short cropped dark hair, sharp face, worn grey Concord army coat with brass buttons and a brass-yellow scarf, leather bracers, holding a long steel pike upright |

## Palette

`tools/style_palette.hex`: the fixed 38 colours of docs/ART_STYLE.md (the Blank's paper white is not in it). `tools/palette_lock.py`:
- `clean()` on every sprite: hard alpha, Ink black outline, and near-white pixels pushed to bone, so paper white
  stays the Blank's alone (pass `--blank` for Blank creatures).
- `snap()` additionally maps to the style palette; every art pass asset goes through it (tiles with `outline=False`).

## Pipeline

1. `tools/pixellab.py`: API client (create, animate, wait, ZIP export) that logs every paid job to `tools/art_spend.jsonl`.
2. `tools/import_sprites.py RAW ID --anim name:fps:loop|once`: palette-cleans frames, packs one strip per
   animation and direction into `assets/sprites/<id>/<anim>_<dir>.png`, and writes the `data/sprites.json` entry.
3. `scripts/sprite_set.gd` (class `SpriteSet`) loads those strips; `Hero` uses it when its id has an entry and falls
   back to the paper doll otherwise.
4. `tools/contact_sheet.py` builds the review sheets posted with each phase PR.

## Spend tracking

Every paid PixelLab job is one line in `tools/art_spend.jsonl` (phase, what, USD from the job's own usage).
`python3 tools/pixellab.py spend` sums it per phase; `docs/ART_SPEND.md` holds planned vs actual per phase.

## OpenAI image settings (Phase 7)

Portraits keep the style block in `docs/PORTRAITS.md`; expressions use the image edit endpoint on the locked neutral
portrait. Filled in when Phase 7 starts.

## Phase 2 additions (meadow)

- **Tilesets:** `POST /v2/create-tileset`, 16 px, high top-down, basic shading (~$0.008 each). The kept set came back
  with lower/upper swapped (as warned in ART_ROADMAP 1.1b), so it is stored by content: `assets/tiles/meadow/<NW><NE><SW><SE>.png`
  with G = grass and D = dirt. A map opts in with `@ground meadow`; `Area` lays it on a dual grid so paths keep the
  shape drawn in the map text. Grass tufts and wildflowers on top are code.
  Kept: lower "dark muted meadow grass, short tufts, dusky green", upper "packed earthy brown dirt path, a few pebbles".
- **Props:** `POST /v2/map-objects` (~$0.006 each, PNG comes back in the job's `last_response.image`), 2 candidates per
  kind, trimmed and cleaned into `assets/props/<kind>.png`; `Prop` uses them over the CC0 sheet wherever the kind appears.
- **Enemies:** Blank creatures import with `--blank` (they keep paper white). Death "dissolve" prompts did not dissolve,
  so deaths are a code crumple + the existing paper burst.
- Art pass tiles and props use `Art.art_world_material()`: the same Blank fade, with a much lighter mood grade.

## Phase 3 additions (Hollowmark) and the style lock

**Read docs/ART_STYLE.md first: it replaces the per-asset settings above for buildings, props and tiles.** The first
Phase 3 batch (map objects, mixed views, palette only cleaned) did not fit together and was replaced.

- **Buildings and props:** `POST /v2/generate-image-v2` with `style_image` = `docs/style/ref_building.png` (buildings)
  or `docs/style/ref_props.png` (props), `style_options.color_palette = false`, `target_palette` = the 38 colours of
  `tools/style_palette.hex`. Sizes: 80x80 for a plot building (9 options per call), 48 or 32 for props. Non-square
  sizes come back small on a square canvas, so ask for square.
- **Building levels:** level 3 first; levels 1 and 2 pass the chosen level 3 as `reference_images` with "the first
  humble version of the ... in the reference image" / "a plainer, slightly smaller earlier version". Stored as
  `assets/buildings/<look>_<level>.png`.
- **Tiles:** `create-tileset` with `lower_reference_image` = `docs/style/ref_grass.png`, cobbles with
  `upper_reference_image` = `docs/style/ref_cobble.png`, `color_image` = the palette strip (`target_palette` needs
  the pricier pro tileset mode). Snapped with `snap(outline=False)`; stored by content (G grass, D dirt or cobbles).
  One of the three meadow sets came back broken (dirt in the wrong corners): check every set on a sheet.
- **Characters:** `create-character-v3` with Ash's settings, then `snap()` on every frame.
- **Map-object inpainting** into a crop of the target was tried for cheap props: unreliable, not used.
- Hub people: Quill, Tobble, Abeyance idle only; townsfolk (`folk_man`, `folk_woman`, `folk_elder`, `folk_child`)
  idle + walk, wandering the plaza (`scripts/townsfolk.gd`).

## Phase 8 remakes (one body plan)

Odile, Verity, Abeyance, Dunmore, Ottoline, the folk man and woman and the Merrow Three were remade to the
heroes' body plan (docs/ART_STYLE.md "Proportions"). What worked:
- **No reference image.** create-character-v3 with Ash as `reference_image` just redraws Ash.
- End the description with `sturdy build with a large head like the other heroes` (for an ordinary build:
  `average build with a large head`). Without it PixelLab draws the slim, small-headed figures we replaced.
  `stocky ... big head and short legs` overshoots into chibi.
- Giants: generate on a 36 px canvas instead of resizing (Ottoline came out 34 px).
- Children: generate each child on 32 px as a normal figure, animate, then shrink every frame to 0.7 with
  `tools/compose_group.py`, which also stands a group (the Merrow Three) side by side in one sprite.
- Cost: a base about $0.027, idle in 5 directions about $0.045, walk in 5 directions about $0.05.

## Field heroes batch (2026-11-20: Ottoline, Jessamy, Odile, Velvette)

Combat sets for the four new field heroes, on the PixelLab characters their town sprites already came from
(Ottoline `ottoline p8` on a 36 px canvas, Jessamy `jessamy base`, Odile `odile p8 pilot 2`) plus a new Velvette
(`velvette field 2`). Same action list and frame counts as Phase 1; weapon wording per hero:

| Id | Attack | Tech (second half = release) | Victory |
|---|---|---|---|
| ottoline | `throwing a heavy straight punch forward with her bare fist` | `... lunging forward in a mighty shoulder charge` | `cracking her knuckles and flexing her arms triumphantly` |
| jessamy | `slashing quickly with two short hooked knives in a fast crossing strike` | `... dashing forward in a flurry of knife slashes` | `twirling a knife in her fingers and bowing with a smirk` |
| odile | `swinging a heavy iron-bound ledger book in a short smacking strike` | `... slamming a large brass stamp seal down in a mighty strike` | `snapping her ledger book shut and adjusting her glasses triumphantly` |
| velvette | `thrusting a thin rapier forward in a quick fencing lunge` | `crouching low into a fencing stance ... mighty rapier thrust` | `saluting with her rapier and taking an elegant bow` |

Velvette's base: `elegant duelist woman around 30 with a big head and a short wine-red bob haircut, black high-collared
coat with gold buttons and crimson lining, long black gloves, thin silver rapier in one hand, sturdy build with a large
head like the other heroes`. The first try with "average build" came out slim with a small head (rejected, $0.027).

Gotchas: the API allows about 8 animation jobs at once (429 "not enough concurrent job slots"), so submit one action at
a time and wait. Two calls with the same animation name land in separate folders in the ZIP (`attack-<id>/`); rename
them to `attack_<dir>_<i>.png` before `tools/import_sprites.py`. Spend for this batch is in
`tools/art_spend_field_heroes.jsonl` (a separate ledger so parallel branches don't both append to `art_spend.jsonl`;
`pixellab.py spend` reads every `art_spend*.jsonl`).
