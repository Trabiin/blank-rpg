# Art Pass Spend: Planned vs Actual

Planned figures come from docs/ART_ROADMAP.md section 5 (whole MVP pass ~$35 to $70). Actual figures are the
sum of every paid job's own usage, logged per call in `tools/art_spend.jsonl` (`python3 tools/pixellab.py spend`).
Claude stops and asks before going on if credit is about to run out or a phase runs well over its estimate.

| Phase | Planned | Actual | Notes |
|---|---|---|---|
| 0. Style lock + pipeline | ~$1 | $0.00 | Reused the approved detail-trial Ash; the rest is code |
| 1. The party | ~$6 to $12 | **$1.34** (PixelLab) | 9 base candidates ($0.26, ~$0.03 each), 4 heroes × 25 to 30 animation directions ($1.08) |
| 2. Prologue (meadow, Nibbler, Spitter, FX) | ~$3 to $5 | **$0.59** (PixelLab) | 4 meadow tilesets ($0.03), 18 prop candidates ($0.12), 3 Spitter candidates ($0.09), Nibbler + Spitter animations ($0.35); Blank, light and motes are code |
| 3. Hollowmark, first try | ~$6 to $12 | **$1.66** (PixelLab) | 108 building/prop candidates ($0.75), 3 town tilesets ($0.02), 14 character candidates ($0.42), idle/walk for Quill, Tobble, Abeyance and 4 townsfolk ($0.47). Characters kept; buildings, props and tiles replaced by the style lock |
| 3b. Style lock + env redo | (not planned) | **$4.60** (PixelLab) | Target plaza and workflow tests ($0.43), 41 palette-locked Pro calls for 9 buildings, 10 level looks and 24 props, several options each ($3.99, about $0.10 per call), 6 tilesets ($0.04). Redid the meadow and town environment art against docs/ART_STYLE.md |
| 3c. Town in true 3/4 (issue #94) | ~$2 to $2.50 | **$1.56** (PixelLab) | Angle test ($0.08), town hall/tavern/stores ($0.24), 5 plot buildings at level 3 ($0.40), levels 1 and 2 by image edit ($0.32), 8 houses ($0.16), fences/trees/gardens ($0.25). Wasted: $0.11 on two level methods that lost the building's shape (reference image, init image) |
| 4. Act 1 world | ~$6 to $10 | **$1.74** (PixelLab) | Forest/marsh/hills tilesets ($0.02; marsh and hills came back flat, replaced by free procedural mud and gravel from tools/make_ground.py), 24 biome props, 4 options per call ($0.66), 7 enemy/Verity bases ($0.22, Verity re-rolled once), 107 animation directions for moth, Enforcer, reedling, scarecrow, sellsword and Verity ($0.85, ~$0.008 each at 32 and 48 px). Biome maps are code (tools/make_biomes.py) |
| 5. The Auditor and recruits | ~$5 to $10 | **$1.49** (PixelLab) | Auditor at 96 px ($0.03 base, 35 animation directions $0.28: boss size costs the same per direction as 32 px), 8 light recruits ($0.23 bases, idle in 5 directions $0.32). Proportion fix ($0.66): PixelLab fills the canvas, so every figure came out ~30 px. The Auditor (now ~2x a hero), Mr. Biscuits, the Merrow Three, the folk child (smaller) and Ottoline (bigger) were resized with PixelLab's pixel-art /resize (~$0.009 per image), imported with all 8 directions given, and re-animated. Governor and clerk NPCs left for when their scenes exist |
| 6. UI and icons | ~$2 to $4 | | |
| 7. Portraits and painted art (OpenAI) | ~$6 to $12 | | |
| 8. Polish sweep | ~$2 to $4 | | |
| **Total so far** | ~$27 to $50 for phases 0 to 5 | **$12.97** | Topped up $10 on 2026-11-19; PixelLab credit left: $6.71 |

## Why Phase 1 came in far under

The roadmap budgeted ~3 generations per animated direction (the website's free-tier figure). Through the API,
PixelLab's v3 animation on a 32 px character costs **one generation per direction (~$0.008)** however many frames
(4 to 16), and only 5 of 8 directions are generated (the rest are mirrored in game). A full hero action set is
about **$0.25**. If later phases price the same way, the pixel-art side of the MVP will land well below the
$25 to $60 estimate; bosses (96 to 128 px) and Pro-mode calls cost more per call, so the big check is Phase 5.

## Cost of the style-locked workflow

Since the style lock (docs/ART_STYLE.md), buildings and props are made with PixelLab's Pro image endpoint at about
$0.08 to $0.12 per call instead of $0.006 per map object, because it is the call that takes the target as a style
reference and locks the palette. One call returns several options (9 at 80 px, 25 at 48 px, 64 at 32 px), so
the extra cost buys picks that fit together. Ground tilesets and character animation prices are unchanged.
Expect Phase 4 (four biomes) at about $5 to $8 this way.

## Cost guard (from 2026-11-19)

Every batch starts with one call; its real cost is read from the balance and compared with the estimate. Batches
stop on their own if a call costs more than 1.5x the estimate. Run batches one after another: two running at
once both see each other's charges and trip the guard.

| Call | Real cost | Returns |
|---|---|---|
| Pro style-locked image (generate-image-v2) | $0.081 | 4 options at 96 px, 16 at 64 px, 25 at 48 px |
| Image edit (edit-images-v2), up to 4 images at 81-128 px | $0.081 | the same buildings, edited (levels 1 and 2) |
| Map object (map-objects) | $0.008 | 1 image; init-image edits lose the shape, not used for levels |
