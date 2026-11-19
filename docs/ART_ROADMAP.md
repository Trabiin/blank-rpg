# Last Ink: Art Pass Roadmap

The plan for replacing every placeholder in Last Ink with custom art, aiming for a polished indie release in the
Sea of Stars / Eastward tier: 2D pixel art, top-down 3/4, rich lighting and FX, painted portraits for story scenes.

Nobody on the project draws by hand. Art comes from three places:

| Tool | Who runs it | Used for | Cost |
|---|---|---|---|
| **PixelLab** (pixellab.ai) | Ojon generates, Claude cleans up and wires in | Every in-game pixel sprite: characters, animations, enemies, bosses, tilesets, props, buildings, icons, some FX | Free: 5 gens/day. Paid: about $12/month for 2,000 gens (check the current tiers before buying) |
| **ChatGPT image generation** | Ojon generates, Claude cuts out and wires in | Painted art: portraits and expressions, title and key art, store art, the territory map base, optional story CGs | Free tier: a handful of images a day. Plus ($20/month) gives far more |
| **Claude in code** | Claude | Palette locking, cleanup, sprite sheets, shaders, lighting, particles, all FX that read better as code, UI frames and HUD, the Blank, the territory map overlay, fonts setup | Free |
| **Free fonts** (SIL Open Font License) | Claude picks, Ojon approves | All in-game text | Free |
| **Pixelorama** (optional, free, runs in the Chromebook browser) | Ojon, only if wanted | One-pixel fixes on a sprite without waiting for Claude | Free |

Music and sound effects are out of scope for this document. Today the game uses synthesized sounds in code; a
separate audio plan (CC0 packs or a commissioned composer) should come after the art pass.

All counts below come from the current repo data (`data/*.json`) and `docs/DESIGN.md`. MVP means the Prologue +
Chapter 1 + Act 1 (what the game is building now). Full game means Chapters 2 to 6 on top.

---

## 1. Style guide (lock this first)

### 1.1 Resolution and scale

| Item | Size | Why |
|---|---|---|
| Layout grid | **640x360**, scaled to any screen (1080p, 4K); UI, text and FX render at full resolution | Already the project setting. See 1.1b: sizes in this table are option A and wait on the detail test |
| Tile grid | **16x16** | Matches today's maps and the SNES feel |
| Heroes and humans | **32x32 canvas, figure about 26 to 28 px tall** (about 1.7 tiles) | The "chunkier heroes" Ojon asked for. The 48 px PixelLab test was too tall; 32 px sits right next to 16 px tiles, as in Secret of Mana |
| Children, small animals, small enemies | 24x24 or 32x32 canvas, figure 12 to 20 px | Nibblers, moths, Mr. Biscuits, the Merrow Three |
| Large enemies | 48x48 | Tithe Enforcer and similar |
| Bosses | 96x96 to 128x128 | The Auditor and every chapter boss. If PixelLab caps the canvas lower, generate at its maximum and Claude builds the rest from parts (body + separate arm/weapon pieces animated in code) |
| Buildings | 48 to 112 px wide, drawn on the 16 px grid | Hollowmark buildings, three upgrade looks each |
| Icons | **16x16** (inventory, HUD) and **24x24** (menus, research, roles) | One consistent icon set |
| Portraits | 512x768 game file from 1024x1536 originals | Already set by `docs/PORTRAITS.md` |

PixelLab rule of thumb: always generate at the final size (32x32 canvas for humans). Never generate big and shrink:
shrinking pixel art destroys it.

### 1.1b Screen resolution and the detail test (decided: mock up both)

The game already runs at 1080p, 1440p and 4K. 640x360 is the layout grid, not the output size: the project uses
Godot's `canvas_items` stretch mode, so text, menus, code-drawn FX and portraits render at the screen's full
resolution. Only the pixel art is drawn at a fixed density (a 16 px tile shows at 6x on a 1080p screen).
Modern pixel games (Sea of Stars, Eastward, Octopath) work the same way: the modern feel comes from lighting,
particles, smooth camera, sharp UI and portraits.

Ojon chose (2026-11-19) to see two detail levels side by side before committing:

| | Option A: standard detail | Option B: double detail |
|---|---|---|
| Tiles | 16x16 | 32x32 |
| Heroes | 32x32 canvas, ~27 px tall | 64x64 canvas, ~56 px tall |
| Small enemies | 24x24 | 48x48 |
| Camera | zoom 2 (today), a bit wider on big screens | zoom 1 |
| Code impact | none | maps keep their layouts but tile size, collision, enemy sizes and FX scale change |
| Art plan impact | as written in this document | same asset count, about 30 to 50% more retries per asset (bigger AI sprites drift more), so about one extra paid PixelLab month for the MVP |

**Mockup gens for Ojon (PixelLab free tier, about 20 gens, 4 days):** for each option, Ash (8 rotations + walk south),
one Nibbler (rotations), and a grass-to-dirt top-down tileset. Settings: high top-down, single-colour black outline,
basic shading, medium detail. Option A at 32 px character / 24 px Nibbler / 16 px tiles; option B at 64 / 48 / 32.
Claude builds both meadow screenshots (and a toggle in the live build) from those, with HUD, lighting and the
Blank edge, so the comparison is on Ojon's own screen. The pick then sets every size in 1.1.

### 1.2 Camera and directions

- Top-down 3/4 ("High top-down" in PixelLab), light from the top left, soft shadow blob under every actor (drawn in code).
- Characters: **8 directions**. Only 5 are generated (S, SE, E, NE, N); SW, W, NW are mirrors. Asymmetric characters
  (an eyepatch, a sword on one hip) still mirror; SNES games did the same and nobody minds.
- Small enemies (Nibblers, moths, slimes): 4 or 2 directions are enough.

### 1.3 Palette

One **master palette** of about 48 to 64 colours for the whole game, so PixelLab output from different days matches.

- **Charcoal, bone white and rust** as the base, the same mood as the portrait style block.
- **Ink black** (a deep blue-black, not pure black) for outlines and for Ink itself.
- **Paper white is reserved for the Blank.** Nothing else in the world uses the near-white paper tone. This keeps the
  Blank instantly readable in a fight and is the game's signature look.
- One **accent colour per main character**, the same as their portrait accent: Ash ink-blue, Bran rust-orange,
  Gristle poison green, Daro to be picked (suggestion: brass yellow), Velvette/Lysandre crimson, Verity violet, Ilse icy cyan.
- Each region gets a 6 to 8 colour **regional ramp** added to the base (meadow greens, Gutterwoods fungal teal,
  marsh olive, Concord gold).
- Characters are slightly more saturated and contrasted than backgrounds; enemies carry a warning hue (Blank kinds
  white with ink-black cores, Concord kinds gold and grey).

Claude will add `tools/palette_lock.py`: it snaps every generated image to the master palette, removes stray
anti-aliasing pixels and soft edges, and fixes the outline colour. Every PixelLab export goes through it.

### 1.4 Outline and shading rules

- 1 px dark outline on characters, enemies and interactable props; coloured (darkest shade of the local colour)
  rather than pure black on the inside edges.
- Background tiles have no outline, so actors pop.
- 3 to 4 shades per material, cel style, no dithering on characters, light dithering allowed on big ground areas.

### 1.5 Style target screenshot

Phase 0 ends with one **target screenshot** of the Frayed Meadow: new Ash, Bran, two Nibblers, the meadow tileset,
a few props, the HUD and the Blank edge. Ojon approves it, and every later asset is judged against it.

### 1.6 Prompt templates

Claude writes a `docs/ART_PROMPTS.md` in Phase 0 with fixed PixelLab prompt blocks (like the portrait style block),
for example:

```
Character: [description]. Dark surreal fantasy, muted charcoal, bone and rust palette with a [accent] accent.
Clean 1px dark outline, cel shading, top-left light. SNES action RPG style.
```

plus the PixelLab settings to reuse every time: canvas size, view (high top-down), outline (single colour black),
shading (basic), detail (medium), and a **style reference image** (the approved Ash sprite) for every later character.

---

## 2. Gen budget at a glance

A "gen" is one PixelLab generation. Figures from Ojon's free-tier test: a full 8-direction character costs about
2 gens, an animation costs about 3 gens per direction. All estimates below include about 50% extra for retries.

| Group | MVP gens | Full game gens |
|---|---|---|
| Field heroes (4 MVP, 12 full) | ~540 | ~1,620 |
| Core staff, recruits, story NPCs and townsfolk | ~630 | ~2,000 |
| Enemies (4 MVP kinds + elite recolours, ~25 full) | ~250 | ~1,500 |
| Bosses (1 MVP, 6 more full) | ~150 | ~1,050 |
| Tilesets and props (6 MVP biomes, 12 full incl. interiors) | ~520 | ~1,250 |
| Hollowmark buildings and town props | ~150 | ~250 |
| Icons | ~160 | ~350 |
| Sprite FX | ~60 | ~150 |
| **Total** | **~2,450** | **~8,200** |

What that means in practice:

- **Free tier (5/day):** about 16 months for the MVP alone. Fine for trying things in Phase 0, not for the pass.
- **Paid tier (~2,000/month):** the MVP pass is about **6 to 8 weeks of paid months** (2 months, about $24), the full
  game about 4 to 5 more paid months spread over the chapters. Pause the subscription between phases.

ChatGPT portraits: about **90 images for the MVP** (incl. retries), **~300 for the full game**. On the free tier that
is several weeks of daily generating for the MVP; ChatGPT Plus for a month makes it a few sessions.

---

## 3. Full asset inventory

Legend for the Tool column: **PL** = PixelLab, **GPT** = ChatGPT image gen, **Code** = Claude in code.

### 3.1 Field heroes (fight on missions)

Every field hero needs the full action set:

| Animation | Directions | Frames (typical) | Gens (×3 per dir) |
|---|---|---|---|
| Base character (8 rotations) | 8 | 1 | 2 to 4 |
| Idle (breathing) | 5 | 4 | 15 |
| Walk / run | 5 | 6 to 8 | 15 |
| Attack (weapon swing, the combo uses one swing + code timing) | 5 | 4 to 6 | 15 |
| Cast / ability (one shared pose for all hotkeyed abilities) | 5 | 4 | 15 |
| Charged tech (wind-up loop + release) | 5 | 6 | 15 |
| Hurt | 3 (S, E, N) | 2 to 3 | 9 |
| Knocked down / KO | 1 | 4 | 3 |
| Victory (results screen) | 1 | 4 | 3 |
| **Per hero** | | | **~90, ~135 with retries** |

Notes:
- Gear no longer changes the sprite (as in most SNES RPGs). Each hero carries their signature weapon. The paper-doll
  system retires; palette swap stays for enemy variants and alt costumes.
- The weapon arc, trail and impact are drawn in code on top, so one attack animation reads as a combo.

| Hero | Weapon in sprite | Accent | MVP? | Gens |
|---|---|---|---|---|
| Ash, the Unwritten | Inkblade (shortsword), cloak fading to white | Ink-blue | MVP | ~135 |
| Brannoc "Bran" Coil | Heavy axe, contract tattoo | Rust-orange | MVP | ~135 |
| Mother Gristle | Herb staff (ladle in gear), bottles on apron | Poison green | MVP | ~135 |
| Corporal "Ninefingers" Daro | Concord pike (the game uses a pike; DESIGN.md still says crossbow, update it) | Brass (suggested) | MVP | ~135 |
| Lysandre, the Velvet Marquise | Rapier | Crimson | Full (Ch. 3) | ~135 |
| Saffron Kiss | Whip | Gold | Full (Ch. 3) | ~135 |
| Hex & Tally | Knuckles + a separate shadow sprite for Tally (extra ~40) | Black / smoke | Full (Ch. 3) | ~175 |
| Ilse of the Mirror | Spear, cracked mirror armour (shimmer done in code) | Icy cyan | Full (Ch. 4) | ~135 |
| 4 more heroes (still to design) | | | Full | ~540 |

Velvette: still undecided whether she is folded into Lysandre or a separate recruit. Decide before Phase 2 so she
gets one sprite and one portrait set, not two.

### 3.2 Hub characters: core staff, recruits and story NPCs

Non-fighters only walk and idle in Hollowmark, so they need far less:

| Animation | Directions | Gens |
|---|---|---|
| Base character (8 rotations) | 8 | 2 to 4 |
| Walk | 5 | 15 |
| Idle / working-at-post loop | 1 to 2 | 3 to 6 |
| Talk gesture (optional, for important NPCs) | 1 | 3 |
| **Per character** | | **~22, ~30 with retries** |

**MVP roster (`data/recruits.json`, 15 people; 4 field heroes above):**

| Character | Look notes for the prompt | Gens |
|---|---|---|
| Quill Marrow, quartermaster | Former Concord clerk, ledger, green cloth | ~30 |
| Old Tobble, tavern keeper | Old, apron, rag over shoulder | ~30 |
| Sister Abeyance, runaway scribe | Pale robes, a page that glows | ~30 |
| Pell Undermoss, gravedigger | Shovel, mud | ~30 |
| Hesper Quoin, cartographer | Rolled maps, compass | ~30 |
| Dunmore Vell, blacksmith | Debt tattoos, hammer, leather apron | ~30 |
| Jessamy Nightjar, smuggler | Dark coat, hood, lantern | ~30 |
| Mr. Biscuits, a dog (possibly) | Quadruped: PixelLab's animal / quadruped mode, 24 px | ~30 |
| The Merrow Three, orphan choir | Three small children as one sprite group (or one child sprite placed three times with palette swaps, cheaper) | ~30 to 60 |
| Odile Penhallow, tax collector | Concord uniform, tidy | ~30 |
| Big Ottoline, cabaret bouncer | Huge, sequins, 32 px but broad | ~30 |
| **Subtotal** | | **~360** |

**Story and town NPCs (MVP):**

| Character | Gens |
|---|---|
| Verity Hale (appears at the Blank's edge, in Ch. 1 and later) | ~30 (+ full-game fight set under bosses) |
| Concord governor (flees in Ch. 1) | ~30 |
| Concord tax clerks / guards (2 variants, palette swaps for more) | ~60 |
| Generic townsfolk (6 base bodies: man, woman, elder, child, labourer, merchant; palette and hair swaps in code make ~20 looks) | ~150 |
| Visitors at the south gate (reuse townsfolk) | 0 |
| **Subtotal** | **~270** |

**Full game:** about 35 more recruits and staff (DESIGN.md: ~50 total, ~8 core staff incl. Vane & Vesper twins),
plus faction leaders (Mercenary Guild, Gutterwood Coven, the Concord, the Abbey), the Abbot, High Scribes, the
drowned lighthouse keeper, and townsfolk sets per region (abbey monks, Causeway masquerade guests, coast villagers).
About **~1,400 more gens**.

### 3.3 Enemies

Per enemy: base (2 to 4), move (2 to 5 dirs), attack/telegraph, hurt, death. Small ones about 40 gens, larger
humanoids about 60 to 80.

**MVP (`data/enemies.json`):**

| Enemy | Size | Directions | Special frames | Gens |
|---|---|---|---|---|
| Nibbler (Blank) | 24 px blob with mouth | 4 | Lunge bite, dissolve-to-paper death | ~40 |
| Spitter (Blank) | 24 to 32 px | 4 | Spit wind-up; the ink glob projectile (Code) | ~45 |
| Letter-moth | 16 to 24 px, flies in packs | 2 | Flutter loop, dive | ~30 |
| Tithe Enforcer (Concord) | 48 px, front shield | 5 | Shield block, red-ring slam wind-up, stagger | ~80 |
| Elite / variant recolours (Gutterwoods, Tithe Road, surge versions) | | | Palette swap in code | 0 |
| Extra Act 1 enemies (suggested, so each biome has one signature foe: a marsh reed-thing, a mill scarecrow, a Guild sellsword) | | | | ~55 |
| **Subtotal** | | | | **~250** |

**Full game:** about 4 new enemies per chapter for 5 chapters (abbey copy-monks and ink wraiths, Causeway masked
duellists and ink eels, coast drowned sailors and half-erased gulls, Spire scribes and golden automatons, Margin
"word-shaped" things that are text drawn in code). About 20 more kinds, **~1,250 gens**.

### 3.4 Bosses

Bosses are big, have several attack patterns and are the "wow" moments, so they get the most care.

| Boss | Chapter | Size | Frames needed | Gens |
|---|---|---|---|---|
| **The Auditor** (lance-sized quill, strikes people out) | Act 1 (MVP) | 96 px | Idle, walk 4 dirs, 3 attacks (thrust, strike-out sweep, stamp), hurt, phase change, defeat | ~150 |
| The Abbot Who Copied Himself | Ch. 2 | 64 px + copies (palette/shader tint in code) | Same as above, plus split | ~150 |
| The Host (mostly mouth) | Ch. 3 | 128 px | Parts animated in code | ~150 |
| The Tide That Forgot | Ch. 4 | 128 px, environmental | Wave parts, plus tiles | ~150 |
| Verity, Unmade (2 phases) | Ch. 5 | 64 to 96 px | Two full sets | ~250 |
| The Vacancy (a page that erases the HUD) | Ch. 6 | Mostly Code (redaction bars, text, shaders) + a few PL pieces | | ~100 |
| Mini-bosses (one per chapter, recolour of a big enemy + new attack) | | | | ~100 |

### 3.5 Tilesets and environment props

PixelLab makes top-down tilesets as **terrain transition sets** (for example grass to dirt, grass to water). Each
biome needs about 4 transition sets, a cliff/wall set, and 20 to 30 props.

| Per biome | Gens |
|---|---|
| 4 terrain transition tilesets (~8 gens each with retries) | ~32 |
| Cliffs / walls / edges set | ~10 |
| Decoration tiles (flowers, cracks, puddles, path details) | ~10 |
| 20 to 30 props (trees, rocks, fences, signs, barrels, ruins; 1 to 2 gens each) | ~40 |
| **Per biome** | **~85 to 95** |

The **Blank versions of every biome are Code**: the existing shader drains tiles to paper white, eats edges and adds
static, so no "erased" tileset is ever generated. Whitewater (an erased village) is the town tileset plus that shader.

**MVP biomes** (the 9 provinces in `data/provinces.json` share these; today all missions reuse `frayed_meadow`):

| Biome | Provinces | Signature details | Gens |
|---|---|---|---|
| Meadow | Frayed Meadow | Grass in half-sentences (letter-shaped grass tufts), stone walls, wildflowers | ~90 |
| Hollowmark town (exterior) | Hollowmark, Whitewater | Cobbles, market stalls, crooked houses, wanted posters | ~90 |
| Gutterwoods forest | Gutterwoods | Trees growing from letters, fungus, wet roots, Coven totems | ~90 |
| River and marsh | Saltreed Marsh, Gallows Ferry, Old Mill Crossing | Water, reeds (some white), docks, ferry, mill wheel (animated prop) | ~95 |
| Hills | Lampwick Hills | Ink springs (animated ink pools), rocky slopes, lamps | ~85 |
| Concord road | Tithe Road | Paved road, checkpoints, toll booths, gold banners | ~70 |
| **Subtotal** | | | **~520** |

**Full game biomes:** Saint Ledger's Abbey (exterior + candlelit interior), Velvet Causeway (bridge city on an ink
lake), Unfinished Coast (shore where the sea stops mid-wave: the frozen waves are a prop set), Gilded Spire (gold and
rot), The Margin (mostly Code: scenery written as words), plus interiors: tavern, Command hall, houses, shops, caves.
About **~730 more gens**.

**Animated tiles and props (all biomes):** water, ink pools, torches, banners, the mill wheel, candles. PixelLab can
animate a prop (about 3 to 6 gens each); simple loops like water shimmer and flicker are done in a shader (Code).

### 3.6 Hollowmark buildings and town

`data/buildings.json` has 6 buildings with 3 levels each, plus the Wardlamp. Each level should look visibly better.

| Asset | Count | Tool | Gens |
|---|---|---|---|
| Command Table, Barracks, Infirmary, Inkworks, Scriptorium, Guildhall: 3 looks each | 18 | PL (map object), generate level 3 first, then ask for "earlier, shabbier" versions with the same reference | ~75 |
| Construction scaffolding (one shared set, layered over any building) | 1 set | PL | ~8 |
| Wardlamp, 3 levels (light glow in Code) | 3 | PL | ~10 |
| Tavern, Tobble's Stall, south gate, town walls, ruined tax office | 5 | PL | ~25 |
| Town props: carts, crates, laundry lines, noticeboard, well, lamp posts, Command Table map prop | ~20 | PL | ~30 |
| **Subtotal** | | | **~150** |

Full game adds any new buildings from later research and an interior for the Command hall and tavern (~100).

### 3.7 FX

Most FX stay in code: they are crisper at pixel scale, cost nothing, and can react to gameplay.

| FX | Tool | Notes |
|---|---|---|
| Weapon trails and slash arcs | Code | Per weapon colour |
| Hit sparks, ink splatter, damage numbers | Code + a small PL splatter set (~10 gens) | |
| Abilities (8 in `data/abilities.json`: Rewrite, Strikethrough, Cleave, Hold the Line, Poultice Toss, Scald, Long Thrust, Pike Sweep) | Code, with PL sprite sheets for the 2 to 3 that need a drawn object (poultice bottle, shield ward) | ~20 gens |
| Charged techs (4 in `data/techs.json`: Full Stop, Breach of Contract, Stir the Pot, Skewer) | Code, plus one PL "big moment" sheet each | ~20 gens |
| The Blank: edge, static, erasing tiles, surges, Blots | Code (shaders) | Signature effect, polish heavily |
| Lighting: 2D lights, day/night tint driven by the empire clock, Wardlamp glow, torches | Code (Godot Light2D, CanvasModulate) | Big quality jump for little cost |
| Weather and ambience: rain, fog, falling letters, fireflies | Code (GPUParticles2D, tested on the Chromebook) | |
| Screen effects: hit stop, shake, flash, vignette, chapter transitions | Code | Already partly there |
| Level-up, rescue, building-complete celebrations | Code | |
| Explosion / puff / dust sheets for KOs, landings, dashes | PL (~10 gens) | |

### 3.8 UI, HUD, menus, icons and fonts

**Frames and HUD (Code, with optional PL texture pieces):** the UI stays code-drawn (it scales cleanly and is easy
to change) but gets a real art direction: ink-on-paper panels, torn edges, wax-seal buttons, a quill cursor.

| Asset | Tool | Gens |
|---|---|---|
| 9-slice panel set (paper, dark ledger, tooltip, VN textbox) | PL (texture pieces) + Code assembly | ~15 |
| Buttons, tabs, scrollbars, selection cursor (quill nib), focus highlight | PL + Code | ~10 |
| HUD: party plates with face icons, HP and Ink bars, power gauge, tech-ready glow | Code | 0 |
| Face icons for HUD and menus (24x24 per character) | Claude derives them from the new sprites; PL if they don't read | ~30 MVP |
| Input prompts (keyboard, Xbox / PlayStation style pad, touch) | Kenney's CC0 Input Prompts pack, recoloured | 0 |
| Touch controls (stick, attack, ability, menu buttons) | Code, styled to match | 0 |
| Territory map UI: province borders, Fray meter, markers, clock dial | Code | 0 |

**Icons (PL, 16x16 or 24x24, one shared prompt and reference sheet):**

| Icon group | MVP count | Full game count |
|---|---|---|
| Field items (`data/items.json`: tonic, salts, draught) | 3 | ~12 |
| Gear (`data/gear.json`: 12 weapons, 3 armours, 4 trinkets) | 19 | ~80 |
| Abilities | 8 | ~40 |
| Charged techs | 4 | 12 |
| Research nodes (`data/research.json`, 4 branches) | 12 + 4 | ~40 |
| Resources (Gilt, Supplies, Ink, Renown, Insight) | 5 | 5 |
| Buildings | 7 | ~10 |
| Roles (governor, staff, expedition, research, envoy, field) | 6 | 6 |
| Traits (`data/recruits.json`: 10) | 10 | ~20 |
| Factions (Guild, Coven, Concord) | 3 | ~6 |
| Status / buffs / map markers / misc | ~15 | ~25 |
| **Total icons** | **~100 (~160 gens)** | **~255 (~350 gens)** |

**Fonts (free, SIL Open Font License, logged in CREDITS.md):**

| Use | Candidates | Notes |
|---|---|---|
| Body text, menus, HUD numbers | A clean pixel font such as Pixelify Sans or Silkscreen (Google Fonts, OFL) | Must be readable at 640x360 on the Chromebook |
| Dialogue | A slightly taller pixel font for long lines | Same family if possible |
| Titles, chapter cards, logo | A serif or blackletter display face (OFL) used at larger sizes | Ledger / archive feel |
| The Vacancy's redacted speech | Code (black bars + occasional clear word) | |

Claude shortlists 3 font pairings with screenshots in Phase 6 for Ojon to pick.

### 3.9 Portraits and expressions (ChatGPT)

Uses the existing style block in `docs/PORTRAITS.md` and the cutting tool `tools/cut_portraits.py`. Six are done:
Ash, Bran, Velvette, Verity, Mother Gristle, Ilse.

**Expressions:** deep cast and villains get all 5 (happy, angry, sad, surprised, smug). Light recruits get neutral
plus 1 expression that fits them. Estimate 1.5 images per finished portrait for retries.

| Group | Characters | Images (neutral + expressions) | With retries |
|---|---|---|---|
| Done, need expressions | Ash, Bran, Gristle, Verity (Ilse and Velvette wait for their chapters) | 4 × 5 = 20 | ~30 |
| MVP deep cast, new | Quill, Tobble, Abeyance, Daro | 4 × 6 = 24 | ~36 |
| MVP boss | The Auditor | 1 + 2 (angry, surprised) = 3 | ~5 |
| MVP light recruits | Pell, Hesper, Dunmore, Jessamy, Mr. Biscuits, Merrow Three, Odile, Ottoline | 8 × 2 = 16 | ~24 |
| MVP story NPCs | Concord governor, a Concord clerk | 2 | ~3 |
| **MVP total** | | **~65** | **~95** |
| Full game additions | Lysandre / Velvette, Saffron, Hex & Tally, Ilse expressions, 4 new heroes, ~4 new core staff (incl. Vane & Vesper), ~30 light recruits, the Abbot, the Host, the lighthouse keeper, faction leaders, Verity Unmade variant, the Vacancy (a mostly-code redacted "portrait") | ~200 | ~300 |

Tips that keep the roster consistent:
- One new chat per character, the style block first, then the character paragraph.
- Expressions in the same chat as the locked neutral image.
- Keep the plain light-grey background; the cut tool depends on it.

### 3.10 Title, key art, map and promotional art

| Asset | Tool | Notes | Images |
|---|---|---|---|
| Territory map base: an ink-on-parchment map of the Inklands, MVP region first | GPT painted, then Code: Claude quantizes it to the palette, and draws province borders, Fray and the Blank on top | Fits the "reality is written" theme; must leave room for the Blank to spread from the east | ~10 |
| Title screen key art: Ash at the Blank's edge, the party behind | GPT (same portrait style, wide 16:9) + Code parallax and animated Blank | | ~8 |
| Logo / wordmark "Last Ink" | GPT for ideas, then Claude rebuilds it cleanly in code or as vector from a chosen font | | ~6 |
| Chapter title cards (Prologue, Ch. 1 to 6) | GPT backgrounds + Code text | Optional for MVP: Prologue and Ch. 1 only | ~4 MVP, ~14 full |
| Story CGs: a few big moments (Ash crawling out of the Blank, the tax office eaten, the Auditor's arrival) | GPT | Optional; the polish that makes a story land | ~6 MVP, ~20 full |
| Loading / game over / results backgrounds | Code | | 0 |
| Store page: itch.io cover 630x500, Steam capsules (header 920x430, small 462x174, main 1232x706, library 600x900 and hero 3840x1240), icon | GPT key art, Claude crops and adds the logo | Only when shipping | ~10 |
| Trailer and GIFs | Claude records from the game | Only when shipping | 0 |

Rights: both OpenAI's and PixelLab's terms give the output to the user for commercial use (see `CREDITS.md`).
Recheck both terms right before release, and keep the raw originals in the project files as proof of origin.

---

## 4. Pipeline (what Claude builds so art just drops in)

Done in Phase 0, before any big generating:

1. **Sprite folders by id:** `assets/sprites/<id>/<anim>_<dir>.png` strips (or a single sheet + JSON). A loader turns
   them into Godot `SpriteFrames`. Any character with no new art falls back to today's paper doll, so the game keeps
   working the whole way through the pass and art can land one character at a time.
2. **`tools/palette_lock.py`:** snaps PixelLab exports to the master palette, cleans stray pixels, fixes outlines,
   trims and aligns feet to one baseline, mirrors the 3 missing directions.
3. **`tools/import_sprites.py`:** takes a zip exported from PixelLab, names and packs the frames, runs palette lock,
   writes the sprite folder. Ojon uploads the zip to the project files; Claude does the rest.
4. **Tileset importer:** turns PixelLab terrain sets into Godot TileSet terrains, so maps auto-tile and the map
   text files keep working.
5. **Contact sheets:** after each batch Claude posts one image with every new sprite next to the target screenshot,
   for a quick yes/no.
6. Remove the temporary PixelLab V-key preview (`scripts/pixellab_preview.gd`, `assets/pixellab/`).

---

## 5. Phases and order

Each phase ends with a PR, a "try this" checklist on the live build and Ojon's sign-off. Gen counts tell you
when to have the paid PixelLab month running.

| Phase | What | Tools | Gens / images | Paid PixelLab? |
|---|---|---|---|---|
| **0. Style lock** | Detail test first (1.1b: option A vs B mockups, Ojon picks); then settle palette and generate the rest of the samples; build the pipeline (section 4); produce the target screenshot; write `docs/ART_PROMPTS.md` | PL, Code | ~40 | No, free tier over about a week |
| **1. The party** | Ash, Bran, Gristle, Daro: full action sets; HUD face icons; code trails for each weapon | PL, Code | ~560 | **Start month 1** |
| **2. First impression: Prologue** | Meadow biome, Nibbler, Spitter, Blank FX polish, lighting and day/night, ambient particles. After this the first 10 minutes look finished | PL, Code | ~180 | Month 1 |
| **3. Hollowmark** | Town tileset, 6 buildings × 3 levels, Wardlamp, scaffolding, town props, Quill / Tobble / Abeyance, townsfolk, Concord clerks and governor | PL, Code | ~570 | Month 1 to 2 |
| **4. Act 1 world** | Gutterwoods, river and marsh, hills, Concord road biomes; moth, Enforcer, extra Act 1 enemies, Verity sprite. Give each province its own map dressing | PL, Code | ~520 | Month 2 |
| **5. The Auditor and recruits** | Boss sprite and attacks; the 8 light recruits | PL, Code | ~420 | Month 2 |
| **6. UI and icons** | Panels, buttons, cursor, ~100 icons, input prompts, font pick | PL, Code, OFL fonts, Kenney prompts | ~185 | Month 2 (end) |
| **7. Portraits and painted art** | MVP portraits and expressions (~95), territory map, title key art, logo, Prologue / Ch. 1 cards, optional CGs | GPT, Code | ~125 images | No (ChatGPT Plus month recommended) |
| **8. Polish sweep** | Consistency pass over everything vs the target screenshot, redo the weakest 10%, Chromebook performance check (texture sizes, particles) | PL, Code | ~100 | Leftover month 2 gens |
| **MVP done** | | | **~2,550 gens, ~125 images** | **About 2 paid months** |

Phases 1 and 2 can swap if Ojon would rather see the meadow finished first. Portraits (Phase 7) can run in parallel
with any phase, since they use a different tool; doing a few each day on the free ChatGPT tier works from now on.

**Full game, one block per chapter** (each about 1,000 to 1,300 gens, so roughly one paid month each, plus
~40 to 60 portrait images):

| Chapter | New art |
|---|---|
| 2. Saint Ledger's Abbey | Abbey tilesets (exterior + interior), monks, 4 enemies, the Abbot, Abbey-faction NPCs, new recruits |
| 3. Velvet Causeway | Bridge city and ink lake, masquerade guests, Lysandre, Saffron, Hex & Tally, 4 enemies, the Host |
| 4. Unfinished Coast | Shore and frozen-wave set, lighthouse, Ilse's sprite, 4 enemies, the Tide That Forgot |
| 5. Gilded Spire | Capital tilesets, High Scribes, 4 enemies, Verity Unmade |
| 6. The Margin | Mostly Code (words as scenery, recombined earlier tiles), the Vacancy |
| Throughout | ~30 remaining light recruits, 4 more heroes, icons for new gear and research, store art at release |

---

## 6. Decisions for Ojon

1. **Detail level:** option A (16 px tiles, 32 px heroes) or B (32 px tiles, 64 px heroes), decided by the side-by-side mockups in 1.1b.
2. **Velvette vs Lysandre:** one character or two? Needed before her sprite and expressions.
3. **Gear on sprites:** recommended no (signature weapon only), which saves thousands of gens.
4. **PixelLab paid months:** recommended two months for the MVP pass (Phases 1 to 6), paused between chapters later.
5. **ChatGPT Plus for one month** in Phase 7 (optional, the free tier works but slowly).
6. **Optional story CGs** in the MVP: yes or later.

---

## 7. Out of scope here

- Music and sound effects (separate audio plan after the art pass).
- Voice acting (none planned; the hero is silent and dialogue is text).
- Localization of art text (keep text out of images so the game can be translated later).
