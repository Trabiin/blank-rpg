class_name EnemyKinds
extends RefCounted
## The Act 1 enemy roster (issue #16): which enemy types live where, and how to spawn them.
## Data: data/enemies.json. Each kind is an Enemy subclass so heroes, allies and abilities treat
## them all alike (group "enemies", radius, dead, take_hit, taunt, goal).
##   nibbler  - scripts/enemy.gd: chase, wind up, lunge
##   spitter  - scripts/spitter.gd: keeps its distance, swells, spits a slow glob
##   moth     - scripts/moth.gd: Gutterwoods letter-moths, in packs; circle, flash, dive
##   enforcer - scripts/enforcer.gd: Concord heavy; front shield, slow ground-slam with a red ring

const SCRIPTS := {
	"nibbler": preload("res://scripts/enemy.gd"),
	"spitter": preload("res://scripts/spitter.gd"),
	"moth": preload("res://scripts/moth.gd"),
	"enforcer": preload("res://scripts/enforcer.gd"),
}

static var _data := {}
static var _told := {}  # kind -> true once its tip was shown this session


static func data() -> Dictionary:
	if _data.is_empty():
		var f := FileAccess.open("res://data/enemies.json", FileAccess.READ)
		if f:
			_data = JSON.parse_string(f.get_as_text())
	return _data


static func kind(id: String) -> Dictionary:
	return data().get("kinds", {}).get(id, {})


## Spawn weights for a mission: its own "enemies", else its province's roster, else the default.
static func roster(mission: Dictionary) -> Dictionary:
	if mission.has("enemies"):
		return mission["enemies"]
	var r: Dictionary = data().get("rosters", {})
	return r.get(str(mission.get("province", "")), r.get("default", {"nibbler": 1}))


static func pick(mission: Dictionary) -> String:
	var r := roster(mission)
	var total := 0.0
	for k in r:
		total += float(r[k])
	var roll := randf() * total
	for k in r:
		roll -= float(r[k])
		if roll <= 0.0 and SCRIPTS.has(k):
			return k
	return "nibbler"


## "Nibblers, Spitters": for the briefing.
static func names(mission: Dictionary) -> String:
	var out := []
	for k in roster(mission):
		out.append(kind(k).get("plural", k))
	return ", ".join(out)


## Spawns one roll of the mission's roster at pos (a pack for moths) and returns what came out.
static func spawn(parent: Node, pos: Vector2, mission: Dictionary, id := "") -> Array:
	if id == "":
		id = pick(mission)
	var info := kind(id)
	var out := []
	var n := randi_range(maxi(1, int(info.get("pack", 1)) - 1), maxi(1, int(info.get("pack", 1))))  # packs vary by one
	for i in n:
		var e: Enemy = SCRIPTS[id].new()
		e.position = pos + (Vector2.RIGHT.rotated(TAU * i / n) * 10.0 if n > 1 else Vector2.ZERO)
		parent.add_child(e)  # _ready runs here; the data overrides the script's defaults after it
		e.max_hp = int(info.get("hp", e.max_hp))
		e.hp = e.max_hp
		e.move_speed = float(info.get("speed", e.move_speed))
		e.xp = int(info.get("xp", e.xp))
		if e.get("damage") != null:
			e.set("damage", int(info.get("damage", e.get("damage"))))
		e.set_meta("kind", id)
		out.append(e)
	return out


## The first time a kind notices the party, the HUD says how to deal with it.
static func notice(e: Enemy) -> void:
	var id: String = e.get_meta("kind", "nibbler")
	if _told.has(id):
		return
	_told[id] = true
	var tip: String = kind(id).get("tip", "")
	var scene := e.get_tree().current_scene
	if tip != "" and scene != null and scene.get("hud") != null:
		scene.hud.say(tip, 4.5)
