# Last Ink

A short action RPG in the spirit of 90s Secret of Mana and Final Fantasy, with modern quality of life.
Reality is being eaten by a hungry Blank, and you are the one person it spat back out.

**Play in your browser:** https://trabiin.github.io/last-ink/ (rebuilt automatically on every push to `main`)

- Design document: [docs/DESIGN.md](docs/DESIGN.md)
- Asset credits: [CREDITS.md](CREDITS.md)

## Controls (prototype)

| Action | Keyboard | Gamepad | Touch |
|---|---|---|---|
| Move | WASD / arrows | Left stick / d-pad | Drag on the left half |
| Attack | J / Space / Z | A | ATTACK button |
| Swap hero | Tab / Q | Y | SWAP button |
| Pause menu | Esc / P | Start | Pause button (top right) |

Attacks use a power gauge: swinging before it refills still hits, but for less damage.

## Development

- Engine: Godot 4.3 (open `project.godot`).
- Art: CC0 packs in `assets/source/` (see [CREDITS.md](CREDITS.md)). After changing them, run
  `python3 tools/import_art.py` to rebuild the paper-doll layers in `assets/characters/`.
- Web export: `godot --headless --export-release "Web" build/web/index.html` (needs the 4.3 web export templates).
- Maps: each area is a plain text file in `maps/` (legend at the top of the file). Edit the
  characters to move paths, bushes, rocks, signs, spawns and the party start; paths get smooth
  edges automatically from `shaders/terrain_blend.gdshader`.
- CI: `.github/workflows/deploy-web.yml` builds every push and PR, and deploys `main` to GitHub Pages.
