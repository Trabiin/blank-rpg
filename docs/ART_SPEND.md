# Art Pass Spend: Planned vs Actual

Planned figures come from docs/ART_ROADMAP.md section 5 (whole MVP pass ~$35 to $70). Actual figures are the
sum of every paid job's own usage, logged per call in `tools/art_spend.jsonl` (`python3 tools/pixellab.py spend`).
Claude stops and asks before going on if credit is about to run out or a phase runs well over its estimate.

| Phase | Planned | Actual | Notes |
|---|---|---|---|
| 0. Style lock + pipeline | ~$1 | $0.00 | Reused the approved detail-trial Ash; the rest is code |
| 1. The party | ~$6 to $12 | **$1.34** (PixelLab) | 9 base candidates ($0.26, ~$0.03 each), 4 heroes × 25 to 30 animation directions ($1.08) |
| 2. Prologue (meadow, Nibbler, Spitter, FX) | ~$3 to $5 | **$0.59** (PixelLab) | 4 meadow tilesets ($0.03), 18 prop candidates ($0.12), 3 Spitter candidates ($0.09), Nibbler + Spitter animations ($0.35); Blank, light and motes are code |
| 3. Hollowmark | ~$6 to $12 | **$1.66** (PixelLab) | 108 building/prop candidates ($0.75, incl. a camera-view test and redoing buildings front-facing), 3 town tilesets ($0.02), 14 character candidates ($0.42), idle/walk for Quill, Tobble, Abeyance and 4 townsfolk ($0.47) |
| 4. Act 1 world | ~$6 to $10 | | |
| 5. The Auditor and recruits | ~$5 to $10 | | |
| 6. UI and icons | ~$2 to $4 | | |
| 7. Portraits and painted art (OpenAI) | ~$6 to $12 | | |
| 8. Polish sweep | ~$2 to $4 | | |
| **Total so far** | ~$16 to $30 for phases 0 to 3 | **$3.58** | PixelLab credit left: $6.10 (2026-11-19) |

## Why Phase 1 came in far under

The roadmap budgeted ~3 generations per animated direction (the website's free-tier figure). Through the API,
PixelLab's v3 animation on a 32 px character costs **one generation per direction (~$0.008)** however many frames
(4 to 16), and only 5 of 8 directions are generated (the rest are mirrored in game). A full hero action set is
about **$0.25**. If later phases price the same way, the pixel-art side of the MVP will land well below the
$25 to $60 estimate; bosses (96 to 128 px) and Pro-mode calls cost more per call, so the big check is Phase 5.
