# Art Pass Spend: Planned vs Actual

Planned figures come from docs/ART_ROADMAP.md section 5 (whole MVP pass ~$35 to $70). Actual figures are the
sum of every paid job's own usage, logged per call in `tools/art_spend.jsonl` (`python3 tools/pixellab.py spend`).
Claude stops and asks before going on if credit is about to run out or a phase runs well over its estimate.

| Phase | Planned | Actual | Notes |
|---|---|---|---|
| 0. Style lock + pipeline | ~$1 | $0.00 | Reused the approved detail-trial Ash; the rest is code |
| 1. The party | ~$6 to $12 | **$1.34** (PixelLab) | 9 base candidates ($0.26, ~$0.03 each), 4 heroes × 25 to 30 animation directions ($1.08) |
| 2. Prologue (meadow, Nibbler, Spitter, FX) | ~$3 to $5 | | |
| 3. Hollowmark | ~$6 to $12 | | |
| 4. Act 1 world | ~$6 to $10 | | |
| 5. The Auditor and recruits | ~$5 to $10 | | |
| 6. UI and icons | ~$2 to $4 | | |
| 7. Portraits and painted art (OpenAI) | ~$6 to $12 | | |
| 8. Polish sweep | ~$2 to $4 | | |
| **Total so far** | ~$7 to $13 for phases 0 and 1 | **$1.34** | PixelLab credit left: $8.35 (2026-11-19) |

## Why Phase 1 came in far under

The roadmap budgeted ~3 generations per animated direction (the website's free-tier figure). Through the API,
PixelLab's v3 animation on a 32 px character costs **one generation per direction (~$0.008)** however many frames
(4 to 16), and only 5 of 8 directions are generated (the rest are mirrored in game). A full hero action set is
about **$0.25**. If later phases price the same way, the pixel-art side of the MVP will land well below the
$25 to $60 estimate; bosses (96 to 128 px) and Pro-mode calls cost more per call, so the big check is Phase 5.
