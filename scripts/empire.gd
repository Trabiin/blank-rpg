extends Node
## Autoload "Empire": the Command layer's state, which outlives scene changes.
##
## Holds the day clock and the territory. The clock only advances when the Command scene
## calls tick(), so it is naturally frozen while the party is out on a mission.
## Other systems (the Blank, construction, research, expeditions) connect to day_passed.

signal day_passed(day: int)
signal speed_changed(speed: int)
signal ledger_settled(changes: Dictionary)  # resource -> net change applied at dawn

const RESOURCES := ["gilt", "supplies", "ink"]
const RES_NAMES := {"gilt": "Gilt", "supplies": "Supplies", "ink": "Ink", "renown": "Renown"}
const START := {"gilt": 120, "supplies": 40, "ink": 5, "renown": 0}
const UPKEEP_SUPPLIES := 1  # per recruit per day
## A province keeps producing as it frays, but loses up to this share of its output.
const FRAY_OUTPUT_LOSS := 0.5

const DAY_SECONDS := 240.0  # real seconds per in-game day at 1x
const SPEEDS := [0, 1, 2, 4]  # index 0 = paused
const MAP_CELLS := Vector2i(214, 166)  # resolution the territory is rasterised at

var day := 1
var day_t := 0.0  # 0..1 through the current day
var speed := 1  # index into SPEEDS
var playtime := 0.0  # real seconds played, across Command and missions
var res := START.duplicate()
var hungry := false  # supplies ran out at the last dawn
## Placeholder roster until recruits exist (#44): Ash and Bran eat like everyone else.
var roster := ["Ash", "Bran"]
var _territory: Territory


func territory() -> Territory:
	if _territory == null:
		_territory = Territory.new()
		_territory.build_grid(MAP_CELLS)
	return _territory


## Fresh campaign: day 1, provinces as written in data/provinces.json.
func reset() -> void:
	day = 1
	day_t = 0.3  # start mid-morning
	speed = 1
	playtime = 0.0
	res = START.duplicate()
	hungry = false
	roster = ["Ash", "Bran"]
	if _territory != null:
		_territory.reload_data()


func tick(delta: float) -> void:
	if SPEEDS[speed] == 0:
		return
	day_t += delta * SPEEDS[speed] / DAY_SECONDS
	while day_t >= 1.0:
		day_t -= 1.0
		day += 1
		_settle()
		day_passed.emit(day)


## Every line of the daily ledger: [{"label", "gilt", "supplies", "ink", "note"}].
## The same list drives the actual payout and the breakdown shown to the player.
func ledger() -> Array:
	var lines := []
	for p in territory().provinces:
		if p["owner"] != "you":
			continue
		var keep := 1.0 - FRAY_OUTPUT_LOSS * float(p["fray"]) / 100.0
		var line := {"label": p["name"], "note": ""}
		for k in RESOURCES:
			line[k] = int(round(float(p.get("output", {}).get(k, 0)) * keep))
		if keep < 0.99:
			line["note"] = "-%d%% from Fray" % int(round((1.0 - keep) * 100.0))
		lines.append(line)
	lines.append({"label": "Upkeep (%d people)" % roster.size(), "gilt": 0, "supplies": -UPKEEP_SUPPLIES * roster.size(), "ink": 0, "note": ""})
	return lines


## Net change per day for each resource.
func daily_net() -> Dictionary:
	var net := {"gilt": 0, "supplies": 0, "ink": 0}
	for line in ledger():
		for k in RESOURCES:
			net[k] += int(line[k])
	return net


func _settle() -> void:
	var net := daily_net()
	for k in RESOURCES:
		res[k] += net[k]
	hungry = res["supplies"] < 0
	if hungry:
		res["supplies"] = 0
	ledger_settled.emit(net)


func can_afford(cost: Dictionary) -> bool:
	for k in cost:
		if int(res.get(k, 0)) < int(cost[k]):
			return false
	return true


func spend(cost: Dictionary) -> bool:
	if not can_afford(cost):
		return false
	for k in cost:
		res[k] -= int(cost[k])
	return true


func gain(k: String, amount: int) -> void:
	res[k] = int(res.get(k, 0)) + amount


func set_speed(i: int) -> void:
	i = clampi(i, 0, SPEEDS.size() - 1)
	if i != speed:
		speed = i
		speed_changed.emit(speed)


## "07:40"-style time of day.
func clock_text() -> String:
	var mins := int(day_t * 24.0 * 60.0)
	return "%02d:%02d" % [mins / 60, (mins % 60) / 10 * 10]


func to_dict() -> Dictionary:
	var ps := []
	for p in territory().provinces:
		ps.append({"id": p["id"], "owner": p["owner"], "fray": p["fray"]})
	return {"day": day, "day_t": day_t, "speed": speed, "playtime": playtime, "provinces": ps,
		"res": res, "hungry": hungry, "roster": roster}


func from_dict(d: Dictionary) -> void:
	reset()
	if d.is_empty():
		return
	day = int(d.get("day", 1))
	day_t = float(d.get("day_t", 0.3))
	speed = clampi(int(d.get("speed", 1)), 0, SPEEDS.size() - 1)
	playtime = float(d.get("playtime", 0.0))
	var saved_res: Dictionary = d.get("res", {})
	for k in START:
		res[k] = int(saved_res.get(k, START[k]))
	hungry = bool(d.get("hungry", false))
	roster = d.get("roster", roster)
	for saved in d.get("provinces", []):
		var p := territory().find(saved["id"])
		if not p.is_empty():
			p["owner"] = saved["owner"]
			p["fray"] = saved["fray"]
