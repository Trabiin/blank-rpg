# Character portraits

Large visual-novel portraits shown in dialogue and bond scenes (issue #12).

## Where they live

| File | What |
|---|---|
| `assets/portraits/<id>.png` | Game portrait, 512x768, transparent background. `<id>` is the recruit id (`ash`, `bran`, `gristle`) or a speaker id from `data/dialogue.json` / `data/story.json` (`verity`, `auditor`, `clerk`, `governor`, `warden`, `captain`). |
| `assets/portraits/<id>_<expr>.png` | Optional expression: `happy`, `angry`, `sad`, `surprised`, `smug`. Code falls back to `<id>.png` when one is missing. |
| `tools/cut_portraits.py` | Turns raw generator output into game portraits: cuts out the flat grey background (and grey pockets between hair strands, axe handles and so on), feathers the edge, scales to 512x768. |

Raw 1024x1536 originals are kept in the project's shared files (`last-ink/portraits/`), not in the repo, to keep the web build small.

To add one: save the raw image as `<id>-v2.png` (or `<id>_<expr>-v2.png`) in a folder, run
`python3 tools/cut_portraits.py <folder>`, open the project in Godot once so it imports, commit `assets/portraits/`.

## How the game uses them

- Bond scenes (`scripts/scene_view.gd`): the character stands on the left, flipped to face Ash on the right. Whoever has the floor is lit; the other is dimmed and pushed back. A soft glow in the character's accent colour sits behind each. A line in `data/bonds.json` can carry a third entry, an expression: `["bran", "Read it again.", "smug"]`.
- Every speaker has a portrait: `tests/test_data.gd` fails the build when one is missing, so the code-drawn safety-net bust never ships. The one exception is a letter read aloud (`"stage": "letter"` on the speaker), which stands on stage as a sealed sheet of paper.
- The dialogue system (#11) loads the same files by the same naming.

## Tool and terms

Generated with **ChatGPT image generation** (OpenAI). OpenAI's Terms of Use assign rights in output to the user and allow commercial use, so the portraits can ship in the game. Keep a note in `CREDITS.md` if the tool changes (for example PixelLab for sprites, whose output the project also owns).

## The style prompt

Every prompt starts with this block, then one paragraph describing the character and ending with their expression. Run each in a new chat, ask for 2:3 portrait.

```
Visual novel character portrait for a dark surreal fantasy game. Half-body, neutral pose, plain flat light-grey background, no text. Painterly anime-influenced illustration with clean dark ink linework and soft cel shading. Muted palette of charcoal, bone white and rust, with one saturated accent color per character. Subtle ink-splatter and erased-paper edges on clothing. Portrait 2:3 aspect ratio. Straight-on camera at the character's own eye level, never looking up from below or down from above. Body angled three-quarters toward the viewer's left, framed from the waist up, with empty space above the head and nothing (hair, weapons) cut off by the frame edges. Stylized anime faces with simple cel-shaded skin, even for older or rugged characters, no realistic skin texture. Same line weight and face style as a cohesive anime character roster.
```

Keep the background plain light grey: the cut-out tool depends on it.

**Accent colours** (one per character): Ash ink-blue, Bran rust-orange, Velvette crimson, Verity violet, Mother Gristle poison green, Ilse icy cyan. Pick a new, distinct one for each new character.

### Character paragraphs used so far

- **Ash:** a quiet young swordsman around 20. Messy black hair, pale skin, faint black ink stains creeping up his hands and neck. Tattered charcoal cloak whose frayed edges fade to blank white, with a deep ink-blue lining as his accent. Dark leather vest, steel shortsword at his hip. Calm, unreadable, determined expression.
- **Bran:** a broad-shouldered mercenary in his 40s. Shaved head, scarred jaw, grey stubble, one clouded eye. Dented grey plate pauldron over a stained brown gambeson, with a rust-orange sash as his accent. A contract written in tiny black script is tattooed down his bare forearm. Heavy axe on his back. Wry, tired half-smirk, a man who'd sell you out for the right price but apologise first.
- **Velvette:** an elegant woman around 30, a duelist and courtesan-spy. Sleek wine-red bob, sharp eyeliner, beauty mark. Fitted black high-collared coat with gold buttons and a deep crimson inner lining as her accent, long gloves, thin rapier. Playful, knowing smile with one raised eyebrow.
- **Verity Hale:** a former chief archivist in her early 50s, now a quiet villain. Tall and thin, silver-streaked dark hair pinned up neatly, a few loose strands, faint lines around tired grey eyes, small round reading spectacles. Long bone-white archivist's robe with a high collar, ink-stained cuffs, and a deep violet stole as her accent. Her right hand and the hem of her robe are fading into blank white paper, as if erased. Holds a closed ledger against her chest. Polite, weary, gently sad smile, someone who believes she is doing the merciful thing.
- **Mother Gristle:** a hunched, sturdy old woman around 70, a swamp herbalist who heals for money. Wild grey hair tied back with twine, sharp hooked nose, deep wrinkles, gold-capped front tooth, shrewd narrow eyes. Patched brown shawl over a dark apron hung with rows of small glass bottles, the liquid inside a glowing poison green as her accent. Gnarled wooden staff wrapped in dried herbs, a coin purse on her belt. Grandmotherly grin that doesn't reach her eyes, like she's already adding up your bill.
- **Ilse:** an ageless knight who is a living reflection that stepped out of a mirror after her original was erased. Strikingly beautiful, long straight pale hair, porcelain skin with thin hairline cracks like broken glass along her cheek and collarbone, her side part and beauty mark on the "wrong" side. Silvered mirror-plate armour over a dark gown, with icy cyan light glinting in the cracks and on her spear tip as her accent. Holds a slender spear upright. Faint mirrored double outline around her silhouette. Cool, vain, faintly amused expression, admiring herself more than the viewer.

### Expressions

In the same chat as the locked neutral image, paste the same full prompt, replace only the last sentence with one of these, and add "Same character, same outfit, same framing, change only the facial expression."

- happy: genuine smile, eyes softened
- angry: brows drawn down, jaw tight, glaring
- sad: eyes lowered, mouth pressed thin
- surprised: eyes wide, mouth slightly open
- smug: half-lidded eyes, crooked smile

### Status

Every recruit and story speaker has a neutral portrait (Phase 8, plus Clerk Pettigrew, Governor Thale, the Concord Warden and Tithe-Captain Morrow for issue #111, and Ozias Crane, Hester Vane, Notary Marrow, Marguerite Penhallow and Augustin Sallow for the personal missions of issue #113). Expressions (`<id>_<expr>.png`) are issue #107.

## API pipeline (Phase 8)

`tools/openai_image.py OUT.png "prompt" --ref a.png --ref b.png --quality medium` calls gpt-image-2 directly (no
ChatGPT chat needed). Give it the style block above + "Match the art style, line weight, face style and rendering of
the two reference portraits exactly, but draw a new character:" + the character paragraph, with the raw Ash and Bran
portraits (downscaled to 512x768) as references. That keeps new faces on-model with the cast. A 1024x1536 medium
portrait costs about $0.054; every call is logged in `tools/art_spend.jsonl` with its token usage. The paragraphs used
are in project files `last-ink/portraits/` next to the raw images.

Corporal Daro is non-binary (they/them).

## Style trial (2026-11-21)

`tools/portrait_style.py OUT_DIR quill velvette bran` makes code-only treatments of existing portraits
(grade, ink, pix336, pix168), and `tools/shot.gd ... scene=town talk=quill_first portraits=OUT_DIR/pix336`
shows one in the real dialogue box without touching `assets/portraits/` (`skip=N` starts N lines in).
Comparison images: project files `last-ink/art-pass/portrait-style/`.
