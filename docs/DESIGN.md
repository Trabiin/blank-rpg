# Last Ink: Design Document

> An action RPG in the spirit of 90s Secret of Mana and Final Fantasy, fused with empire management:
> you hold the last written town against a hungry Blank, recruit dozens of misfits to run it, and lead a
> party into the field on missions. Modern quality of life. Weird, dark, funny. Rated Mature.
>
> Title: **Last Ink**. Repo: `Trabiin/last-ink` (renamed from `blank-rpg`).

---

## 1. Pillars

1. **Two halves, one fight.** Running the empire and going on missions are an even split, and each feeds the
   other: missions reclaim land, find recruits and loot; the empire turns that into Ink, wards, gear and new missions.
2. **Real-time party combat that feels good.** Snappy movement, a weighty swing, readable enemy tells.
3. **No ring menus, ever.** Hotkeyed abilities plus clean list-based menus. Every action is two presses or fewer.
4. **A world that is visibly being eaten.** The Blank is on the territory map and on the mission maps. It moves on
   a clock, it moves faster when you neglect things, and it takes what you built.
5. **People are the resource.** About 50 recruits, each good at something. Who you put where matters more than
   any number in a menu, and about 20 of them are people you get to know properly.
6. **Dark, but with a grin.** Grim stakes, mercenaries who bicker, villains who are sometimes right.
7. **Respect the player's time.** Save anywhere, autosave, adjustable speed and difficulty, the clock never runs
   while you are in a fight, no random encounters. MVP about 4 hours; full game 15 to 20 hours.

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

## 4. Game structure: Command and Missions

The game alternates between two layers that share one save, one roster and one clock.

| | **Command** (empire) | **Missions** (action RPG) |
|---|---|---|
| Where | Hollowmark (a small walkable hub town) and the **territory map** | Hand-built mission maps in the provinces |
| Clock | Runs in real time (adjustable speed, pausable) | **Frozen.** No timers move while you are on a mission |
| You do | Build, assign recruits, research, send expeditions, negotiate, answer Blank surges, talk to people | Fight with a party of 3, reclaim land, rescue recruits, story chapters and bosses |
| Menus | List menus and panels from the Command Table, hotkeys for common actions | Pause menu, quick menu, hotkeyed abilities |

**The loop.** Check the territory map, see where the Blank is pushing, spend resources and staff to shore things
up, pick a mission, play it, come back with loot, land and maybe a new recruit, repeat. Story chapters are
missions too: they unlock on the map when you have met their conditions (renown, a building, a province held).

**Why the hub is walkable.** Hollowmark is where the roster lives. Recruits you have placed show up at their posts
(the forge, the infirmary, the tavern), so the town visibly fills up as you grow, and talking to people is how the
relationship side happens. Anything you can do on foot you can also do from the Command Table menus, so walking is
never required.

## 5. Empire management

### 5.1 The clock

- While in Command, the **day clock** runs in real time: 1 in-game day is about 4 real minutes at normal speed.
- Speed controls: **pause, 1x, 2x, 4x**, on hotkeys and on screen. Pausing is free and unlimited.
- Construction, research, expeditions, envoy trips and the Blank all advance on this clock.
- **On a mission the clock is frozen.** Leaving for a mission and coming back costs no time.
- Mission availability can still expire on the clock (a Blank surge you ignore for two days resolves without you).

### 5.2 The territory map

The Inklands are split into **provinces**, connected by roads. The MVP map has about **8 provinces** around
Hollowmark; the full game has about **24** across five regions.

Each province shows:
- **Fray** (0 to 100): how far the Blank has eaten into it. At 100 it is **Erased**: it turns paper-white,
  stops producing, and anything built there is lost. Recruits stationed there flee back to Hollowmark, hurt.
- **Owner**: yours, unclaimed, a faction's, or erased.
- **Output**: what it gives per day when you hold it (Gilt, Supplies, sometimes Ink).
- **Governor** slot and one or two **site** slots (a mine, a lamp post, a shrine) that can be developed.
- Available **missions**, marked with an icon and, if timed, a countdown.

### 5.3 The Blank

The Blank advances on its own and gets worse when you give it openings:

- **Base spread:** every province bordering the Blank gains Fray each day.
- **Faster when:** a province has no governor, sits next to an erased province, has unrepaired damage from a
  surge, or when a story choice or Verity's plans aim it there. Each source is listed in the province panel, so the
  player can always see *why* it is moving.
- **Slower when:** a governor with good Grit is posted, a **Wardlamp** burns there, or research says so.
- **Surges:** every few days the Blank lunges at one province. It appears as a timed **Defense mission**. Win it to
  knock that province's Fray down; ignore it and the Fray jumps.
- **Reclaiming:** an erased province can be taken back with a **Reclaim mission** (fight to the Blot at its heart
  and break it) plus an Ink cost to rewrite the land.
- **Losing:** if Hollowmark itself is erased, the game is over (reload). Losing other provinces hurts but is
  recoverable, which keeps the pressure real without being a fail-state treadmill.

### 5.4 Resources

Three resources, kept deliberately few:

| Resource | From | Spent on |
|---|---|---|
| **Gilt** (money) | Province output, the Market, mission loot, trade deals | Construction, hiring, gear, bribes |
| **Supplies** | Province output, expeditions | Recruit upkeep (each recruit eats), construction, expeditions |
| **Ink** | The Inkworks, reclaimed provinces, rare mission finds | Rewriting reclaimed land, Wardlamps, research, top-tier gear |

Plus **Renown**, a meter that only goes up: it grows with missions, holdings and story, and unlocks recruits,
faction interest and story chapters.

### 5.5 Recruits and roles

About **50 recruits** in the full game (about 12 to 15 in the MVP). Everyone has four stats and one or two traits:

- **Might** (fighting, defense), **Craft** (building, forging, production), **Lore** (research, Ink, the
  Blank), **Charm** (diplomacy, trade, morale). Plus **Grit**, a hidden-ish modifier for holding a Blank-touched
  province.
- Traits change outcomes in readable ways: *Greedy* (+Gilt, -faction standing), *Night Owl*, *Ink-sick*,
  *Ex-Concord*, *Flirt*, *Coward*, and so on.

A recruit can hold **one role at a time**:

| Role | What it does |
|---|---|
| **Party** | Fights on missions. Only recruits with a combat kit can do this (about 12 in the full game, 4 in the MVP) |
| **Governor** | Runs a province: raises its output and slows its Fray, based on stats and traits |
| **Staff** | Works a building in Hollowmark (each building has 1 to 3 slots); stats drive the building's effect |
| **Expedition** | Goes on an off-screen squad mission (below) |
| **Researcher** | Works in the Scriptorium; Lore drives research speed |
| **Envoy** | Represents you with a faction; Charm drives results |

Recruits come from story missions, rescue missions, reclaimed provinces, the Guildhall (hire for Gilt),
buildings that attract certain people (open a cabaret and singers come), and faction deals.

**Governors in the MVP** (numbers in `scripts/empire.gd` and `data/provinces.json`): each province **wants** one
stat (Hollowmark Charm, Old Mill Craft, Lampwick Lore, the Meadow and Saltreed Grit, and so on). A governor with 7+
in it is a **good fit** (+50% of the province's output, Fray 1 slower); 3 or less is a **poor fit** (-25%, Fray 1
faster). On top of that Grit slows Fray, Charm adds Gilt, Craft adds Supplies, and traits chip in (Stubborn,
Coward, Greedy, Ink-sick, Ex-Concord). A province you hold with **no governor** frays +3 a day and delivers 25%
less. **Claiming:** an unclaimed province next to your land can be claimed from the Command Table (G) for Gilt and
Supplies; someone has to go and run it, so every claim costs a recruit. Faction land waits for diplomacy, erased
land for Reclaim missions.

### 5.6 Buildings (Hollowmark)

Built and upgraded from the Command Table; each appears in the walkable town when finished.

| Building | Effect | MVP |
|---|---|---|
| **Command Table** | The territory map and all management menus | Yes (from the start) |
| **Barracks** | Party training (XP over time for benched fighters), more party options | Yes |
| **Infirmary** | Heals injured recruits faster; staff with Lore | Yes |
| **Inkworks** | Produces Ink; output scales with Craft staff and Ink provinces held | Yes |
| **Scriptorium** | Research | Yes |
| **Guildhall** | Hire recruits, launch expeditions | Yes |
| **Market** | Gilt income and a shop | Later |
| **Forge** | Gear crafting and upgrades | Later |
| **Tavern / Cabaret** | Morale, relationship scenes, attracts certain recruits | Later (tavern is walkable from the start) |
| **Wardlamp** (built in a province) | Slows Fray there | Yes |

How it works in the MVP (numbers in `data/buildings.json`): every building has 3 levels, each costing Gilt,
Supplies and sometimes Ink, and taking 1 to 4 days on the clock. Hollowmark has **one building crew**, so only
one building is built or upgraded at a time; Wardlamps are put up by locals and can go up alongside. Each level
adds staff slots, and one stat drives each building: Command Table (Craft: quartermaster cuts upkeep; levels
give earlier surge warnings), Barracks (Might: party max HP on missions), Infirmary (Lore: faster healing),
Inkworks (Craft: Ink per day, needs a worker), Scriptorium (Lore: Insight banked for research, Bookish counts
double), Guildhall (Charm: contract Gilt; each level lets one more expedition squad be out at once; hiring arrives later). Wardlamps
have 2 levels (-1 and -2 Fray a day) and go out if their province is erased.

### 5.7 Expeditions

Send a squad of 2 to 4 recruits on a timed off-screen mission: scouting, salvage, escort, a supply run, a rescue.
Before sending, the panel shows the **success chance** and what drives it (stats, traits, pairings). Results come
back as a short written report, often funny, sometimes grim: loot, recruits, injuries, rarely a loss. Expeditions
are how the non-fighters see the world and how the player gets value from a big roster without playing every
mission by hand.

**Expeditions in the MVP** (jobs in `data/expeditions.json`, rules in `scripts/empire.gd`, screen E): the Guildhall
offers about 8 jobs tied to provinces (forage, salvage, escort, scouting, three rescues that bring in Mother
Gristle, Sister Abeyance and Corporal Daro, and a deadly Ink run at the erased edge). Each job wants one or two
stats; squad strength is the sum of those stats over the two strongest members plus half for each extra member, and every point above or below the job's target
moves the chance 4% from 50% (5% to 95%). Traits and pairings add or subtract (Coward on dangerous jobs, Night Owl
on scouting and rescues, Ink-sick near the Blank, Ex-Concord on Tithe Road, Bran and Daro together, Quill and
Tobble bickering). Rations cost Supplies per person. People on an expedition leave their job and town until they
are back. One squad out per Guildhall level. Success pays the job's reward (a fifth of the time half again);
failure pays a quarter and hurts people; on deadly jobs a failed squad can lose a light recruit for good (core
and field characters come back badly hurt instead). Every return writes a short report.

### 5.8 Research

A small tree in the Scriptorium with four branches: **Wardcraft** (Fray resistance, Wardlamps, reclaim costs),
**Logistics** (upkeep, expedition speed and odds), **Inkcraft** (abilities and Ink magic for the party), **Arms**
(gear tiers). About 12 nodes in the MVP, about 40 in the full game.

**As built (MVP, PR for #48):** 4 branches of 3 nodes, each a chain (data/research.json; screen on T). A node costs
Insight (the top tier also Ink and Scriptorium level 2), paid once when you first start it. Study then runs on the
Command clock: 2/3/4 days at 100% pace, and pace is 100% + 5% per point of researcher Lore (Bookish counts double)
+ 25% per Scriptorium level past 1. One node at a time; switching sets the old one aside with its progress kept.
No researcher at work = stalled. Effects: Wardcraft (Fray -1 in every held province; Wardlamps -1 more; surges
warned a day sooner and hit for 8), Logistics (upkeep -1 per 4 people; expeditions 25% shorter; +10% expedition
odds), Inkcraft (+1 Ink at the Inkworks; faster revives; -25% damage taken on missions), Arms (+2 damage; +10 max
HP; +3 damage and a faster attack gauge). Reclaim costs and Ink abilities join these branches once #51 and #7 exist.

### 5.9 Diplomacy

Factions each have a **standing** with you (hostile to allied). Envoys can open trade, ask for aid during a surge,
buy peace, or gather intel. Factions also react to what you do on missions.

| Faction | Wants | MVP |
|---|---|---|
| **The Gilded Concord** | You registered, taxed, or dissected | Yes (hostile) |
| **The Mercenary Guild** | Paid | Yes |
| **The Gutterwood Coven** | Left alone, and the Blank kept out of the woods | Yes |
| **Saint Ledger's Abbey** | Copies of everything | Later |
| **The Velvet Nobility** | Entertainment and leverage | Later |
| **The Erasers** (Verity's followers) | A clean page | Later |

**As built (MVP, PR for #49):** data/factions.json; screen on F. Standing runs -100 to +100 in five tiers: Hostile,
Wary (-39), Neutral (-9), Friendly (20), Allied (60). Start: Guild +5, Coven -15, Concord -55. One **envoy** per
faction (a recruit role; they live with the faction, away from Hollowmark) wins standing every day: 1 + Charm/3
(Flirt doubles Charm), +1 if the stat the faction respects is 7+ (Guild Might, Coven Lore, Concord Charm), -1 if 3 or
less; Greedy -1, Ex-Concord -2 with the Concord, Contracted +1 with the Guild, Ink-sick +1 with the Coven. The
Concord files against you (-1 a day, down to -80) unless someone is posted there. **Deals** (all need an envoy):
gift (any tier, coin for +8/+10 standing), intel (Neutral: Insight and +1 day of surge warning for 5 days), trade
pact (Friendly: daily Gilt/Supplies/Ink in the ledger, torn up if standing drops below 0), aid (Friendly, while a
surge gathers against your land: it lands at half, -15 standing), cede (Allied, Guild and Coven only: their
province becomes yours, -30 standing, then it needs a governor). **Friendly perks:** Guild +10% expedition odds,
Coven -1 Fray a day on your land next to the Gutterwoods, Concord stops auditing and +2 Gilt a day. **Trouble:** a
Hostile Concord fines you, seizes Supplies or reads Erasure writs (+6 Fray) every 4-6 days; Wary, it only fines,
every 7-9 days. **Reactions:** claiming land next to the Coven (-6) or Concord (-4), land next to the woods being
erased (Coven -10), a Wardlamp lit next to the woods (Coven +4), and expeditions: the Guild barge escort (+6, -3
on failure), finding the hedge-witch before the Coven does (-8), springing Daro from the Concord (-8). Story
missions will call the same hook (Empire.faction_react) once they exist.

### 5.10 Relationships

About **20 core characters** (all the combat heroes plus the most important staff) have relationships:

- A **bond rank** (0 to 5) that rises from missions together, conversations in Hollowmark, choices, gifts and
  having them in roles they like.
- Each rank unlocks a short scene, and higher ranks unlock a perk (a combat technique, a building bonus) and a
  **personal mission**.
- Some bonds can turn romantic (flirty, innuendo, never explicit), and some characters dislike each other:
  posting rivals together has effects, good or bad.
- Every core character gets an epilogue line that depends on their bond and fate.

**Built (MVP, `data/bonds.json`, Bonds screen on H):** six bonds: Bran, Mother Gristle and Daro (field) plus
Quill, Tobble and Sister Abeyance (core staff). Ranks need 6/16/30/46/64 points. Points: +2 for the first chat of
the day in Hollowmark, +2 a day in a liked role, -1 a day in a disliked one, +2 for a successful expedition, +1 per
8 kills fighting beside Ash (max 4 per mission), and +0 to +3 from the one choice in each rank scene (Ash never
speaks; choices are gestures). Points never drop below the current rank and stop at the next rank until its scene
is seen: the person gets a heart over their head in town and "wants a word". Each person has five rank scenes
(replayable from the Bonds screen), perks at ranks 3 and 5 (mission HP/damage/revives, healing, expedition odds,
surge warning, daily Gilt/Supplies/Insight, study pace), and a **personal job** on the Guildhall board at rank 4
that they must go on; rank 5 needs it done. Scenes use a placeholder visual-novel layout (code-drawn bust, text
box) that the AI portraits (#12) and the dialogue system (#11) will replace. Rivalries are still only the
expedition pair modifiers.

The other ~30 recruits are lighter: a trait, a couple of lines, a reason to recruit them, and a quip in
expedition reports.

### 5.11 Missions

| Type | What happens | Source |
|---|---|---|
| **Story** | Scripted chapter missions with dialogue and bosses | Unlock by story conditions |
| **Reclaim** | Push into an erased province, break the Blot | Any erased province |
| **Defense** | Hold a province against a Blank surge | Timed events |
| **Rescue / Recruit** | Find someone in a dangerous spot | Rumors, expeditions, factions |
| **Raid / Salvage** | Grab resources from a contested place | Map, factions |
| **Personal** | A core character's story | Bond rank |

Mission maps are hand-built text maps; non-story missions reuse a pool of maps with different spawns, objectives
and Blank positions so the content stretches without feeling copy-pasted.

## 6. Combat

**Real-time**, Mana-inspired, minus the ring.

- **Attack power gauge.** Each hero has a power gauge that refills after every swing (about 1.1 s). Swinging early
  still hits, but for proportionally less damage. A full gauge does full damage; a full gauge held for 1 s more
  becomes a **charged tech** (later milestone).
- **Abilities on hotkeys.** Each hero has up to 4 abilities mapped to keys 1-4 / gamepad shoulder + face buttons.
  Using one does not pause; it costs **Ink** (MP).
  **As built (#7):** data/abilities.json + scripts/abilities.gd. Each field hero has an Ink pool (10-14) that refills
  0.4/s and +1 per full-power hit that lands (Spring Tapping research: 25% faster). Two abilities each: Ash Rewrite
  (party heal + shield) and Strikethrough (dash), Bran Cleave (wide Red Ink arc) and Hold the Line (taunt + half
  damage), Gristle Poultice Toss and Scald, Daro Long Thrust and Pike Sweep. Keys 1-4, gamepad LB/RB/LT/RT, touch
  buttons around Attack. Allies fire them on simple rules (hurt ally, crowd, target in range, leader threatened).
- **Quick menu.** One button opens a list menu that slows time to 10% (not a full pause). Tabs: Items, Abilities,
  Party (swap leader, set AI behavior), Equip. Fully navigable by d-pad, mouse/touch, or hotkeys.
- **Party of 3.** You control one hero; two AI allies follow. Swap control instantly with one button.
- **Ally AI presets** (set per hero in the Party tab): *Aggressive*, *Balanced*, *Keep Distance*, *Support*. AI waits
  for a full power gauge before striking so allies hit meaningfully.
- **Visible enemies with tells.** Every enemy attack has a wind-up (flash or crouch) so dodging by movement is always possible.
- **Downed, not dead.** Heroes at 0 HP are downed and can be revived by items or by standing next to them for 3 s
  outside combat. If all three go down, you reload the latest autosave.

## 7. Progression

Party progression (per fighter), on top of the empire's own progression (buildings, research, provinces):

1. **Levels and gear.** XP raises HP, Ink and base stats. Gear: weapon, armor, one trinket per hero.
   MVP (issue #15, numbers in `data/gear.json`): every enemy gives XP to the whole party (a Blot gives more), a
   finished mission adds a bonus, and the Barracks drills benched fighters for XP each day. Each hero has their
   own weapon line (start weapon plus two upgrades, the best needing research); armor and trinkets fit anyone.
   Gear is bought at Tobble's Stall (K in town or on the Command Table, half price back when selling) or found
   on missions (rare drops, kept unless the party is wiped). Equip from the Gear screen (K, or Party gear in the
   pause menu mid-mission, where it applies at once). Consumables are the quick menu's satchel (#6).
2. **Weapon and Ink skill levels (Mana-style).** Using a weapon type or Ink color raises its skill level (cap 5),
   unlocking a charged tech per level for weapons, and stronger spell tiers for Inks.
3. **Per-hero skill trees.** Each hero has a small tree (about 10 nodes, two branches) bought with Skill Points from levels.
   Branches reflect personality (e.g. Bran: *Bodyguard* vs *Turncoat*).

Weapon types: sword, axe, spear, rapier, crossbow, whip, knuckles, staff.
Ink colors (magic): **Red** (fire), **Blue** (frost), **Gold** (light, healing), **Green** (growth, poison),
**Black** (gravity, debuffs), **White** (only the Blank and its servants use it: erasure).

## 8. Quality of life

- **Save anywhere** (pause menu, three slots) plus **autosave** every minute when safe, on returning from a
  mission, and on quitting.
- **Clock speed** (pause, 1x, 2x, 4x) in Command; the clock never runs during missions.
- **Adjustable battle speed** (0.75x to 1.25x) and **difficulty** (Story, Normal, Hard), changeable at any time.
  Difficulty also scales the Blank's spread.
- **Objectives and alerts:** the current story goal is pinned; Blank surges, finished buildings and returning
  expeditions raise a notice with a "go there" button.
- **Assign screens show consequences up front** (output, Fray slowdown, success chance) before you commit.
- **No random encounters.** Enemies are visible on the field and avoidable.
- Remappable controls, text speed, screen shake toggle, colorblind-safe telegraphs.

## 9. World

A **hub and territory map** instead of one connected overworld. Hollowmark is the hub. The rest of the world is
the territory map of provinces; you travel by picking a mission there. The Blank spreads from the east across that
map and into the mission maps themselves (its edge is visible in the field, as in the prototype). Erased provinces
can be reclaimed, so places you lost come back scarred.

**The setting: the Inklands.** A once-gaudy empire where reality is literally *written*. The ruling
**Gilded Concord** keeps the Great Ledger, and whatever the Ledger says is true. Debts are inked onto skin, history
is edited weekly, and inconvenient people are simply *struck out*. Everyone knows the system is rotten; most people
are too busy surviving to care. Then the Blank arrived: a white, silent nothing that eats whatever it touches, ink
and all.

### Regions

Each region is a group of provinces on the territory map, opened up roughly in story order.

| # | Region | Mood | Hook |
|---|---|---|---|
| 1 | **The Frayed Meadow** | Pastoral, wrong at the edges | Grass grows in half-sentences. Starting area and prototype map |
| 2 | **Hollowmark** (town) | Seedy market town | **The hub.** Mercenary guild, a tavern, the Concord's tax office until the Blank eats it |
| 3 | **The Gutterwoods** | Fungal, wet, whispering | Trees grow from discarded letters. Poisoners live here |
| 4 | **Saint Ledger's Abbey** | Gothic, candlelit | Monks who copy the Ledger by hand, forever, in blood |
| 5 | **The Velvet Causeway** | Decadent bridge-city on a lake of ink | Masquerades, duels, the Marquise's home turf |
| 6 | **The Unfinished Coast** | Half-erased shoreline | The sea stops mid-wave. Ships sail into white |
| 7 | **The Gilded Spire** | Capital, gold and rot | The Great Ledger itself. Concord's last stand |
| 8 | **The Margin** | Pure surreal void | Final dungeon inside the Blank |

## 10. Story

### Premise

Reality is being eaten by a hungry Blank spreading across the map. The Concord's answer is to write faster
("the Ledger says we are fine"). It does not work. Somebody has to actually hold the line, and the only person
free to do it is someone who, legally, does not exist.

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

### How the story fits the empire

The main story stays **linear**: chapters happen in a fixed order. What changes is that each chapter is a
**story mission** on the territory map, and between chapters the player runs Hollowmark, takes side missions and
fights the Blank at their own pace. A chapter unlocks when its conditions are met (for example: hold the
Gutterwoods, have an Infirmary, reach a renown level), so the empire side gates and paces the story without
branching it. Recruits named below are the story recruits; most of the ~50 come from the empire side.

The big structural addition is the end of Chapter 1: **Ash takes over Hollowmark**. The Concord's tax office is
eaten, the governor flees, and the town is leaderless. Nobody can legally run it, so the one person with no Ledger
entry ends up in charge, which the Concord considers a clerical nightmare and Bran considers a business opportunity.

### Outline (about 15 to 20 hours with the empire layer; the MVP covers the Prologue and Act 1)

**Prologue: Spat Out** (Frayed Meadow, ~10 min)
Ash crawls out of the Blank's edge. Nibblers (small hungry blank-creatures) attack. Brannoc Coil, a mercenary
paid to "check out the static," finds Ash and decides an unregistered person is either worthless or priceless.
Tutorial: movement, attack, power gauge, swapping heroes. *(This is the current prototype.)*

**Chapter 1: No Such Person** (Hollowmark, ~30 min)
The Concord tax office cannot process someone with no Ledger entry, so Ash is arrested for "existing without
authorization." Bran breaks Ash out (for a fee, payable later). First glimpse of Verity, watching from the edge of
the Blank as it eats the tax office. The governor flees; Hollowmark is leaderless. **Ash takes the town.** The
Command Table, the territory map and the clock switch on here.

**Act 1 command phase** (~2.5 hours in the MVP)
Build up Hollowmark, take the provinces around it, answer surges, hire and place recruits. Story missions in this
phase: recruit **Mother Gristle** in the Gutterwoods (who heals the party and bills them for it), rescue
**Corporal Ninefingers** from a Concord press gang (moved up from Chapter 2), and deal with the Concord's answer to
an unregistered town. Act 1 ends with the boss **The Auditor**, a Concord enforcer who strikes people out with a
quill the size of a lance, sent to strike out Hollowmark itself. Verity sends a polite letter afterward. **MVP ends
here.**

**Chapter 2: The Copying Monks** (Saint Ledger's Abbey, ~30 min)
The monks are hand-copying the Ledger to "back up reality." It is not working; they are copying blank pages and
going mad. The Abbey can become an ally faction. Verity confronts the party here
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

## 11. Roster

Flavor targets: **morally grey mercenaries** and **glamorous/flirty** types, with the weird edge of the setting.
All characters share the paper-doll rig; differences come from layers, palettes, weapon and AI personality.

The roster has three tiers:

| Tier | Count | Who | Depth |
|---|---|---|---|
| **Field heroes** | ~12 (4 in MVP) | Can join the party on missions; also can take any other role | Core: bonds, personal missions, banter |
| **Core staff** | ~8 (3 to 4 in MVP) | Non-fighters who matter: the quartermaster, the head scribe, the tavern keeper... | Core: bonds, scenes, personal missions done by the party |
| **Recruits** | ~30 (6 to 8 in MVP) | Everyone else: specialists, oddballs, defectors | Light: trait, quips, one recruitment hook |

### Field heroes (story)

| Hero | Flavor | Weapon / Ink | Role | Where recruited | Hook |
|---|---|---|---|---|---|
| **Ash, the Unwritten** | Silent protagonist | Inkblade (sword), any Ink | All-rounder | Prologue | Spat out by the Blank; can briefly walk inside it |
| **Brannoc "Bran" Coil** | Mercenary | Axe, Red Ink | Tank / bruiser | Prologue (Frayed Meadow) | His contract is tattooed on his arm and tightens if he breaks it. Will absolutely sell you out if outbid, and tells you so |
| **Mother Gristle** | Mercenary | Staff, Green + Gold Ink | Healer / poisoner | Gutterwoods | Charges per heal (gold counter in the UI as a joke). Her poisons and her medicines are the same bottles |
| **Corporal "Ninefingers" Daro** | Mercenary (deserter) | Crossbow, Black Ink | Ranged DPS | Act 1 (rescue mission) | Deserted the Concord army after being ordered to strike out a village. Sharpest tongue in the party |
| **Lysandre, the Velvet Marquise** | Glamorous / flirty, spy | Rapier, Blue Ink | Fast duelist | Velvet Causeway | Flirts with everyone, including enemies, mid-fight. Secretly sent to capture Ash |
| **Saffron Kiss** | Glamorous / flirty | Whip, Gold Ink | Support / buffer | Velvet Causeway | Cabaret singer whose voice makes things exist for a few seconds. Buffs are literally songs |
| **Hex & Tally** | Mercenary con artists | Knuckles, Black Ink | Trickster / debuffer | Velvet Causeway (optional) | A grifter and her talking shadow, who signs the contracts she does not want to honor |
| **Ilse of the Mirror** | Glamorous, unsettling | Spear, Blue + White Ink | Lancer / counter | Unfinished Coast | A reflection whose original was erased. Vain, gorgeous, and the only hero besides Ash who can touch White Ink |

Four more field heroes are still to be designed for the full game (to reach about 12), plus the core staff and the
recruit pool. Prototype implements **Ash** (player) and **Bran** (AI ally).

### Core staff (first ideas, MVP picks marked)

| Character | Post | Hook |
|---|---|---|
| **Quill Marrow** (MVP) | Quartermaster at the Command Table | A former Concord clerk who kept Hollowmark's books and now cooks them for you. Knows where every coin is buried |
| **Sister Abeyance** (MVP) | Head of the Scriptorium | Ran away from the Abbey with one stolen page that rewrites itself every night |
| **Old Tobble** (MVP) | Tavern keeper | Has been "about to retire" for thirty years. Hears everything; sells most of it |
| **Vane & Vesper** | Inkworks | Twin chemists who disagree about everything except that the ink is alive |

### Recruit pool (examples of the light tier)

A gravedigger who digs too fast, a Concord tax collector with a conscience, a cartographer who maps places before
they exist, a cabaret bouncer, a choir of three orphans who share one voice, a debt-tattooed blacksmith, a smuggler
who only moves cargo at night, a dog that might be a person. Each brings a trait and a stat spread, a few lines,
and a recruitment hook (a rescue, a bribe, a building, a faction, a choice).

### Banter

Short, skippable party banter triggers while walking (two or three lines, top of screen, no pause), and in
Hollowmark people at their posts comment on what is happening in the empire. This carries most of the humor
without slowing the story.

## 12. Tone and rating

Weird/surreal dark fantasy with sharp humor. **Mature**: strong violence, death, cruelty of institutions, drugs and
alcohol, innuendo and flirting. **No explicit sexual content.** Gore is stylized (ink, not blood, for most enemies).

## 13. Controls (current)

| Action | Keyboard | Gamepad | Touch |
|---|---|---|---|
| Move | WASD / arrows | Left stick / d-pad | Left on-screen stick |
| Attack | J / Space / Z | A (bottom face) | Attack button |
| Swap hero | Tab / Q | Y (top face) | Swap button |
| Pause menu | Esc / P | Start | Pause button (top right) |

## 14. Milestones

1. **Prototype (done):** one area, movement, attack with power gauge, one enemy type, one AI ally, hero swap, web build.
2. **Foundations (mostly done):** CC0 art and paper dolls, hand-built maps, title/pause/game over, save and autosave.
3. **Command core:** territory map and provinces, the clock, resources, the Blank's Fray and surges, Hollowmark hub
   with the Command Table, buildings, recruit roles and assignment.
4. **Mission core:** launching missions from the map and returning, mission types (story, reclaim, defense,
   rescue), the quick menu, abilities, party picking from the roster, XP and gear.
5. **Act 1 content (MVP, ~4 hours):** Prologue, Chapter 1 and the Act 1 command phase, about 8 provinces, 12 to 15
   recruits, expeditions, research, two factions plus the Concord, relationships for the MVP core cast, The Auditor.
6. **Full game (15 to 20 hours):** about 24 provinces, about 50 recruits, Chapters 2 to 6, all factions, full
   research tree, portraits, music, balancing, accessibility.
