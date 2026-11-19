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

`tools/master_palette.hex`: Ink black, the reserved Blank paper white, bone, one accent per main character, and 48
shades sampled from the approved sprites and meadow tiles. `tools/palette_lock.py`:
- `clean()` on every sprite: hard alpha, Ink black outline, and near-white pixels pushed to bone, so paper white
  stays the Blank's alone (pass `--blank` for Blank creatures).
- `snap()` additionally maps to the master palette; used for tiles and props from Phase 2 on.

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
