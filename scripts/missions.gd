class_name Missions
extends RefCounted
## Missions on the territory map (issue #5): which mission a province offers, launching it,
## and settling the results when the party comes home.
##
## A mission is a plain Dictionary (see data/missions.json). Missions can also be built at
## runtime (a Defense mission for a surge, say) and passed straight to launch().
## While one is being played it lives in Empire.active_mission (saved with the mission scene,
## not with the empire: the clock is frozen until the party is back).

const PATH := "res://data/missions.json"
const MISSION_SCENE := "res://scenes/main.tscn"
const DEFAULT := "meadow_prologue"  # New Game drops you straight into this one
const OUTCOME_TITLES := {"success": "Mission complete", "retreat": "Retreated", "wiped": "Driven out"}

static var _data: Array = []


static func all() -> Array:
	if _data.is_empty():
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if typeof(parsed) == TYPE_DICTIONARY:
			_data = parsed.get("missions", [])
	return _data


static func find(id: String) -> Dictionary:
	for m in all():
		if m["id"] == id:
			return m
	return {}


static func cleared(id: String) -> bool:
	return id in Empire.missions_cleared


## Whether the map offers this mission right now.
static func offered(m: Dictionary) -> bool:
	if m.get("story", false) and cleared(m["id"]):
		return false
	var after: String = m.get("after", "")
	if after != "" and not cleared(after):
		return false
	var p := Empire.territory().find(m.get("province", ""))
	return not p.is_empty() and p["owner"] != "erased"


## The mission a province offers, or {} when there is none. Story missions come first.
static func for_province(pid: String) -> Dictionary:
	for m in all():
		if m.get("province", "") == pid and offered(m):
			return m
	return {}


## The mission being played, falling back to the right Meadow mission for New Game and for
## saves made before missions existed.
static func current() -> Dictionary:
	if not Empire.active_mission.is_empty():
		return Empire.active_mission
	var m := find(DEFAULT)
	if cleared(DEFAULT):
		m = for_province("meadow")
		if m.is_empty():
			m = find("meadow_patrol")
	return m


## Sets the mission and loads its map. The caller autosaves first (Command does in _leave).
static func launch(m: Dictionary) -> void:
	Empire.active_mission = m.duplicate(true)
	Saves.pending = {}
	var tree := Engine.get_main_loop() as SceneTree
	tree.paused = false
	tree.change_scene_to_file(m.get("scene", MISSION_SCENE))


## "40 Gilt, 15 Supplies, 2 Ink" (empty string for nothing).
static func res_text(d: Dictionary) -> String:
	var parts := []
	for k in ["gilt", "supplies", "ink", "renown", "insight"]:
		if int(d.get(k, 0)) != 0:
			parts.append("%d %s" % [int(d[k]), Empire.RES_NAMES.get(k, k)])
	return ", ".join(parts)


## Rolls one kill's pickup from the mission's loot table. Returns {} for nothing.
static func roll_loot(m: Dictionary) -> Dictionary:
	var out := {}
	var table: Dictionary = m.get("loot", {})
	for k in table:
		var row: Array = table[k]
		if randf() < float(row[0]):
			out[k] = randi_range(int(row[1]), int(row[2]))
	return out


## Works out what the party brings home. Nothing is paid until apply().
## outcome: "success", "retreat" or "wiped".
static func settle(m: Dictionary, outcome: String, found: Dictionary, stats: Dictionary) -> Dictionary:
	var pay := {}
	if outcome != "wiped":  # the wiped-out party drops everything it picked up
		for k in found:
			pay[k] = int(pay.get(k, 0)) + int(found[k])
	var fray := 0
	if outcome == "success":
		var r: Dictionary = m.get("rewards", {})
		for k in r:
			pay[k] = int(pay.get(k, 0)) + int(r[k])
		fray = int(m.get("fray", 0))
	var p := Empire.territory().find(m.get("province", ""))
	return {
		"outcome": outcome, "title": OUTCOME_TITLES.get(outcome, outcome),
		"mission": m.get("id", ""), "name": m.get("name", "Mission"),
		"province": p.get("name", ""), "province_id": p.get("id", ""),
		"fray": fray, "fray_now": int(p.get("fray", 0)),
		"found": found.duplicate(), "pay": pay,
		"first_clear": outcome == "success" and not cleared(m.get("id", "")),
		"kills": int(stats.get("kills", 0)), "time": float(stats.get("time", 0.0)),
		"objective": stats.get("objective", ""),
		"lines": [],  # extra lines for the results screen (mission-type effects, issue #51)
	}


## Pays out a settled result and marks the mission cleared.
static func apply(result: Dictionary) -> void:
	var pay: Dictionary = result["pay"]
	for k in pay:
		Empire.gain(k, int(pay[k]))
	if result["outcome"] == "success" and not cleared(result["mission"]):
		Empire.missions_cleared.append(result["mission"])
	var p := Empire.territory().find(result.get("province_id", ""))
	if not p.is_empty() and p["owner"] != "erased" and int(result["fray"]) != 0:
		p["fray"] = clampi(int(p["fray"]) + int(result["fray"]), 0, 99)
	# Mission types with effects beyond rewards (issue #51) hook in here, e.g.:
	# if m.has("effects"): MissionTypes.apply(m, result["outcome"])
	Empire.active_mission = {}
	Empire.last_mission = result


## Pays out, autosaves in Hollowmark and walks the party home.
static func go_home(result: Dictionary) -> void:
	apply(result)
	Saves.pending = {}
	Saves.save("auto", {"scene": Saves.HUB_SCENE, "area_name": "Hollowmark"})
	var tree := Engine.get_main_loop() as SceneTree
	tree.paused = false
	tree.change_scene_to_file(Saves.HUB_SCENE)
