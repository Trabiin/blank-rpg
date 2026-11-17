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
signal building_finished(id: String)  # a Hollowmark building was built or upgraded

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
const RES_NAMES := {"gilt": "Gilt", "supplies": "Supplies", "ink": "Ink", "renown": "Renown", "insight": "Insight"}
const START := {"gilt": 120, "supplies": 40, "ink": 5, "renown": 0, "insight": 0}
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
## Recruits who have joined: id -> {"role": idle|party|governor, "target": province id, "injured": days}.
## Static facts (name, stats, traits) live in data/recruits.json, see recruit().
var recruits := {}
var recruit_data := {}  # id -> Dictionary from the JSON, in file order
var trait_data := {}
var surge := {}  # {"id": province id, "day": day it lands} while one is gathering
var next_surge_day := 4
## Buildings: id -> level (0 = not built). Static facts live in data/buildings.json, see building().
var buildings := {}
## The Hollowmark building crew works on one thing at a time: {"id", "start", "finish"} in days.
var construction := {}
## Wardlamps: province id -> level, and lamps being put up: province id -> {"start", "finish"}.
var lamps := {}
var lamp_jobs := {}
var building_data := {}  # id -> Dictionary from the JSON, in file order
var lamp_data := {}
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
	_load_recruit_data()
	recruits = {}
	for id in recruit_data:
		if recruit_data[id].get("start", false):
			recruits[id] = {"role": "idle", "target": "", "injured": 0}
	for id in ["ash", "bran"]:
		if recruits.has(id):
			recruits[id]["role"] = "party"
	surge = {}
	next_surge_day = 4
	_load_building_data()
	buildings = {}
	for id in building_data:
		buildings[id] = int(building_data[id].get("start_level", 0))
	construction = {}
	lamps = {}
	lamp_jobs = {}
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
		_heal()
		_settle()
		_advance_blank()
		day_passed.emit(day)
	_advance_construction()


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
	for p in territory().provinces:
		var gov := governor_of(p["id"])
		if p["owner"] == "you" and gov != "":
			var e := governor_effect(gov)
			lines.append({"label": "  Governor %s" % recruit(gov)["name"], "gilt": e["gilt"], "supplies": e["supplies"], "ink": 0, "note": ""})
	var upkeep := UPKEEP_SUPPLIES * recruits.size()
	lines.append({"label": "Upkeep (%d people)" % recruits.size(), "gilt": 0, "supplies": -upkeep, "ink": 0, "note": ""})
	var qm := current_effect("command_table")
	if int(qm.get("upkeep_cut", 0)) > 0:
		lines.append({"label": "  Quartermaster's savings", "gilt": 0, "supplies": mini(int(qm["upkeep_cut"]), upkeep), "ink": 0, "note": ""})
	var ink := current_effect("inkworks")
	if int(ink.get("ink", 0)) > 0:
		lines.append({"label": "Inkworks", "gilt": 0, "supplies": 0, "ink": int(ink["ink"]), "note": ""})
	var guild := current_effect("guildhall")
	if int(guild.get("gilt", 0)) > 0:
		lines.append({"label": "Guildhall contracts", "gilt": int(guild["gilt"]), "supplies": 0, "ink": 0, "note": ""})
	var ins := int(current_effect("scriptorium").get("insight", 0))
	if ins > 0:
		lines.append({"label": "Scriptorium", "gilt": 0, "supplies": 0, "ink": 0, "note": "+%d Insight" % ins})
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
	res["insight"] = int(res.get("insight", 0)) + int(current_effect("scriptorium").get("insight", 0))
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
		var gov := governor_of(p["id"])
		if gov == "":
			out.append(["No governor posted", FRAY_UNGOVERNED])
		else:
			out.append(["Governed by %s" % recruit(gov)["name"], governor_effect(gov)["fray"]])
		out.append(["Tended by your people", FRAY_TENDED])
		if int(lamps.get(p["id"], 0)) > 0:
			out.append(["Wardlamp (level %d)" % int(lamps[p["id"]]), lamp_fray(int(lamps[p["id"]]))])
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
	var gov := governor_of(p["id"])
	if gov != "":
		recruits[gov] = {"role": "idle", "target": "", "injured": 3}
		notice.emit("%s fled %s, hurt. Out of action for 3 days." % [recruit(gov)["name"], p["name"]], true)
	p["owner"] = "erased"
	p["fray"] = 100
	lamps.erase(p["id"])  # the lamp goes out with everything else
	lamp_jobs.erase(p["id"])
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
	var warn := surge_warning_days()
	if surge.is_empty() and day >= next_surge_day - warn:
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
			next_surge_day = maxi(next_surge_day, day + warn)
			var target: Dictionary = pool[rng.rand_weighted(PackedFloat32Array(weights))]
			surge = {"id": target["id"], "day": next_surge_day}
			notice.emit("The Blank is gathering against %s. Surge in %d days." % [target["name"], next_surge_day - day], target["owner"] == "you")


func surge_days_left() -> int:
	return int(surge["day"]) - day if not surge.is_empty() else -1


# ---------------------------------------------------------------- recruits and roles

const PARTY_SIZE := 3
const ROLE_NAMES := {"idle": "Idle", "party": "Party", "governor": "Governor", "staff": "Building staff",
	"expedition": "Expedition", "researcher": "Researcher", "envoy": "Envoy"}


func _load_recruit_data() -> void:
	if not recruit_data.is_empty():
		return
	var f := FileAccess.open("res://data/recruits.json", FileAccess.READ)
	var parsed = JSON.parse_string(f.get_as_text())
	trait_data = parsed["traits"]
	for r in parsed["recruits"]:
		recruit_data[r["id"]] = r


func recruit(id: String) -> Dictionary:
	_load_recruit_data()
	return recruit_data.get(id, {})


## Joined recruits in roster order (the order of data/recruits.json).
func roster_ids() -> Array:
	return recruit_data.keys().filter(func(id): return recruits.has(id))


func role_of(id: String) -> String:
	return recruits.get(id, {}).get("role", "idle")


func party_ids() -> Array:
	return roster_ids().filter(func(id): return role_of(id) == "party")


func governor_of(province_id: String) -> String:
	for id in recruits:
		if recruits[id]["role"] == "governor" and recruits[id]["target"] == province_id:
			return id
	return ""


func has_trait(id: String, t: String) -> bool:
	return t in recruit(id).get("traits", [])


## What a recruit does for a province they govern: Fray change per day and extra output.
func governor_effect(id: String) -> Dictionary:
	var st: Dictionary = recruit(id)["stats"]
	var fray := -(1 + int(st["grit"]) / 4)
	if has_trait(id, "stubborn"):
		fray -= 1
	if has_trait(id, "coward"):
		fray += 1
	var gilt := int(st["charm"]) / 3 + (2 if has_trait(id, "greedy") else 0)
	return {"fray": fray, "gilt": gilt, "supplies": int(st["craft"]) / 3}


## Everything a recruit could be assigned to right now, with what it would do.
## Each: {"role", "target", "label", "enabled", "note", "preview"}.
func role_options(id: String) -> Array:
	var r := recruit(id)
	var st: Dictionary = recruits[id]
	var out := []
	var hurt := int(st["injured"]) > 0
	var locked: bool = r.get("locked_party", false)
	out.append({"role": "idle", "target": "", "label": "Idle in Hollowmark", "enabled": not locked,
		"note": "Ash always leads the party" if locked else "", "preview": "Rests. Still eats."})
	var in_party := party_ids().size()
	var can_fight: bool = r["tier"] == "field"
	var party_note := ""
	if not can_fight:
		party_note = "not a fighter"
	elif role_of(id) != "party" and in_party >= PARTY_SIZE:
		party_note = "party is full (%d/%d)" % [in_party, PARTY_SIZE]
	elif hurt:
		party_note = "injured"
	out.append({"role": "party", "target": "", "label": "Party (%d/%d)" % [in_party, PARTY_SIZE],
		"enabled": party_note == "" and not locked, "note": party_note, "preview": "Goes on missions with Ash."})
	for p in territory().provinces:
		if p["owner"] != "you":
			continue
		var e := governor_effect(id)
		var current := governor_of(p["id"])
		var replaces := "" if current == "" or current == id else "  (replaces %s)" % recruit(current)["name"]
		var preview := "%s: Fray %d/day instead of +%d, +%d Gilt, +%d Supplies a day%s" % [p["name"], e["fray"], FRAY_UNGOVERNED, e["gilt"], e["supplies"], replaces]
		out.append({"role": "governor", "target": p["id"], "label": "Govern %s" % p["name"],
			"enabled": not locked and not hurt, "note": "injured" if hurt else "", "preview": preview})
	for bid in building_data:
		var lv := level_of(bid)
		if lv <= 0 or slots_of(bid) <= 0:
			continue
		var b := building(bid)
		var staff := staff_of(bid)
		var here: bool = id in staff
		var full := not here and staff.size() >= slots_of(bid)
		var note := ""
		if locked:
			note = "Ash leads the party"
		elif hurt:
			note = "injured"
		elif full:
			note = "full (%d/%d)" % [staff.size(), slots_of(bid)]
		var with_me := staff.duplicate()
		if not here:
			with_me.append(id)
		var preview := "%s: %s  (now: %s)" % [b["name"], building_effect(bid, lv, with_me)["text"], building_effect(bid, lv, staff)["text"]]
		out.append({"role": "staff", "target": bid, "label": "Work the %s (%d/%d)" % [b["name"], staff.size(), slots_of(bid)],
			"enabled": note == "", "note": note, "preview": preview})
	var expedition_note := "expeditions arrive with #47" if level_of("guildhall") > 0 else "needs a Guildhall"
	for locked_role in [["expedition", expedition_note], ["envoy", "needs a faction contact"]]:
		out.append({"role": locked_role[0], "target": "", "label": ROLE_NAMES[locked_role[0]], "enabled": false, "note": locked_role[1], "preview": ""})
	return out


func assign(id: String, role: String, target := "") -> bool:
	for o in role_options(id):
		if o["role"] == role and o["target"] == target and o["enabled"]:
			if role == "governor":
				var current := governor_of(target)
				if current != "" and current != id:
					recruits[current]["role"] = "idle"
					recruits[current]["target"] = ""
			recruits[id]["role"] = role
			recruits[id]["target"] = target
			return true
	return false


func role_label(id: String) -> String:
	var st: Dictionary = recruits[id]
	var label: String = ROLE_NAMES.get(st["role"], st["role"])
	if st["role"] == "governor":
		label = "Governor of %s" % territory().find(st["target"]).get("name", "?")
	elif st["role"] == "staff":
		var b := building(st["target"])
		label = "%s at the %s" % [b.get("staff_title", "Staff"), b.get("name", "?")]
	if int(st["injured"]) > 0:
		label += "  (injured, %d days)" % int(st["injured"])
	return label


func _heal() -> void:
	var per_day := 1 + int(current_effect("infirmary").get("extra_heal", 0))
	for id in recruits:
		if int(recruits[id]["injured"]) > 0:
			recruits[id]["injured"] = maxi(int(recruits[id]["injured"]) - per_day, 0)


# ---------------------------------------------------------------- buildings and construction

func _load_building_data() -> void:
	if not building_data.is_empty():
		return
	var f := FileAccess.open("res://data/buildings.json", FileAccess.READ)
	var parsed = JSON.parse_string(f.get_as_text())
	for b in parsed["buildings"]:
		building_data[b["id"]] = b
	lamp_data = parsed["wardlamp"]


func building(id: String) -> Dictionary:
	_load_building_data()
	return building_data.get(id, {})


func building_ids() -> Array:
	_load_building_data()
	return building_data.keys()


func level_of(id: String) -> int:
	return int(buildings.get(id, 0))


func max_level(id: String) -> int:
	return building(id).get("levels", []).size()


func slots_of(id: String) -> int:
	var lv := level_of(id)
	return int(building(id)["levels"][lv - 1]["slots"]) if lv > 0 else 0


## Everyone posted to a building, in roster order.
func staff_of(id: String) -> Array:
	return roster_ids().filter(func(r): return recruits[r]["role"] == "staff" and recruits[r]["target"] == id)


func _stat_sum(staff: Array, stat: String, div: int, bookish_double := false) -> int:
	var total := 0
	for r in staff:
		if int(recruits.get(r, {}).get("injured", 0)) > 0:
			continue  # hurt people don't work
		var v := int(recruit(r)["stats"][stat]) / div
		if bookish_double and has_trait(r, "bookish"):
			v *= 2
		total += v
	return total


func _working(staff: Array) -> int:
	return staff.filter(func(r): return int(recruits.get(r, {}).get("injured", 0)) == 0).size()


## What a building does at a level with a given staff. Returns the numbers plus one line of
## text; previews (assigning someone, upgrading) call this with what-if arguments.
func building_effect(id: String, level: int, staff: Array) -> Dictionary:
	if level <= 0:
		return {"text": "not built"}
	var working := _working(staff)
	match id:
		"command_table":
			var cut := _stat_sum(staff, "craft", 3)
			var warn := SURGE_WARNING_DAYS + level - 1
			var t := "Surge warning %d days ahead" % warn
			if cut > 0:
				t += ", upkeep -%d Supplies a day" % cut
			return {"warning": warn, "upkeep_cut": cut, "text": t}
		"barracks":
			var hp := 5 * level + _stat_sum(staff, "might", 2)
			return {"hp": hp, "text": "Party leaves on missions with +%d max HP" % hp}
		"infirmary":
			var extra := (level + _stat_sum(staff, "lore", 3)) / 2
			return {"extra_heal": extra, "text": "Injuries heal %d day%s per day (normally 1)" % [1 + extra, "" if extra == 0 else "s"]}
		"inkworks":
			if working == 0:
				return {"ink": 0, "text": "Idle: needs a worker"}
			var held := 0
			for p in territory().provinces:
				if p["owner"] == "you" and int(p.get("output", {}).get("ink", 0)) > 0:
					held += 1
			var ink := level + _stat_sum(staff, "craft", 3) + held
			return {"ink": ink, "text": "+%d Ink a day" % ink + (" (%d from Ink provinces)" % held if held > 0 else "")}
		"scriptorium":
			if working == 0:
				return {"insight": 0, "text": "Idle: needs a researcher"}
			var ins := level + _stat_sum(staff, "lore", 2, true)
			return {"insight": ins, "text": "+%d Insight a day, banked for research" % ins}
		"guildhall":
			if working == 0:
				return {"gilt": 0, "text": "Idle: needs a broker"}
			var g := 2 * level + _stat_sum(staff, "charm", 2)
			return {"gilt": g, "text": "+%d Gilt a day from contracts" % g}
	return {"text": ""}


func current_effect(id: String) -> Dictionary:
	return building_effect(id, level_of(id), staff_of(id))


func surge_warning_days() -> int:
	return int(current_effect("command_table").get("warning", SURGE_WARNING_DAYS))


func party_hp_bonus() -> int:
	return int(current_effect("barracks").get("hp", 0))


## The next level of a building: {"level", "cost", "days", "slots"}, or {} at max level.
func next_level(id: String) -> Dictionary:
	var lv := level_of(id)
	var levels: Array = building(id).get("levels", [])
	if lv >= levels.size():
		return {}
	var l: Dictionary = levels[lv]
	return {"level": lv + 1, "cost": l["cost"], "days": int(l["days"]), "slots": int(l["slots"])}


## Why a building can't be built or upgraded right now, or "" if it can.
func build_blocker(id: String) -> String:
	var nl := next_level(id)
	if nl.is_empty():
		return "fully upgraded"
	if not construction.is_empty():
		return "your builders are busy on the %s" % building(construction["id"])["name"]
	if not can_afford(nl["cost"]):
		return "not enough " + _missing(nl["cost"])
	return ""


func _missing(cost: Dictionary) -> String:
	var out := []
	for k in cost:
		if int(res.get(k, 0)) < int(cost[k]):
			out.append(RES_NAMES[k])
	return ", ".join(out)


func start_build(id: String) -> bool:
	if build_blocker(id) != "":
		return false
	var nl := next_level(id)
	spend(nl["cost"])
	var now := day + day_t
	construction = {"id": id, "start": now, "finish": now + float(nl["days"])}
	return true


## 0..1 through a job ({"start", "finish"}).
func job_progress(job: Dictionary) -> float:
	if job.is_empty():
		return 0.0
	return clampf((day + day_t - float(job["start"])) / maxf(float(job["finish"]) - float(job["start"]), 0.001), 0.0, 1.0)


## "1 day 6 hours"-style time left on a job.
func job_left_text(job: Dictionary) -> String:
	var hours := ceili(maxf(float(job["finish"]) - (day + day_t), 0.0) * 24.0)
	var d := hours / 24
	var h := hours % 24
	if d > 0 and h > 0:
		return "%d day%s %d h" % [d, "" if d == 1 else "s", h]
	if d > 0:
		return "%d day%s" % [d, "" if d == 1 else "s"]
	return "%d h" % maxi(h, 1)


func lamp_fray(level: int) -> int:
	return int(lamp_data["levels"][level - 1]["fray"]) if level > 0 else 0


## Next Wardlamp level for a province: {"level", "cost", "days", "fray"}, or {} at max.
func lamp_next(pid: String) -> Dictionary:
	var lv := int(lamps.get(pid, 0))
	var levels: Array = lamp_data["levels"]
	if lv >= levels.size():
		return {}
	var l: Dictionary = levels[lv]
	return {"level": lv + 1, "cost": l["cost"], "days": int(l["days"]), "fray": int(l["fray"])}


func lamp_blocker(pid: String) -> String:
	var p := territory().find(pid)
	if p.get("owner", "") != "you":
		return "you don't hold it"
	var nl := lamp_next(pid)
	if nl.is_empty():
		return "fully upgraded"
	if lamp_jobs.has(pid):
		return "already being built"
	if not can_afford(nl["cost"]):
		return "not enough " + _missing(nl["cost"])
	return ""


func start_lamp(pid: String) -> bool:
	if lamp_blocker(pid) != "":
		return false
	var nl := lamp_next(pid)
	spend(nl["cost"])
	var now := day + day_t
	lamp_jobs[pid] = {"start": now, "finish": now + float(nl["days"])}
	return true


## Finishes construction the moment its time is up (checked every frame the clock runs).
func _advance_construction() -> void:
	var now := day + day_t
	if not construction.is_empty() and now >= float(construction["finish"]):
		var id: String = construction["id"]
		construction = {}
		buildings[id] = level_of(id) + 1
		var b := building(id)
		if level_of(id) == 1:
			notice.emit("The %s is finished. Give it staff on the Buildings screen (B)." % b["name"], false)
		else:
			notice.emit("The %s is now level %d." % [b["name"], level_of(id)], false)
		building_finished.emit(id)
	for pid in lamp_jobs.keys():
		if now >= float(lamp_jobs[pid]["finish"]):
			lamp_jobs.erase(pid)
			lamps[pid] = int(lamps.get(pid, 0)) + 1
			var p := territory().find(pid)
			notice.emit("The Wardlamp in %s is lit%s." % [p.get("name", "?"), "" if int(lamps[pid]) == 1 else " brighter (level %d)" % int(lamps[pid])], false)


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
		"res": res, "hungry": hungry, "recruits": recruits, "surge": surge, "next_surge_day": next_surge_day,
		"buildings": buildings, "construction": construction, "lamps": lamps, "lamp_jobs": lamp_jobs,
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
	var saved_recruits = d.get("recruits", {})
	if typeof(saved_recruits) == TYPE_DICTIONARY and not saved_recruits.is_empty():
		recruits = {}
		for id in saved_recruits:
			if recruit_data.has(id):
				var r: Dictionary = saved_recruits[id]
				recruits[id] = {"role": r.get("role", "idle"), "target": r.get("target", ""), "injured": int(r.get("injured", 0))}
	surge = d.get("surge", {})
	next_surge_day = int(d.get("next_surge_day", 4))
	var saved_b: Dictionary = d.get("buildings", {})
	for id in saved_b:
		if building_data.has(id):
			buildings[id] = clampi(int(saved_b[id]), 0, building_data[id]["levels"].size())
	var c: Dictionary = d.get("construction", {})
	if building_data.has(c.get("id", "")):
		construction = {"id": c["id"], "start": float(c["start"]), "finish": float(c["finish"])}
	var saved_l: Dictionary = d.get("lamps", {})
	for pid in saved_l:
		lamps[pid] = int(saved_l[pid])
	var saved_j: Dictionary = d.get("lamp_jobs", {})
	for pid in saved_j:
		lamp_jobs[pid] = {"start": float(saved_j[pid]["start"]), "finish": float(saved_j[pid]["finish"])}
	if d.has("rng_state"):
		rng.state = int(d["rng_state"])
	for saved in d.get("provinces", []):
		var p := territory().find(saved["id"])
		if not p.is_empty():
			p["owner"] = saved["owner"]
			p["fray"] = saved["fray"]
			p["scar"] = int(saved.get("scar", 0))
