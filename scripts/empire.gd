extends Node
## Autoload "Empire": the Command layer's state, which outlives scene changes.
##
## Holds the day clock and the territory. The clock only advances when the Command scene
## calls tick(), so it is naturally frozen while the party is out on a mission.
## Other systems (the Blank, construction, research, expeditions) connect to day_passed.

signal day_passed(day: int)
signal speed_changed(speed: int)
signal ledger_settled(changes: Dictionary)  # resource -> net change applied at dawn
signal notice(text: String, warning: bool)  # something the player should hear about
signal hollowmark_lost

## The Blank. Fray per day from each source; see fray_sources().
const FRAY_FIRST_ERASED_NEIGHBOR := 3
const FRAY_MORE_ERASED_NEIGHBORS := 1  # each erased neighbour after the first
const FRAY_AT_EDGE := 2
const FRAY_UNHELD := 1
const FRAY_UNGOVERNED := 1
const FRAY_MOMENTUM := 1  # above 50, unravelling feeds itself
const FRAY_TENDED := -2  # your people patch up what they can
const SCAR_FRAY := 2  # per day while a surge scar lasts
const SURGE_FRAY := 12
const SURGE_SCAR_DAYS := 3
const SURGE_WARNING_DAYS := 2
const SURGE_GAP := [3, 5]  # days between surges

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
var surge := {}  # {"id": province id, "day": day it lands} while one is gathering
var next_surge_day := 4
var rng := RandomNumberGenerator.new()
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
	surge = {}
	next_surge_day = 4
	rng.seed = 1234
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
		_advance_blank()
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


# ---------------------------------------------------------------- the Blank

## Every reason a province's Fray moves each day: [[label, change], ...]. The province panel
## shows exactly this list, so the player can always see why the Blank is moving.
func fray_sources(p: Dictionary) -> Array:
	var out := []
	if p["owner"] == "erased":
		return out
	var t := territory()
	var erased := []
	for n in t.neighbors[p["index"]]:
		if t.provinces[n]["owner"] == "erased":
			erased.append(t.provinces[n]["name"])
	if not erased.is_empty():
		out.append(["Borders erased land (%s)" % ", ".join(erased), FRAY_FIRST_ERASED_NEIGHBOR + FRAY_MORE_ERASED_NEIGHBORS * (erased.size() - 1)])
	if p.get("at_edge", false):
		out.append(["Touches the Blank's edge", FRAY_AT_EDGE])
	if int(p.get("scar", 0)) > 0:
		out.append(["Surge damage (%d more days)" % int(p["scar"]), SCAR_FRAY])
	if float(p["fray"]) > 50.0:
		out.append(["Unravelling feeds itself", FRAY_MOMENTUM])
	if p["owner"] == "you":
		out.append(["No governor posted", FRAY_UNGOVERNED])
		out.append(["Tended by your people", FRAY_TENDED])
	elif p["owner"] == "free":
		out.append(["Nobody holds it", FRAY_UNHELD])
	return out


func fray_rate(p: Dictionary) -> int:
	var total := 0
	for src in fray_sources(p):
		total += int(src[1])
	return total


## Dawn: Fray moves, surges gather and land, provinces fall.
func _advance_blank() -> void:
	var t := territory()
	var rates := []
	for p in t.provinces:
		rates.append(fray_rate(p))  # all rates from the same morning, before anything falls
	for p in t.provinces:
		if p["owner"] == "erased":
			continue
		p["fray"] = clampi(int(p["fray"]) + int(rates[p["index"]]), 0, 100)
		if int(p.get("scar", 0)) > 0:
			p["scar"] = int(p["scar"]) - 1
	_update_surge()
	for p in t.provinces:
		if p["owner"] != "erased" and int(p["fray"]) >= 100:
			_erase(p)


func _erase(p: Dictionary) -> void:
	var was_yours: bool = p["owner"] == "you"
	p["owner"] = "erased"
	p["fray"] = 100
	p["scar"] = 0
	if surge.get("id", "") == p["id"]:
		surge = {}
		next_surge_day = day + rng.randi_range(SURGE_GAP[0], SURGE_GAP[1])
	notice.emit("%s has been erased." % p["name"], was_yours)
	if p["id"] == "hollowmark":
		hollowmark_lost.emit()


func _update_surge() -> void:
	var t := territory()
	if not surge.is_empty() and day >= int(surge["day"]):
		var p := t.find(surge["id"])
		surge = {}
		if not p.is_empty() and p["owner"] != "erased":
			p["fray"] = mini(int(p["fray"]) + SURGE_FRAY, 100)
			p["scar"] = SURGE_SCAR_DAYS
			notice.emit("The Blank surged into %s. +%d Fray." % [p["name"], SURGE_FRAY], p["owner"] == "you")
		next_surge_day = day + rng.randi_range(SURGE_GAP[0], SURGE_GAP[1])
	if surge.is_empty() and day >= next_surge_day - SURGE_WARNING_DAYS:
		# Targets: anything still standing next to erased land. Yours and the worn-thin are likelier.
		var pool := []
		var weights := []
		for p in t.provinces:
			if p["owner"] == "erased":
				continue
			var exposed := false
			for n in t.neighbors[p["index"]]:
				exposed = exposed or t.provinces[n]["owner"] == "erased"
			if exposed or p.get("at_edge", false):
				pool.append(p)
				weights.append((3.0 if p["owner"] == "you" else 1.0) + float(p["fray"]) / 25.0)
		if not pool.is_empty():
			next_surge_day = maxi(next_surge_day, day + SURGE_WARNING_DAYS)
			var target: Dictionary = pool[rng.rand_weighted(PackedFloat32Array(weights))]
			surge = {"id": target["id"], "day": next_surge_day}
			notice.emit("The Blank is gathering against %s. Surge in %d days." % [target["name"], next_surge_day - day], target["owner"] == "you")


func surge_days_left() -> int:
	return int(surge["day"]) - day if not surge.is_empty() else -1


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
		ps.append({"id": p["id"], "owner": p["owner"], "fray": p["fray"], "scar": p.get("scar", 0)})
	return {"day": day, "day_t": day_t, "speed": speed, "playtime": playtime, "provinces": ps,
		"res": res, "hungry": hungry, "roster": roster, "surge": surge, "next_surge_day": next_surge_day,
		"rng_state": str(rng.state)}


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
	surge = d.get("surge", {})
	next_surge_day = int(d.get("next_surge_day", 4))
	if d.has("rng_state"):
		rng.state = int(d["rng_state"])
	for saved in d.get("provinces", []):
		var p := territory().find(saved["id"])
		if not p.is_empty():
			p["owner"] = saved["owner"]
			p["fray"] = saved["fray"]
			p["scar"] = int(saved.get("scar", 0))
