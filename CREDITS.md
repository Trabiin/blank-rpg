# Credits and asset licenses

Every third-party asset in the project is listed here with its source and license.
Only CC0 (public domain) art and audio are used unless noted otherwise. Untouched
originals live in `assets/source/`; `tools/import_art.py` builds the runtime files from them.

| Asset | Author | Source | License | Used for |
|---|---|---|---|---|
| Zelda-like tilesets and sprites (`Overworld.png`) | ArMM1998 | https://opengameart.org/content/zelda-like-tilesets-and-sprites | CC0 | Meadow ground, path, bushes, rocks, stump, sign, bones |
| Puny Characters (`Character-Base`, `Archer`, `Warrior`, `Soldier`, `Mage`, `Slime`) | Shade | https://opengameart.org/content/puny-characters | CC0 | Paper-doll hero body and outfit layers with all animations; Nibbler enemy (recolored slime) |
| Character, enemy, tile and prop art (`assets/sprites/`, `assets/tiles/meadow/`, `assets/props/`, art pass) | Generated with PixelLab AI for this project (API, pay per call) | https://www.pixellab.ai | Owned by the project (PixelLab output) | Heroes in missions, town and the party picker |
| Character portraits (`assets/portraits/`) | Generated with ChatGPT image generation (OpenAI) for this project; prompts by the project | https://openai.com/policies/terms-of-use | Owned by the project (OpenAI's terms assign output to the user, commercial use allowed) | Dialogue and bond scenes; see `docs/PORTRAITS.md` |
| Music (`assets/audio/music/`): title = "Whispers From Beyond", town = "Where Time Stands Still", command = "Peaceful Days", meadow = "Grasslands", woods = "Prairie Nights", breakout = "Sneaking Around", blank = "Witch's Lair", boss = "Encounter With The Witches" | Juhani Junkala (SubspaceAudio) | JRPG Music Packs #1 to #5: https://opengameart.org/content/jrpg-pack-1-exploration (and packs 2-towns, 3-evil, 4-calm, 5-action) | CC0 | Background music; re-encoded to smaller Ogg Vorbis |
| Sound effects (`assets/audio/sfx/`) | Juhani Junkala (SubspaceAudio) | The Essential Retro Video Game Sound Effects Collection [512 sounds]: https://opengameart.org/content/512-sound-effects-8-bit-style | CC0 | Menus, swings, hits, deaths, level-ups, loot, alerts; converted to mono 22 kHz WAV |
| The Blank's hum | Made in code for this project (`scripts/audio.gd`) | | Owned by the project | Drone near the Blank's edge and Blots |

CC0 does not require credit, but we give it anyway. Thank you!

Engine: [Godot Engine](https://godotengine.org) (MIT).
