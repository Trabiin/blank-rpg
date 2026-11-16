# Last Ink

A short action RPG in the spirit of 90s Secret of Mana and Final Fantasy, with modern quality of life.
Reality is being eaten by a hungry Blank, and you are the one person it spat back out.

**Play in your browser:** https://trabiin.github.io/blank-rpg/ (rebuilt automatically on every push to `main`)

- Design document: [docs/DESIGN.md](docs/DESIGN.md)
- Asset credits: [CREDITS.md](CREDITS.md)

## Controls (prototype)

| Action | Keyboard | Gamepad | Touch |
|---|---|---|---|
| Move | WASD / arrows | Left stick / d-pad | Drag on the left half |
| Attack | J / Space / Z | A | ATTACK button |
| Swap hero | Tab / Q | Y | SWAP button |
| Restart | R | Start | Tap after a game over |

Attacks use a power gauge: swinging before it refills still hits, but for less damage.

## Development

- Engine: Godot 4.3 (open `project.godot`).
- Web export: `godot --headless --export-release "Web" build/web/index.html` (needs the 4.3 web export templates).
- CI: `.github/workflows/deploy-web.yml` builds every push and PR, and deploys `main` to GitHub Pages.
