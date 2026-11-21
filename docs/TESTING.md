# Automated tests

Every push and pull request runs the tests in GitHub Actions (job `test` in
`.github/workflows/deploy-web.yml`). `main` only deploys to GitHub Pages when they pass.

## Running them

```sh
tools/run_tests.sh            # everything (about a minute and a half)
tools/run_tests.sh saves      # only test files whose name contains "saves"
GODOT=~/godot/godot tools/run_tests.sh   # pick the Godot 4.3 binary
```

The script imports the project, runs `tests/run.gd` headless, and fails when:

- any test fails, or
- the log has any `SCRIPT ERROR`, `ERROR` or `WARNING` line (warnings count as errors). A test that
  triggers one on purpose, like a corrupt save being set aside, announces it first with
  `allow_log("<regex>")`. Engine noise at shutdown and on machines with no sound card is ignored.

Tests never touch your real saves: they write to `user://test_run/`.

## What is covered

| File | Checks |
|---|---|
| `tests/test_data.gd` | Every `data/*.json` parses. Every id it points at exists: recruits, traits, join hooks, field heroes, abilities, AI styles, techs, gear, items, bonds and their scenes, provinces, factions and deals, buildings, research, expeditions, missions, mission types, personal missions (steps, spots on their maps, speakers and talks), maps and their @spot lines, enemies and rosters, Verity's plans, dialogue and story speakers, talks, beats and goals, portraits, sprite sets and every sprite frame. |
| `tests/test_saves.gd` | Save migrations (docs/SAVES.md): every step is well formed and has a fixture, every fixture upgrades and loads, cut content is dropped safely, newer saves are kept and not loaded, broken saves are set aside and reported, backups before overwriting, and old saves resume in the real scenes. |
| `tests/test_scenes.gd` | Boots the title, New Game into the prologue, the hub, the Command Table and every screen on it, one mission of each type (patrol, boss, defense, reclaim, rescue, raid, salvage, and a personal mission with a forced hero and one with an escort) launched and settled, map layouts varying between visits, a retreat, the quick menu, and save/load round trips in a mission, in town and at the table. |
| `tests/test_skills.gd` | Weapon and Ink skills (#24): five techs per hero with known keys, motifs and sounds, Ink colours and tiers on every ability, skill levels, the Barracks cap, the save step, every tech fired at an enemy in a real mission, allies choosing among techs, and the Techs tab and Skills screen. |
| `tests/test_ally_techs.gd` | Allies' charged techs (#108, #124): every field hero as an AI ally in a real mission fires its tech at a crowd under each preset, "On my call" never charges or fires by itself, "Unleash" fires within a few seconds, taking control mid-charge never fires the tech and keeps the gauge, every tech a hero can learn scores at its standoff, and tech modes survive a save. Fights run three times faster with three times the physics ticks, so the game sees the same 1/60 s steps. `tools/ai_tech_sim.gd` stays as the long soak test. |
| `tests/test_bonds.gd` | Bonds (#50, #120, #122): every bond has a portrait, rank 3 and 5 perks, a personal mission with a home province, one scene per rank with 2 to 3 choices, known speakers and expressions, and every line and choice fits the scene view's text box; every rank scene (and the romance moment) plays through the real scene view and moves the bond on; personal missions come up at rank 4, an erased home province locks them until it is reclaimed; every perk unlocks at its rank, and the eight perks from #120 do what they say. Screenshots: `BOND_SHOTS=/tmp/bonds xvfb-run -a godot --audio-driver Dummy --path . -s tests/run.gd -- bonds`. |
| `tests/test_skill_trees.gd` | Skill trees (#25): every field hero has a full tree whose nodes use only stats, perks, focuses and ability changes the code reads, every branch changes how the hero plays, bond gates and one capstone, Skill Points from levels, learning in order, unlearning for Gilt (not on missions), stats and abilities changed, the save step and cleaning bad saved trees, every kind of passive in a real fight (bodyguard, evade, last stand, auras, thorns, damage bonuses, kill rewards, leech, swing stun, poison kills, revives), tree poison as the shared poison status (no stagger per tick, credit and kill rewards, cures, a dormant Auditor untouched), learning mid-mission, ally focus, and the screen from the quick menu and the Gear screen. |
| `tests/test_journal.gd` | The journal (#114): `data/journal.json` is well formed and complete (every region, faction, enemy kind and Ink colour has a codex entry, every story goal names a chapter, figure portraits exist), the quest log through the story, personal stories, factions, surges and Verity's plans, enemies and history recorded and saved, the save step on an old save, and the screen in town (I, the menu, show on map to the Command Table), at the table and from the mission pause menu. |
| `tests/test_items.gd` | Items, Forge and Market (#112): about a dozen consumables of every kind including the Blank ward, every material with a source, a use and an icon, every recipe well formed with an icon, six-tier weapon lines, armour and perk trinkets, Forge/Market sprites and status icons, satchel capacity and restock, Forge jobs (blockers, crafting over days, weapon upgrades, saved), Market income, stable rotating stock, buying and selling, statuses taking hold, curing, stun immunity, boons, the ward, trinket perks, and the Forge & Market screen in town and at the table. |
| `tests/test_scripts.gd` | Every script in `scripts/` compiles. |

## Writing a test

Add `tests/test_<area>.gd`:

```gdscript
extends "res://tests/test_case.gd"

func test_something() -> void:
    var empire := autoload("Empire")
    empire.reset()
    check_eq(empire.day, 1, "a new campaign starts on day 1")
    var hub := await goto("res://scenes/hub.tscn")
    check(hub.leader != null, "Ash is in town")
```

Each `test_*` method gets a fresh instance; `before_each()` / `after_each()` run around it. Helpers:
`check`, `check_eq`, `frames(n)`, `goto(scene)`, `wait_scene(scene)` (after the game changed scene
itself), `autoload(name)`, `allow_log(regex)`.
