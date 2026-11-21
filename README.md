# Last Ink

A short action RPG in the spirit of 90s Secret of Mana and Final Fantasy, with modern quality of life.
Reality is being eaten by a hungry Blank, and you are the one person it spat back out.

**Play in your browser:** https://trabiin.github.io/last-ink/ (rebuilt automatically on every push to `main`)

**Desktop (Windows, macOS, Linux):** every push to `main` builds all three; download them from the latest
[Desktop builds](https://github.com/Trabiin/last-ink/actions/workflows/desktop.yml) run (Artifacts, at the bottom),
or from [Releases](https://github.com/Trabiin/last-ink/releases) once a version is tagged. See [docs/DESKTOP.md](docs/DESKTOP.md).

- Design document: [docs/DESIGN.md](docs/DESIGN.md)
- Asset credits: [CREDITS.md](CREDITS.md)

## Controls (prototype)

| Action | Keyboard | Gamepad | Touch |
|---|---|---|---|
| Move | WASD / arrows | Left stick / d-pad | Drag on the left half |
| Attack | J / Space / Z | A | ATTACK button |
| Swap hero | Tab / Q | Y | SWAP button |
| Pause menu | Esc / P | Start | Pause button (top right) |
| Journal (quests, people, codex, history) | I | Pause menu > Journal; LB / RB switch tabs | Journal button on the Command Table, or the menu |
| Fullscreen (desktop) | Alt+Enter / F11 | Options > Display | - |

Attacks use a power gauge: swinging before it refills still hits, but for less damage.

Saving: pick Save game in the pause menu (three slots). The game also autosaves every minute when no enemy is close and nobody is down, and when you quit to the title or switch away from the tab. In the browser, saves live in the browser's storage, so they stay on that browser and device; the desktop builds keep them in a Last Ink folder (Options > Save folder opens it). Saves from older versions of the game load and are upgraded automatically; a save that cannot be read is set aside (never deleted) and the title screen says so.

## Development

- Engine: Godot 4.3 (open `project.godot`).
- Art: CC0 packs in `assets/source/` (see [CREDITS.md](CREDITS.md)). After changing them, run
  `python3 tools/import_art.py` to rebuild the paper-doll layers in `assets/characters/`.
- Web export: `godot --headless --export-release "Web" build/web/index.html` (needs the 4.3 web export templates).
- Desktop exports (Windows, macOS, Linux), releases and their smoke tests: [docs/DESKTOP.md](docs/DESKTOP.md).
- Maps: each area is a plain text file in `maps/` (legend at the top of the file). Edit the
  characters to move paths, bushes, rocks, signs, spawns and the party start; paths get smooth
  edges automatically from `shaders/terrain_blend.gdshader`.
- Hollowmark (`maps/hollowmark.txt`, `scripts/hub.gd`) is the walkable hub. Its `@prop` lines place
  buildings and town props, and its `@mark` lines mark recruit posts and the Command Table. Where each
  recruit stands, their look and their town lines come from `data/recruits.json`. Town props are art pass
  sprites in `assets/props/`, each one line in `scripts/prop.gd`.
- Buildings: `data/buildings.json` holds each building's levels (cost, build days, staff slots) and the
  Wardlamp; what each building does is computed in `Empire.building_effect()` (`scripts/empire.gd`), so the
  Buildings screen (`scripts/buildings_view.gd`, key B) always shows the real numbers. Plots in town are
  `@mark` lines named `site_<building id>` in `maps/hollowmark.txt`; `scripts/building_site.gd` draws the
  plot, scaffolding and finished building: art in `assets/buildings/<look>_<level>.png` (a test fails if a level
  has none) and a collision box in its `LOOKS` table.
- Expeditions: jobs live in `data/expeditions.json` (stats wanted, target strength, danger, rations, rewards,
  report lines, trait tags) along with squad pairings; odds and outcomes are in the expeditions section of
  `scripts/empire.gd`, and the screen is `scripts/expedition_view.gd` (key E). Report quips per recruit are the
  `quips` lists in `data/recruits.json`.
- Territory: provinces live in `data/provinces.json` (name, seed point, owner, Fray, output, sites,
  missions). Province shapes and borders are generated from the seed points by `scripts/territory.gd`,
  so moving a seed or changing its weight reshapes the map and its adjacency together.
- CI: `.github/workflows/deploy-web.yml` tests and builds every push and PR, and deploys `main` to GitHub Pages
  only when the tests pass. `.github/workflows/desktop.yml` builds and smoke-tests the desktop versions.
- Tests: `tools/run_tests.sh` (data checks, save migrations, scene smoke tests). See [docs/TESTING.md](docs/TESTING.md).
- Saves: old saves must keep loading. Any change to saved state follows [docs/SAVES.md](docs/SAVES.md).
