# Last Ink: Design Document

> A short, complete action RPG in the spirit of 90s Secret of Mana and Final Fantasy,
> with modern quality of life. Weird, dark, funny. Rated Mature.
>
> Title: **Last Ink**. Repo: `Trabiin/last-ink` (renamed from `blank-rpg`).

---

## 1. Pillars

1. **Real-time party combat that feels good.** Snappy movement, a weighty swing, readable enemy tells.
2. **No ring menus, ever.** Hotkeyed abilities plus one clean list-based quick menu. Every action is two presses or fewer.
3. **A world that is visibly being eaten.** The Blank is not just a plot device; it is on the map, it moves, it changes what you can do.
4. **Dark, but with a grin.** Grim stakes, mercenaries who bicker, villains who are sometimes right.
5. **Respect the player's time.** Save anywhere, autosave, fast travel, adjustable speed and difficulty, no random encounters, 2 to 4 hours start to finish.

## 2. Platform and tech

| Topic | Decision |
|---|---|
| Engine | Godot 4.3 (GDScript) |
| Main target | Web (HTML5), auto-built and published to GitHub Pages on every push to `main` |
| Testing device | Chromebook in Chrome; must run well on modest hardware |
| Resolution | 640x360 base, integer-ish scaling, pixel art filtering off |
| Input | Keyboard, gamepad, and touch (on-screen stick plus buttons, shown only on touch devices) |
| View | Top-down 3/4 perspective (Mana-like), Y-sorted |
| Repo | Public on GitHub under Trabiin |

Web builds use Godot's single-threaded export, so they run on GitHub Pages without special server headers.

## 3. Art plan (no hand-drawn art from the owner)

| Layer | Source |
|---|---|
| Tiles, props, enemies, base animations | CC0 pixel packs (Kenney, OpenGameArt CC0 only). Every pack logged in `CREDITS.md` with link and license |
| Heroes | Modular "paper doll" sprites: one shared animated body rig, swappable hair/outfit/weapon layers, **recolored in code** with palette swaps. Every hero animates the same way but looks distinct |
| Portraits | AI-generated stills for dialogue and menus, one consistent style prompt, cleaned up per hero |
| FX and UI | Drawn in code (slashes, damage numbers, the Blank's static, menus) |

**Status (art feasibility pass):** the meadow now uses ArMM1998's CC0 Zelda-like overworld tiles, graded darker
by a shader, and the Blank drains them to paper-white as it approaches. Heroes use Shade's CC0 *Puny Characters*:
`tools/import_art.py` diffs each class sheet against the bare body sheet to produce separate outfit layers, and a
palette-swap shader recolors the body and outfit per hero (skin, cloth, metal, accent...). Every hero shares the
same 8-direction walk, swing, hurt and knockdown animations. Nibblers are Puny's slime recolored to blank-white.
Ash = body + archer layer in indigo; Bran = body + warrior layer in bronze and rust.

## 4. Combat

**Real-time**, Mana-inspired, minus the ring.

- **Attack power gauge.** Each hero has a power gauge that refills after every swing (about 1.1 s). Swinging early
  still hits, but for proportionally less damage. A full gauge does full damage; a full gauge held for 1 s more
  becomes a **charged tech** (later milestone).
- **Abilities on hotkeys.** Each hero has up to 4 abilities mapped to keys 1-4 / gamepad shoulder + face buttons.
  Using one does not pause; it costs **Ink** (MP).
- **Quick menu.** One button opens a list menu that slows time to 10% (not a full pause). Tabs: Items, Abilities,
  Party (swap leader, set AI behavior), Equip. Fully navigable by d-pad, mouse/touch, or hotkeys.
- **Party of 3.** You control one hero; two AI allies follow. Swap control instantly with one button.
- **Ally AI presets** (set per hero in the Party tab): *Aggressive*, *Balanced*, *Keep Distance*, *Support*. AI waits
  for a full power gauge before striking so allies hit meaningfully.
- **Visible enemies with tells.** Every enemy attack has a wind-up (flash or crouch) so dodging by movement is always possible.
- **Downed, not dead.** Heroes at 0 HP are downed and can be revived by items or by standing next to them for 3 s
  outside combat. If all three go down, you reload the latest autosave.

## 5. Progression

A deliberate combination, kept light enough for a short game:

1. **Levels and gear.** XP raises HP, Ink and base stats. Gear: weapon, armor, one trinket per hero.
2. **Weapon and Ink skill levels (Mana-style).** Using a weapon type or Ink color raises its skill level (cap 5),
   unlocking a charged tech per level for weapons, and stronger spell tiers for Inks.
3. **Per-hero skill trees.** Each hero has a small tree (about 10 nodes, two branches) bought with Skill Points from levels.
   Branches reflect personality (e.g. Bran: *Bodyguard* vs *Turncoat*).

Weapon types: sword, axe, spear, rapier, crossbow, whip, knuckles, staff.
Ink colors (magic): **Red** (fire), **Blue** (frost), **Gold** (light, healing), **Green** (growth, poison),
**Black** (gravity, debuffs), **White** (only the Blank and its servants use it: erasure).

## 6. Quality of life

- **Save anywhere** from the quick menu, plus **autosave** on every area transition and after every boss.
- **Fast travel** between discovered "Waymarks" (lamp posts that still burn in a world being erased).
- **Adjustable battle speed** (0.75x to 1.25x) and **difficulty** (Story, Normal, Hard), changeable at any time.
- **Quest log with map markers**; the current main objective is always pinned on the minimap.
- **No random encounters.** Enemies are visible on the field and avoidable.
- Remappable controls, text speed, screen shake toggle, colorblind-safe telegraphs.

## 7. World

A **connected overworld**: areas join edge-to-edge with no world-map screen. The Blank spreads from the east,
and story beats visibly push it forward, swallowing places you already visited (they stay reachable through the
Waymarks, now as eerie white ruins).

**The setting: the Inklands.** A once-gaudy empire where reality is literally *written*. The ruling
**Gilded Concord** keeps the Great Ledger, and whatever the Ledger says is true. Debts are inked onto skin, history
is edited weekly, and inconvenient people are simply *struck out*. Everyone knows the system is rotten; most people
are too busy surviving to care. Then the Blank arrived: a white, silent nothing that eats whatever it touches, ink
and all.

### Regions (linear order)

| # | Region | Mood | Hook |
|---|---|---|---|
| 1 | **The Frayed Meadow** | Pastoral, wrong at the edges | Grass grows in half-sentences. Starting area and prototype map |
| 2 | **Hollowmark** (town) | Seedy market town | Mercenary guild, cabaret, the Concord's tax office. Hub for Act 1 |
| 3 | **The Gutterwoods** | Fungal, wet, whispering | Trees grow from discarded letters. Poisoners live here |
| 4 | **Saint Ledger's Abbey** | Gothic, candlelit | Monks who copy the Ledger by hand, forever, in blood |
| 5 | **The Velvet Causeway** | Decadent bridge-city on a lake of ink | Masquerades, duels, the Marquise's home turf |
| 6 | **The Unfinished Coast** | Half-erased shoreline | The sea stops mid-wave. Ships sail into white |
| 7 | **The Gilded Spire** | Capital, gold and rot | The Great Ledger itself. Concord's last stand |
| 8 | **The Margin** | Pure surreal void | Final dungeon inside the Blank |

## 8. Story

### Premise

Reality is being eaten by a hungry Blank spreading across the map. The Concord's answer is to write faster
("the Ledger says we are fine"). It does not work.

### The protagonist: the Unwritten

Silent by design *and* by story. The protagonist was eaten by the Blank and, impossibly, **spat back out**, without
a name, a voice, or a Ledger entry. Officially they do not exist. Mechanically this means the Blank treats them
oddly: they can walk short distances into it, and the **Inkblade** they wake up holding can "re-write" small things
the Blank has taken. Other characters project wildly different personalities onto the silent hero, which is a
running joke. Default name: **Ash** (player can rename).

### The villains: a duo

**1. Saint Verity Hale, "the Eraser"** (the sympathetic antagonist with a point)
Former Chief Archivist of the Great Ledger. She spent twenty years reading the *unedited* drafts: every massacre
the Concord wrote out of history, every family struck out for unpaid debt, every lie made true. She concluded the
world cannot be fixed by editing, because the editors are the disease. Her answer: **a clean page**. She opened the
way for the Blank and guides its hunger, aiming it at Concord strongholds first.

Her point lands: the Concord *is* monstrous, and the heroes will see it. She is polite, tired, funny in a dry way,
and genuinely mourns what she erases. She believes she will be the last thing eaten, and is at peace with it.

**2. The Vacancy** (the cosmic horror)
The Blank is the edge of something. The Vacancy is what exists in the space before anything was written: an
appetite that experiences existence as noise. It does not hate; it *corrects*. It speaks only in redacted text
(lines of black bars with the occasional terribly clear word). Verity thinks the Vacancy is a tool, a mercy with
no will of its own. She is wrong. It has been steering her the whole time, and it has no intention of stopping at
the Concord, or at the world. The Unwritten, spat back out, is the one thing it has ever *failed to digest*, and it
wants them back.

**Their dynamic:** Verity is the face the player argues with; the Vacancy is the shadow behind her that grows
more visible each act. The midgame twist is not that Verity is evil, but that she is losing control and refuses to
admit it.

### Outline (simple, linear, about 2 to 4 hours)

**Prologue: Spat Out** (Frayed Meadow, ~10 min)
Ash crawls out of the Blank's edge. Nibblers (small hungry blank-creatures) attack. Brannoc Coil, a mercenary
paid to "check out the static," finds Ash and decides an unregistered person is either worthless or priceless.
Tutorial: movement, attack, power gauge, swapping heroes. *(This is the current prototype.)*

**Chapter 1: No Such Person** (Hollowmark, Gutterwoods, ~35 min)
The Concord tax office cannot process someone with no Ledger entry, so Ash is arrested for "existing without
authorization." Bran breaks Ash out (for a fee, payable later). Recruit **Mother Gristle** in the Gutterwoods, who
heals the party and bills them for it. Boss: **The Auditor**, a Concord enforcer who strikes people out with a quill
the size of a lance. First glimpse of Verity, watching from the edge of the Blank as it eats the tax office.

**Chapter 2: The Copying Monks** (Saint Ledger's Abbey, ~30 min)
The monks are hand-copying the Ledger to "back up reality." It is not working; they are copying blank pages and
going mad. Recruit **Corporal Ninefingers**, a deserter hiding in the crypts. Verity confronts the party here
for the first time and *does not fight*. She shows them an unedited page: the Abbey was built on a mass grave the
Concord wrote out. Boss: **The Abbot Who Copied Himself** (many copies, one real).

**Chapter 3: Masquerade** (Velvet Causeway, ~40 min)
The Concord's elite throw a masquerade while the city drowns in ink. Recruit **Lysandre, the Velvet Marquise**
(duelist, flirt, obvious liar) and **Saffron Kiss** (cabaret singer whose voice makes things briefly real).
Optional recruit: **Hex & Tally**. Twist: Lysandre is a Concord spy assigned to bring Ash in, because the Concord
wants to dissect the one person the Blank spat out. Player chooses dialogue tone, but the story stays linear;
Lysandre stays (she has fallen for the party, or at least for their odds). Boss: **The Host**, a party guest who is
mostly mouth.

**Chapter 4: The Sea Stops** (Unfinished Coast, ~30 min)
The Vacancy speaks for the first time, through a drowned lighthouse keeper, in redacted text. Recruit **Ilse of the
Mirror**, a knight who is actually a reflection that walked out of her mirror when the original was erased. Verity
realizes the Blank is eating places she did not aim it at. She does not tell anyone. Boss: **The Tide That Forgot**.

**Chapter 5: The Gilded Spire** (~35 min)
The party storms the capital, alongside or against Verity depending on the scene (still linear). The Concord's
High Scribes try to write the Blank out of existence and instead get erased mid-sentence. Verity reaches the Great
Ledger and finally understands: the Vacancy was never her tool. It possesses her. Boss: **Verity, Unmade**, a
tragic fight where she resists the Vacancy between phases.

**Chapter 6: The Margin** (~25 min)
Ash leads the party into the Blank. Surreal final dungeon: places from earlier chapters, half-remembered, with
scenery written as words instead of pictures. Verity's surviving fragment helps from inside. Final boss: **The
Vacancy**, fought as a page that keeps erasing your HUD.

**Ending.** The last ink in the world goes into one final line. The Vacancy is driven back, not destroyed. The world is smaller, scarred, and *unwritten*: the Ledger
is gone, so nothing is true just because the Concord said so. Verity got her clean page, just not the way she
wanted it. Bran sends Ash an invoice.

## 9. Hero roster (8)

Flavor targets: **morally grey mercenaries** and **glamorous/flirty** types, with the weird edge of the setting.
All heroes share the paper-doll rig; differences come from layers, palettes, weapon and AI personality.

| Hero | Flavor | Weapon / Ink | Role | Where recruited | Hook |
|---|---|---|---|---|---|
| **Ash, the Unwritten** | Silent protagonist | Inkblade (sword), any Ink | All-rounder | Prologue | Spat out by the Blank; can briefly walk inside it |
| **Brannoc "Bran" Coil** | Mercenary | Axe, Red Ink | Tank / bruiser | Prologue (Frayed Meadow) | His contract is tattooed on his arm and tightens if he breaks it. Will absolutely sell you out if outbid, and tells you so |
| **Mother Gristle** | Mercenary | Staff, Green + Gold Ink | Healer / poisoner | Gutterwoods | Charges per heal (gold counter in the UI as a joke). Her poisons and her medicines are the same bottles |
| **Corporal "Ninefingers" Daro** | Mercenary (deserter) | Crossbow, Black Ink | Ranged DPS | Saint Ledger's Abbey | Deserted the Concord army after being ordered to strike out a village. Sharpest tongue in the party |
| **Lysandre, the Velvet Marquise** | Glamorous / flirty, spy | Rapier, Blue Ink | Fast duelist | Velvet Causeway | Flirts with everyone, including enemies, mid-fight. Secretly sent to capture Ash |
| **Saffron Kiss** | Glamorous / flirty | Whip, Gold Ink | Support / buffer | Velvet Causeway | Cabaret singer whose voice makes things exist for a few seconds. Buffs are literally songs |
| **Hex & Tally** | Mercenary con artists | Knuckles, Black Ink | Trickster / debuffer | Velvet Causeway (optional) | A grifter and her talking shadow, who signs the contracts she does not want to honor |
| **Ilse of the Mirror** | Glamorous, unsettling | Spear, Blue + White Ink | Lancer / counter | Unfinished Coast | A reflection whose original was erased. Vain, gorgeous, and the only hero besides Ash who can touch White Ink |

Prototype implements **Ash** (player) and **Bran** (AI ally).

### Banter

Short, skippable party banter triggers while walking (two or three lines, top of screen, no pause). This carries
most of the humor without slowing the linear story.

## 10. Tone and rating

Weird/surreal dark fantasy with sharp humor. **Mature**: strong violence, death, cruelty of institutions, drugs and
alcohol, innuendo and flirting. **No explicit sexual content.** Gore is stylized (ink, not blood, for most enemies).

## 11. Controls (current)

| Action | Keyboard | Gamepad | Touch |
|---|---|---|---|
| Move | WASD / arrows | Left stick / d-pad | Left on-screen stick |
| Attack | J / Space / Z | A (bottom face) | Attack button |
| Swap hero | Tab / Q | Y (top face) | Swap button |
| Pause menu | Esc / P | Start | Pause button (top right) |

## 12. Milestones

1. **Prototype (this PR):** one area, movement, one attack with power gauge, one enemy type, one AI ally, hero swap, web build on GitHub Pages.
2. **Vertical slice:** CC0 tileset and enemy sprites, paper-doll hero sprites, quick menu, abilities on hotkeys, save/load, the Prologue playable start to finish.
3. **Systems pass:** levels, gear, weapon skill levels, skill trees, quest log, fast travel, options menu.
4. **Content:** Chapters 1 to 6, bosses, recruits, banter.
5. **Polish:** music and SFX (CC0), portraits, balancing, accessibility.
