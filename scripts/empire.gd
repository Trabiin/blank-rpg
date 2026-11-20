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
signal expedition_returned(report: Dictionary)
signal research_finished(id: String)
signal bond_ready(id: String)  # someone has a rank scene waiting

## The Blank. Fray per day from each source; see fray_sources().
const FRAY_FIRST_ERASED_NEIGHBOR := 3
const FRAY_MORE_ERASED_NEIGHBORS := 1  # each erased neighbour after the first
const FRAY_AT_EDGE := 2
const FRAY_UNHELD := 1
const FRAY_UNGOVERNED := 3  # nobody in charge: the Blank finds the gaps
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
## A province you hold with no governor only delivers this share (nobody collects).
const UNGOVERNED_OUTPUT := 0.75
## Governor fit: the province's favoured stat (data/provinces.json "favors").
const FIT_GOOD := 7  # this or more: +50% of the province's output and 1 less Fray a day
const FIT_POOR := 3  # this or less: -25% of its output and 1 more Fray a day
const FIT_BONUS := {"good": 0.5, "fair": 0.0, "poor": -0.25}
const FIT_FRAY := {"good": -1, "fair": 0, "poor": 1}
const STAT_NAMES := {"might": "Might", "craft": "Craft", "lore": "Lore", "charm": "Charm", "grit": "Grit"}
const CLAIM_DEFAULT := {"gilt": 40, "supplies": 10}

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
## Verity's plans and story pressure on the Blank: see scripts/blank_plans.gd.
var blank_plans := BlankPlans.fresh()
## Buildings: id -> level (0 = not built). Static facts live in data/buildings.json, see building().
var buildings := {}
## The Hollowmark building crew works on one thing at a time: {"id", "start", "finish"} in days.
var construction := {}
## Wardlamps: province id -> level, and lamps being put up: province id -> {"start", "finish"}.
var lamps := {}
var lamp_jobs := {}
var building_data := {}  # id -> Dictionary from the JSON, in file order
var lamp_data := {}
## Expeditions out right now: [{"job", "squad": [ids], "start", "finish"}] (days, like construction).
var expeditions := []
## Written reports from squads that came back, newest first: {"day", "job", "title", "outcome", "lines", "read"}.
var reports := []
var job_ready := {}  # job id -> first day it can be taken again
var job_data := {}  # id -> Dictionary from data/expeditions.json
var pair_data := []
## Research: finished node ids, days of study done per node, the node being studied now ("" = none),
## and nodes whose cost has been paid (shelving a node keeps both its progress and its payment).
var research_done := []
var research_progress := {}
var research_active := ""
var research_paid := []
var research_data := {}  # id -> Dictionary from data/research.json, in file order
var branch_data := []
## Diplomacy: faction id -> standing (-100..100), factions you have a trade pact with,
## "faction:deal" -> first day it can be asked again, the day fresh intel runs out, the next
## dawn the Concord makes trouble, and what happened lately (newest first).
var standing := {}
var pacts := []
var deal_ready := {}
var intel_until := 0
var next_trouble_day := 5
var diplo_log := []
var faction_data := {}  # id -> Dictionary from data/factions.json, in file order
var tier_data := []
var trade_breaks := 0
# Bonds (data/bonds.json): id -> {"points", "rank", "talk_day", "personal_done"} for the core cast who have joined.
var bonds := {}
var bond_data := {}
var mission_kills_bonded := 0  # how many kill steps this mission already paid out (not saved)
# Missions (scripts/missions.gd): the one being played (saved with the mission, not here),
# the ones cleared, and the last result (Hollowmark greets the party with it; not saved).
var active_mission := {}
var missions_cleared := []
var last_mission := {}
var progress := {}  # party XP, levels and gear (scripts/progress.gd, issue #15)
var rng := RandomNumberGenerator.new()
var _territory: Territory


## Quick menu (issue #6): field items carried into missions (scripts/satchel.gd) and the AI
## behaviour picked per hero in its Party tab (recruit id -> AllyAI.PRESETS key).
var satchel := {}
var ai_presets := {}


func territory() -> Territory:
	if _territory == null:
		_territory = Territory.new()
		_territory.build_grid(MAP_CELLS)
	return _territory


## Fresh campaign: day 1, provinces as written in data/provinces.json.
func reset() -> void:
	satchel = Satchel.start_stock()
	ai_presets = {}
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
	blank_plans = BlankPlans.fresh()
	Dialogue.seen = {}  # conversations and banter seen this campaign (dialogue.gd)
	_load_building_data()
	buildings = {}
	for id in building_data:
		buildings[id] = int(building_data[id].get("start_level", 0))
	construction = {}
	lamps = {}
	lamp_jobs = {}
	_load_expedition_data()
	expeditions = []
	reports = []
	job_ready = {}
	_load_research_data()
	research_done = []
	research_progress = {}
	research_active = ""
	research_paid = []
	_load_faction_data()
	standing = {}
	for fid in faction_data:
		standing[fid] = int(faction_data[fid].get("start", 0))
	pacts = []
	deal_ready = {}
	intel_until = 0
	next_trouble_day = 5
	diplo_log = []
	_load_bond_data()
	bonds = {}
	mission_kills_bonded = 0
	active_mission = {}
	missions_cleared = []
	last_mission = {}
	progress = Progress.fresh()
	visitors = {}
	rng.seed = 1234
	if _territory != null:
		_territory.reload_data()


func tick(delta: float) -> void:
	_check_leads()
	if SPEEDS[speed] == 0:
		return
	var days: float = delta * SPEEDS[speed] / DAY_SECONDS
	day_t += days
	_advance_research(days)
	while day_t >= 1.0:
		day_t -= 1.0
		day += 1
		_heal()
		_settle()
		_advance_blank()
		_advance_diplomacy()
		_advance_bonds()
		day_passed.emit(day)
	_advance_construction()
	_advance_expeditions()


## Every line of the daily ledger: [{"label", "gilt", "supplies", "ink", "note"}].
## The same list drives the actual payout and the breakdown shown to the player.
func ledger() -> Array:
	var lines := []
	for p in territory().provinces:
		if p["owner"] != "you":
			continue
		var keep := 1.0 - FRAY_OUTPUT_LOSS * float(p["fray"]) / 100.0
		var notes := []
		if keep < 0.99:
			notes.append("-%d%% from Fray" % int(round((1.0 - keep) * 100.0)))
		var gov := governor_of(p["id"])
		if gov == "":
			keep *= UNGOVERNED_OUTPUT
			notes.append("-%d%% no governor" % int(round((1.0 - UNGOVERNED_OUTPUT) * 100.0)))
		var line := {"label": p["name"], "note": ", ".join(notes)}
		for k in RESOURCES:
			line[k] = int(round(float(p.get("output", {}).get(k, 0)) * keep))
		lines.append(line)
		if gov != "":
			var e := governor_effect(gov, p["id"])
			lines.append({"label": "  Governor %s" % recruit(gov)["name"], "gilt": e["gilt"], "supplies": e["supplies"], "ink": e["ink"],
				"note": "%s fit" % e["fit"].capitalize()})
	var upkeep := UPKEEP_SUPPLIES * recruits.size()
	lines.append({"label": "Upkeep (%d people)" % recruits.size(), "gilt": 0, "supplies": -upkeep, "ink": 0, "note": ""})
	var qm := current_effect("command_table")
	if int(qm.get("upkeep_cut", 0)) > 0:
		lines.append({"label": "  Quartermaster's savings", "gilt": 0, "supplies": mini(int(qm["upkeep_cut"]), upkeep), "ink": 0, "note": ""})
	if has_research("log_rations") and recruits.size() >= 4:
		lines.append({"label": "  Ration tables", "gilt": 0, "supplies": recruits.size() / 4, "ink": 0, "note": "research"})
	var ink := current_effect("inkworks")
	if int(ink.get("ink", 0)) > 0:
		lines.append({"label": "Inkworks", "gilt": 0, "supplies": 0, "ink": int(ink["ink"]), "note": ""})
	var guild := current_effect("guildhall")
	if int(guild.get("gilt", 0)) > 0:
		lines.append({"label": "Guildhall contracts", "gilt": int(guild["gilt"]), "supplies": 0, "ink": 0, "note": ""})
	var ins := int(current_effect("scriptorium").get("insight", 0))
	if ins > 0:
		lines.append({"label": "Scriptorium", "gilt": 0, "supplies": 0, "ink": 0, "note": "+%d Insight" % ins})
	_diplomacy_ledger(lines)
	for b in bond_perk_lines():
		lines.append(b)
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
	res["insight"] = int(res.get("insight", 0)) + int(current_effect("scriptorium").get("insight", 0)) + bond_perk_total("insight")
	hungry = res["supplies"] < 0
	if hungry:
		res["supplies"] = 0
	Progress.dawn()  # the Barracks trains whoever is on the bench
	ledger_settled.emit(net)


# ---------------------------------------------------------------- the Blank

## Every reason a province's Fray moves each day: [[label, change], ...]. The province panel
## shows exactly this list, so the player can always see why the Blank is moving.
## gov: "-" = as things stand; otherwise "what if you held it with this governor" ("" = none).
func fray_sources(p: Dictionary, gov := "-") -> Array:
	var out := []
	var owner: String = p["owner"]
	if gov != "-" and owner != "erased":
		owner = "you"
	elif gov == "-":
		gov = governor_of(p["id"])
	if owner == "erased":
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
	if owner == "you":
		if gov == "":
			out.append(["No governor posted", FRAY_UNGOVERNED])
		else:
			out.append(["Governed by %s" % recruit(gov)["name"], governor_effect(gov, p["id"])["fray"]])
		out.append(["Tended by your people", FRAY_TENDED])
		if has_research("ward_margins"):
			out.append(["Margin wards (research)", -1])
		if int(lamps.get(p["id"], 0)) > 0:
			var lv := int(lamps[p["id"]])
			var bright := has_research("ward_lampwright")
			out.append(["Wardlamp (level %d%s)" % [lv, ", written" if bright else ""], lamp_fray(lv) - (1 if bright else 0)])
		if has_perk("coven"):
			var woods := t.find(faction("coven")["province"])
			if not woods.is_empty() and woods["owner"] != "erased" and woods["index"] in t.neighbors[p["index"]]:
				out.append(["Coven hedge-wards (Friendly)", -1])
	elif owner == "free":
		out.append(["Nobody holds it", FRAY_UNHELD])
	out.append_array(BlankPlans.sources(p, gov if owner == "you" else "-"))
	return out


func fray_rate(p: Dictionary, gov := "-") -> int:
	var total := 0
	for src in fray_sources(p, gov):
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
	BlankPlans.dawn()


## Story beats aim the Blank too: +per_day Fray on a province for the next `days` dawns, listed in
## its panel under `label`. counter: "governor" (halved while governed), "lamp" (a Wardlamp cancels it) or "".
func add_pressure(province_id: String, label: String, per_day: int, days: int, counter := "") -> void:
	BlankPlans.add(province_id, label, per_day, days, counter)


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
	_react_near(p["id"], "erased_near")
	if p["id"] == "hollowmark":
		hollowmark_lost.emit()


func _update_surge() -> void:
	var t := territory()
	if not surge.is_empty() and day >= int(surge["day"]):
		var p := t.find(surge["id"])
		var aid: String = surge.get("aid", "")
		surge = {}
		if not p.is_empty() and p["owner"] != "erased":
			var hit := surge_fray() / (2 if aid != "" else 1)
			p["fray"] = mini(int(p["fray"]) + hit, 100)
			p["scar"] = SURGE_SCAR_DAYS
			notice.emit("The Blank surged into %s. +%d Fray%s." % [p["name"], hit, " (halved: the %s held the line)" % faction(aid)["short"] if aid != "" else ""], p["owner"] == "you")
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


## How hard a surge hits. The Long Watch takes the edge off.
func surge_fray() -> int:
	return SURGE_FRAY - (4 if has_research("ward_longwatch") else 0)


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


## How well a recruit suits a province: "good", "fair" or "poor", from its favoured stat.
func governor_fit(id: String, pid: String) -> String:
	var p := territory().find(pid)
	if p.is_empty():
		return "fair"
	var v := int(recruit(id)["stats"].get(p.get("favors", "charm"), 5))
	return "good" if v >= FIT_GOOD else ("poor" if v <= FIT_POOR else "fair")


## What a recruit does for a province they govern: Fray change per day, extra output, and
## "why": [[text, good?], ...] so the screens can show every reason.
func governor_effect(id: String, pid := "") -> Dictionary:
	var st: Dictionary = recruit(id)["stats"]
	var p := territory().find(pid) if pid != "" else {}
	var why := []
	var grit := int(st["grit"])
	var fray := -(1 + grit / 4)
	why.append(["Grit %d: holds the line, Fray %d a day" % [grit, fray], true])
	var gilt := int(st["charm"]) / 3
	var supplies := int(st["craft"]) / 3
	var ink := 0
	why.append(["Charm %d: +%d Gilt, Craft %d: +%d Supplies" % [int(st["charm"]), gilt, int(st["craft"]), supplies], true])
	var fit := "fair"
	if not p.is_empty():
		var fav: String = p.get("favors", "charm")
		fit = governor_fit(id, pid)
		var share: float = FIT_BONUS[fit]
		var bonus := []
		for k in RESOURCES:
			var base := int(p.get("output", {}).get(k, 0))
			var extra := int(round(base * share))
			if base > 0 and share > 0.0:
				extra = maxi(extra, 1)
			if k == "gilt":
				gilt += extra
			elif k == "supplies":
				supplies += extra
			else:
				ink += extra
			if extra != 0:
				bonus.append("%+d %s" % [extra, RES_NAMES[k]])
		fray += FIT_FRAY[fit]
		var label: String = {"good": "Good fit", "fair": "Fair fit", "poor": "Poor fit"}[fit]
		var tail := ""
		if fit != "fair":
			tail = ": %s, Fray %+d" % [", ".join(bonus), FIT_FRAY[fit]]
		why.append(["%s (%s %d; %s wants %s)%s" % [label, STAT_NAMES[fav], int(st[fav]), p["name"], STAT_NAMES[fav], tail], fit != "poor"])
	if has_trait(id, "stubborn"):
		fray -= 1
		why.append(["Stubborn: will not give an inch, Fray -1", true])
	if has_trait(id, "coward"):
		var c := 2 if not p.is_empty() and int(p["fray"]) >= 50 else 1
		fray += c
		why.append(["Coward: flinches%s, Fray +%d" % [" at the edge" if c > 1 else "", c], false])
	if has_trait(id, "greedy"):
		gilt += 2
		why.append(["Greedy: squeezes harder, +2 Gilt", true])
	if has_trait(id, "ink_sick") and not p.is_empty():
		if int(p.get("output", {}).get("ink", 0)) > 0:
			ink += 1
			why.append(["Ink-sick: hears the spring, +1 Ink", true])
		if int(p["fray"]) >= 25:
			fray += 1
			why.append(["Ink-sick: the Blank smells them, Fray +1", false])
	if has_trait(id, "ex_concord") and not p.is_empty():
		var t := territory()
		for n in t.neighbors[p["index"]]:
			if t.provinces[n]["owner"] == "concord":
				gilt += 1
				why.append(["Ex-Concord: knows the toll forms next door, +1 Gilt", true])
				break
	return {"fray": fray, "gilt": gilt, "supplies": supplies, "ink": ink, "fit": fit, "why": why}


## A rough single number for sorting governor candidates (higher is better).
func governor_score(id: String, pid: String) -> int:
	var e := governor_effect(id, pid)
	return -3 * int(e["fray"]) + int(e["gilt"]) + int(e["supplies"]) + 3 * int(e["ink"])


## Why a recruit can't govern right now ("" = they can).
func governor_blocker(id: String) -> String:
	if recruit(id).get("locked_party", false):
		return "Ash leads every mission"
	if role_of(id) == "expedition":
		return "away on an expedition"
	if int(recruits[id]["injured"]) > 0:
		return "injured"
	return ""


func claim_cost(pid: String) -> Dictionary:
	return territory().find(pid).get("claim", CLAIM_DEFAULT)


func borders_yours(pid: String) -> bool:
	var t := territory()
	var p := t.find(pid)
	for n in t.neighbors[p["index"]]:
		if t.provinces[n]["owner"] == "you":
			return true
	return false


## Why a province can't be claimed right now ("" = it can, given a governor).
func claim_blocker(pid: String) -> String:
	var p := territory().find(pid)
	match p.get("owner", ""):
		"you":
			return "already yours"
		"erased":
			return "Erased. Reclaim missions arrive with #51"
		"concord", "coven", "guild":
			var fa := faction(p["owner"])
			if deal(p["owner"], "cede").is_empty():
				return "%s land. They will never hand it over" % fa["short"]
			return "%s land. Reach Allied standing and ask for it%s" % [fa["short"], Prompts.tag("diplomacy")]
	if not borders_yours(pid):
		return "Too far. Claim the land in between first"
	var miss := _missing(claim_cost(pid))
	if miss != "":
		return "Need " + miss
	return ""


## Plants your flag on an unclaimed province and posts a governor there in one go.
func claim(pid: String, gov: String) -> bool:
	if claim_blocker(pid) != "" or governor_blocker(gov) != "":
		return false
	if not spend(claim_cost(pid)):
		return false
	var p := territory().find(pid)
	p["owner"] = "you"
	assign(gov, "governor", pid)
	notice.emit("%s is yours. %s governs it." % [p["name"], recruit(gov)["name"]], false)
	_react_near(pid, "claim_near")
	return true


## Takes the governor out of a province (they go back to Hollowmark, idle).
func recall_governor(pid: String) -> void:
	var gov := governor_of(pid)
	if gov != "":
		recruits[gov]["role"] = "idle"
		recruits[gov]["target"] = ""


## Everything a recruit could be assigned to right now, with what it would do.
## Each: {"role", "target", "label", "enabled", "note", "preview"}.
func role_options(id: String) -> Array:
	var r := recruit(id)
	var st: Dictionary = recruits[id]
	var out := []
	if st["role"] == "expedition":
		var e := expedition_running(st["target"])
		var back := job_left_text(e) if not e.is_empty() else "soon"
		out.append({"role": "expedition", "target": st["target"], "label": "On expedition: %s" % job(st["target"]).get("name", "?"),
			"enabled": false, "note": "back in %s" % back, "preview": "Away from Hollowmark. Back in %s; nothing can be changed until then." % back})
		return out
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
		var e := governor_effect(id, p["id"])
		var current := governor_of(p["id"])
		var replaces := "" if current == "" or current == id else "  Replaces %s." % recruit(current)["name"]
		var reasons := []
		for w in e["why"]:
			reasons.append(w[0])
		var preview := "%s: Fray %+d/day there (now %+d). Governor adds %s a day.%s\n%s" % [p["name"], fray_rate(p, id), fray_rate(p),
			output_text(e), replaces, "\n".join(reasons)]
		out.append({"role": "governor", "target": p["id"], "label": "Govern %s  (%s fit)" % [p["name"], e["fit"]],
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
	var expedition_note := ("send squads from the Expeditions screen" + Prompts.tag("expeditions")) if level_of("guildhall") > 0 else "needs a Guildhall"
	for fid in faction_ids():
		var fa := faction(fid)
		var cur := envoy_of(fid)
		var replaces := "" if cur == "" or cur == id else "  Replaces %s." % short_name(cur)
		var reasons := []
		for w in envoy_effect(id, fid)["why"]:
			reasons.append(w[0])
		var preview := "%s: standing %+d/day (now %+d). %s %d, %s.%s\n%s" % [fa["name"], standing_rate(fid, id), standing_rate(fid),
			tier_name(tier_of(fid)), standing_of(fid), "they respect " + STAT_NAMES[fa["respects"]], replaces, "\n".join(reasons)]
		var note := "Ash leads the party" if locked else ("injured" if hurt else "")
		out.append({"role": "envoy", "target": fid, "label": "Envoy to the %s  (%+d/day)" % [fa["short"], int(envoy_effect(id, fid)["drift"])],
			"enabled": note == "", "note": note, "preview": preview})
	out.append({"role": "expedition", "target": "", "label": ROLE_NAMES["expedition"], "enabled": false, "note": expedition_note, "preview": ""})
	return out


func assign(id: String, role: String, target := "") -> bool:
	for o in role_options(id):
		if o["role"] == role and o["target"] == target and o["enabled"]:
			if role == "envoy":
				var cur := envoy_of(target)
				if cur != "" and cur != id:
					recruits[cur]["role"] = "idle"
					recruits[cur]["target"] = ""
			if role == "governor":
				var current := governor_of(target)
				if current != "" and current != id:
					recruits[current]["role"] = "idle"
					recruits[current]["target"] = ""
			recruits[id]["role"] = role
			recruits[id]["target"] = target
			return true
	return false


## "+3 Gilt, +1 Supplies" (or "nothing").
func output_text(e: Dictionary) -> String:
	var parts := []
	for k in RESOURCES:
		if int(e.get(k, 0)) != 0:
			parts.append("%+d %s" % [int(e[k]), RES_NAMES[k]])
	return ", ".join(parts) if not parts.is_empty() else "nothing"


func role_label(id: String) -> String:
	var st: Dictionary = recruits[id]
	var label: String = ROLE_NAMES.get(st["role"], st["role"])
	if st["role"] == "governor":
		label = "Governor of %s" % territory().find(st["target"]).get("name", "?")
	elif st["role"] == "staff":
		var b := building(st["target"])
		label = "%s at the %s" % [b.get("staff_title", "Staff"), b.get("name", "?")]
	elif st["role"] == "envoy":
		label = "Envoy to the %s" % faction(st["target"]).get("short", "?")
	elif st["role"] == "expedition":
		var e := expedition_running(st["target"])
		label = "Away: %s%s" % [job(st["target"]).get("name", "?"), (" (back in %s)" % job_left_text(e)) if not e.is_empty() else ""]
	if int(st["injured"]) > 0:
		label += "  (injured, %d days)" % int(st["injured"])
	return label


func _heal() -> void:
	var per_day := 1 + int(current_effect("infirmary").get("extra_heal", 0)) + bond_perk_total("heal")
	for id in recruits:
		if int(recruits[id]["injured"]) > 0:
			recruits[id]["injured"] = maxi(int(recruits[id]["injured"]) - per_day, 0)


# ---------------------------------------------------------------- expeditions

const SQUAD_MIN := 2
const SQUAD_MAX := 4
const EXPEDITION_PER_POINT := 4  # % success per point of squad strength over or under the job's target
const CHANCE_MIN := 5
const CHANCE_MAX := 95
const REPORTS_KEPT := 12
const DANGER_NAMES := ["", "Low", "Risky", "Deadly"]


func _load_expedition_data() -> void:
	if not job_data.is_empty():
		return
	var f := FileAccess.open("res://data/expeditions.json", FileAccess.READ)
	var parsed = JSON.parse_string(f.get_as_text())
	for j in parsed["jobs"]:
		job_data[j["id"]] = j
	pair_data = parsed.get("pairs", [])


func job(id: String) -> Dictionary:
	_load_expedition_data()
	return job_data.get(id, {})


## Jobs worth listing: rescues vanish once the person has joined.
func job_ids() -> Array:
	_load_expedition_data()
	return job_data.keys().filter(func(j): return not recruits.has(job_data[j].get("recruit", "")) and personal_open(j))


## How many squads the Guildhall can have out at once (one per level).
func expedition_slots() -> int:
	return level_of("guildhall")


func expedition_running(jid: String) -> Dictionary:
	for e in expeditions:
		if e["job"] == jid:
			return e
	return {}


## Why a job can't be taken right now ("" = it can, given a squad).
func job_blocker(jid: String) -> String:
	var j := job(jid)
	var needs: Dictionary = j.get("needs", {})
	var gh := level_of("guildhall")
	if gh <= 0:
		return "build the Guildhall first" + Prompts.tag("buildings")
	if gh < int(needs.get("guildhall", 1)):
		return "needs Guildhall level %d" % int(needs["guildhall"])
	var p := territory().find(j["province"])
	if needs.get("erased", false):
		if p.get("owner", "") != "erased":
			return "only once %s is erased" % p.get("name", "?")
	elif p.get("owner", "") == "erased":
		return "%s has been erased" % p.get("name", "?")
	if not expedition_running(jid).is_empty():
		return "a squad is already out on it"
	if int(job_ready.get(jid, 0)) > day:
		var d := int(job_ready[jid]) - day
		return "nothing new there for %d day%s" % [d, "" if d == 1 else "s"]
	if expeditions.size() >= expedition_slots():
		return "all squads are out (%d/%d). Upgrade the Guildhall for more" % [expeditions.size(), expedition_slots()]
	return ""


## Why a recruit can't join a squad ("" = they can).
func squad_blocker(id: String) -> String:
	if recruit(id).get("locked_party", false):
		return "Ash leads every mission"
	if role_of(id) == "expedition":
		return "already away"
	if int(recruits[id]["injured"]) > 0:
		return "injured"
	return ""


## How long a job takes, in days. Waystations cut a quarter off.
func job_days(jid: String) -> float:
	return float(job(jid).get("days", 1)) * (0.75 if has_research("log_waystations") else 1.0)


## "2 days", "1.5 days", "1 day".
func job_days_text(jid: String) -> String:
	var d := job_days(jid)
	var s := str(int(d)) if is_equal_approx(d, roundf(d)) else ("%.2f" % d).rstrip("0")
	return "%s day%s" % [s, "" if is_equal_approx(d, 1.0) else "s"]


func expedition_cost(jid: String, n: int) -> Dictionary:
	return {"supplies": int(job(jid).get("rations", 1)) * n}


## One recruit's strength for a job: their stats times the job's weights.
func job_strength(jid: String, id: String) -> float:
	var total := 0.0
	var st: Dictionary = recruit(id)["stats"]
	var w: Dictionary = job(jid)["stats"]
	for k in w:
		total += float(st.get(k, 0)) * float(w[k])
	return total


## Success chance for a squad, and every reason behind it: {"chance", "strength", "why": [[text, good?]]}.
func expedition_odds(jid: String, squad: Array) -> Dictionary:
	var j := job(jid)
	var needs: Dictionary = j.get("needs", {})
	var why := []
	# The two strongest count in full; extra hands help, but only half as much.
	var parts := squad.map(func(id): return job_strength(jid, id))
	parts.sort()
	parts.reverse()
	var strength := 0.0
	for i in parts.size():
		strength += parts[i] * (1.0 if i < 2 else 0.5)
	var target := float(j["target"])
	var chance := 50.0 + (strength - target) * EXPEDITION_PER_POINT
	var stat_names := []
	for k in j["stats"]:
		stat_names.append(STAT_NAMES[k] + ("" if float(j["stats"][k]) >= 1.0 else " (half)"))
	why.append(["Squad %s: %d vs %d needed" % [" + ".join(stat_names), int(round(strength)), int(target)], strength >= target])
	if squad.size() > 2:
		why.append(["Extra hands: everyone past the strongest two counts half", true])
	var danger := int(j["danger"])
	for id in squad:
		var n := short_name(id)
		if has_trait(id, "coward") and danger >= 2:
			chance -= 10
			why.append(["%s is a Coward: bolts at the first noise, -10%%" % n, false])
		if has_trait(id, "stubborn") and danger >= 2:
			chance += 5
			why.append(["%s is Stubborn: will not turn back, +5%%" % n, true])
		if has_trait(id, "night_owl") and j["kind"] in ["Scouting", "Rescue"]:
			chance += 5
			why.append(["%s is a Night Owl: moves by dark, +5%%" % n, true])
		if has_trait(id, "bookish"):
			if j["kind"] == "Scouting":
				chance += 5
				why.append(["%s is Bookish: draws a proper map, +5%%" % n, true])
			elif j["kind"] == "Escort":
				chance -= 5
				why.append(["%s is Bookish: reads through the ambush, -5%%" % n, false])
		if has_trait(id, "contract") and j.get("reward", {}).has("gilt"):
			chance += 5
			why.append(["%s is Contracted: fights harder for coin, +5%%" % n, true])
		if has_trait(id, "flirt") and j["kind"] == "Rescue":
			chance += 5
			why.append(["%s is a Flirt: rescues go smoother, +5%%" % n, true])
		if has_trait(id, "ink_sick") and needs.get("blank", false):
			chance += 10
			why.append(["%s is Ink-sick: can feel where the Blank is thin, +10%%" % n, true])
		if has_trait(id, "ex_concord") and needs.get("concord", false):
			chance += 10
			why.append(["%s is Ex-Concord: knows the toll posts, +10%%" % n, true])
		if has_trait(id, "greedy") and j.get("reward", {}).has("gilt"):
			why.append(["%s is Greedy: brings back 20%% more Gilt (and pockets some)" % n, true])
	if has_research("log_fieldmaps"):
		chance += 10
		why.append(["Field Maps (research), +10%", true])
	if has_perk("guild"):
		chance += 10
		why.append(["Guild scouts share the road (Friendly), +10%", true])
	for pk in bond_perks_with("squad_odds"):
		if pk["id"] in squad:
			chance += int(pk["effect"]["squad_odds"])
			why.append(["%s (%s's bond), +%d%%" % [pk["name"], short_name(pk["id"]), int(pk["effect"]["squad_odds"])], true])
	for pk in bond_perks_with("all_odds"):
		chance += int(pk["effect"]["all_odds"])
		why.append(["%s (%s's bond), +%d%%" % [pk["name"], short_name(pk["id"]), int(pk["effect"]["all_odds"])], true])
	var who: String = j.get("personal", "")
	if who != "" and not who in squad:
		why.append(["Personal: %s has to go" % short_name(who), false])
	for pair in pair_data:
		if pair["ids"][0] in squad and pair["ids"][1] in squad:
			chance += int(pair["mod"])
			why.append(["%s, %+d%%" % [pair["text"], int(pair["mod"])], int(pair["mod"]) > 0])
	var c := clampi(int(round(chance)), CHANCE_MIN, CHANCE_MAX)
	return {"chance": c, "strength": strength, "why": why}


## "+16-24 Supplies, +1 Renown, a new recruit".
func reward_text(jid: String) -> String:
	var j := job(jid)
	var parts := []
	var rw: Dictionary = j.get("reward", {})
	for k in ["gilt", "supplies", "ink", "insight", "renown"]:
		if not rw.has(k):
			continue
		var v = rw[k]
		if typeof(v) == TYPE_ARRAY:
			parts.append("+%d-%d %s" % [int(v[0]), int(v[1]), RES_NAMES[k]] if int(v[0]) != int(v[1]) else "+%d %s" % [int(v[0]), RES_NAMES[k]])
		else:
			parts.append("+%d %s" % [int(v), RES_NAMES[k]])
	if int(j.get("fray", 0)) != 0:
		parts.append("%s Fray %d" % [territory().find(j["province"]).get("name", "?"), int(j["fray"])])
	if j.get("recruit", "") != "":
		parts.append("%s joins" % recruit(j["recruit"])["name"])
	return ", ".join(parts)


func send_expedition(jid: String, squad: Array) -> bool:
	if job_blocker(jid) != "" or squad_rule(jid, squad) != "" or squad.size() < SQUAD_MIN or squad.size() > SQUAD_MAX:
		return false
	for id in squad:
		if squad_blocker(id) != "":
			return false
	if not spend(expedition_cost(jid, squad.size())):
		return false
	var now := day + day_t
	for id in squad:
		recruits[id]["role"] = "expedition"
		recruits[id]["target"] = jid
	expeditions.append({"job": jid, "squad": squad.duplicate(), "start": now, "finish": now + job_days(jid)})
	return true


func unread_reports() -> int:
	return reports.filter(func(r): return not r.get("read", false)).size()


func _roll_amount(v) -> int:
	if typeof(v) == TYPE_ARRAY:
		return rng.randi_range(int(v[0]), int(v[1]))
	return int(v)


func _fill(s: String, squad: Array) -> String:
	var names := squad.map(func(id): return short_name(id))
	var all: String = ", ".join(names.slice(0, names.size() - 1)) + " and " + names[-1] if names.size() > 1 else names[0]
	var b: String = names[1] if names.size() > 1 else names[0]
	return s.replace("{lead}", names[0]).replace("{a}", names[0]).replace("{b}", b).replace("{squad}", all)


## A squad comes home: roll the outcome, pay out, hurt people, write the report.
func _resolve_expedition(e: Dictionary) -> void:
	var jid: String = e["job"]
	var j := job(jid)
	var squad: Array = e["squad"].filter(func(id): return recruits.has(id))
	for id in squad:
		recruits[id]["role"] = "idle"
		recruits[id]["target"] = ""
	job_ready[jid] = day + int(j.get("cooldown", 1))
	if squad.is_empty():
		return
	var odds := expedition_odds(jid, squad)
	var roll := rng.randf() * 100.0
	var outcome := "fail"
	if roll < float(odds["chance"]):
		outcome = "great" if roll < float(odds["chance"]) * 0.2 else "success"
	var lines := []
	var order := squad  # {lead} is whoever was picked first
	var tales: Array = j["text"]["fail" if outcome == "fail" else "success"]
	lines.append(_fill(tales[rng.randi_range(0, tales.size() - 1)], order))
	if outcome == "great":
		lines.append("A great haul: half again what anyone expected.")
	# Loot
	var mult: float = {"great": 1.5, "success": 1.0, "fail": 0.25}[outcome]
	var loot := []
	var greedy := squad.filter(func(id): return has_trait(id, "greedy")).size()
	for k in ["gilt", "supplies", "ink", "insight", "renown"]:
		if not j.get("reward", {}).has(k):
			continue
		var amount := int(round(_roll_amount(j["reward"][k]) * mult))
		if k == "gilt" and greedy > 0:
			amount = int(round(amount * (1.0 + 0.2 * greedy)))
		if k == "renown" and outcome == "fail":
			amount = 0
		if amount > 0:
			gain(k, amount)
			loot.append("+%d %s" % [amount, RES_NAMES[k]])
	lines.append("Brought back: %s." % (", ".join(loot) if not loot.is_empty() else "nothing but stories"))
	if outcome == "fail":
		for fid in j.get("standing_fail", {}):
			change_standing(fid, int(j["standing_fail"][fid]), j["name"] + " (failed)", true)
			lines.append("%s standing %+d." % [faction(fid).get("short", fid), int(j["standing_fail"][fid])])
	if outcome != "fail":
		var p := territory().find(j["province"])
		if int(j.get("fray", 0)) != 0 and not p.is_empty() and p["owner"] != "erased":
			p["fray"] = clampi(int(p["fray"]) + int(j["fray"]), 0, 100)
			lines.append("%s's Fray %+d." % [p["name"], int(j["fray"])])
		for fid in j.get("standing", {}):
			change_standing(fid, int(j["standing"][fid]), j["name"], true)
			lines.append("%s standing %+d." % [faction(fid).get("short", fid), int(j["standing"][fid])])
		for id in squad:
			if has_bond(id):
				bond_gain(id, int(bond_data["points"]["expedition"]), "", true)
		var pid: String = j.get("personal", "")
		if pid != "" and has_bond(pid):
			bonds[pid]["personal_done"] = true
			bond_gain(pid, 999, "", true)
			lines.append("%s has something to tell Ash. (Bonds: H, or find them in Hollowmark.)" % short_name(pid))
		var rid: String = j.get("recruit", "")
		if rid != "" and not recruits.has(rid) and recruit_data.has(rid):
			recruits[rid] = {"role": "idle", "target": "", "injured": 0}
			lines.append("%s joins your roster. Find them in Hollowmark or give them a job%s." % [recruit(rid)["name"], Prompts.tag("roster")])
	# A quip from someone on the squad
	var quippers := squad.filter(func(id): return not recruit(id).get("quips", []).is_empty())
	if not quippers.is_empty():
		var q: Array = recruit(quippers[rng.randi_range(0, quippers.size() - 1)])["quips"]
		lines.append(q[rng.randi_range(0, q.size() - 1)])
	# Injuries, and (rarely) a loss
	var danger := int(j["danger"])
	var hurt := []
	if outcome == "fail":
		for id in squad:
			if rng.randf() < 0.2 * danger:
				hurt.append(id)
		if danger >= 3 and rng.randf() < 0.12:
			var who: String = squad[rng.randi_range(0, squad.size() - 1)]
			hurt.erase(who)
			if recruit(who)["tier"] == "recruit":
				recruits.erase(who)
				lines.append("%s did not come back. The others waited a day at the edge. The white gave nothing back." % recruit(who)["name"])
			else:
				recruits[who]["injured"] = 8
				lines.append("%s was dragged back from the white, barely. Out of action for 8 days." % short_name(who))
	elif danger >= 2 and rng.randf() < 0.1 * (danger - 1):
		hurt.append(squad[rng.randi_range(0, squad.size() - 1)])
	for id in hurt:
		var days := 1 + danger + rng.randi_range(0, 1)
		recruits[id]["injured"] = maxi(int(recruits[id]["injured"]), days)
		lines.append("%s came back hurt: out of action for %d days." % [short_name(id), days])
	var title := "%s: %s" % [j["name"], {"great": "great success", "success": "success", "fail": "failed"}[outcome]]
	reports.push_front({"day": day, "job": jid, "title": title, "outcome": outcome, "squad": squad,
		"chance": int(odds["chance"]), "lines": lines, "read": false})
	if reports.size() > REPORTS_KEPT:
		reports.resize(REPORTS_KEPT)
	notice.emit("Squad back from %s: %s. Report: E" % [territory().find(j["province"]).get("name", "?"), {"great": "great success", "success": "success", "fail": "it went badly"}[outcome]], outcome == "fail")
	expedition_returned.emit(reports[0])


func _advance_expeditions() -> void:
	var now := day + day_t
	for e in expeditions.duplicate():
		if now >= float(e["finish"]):
			expeditions.erase(e)
			_resolve_expedition(e)


## "Brannoc", "Old Tobble", "Mother Gristle": how people are named in reports.
func short_name(id: String) -> String:
	var n: String = recruit(id).get("name", "?")
	for title in ["Old ", "Mother ", "Sister ", "Corporal ", "Mr. ", "The ", "Big "]:
		if n.begins_with(title):
			return n.get_slice(" ", 1) if title in ["Corporal ", "Big "] else n
	return n.get_slice(" ", 0)


# ---------------------------------------------------------------- research

const RESEARCH_PER_LORE := 0.05  # +5% study pace per point of researcher Lore (Bookish counts double)
const RESEARCH_PER_LEVEL := 0.25  # +25% per Scriptorium level past the first


func _load_research_data() -> void:
	if not research_data.is_empty():
		return
	var f := FileAccess.open("res://data/research.json", FileAccess.READ)
	var parsed = JSON.parse_string(f.get_as_text())
	branch_data = parsed["branches"]
	for n in parsed["nodes"]:
		research_data[n["id"]] = n


func research_node(id: String) -> Dictionary:
	_load_research_data()
	return research_data.get(id, {})


func research_ids() -> Array:
	_load_research_data()
	return research_data.keys()


func research_branches() -> Array:
	_load_research_data()
	return branch_data


func has_research(id: String) -> bool:
	return id in research_done


## How fast the Scriptorium studies: {"pace": 1.0 = 100%, "why": [text, ...]}. 0 = stalled.
func research_pace() -> Dictionary:
	var lv := level_of("scriptorium")
	if lv <= 0:
		return {"pace": 0.0, "why": ["No Scriptorium yet: build it on the Buildings screen" + Prompts.tag("buildings")]}
	var staff := staff_of("scriptorium")
	if _working(staff) == 0:
		return {"pace": 0.0, "why": ["Nobody at the desks: give the Scriptorium a researcher (B or R)"]}
	var why := ["Base pace 100%"]
	var pace := 1.0
	for r in staff:
		if int(recruits[r]["injured"]) > 0:
			why.append("%s is injured and not reading" % short_name(r))
			continue
		var lore := int(recruit(r)["stats"]["lore"])
		var pts := lore * (2 if has_trait(r, "bookish") else 1)
		pace += pts * RESEARCH_PER_LORE
		why.append("%s, Lore %d%s: +%d%%" % [short_name(r), lore, " x2 (Bookish)" if has_trait(r, "bookish") else "", int(round(pts * RESEARCH_PER_LORE * 100))])
	if lv > 1:
		pace += (lv - 1) * RESEARCH_PER_LEVEL
		why.append("Scriptorium level %d: +%d%%" % [lv, int(round((lv - 1) * RESEARCH_PER_LEVEL * 100))])
	for pk in bond_perks_with("research_pace"):
		pace += float(pk["effect"]["research_pace"])
		why.append("%s (%s's bond): +%d%%" % [pk["name"], short_name(pk["id"]), int(round(float(pk["effect"]["research_pace"]) * 100))])
	return {"pace": pace, "why": why}


## Days of study still owed on a node (at 100% pace).
func research_remaining(id: String) -> float:
	return maxf(float(research_node(id).get("days", 1)) - float(research_progress.get(id, 0.0)), 0.0)


func research_fraction(id: String) -> float:
	return clampf(float(research_progress.get(id, 0.0)) / maxf(float(research_node(id).get("days", 1)), 0.001), 0.0, 1.0)


## "1 day 4 h" at the current pace, or "stalled".
func research_left_text(id: String) -> String:
	var pace := float(research_pace()["pace"])
	if pace <= 0.0:
		return "stalled"
	return days_left_text(research_remaining(id) / pace)


## "available", "active", "shelved" (started, then set aside), "done" or "locked".
func research_state(id: String) -> String:
	if has_research(id):
		return "done"
	if id == research_active:
		return "active"
	if id in research_paid:
		return "shelved"
	return "available" if _research_lock(id) == "" else "locked"


## What stops a node from being studied at all, regardless of resources ("" = nothing).
func _research_lock(id: String) -> String:
	var n := research_node(id)
	for need in n.get("needs", []):
		if not has_research(need):
			return "needs %s first" % research_node(need)["name"]
	var lv := int(n.get("scriptorium", 1))
	if level_of("scriptorium") < lv:
		return "needs the Scriptorium" + (" at level %d" % lv if lv > 1 else "")
	return ""


## Why a node can't be started right now ("" = it can).
func research_blocker(id: String) -> String:
	if has_research(id):
		return "already known"
	if id == research_active:
		return "already being studied"
	var lock := _research_lock(id)
	if lock != "":
		return lock
	if not id in research_paid and not can_afford(research_node(id)["cost"]):
		return "not enough " + _missing(research_node(id)["cost"])
	return ""


## "8 Insight, 3 Ink".
func cost_text(cost: Dictionary) -> String:
	var parts := []
	for k in ["insight", "ink", "gilt", "supplies"]:
		if int(cost.get(k, 0)) > 0:
			parts.append("%d %s" % [int(cost[k]), RES_NAMES[k]])
	return ", ".join(parts) if not parts.is_empty() else "free"


## Starts (or resumes) studying a node. Pays its cost the first time; whatever was being
## studied before is shelved with its progress kept.
func start_research(id: String) -> bool:
	if research_blocker(id) != "":
		return false
	if not id in research_paid:
		spend(research_node(id)["cost"])
		research_paid.append(id)
	research_active = id
	return true


## Stops studying. Progress and payment stay with the node.
func shelve_research() -> void:
	research_active = ""


func _advance_research(days: float) -> void:
	if research_active == "":
		return
	var pace := float(research_pace()["pace"])
	if pace <= 0.0:
		return
	var id := research_active
	research_progress[id] = float(research_progress.get(id, 0.0)) + days * pace
	if research_remaining(id) <= 0.0:
		research_done.append(id)
		research_progress.erase(id)
		research_paid.erase(id)
		research_active = ""
		var n := research_node(id)
		notice.emit("Research done: %s. %s." % [n["name"], n["effect"]], false)
		research_finished.emit(id)


## What finished research does on missions: the numbers main.gd applies, plus a short line
## per node for the mission HUD.
func mission_boosts() -> Dictionary:
	var b := {"damage": 0, "hp": 0, "revive": 1.0, "guard": 0.0, "power_rate": 1.0, "ink_regen": 1.0, "lines": []}
	if has_research("arms_whetstone"):
		b["damage"] += 2
	if has_research("arms_steel"):
		b["damage"] += 3
		b["power_rate"] = 1.2
	if b["damage"] > 0:
		b["lines"].append("+%d damage" % b["damage"])
	if has_research("arms_steel"):
		b["lines"].append("faster gauge")
	if has_research("arms_leather"):
		b["hp"] += 10
		b["lines"].append("+10 max HP")
	if has_research("ink_tap"):
		b["ink_regen"] = 1.25
		b["lines"].append("faster Ink")
	if has_research("ink_blot"):
		b["revive"] = 1.4
		b["lines"].append("faster revives")
	if has_research("ink_skin"):
		b["guard"] = 0.25
		b["lines"].append("-25% damage taken")
	for pk in bond_perks_with("mission_hp"):
		b["hp"] += int(pk["effect"]["mission_hp"])
		b["lines"].append("+%d max HP (%s)" % [int(pk["effect"]["mission_hp"]), pk["name"]])
	for pk in bond_perks_with("mission_damage"):
		b["damage"] += int(pk["effect"]["mission_damage"])
		b["lines"].append("+%d damage (%s)" % [int(pk["effect"]["mission_damage"]), pk["name"]])
	for pk in bond_perks_with("mission_revive"):
		b["revive"] *= 1.0 + float(pk["effect"]["mission_revive"])
		b["lines"].append("faster revives (%s)" % pk["name"])
	return b


## Damage a party member actually takes from a hit, after Inkskin.
func damage_to_party(amount: int) -> int:
	if has_research("ink_skin"):
		return maxi(1, int(round(amount * 0.75)))
	return amount


# ---------------------------------------------------------------- diplomacy

const DIPLO_LOG_KEPT := 12
const DEAL_ORDER := ["gift", "intel", "trade", "aid", "cede"]
const DEAL_TIER := {"gift": "hostile", "intel": "neutral", "trade": "friendly", "aid": "friendly", "cede": "allied"}
const FACTION_FIT_GOOD := 7
const FACTION_FIT_POOR := 3


func _load_faction_data() -> void:
	if not faction_data.is_empty():
		return
	var f := FileAccess.open("res://data/factions.json", FileAccess.READ)
	var parsed = JSON.parse_string(f.get_as_text())
	tier_data = parsed["tiers"]
	trade_breaks = int(parsed.get("trade_breaks", 0))
	for fa in parsed["factions"]:
		faction_data[fa["id"]] = fa


func faction(fid: String) -> Dictionary:
	_load_faction_data()
	return faction_data.get(fid, {})


func faction_ids() -> Array:
	_load_faction_data()
	return faction_data.keys()


func standing_of(fid: String) -> int:
	return int(standing.get(fid, 0))


## "hostile", "wary", "neutral", "friendly" or "allied" for a standing value.
func tier_for(v: int) -> String:
	_load_faction_data()
	var out := "hostile"
	for t in tier_data:
		if v >= int(t["min"]):
			out = t["id"]
	return out


func tier_of(fid: String) -> String:
	return tier_for(standing_of(fid))


func tier_name(tier: String) -> String:
	_load_faction_data()
	for t in tier_data:
		if t["id"] == tier:
			return t["name"]
	return tier.capitalize()


func tier_min(tier: String) -> int:
	_load_faction_data()
	for t in tier_data:
		if t["id"] == tier:
			return int(t["min"])
	return -100


func tier_rank(tier: String) -> int:
	_load_faction_data()
	for i in tier_data.size():
		if tier_data[i]["id"] == tier:
			return i
	return 0


func at_least(fid: String, tier: String) -> bool:
	return tier_rank(tier_of(fid)) >= tier_rank(tier)


## Friendly standing switches on a faction's perk.
func has_perk(fid: String) -> bool:
	return at_least(fid, "friendly")


func envoy_of(fid: String) -> String:
	for id in roster_ids():
		if recruits[id]["role"] == "envoy" and recruits[id]["target"] == fid:
			return id
	return ""


## What a recruit does posted as envoy to a faction: standing per day, plus every reason.
func envoy_effect(id: String, fid: String) -> Dictionary:
	var fa := faction(fid)
	var st: Dictionary = recruit(id)["stats"]
	var why := []
	var charm := int(st["charm"])
	var flirt := has_trait(id, "flirt")
	var drift := 1 + (charm * (2 if flirt else 1)) / 3
	why.append(["Charm %d%s: %+d a day" % [charm, " x2 (Flirt)" if flirt else "", drift], true])
	var stat: String = fa.get("respects", "charm")
	var v := int(st.get(stat, 5))
	if v >= FACTION_FIT_GOOD:
		drift += 1
		why.append(["%s %d: the %s respect that, +1" % [STAT_NAMES[stat], v, fa["short"]], true])
	elif v <= FACTION_FIT_POOR:
		drift -= 1
		why.append(["%s %d: the %s want %s, -1" % [STAT_NAMES[stat], v, fa["short"], STAT_NAMES[stat]], false])
	if has_trait(id, "greedy"):
		drift -= 1
		why.append(["Greedy: haggles over everything, -1", false])
	if has_trait(id, "ex_concord") and fid == "concord":
		drift -= 2
		why.append(["Ex-Concord: the Concord hates them for it, -2", false])
	if has_trait(id, "ink_sick") and fid == "coven":
		drift += 1
		why.append(["Ink-sick: the witches take pity, +1", true])
	if has_trait(id, "contract") and fid == "guild":
		drift += 1
		why.append(["Contracted: speaks fluent Guild, +1", true])
	if int(recruits.get(id, {}).get("injured", 0)) > 0:
		why.append(["Injured: not talking to anyone, no effect", false])
		drift = 0
	return {"drift": drift, "why": why}


## Every reason a faction's standing moves each day: [[label, change], ...].
## env: "-" = as things stand; otherwise "what if this recruit were envoy" ("" = none).
func standing_sources(fid: String, env := "-") -> Array:
	var fa := faction(fid)
	var out := []
	if env == "-":
		env = envoy_of(fid)
	if env != "":
		out.append(["Envoy %s" % short_name(env), int(envoy_effect(env, fid)["drift"])])
	var base := int(fa.get("drift", 0))
	if base != 0 and standing_of(fid) > int(fa.get("floor", -100)):
		out.append([fa.get("drift_why", "Drifts"), base])
	return out


func standing_rate(fid: String, env := "-") -> int:
	var total := 0
	for s in standing_sources(fid, env):
		total += int(s[1])
	return total


## Moves a faction's standing, writes it in the diplomacy log and says so when a tier changes.
func change_standing(fid: String, amount: int, why: String, quiet := false) -> void:
	if amount == 0 or not faction_data.has(fid):
		return
	var before := tier_of(fid)
	standing[fid] = clampi(standing_of(fid) + amount, -100, 100)
	var after := tier_of(fid)
	if why != "":
		diplo_log.push_front({"day": day, "faction": fid, "text": why, "change": amount})
		if diplo_log.size() > DIPLO_LOG_KEPT:
			diplo_log.resize(DIPLO_LOG_KEPT)
	var fa := faction(fid)
	if before != after:
		var up := tier_rank(after) > tier_rank(before)
		notice.emit("%s: now %s with you.%s" % [fa["name"], tier_name(after), " " + fa["perk"]["text"] + "." if up and after == "friendly" else ""], not up)
	elif not quiet and why != "":
		notice.emit("%s %+d standing: %s." % [fa["short"], amount, why], amount < 0)
	if fid in pacts and standing_of(fid) < trade_breaks:
		pacts.erase(fid)
		notice.emit("%s tore up your trade pact." % fa["name"], true)


func deal(fid: String, kind: String) -> Dictionary:
	return faction(fid).get("deals", {}).get(kind, {})


func deal_ids(fid: String) -> Array:
	return DEAL_ORDER.filter(func(k): return not deal(fid, k).is_empty())


func deal_cooldown_left(fid: String, kind: String) -> int:
	return maxi(int(deal_ready.get(fid + ":" + kind, 0)) - day, 0)


## Why a deal can't be made right now ("" = it can).
func deal_blocker(fid: String, kind: String) -> String:
	var fa := faction(fid)
	var d := deal(fid, kind)
	if d.is_empty():
		return "the %s don't do that" % fa.get("short", "?")
	if kind == "trade" and fid in pacts:
		return "already trading"
	if kind == "cede" and territory().find(fa["province"]).get("owner", "") != fid:
		return "it isn't theirs to give any more"
	if envoy_of(fid) == "":
		return "post an envoy first"
	if int(recruits[envoy_of(fid)]["injured"]) > 0:
		return "your envoy is injured"
	var need: String = DEAL_TIER[kind]
	if not at_least(fid, need):
		return "needs %s standing (%d+)" % [tier_name(need), tier_min(need)]
	var cd := deal_cooldown_left(fid, kind)
	if cd > 0:
		return "ask again in %d day%s" % [cd, "" if cd == 1 else "s"]
	if kind == "aid":
		if surge.is_empty() or territory().find(surge["id"]).get("owner", "") != "you":
			return "only while a surge gathers against your land"
		if surge.get("aid", "") != "":
			return "%s already help with this surge" % faction(surge["aid"]).get("short", "?")
	if kind == "intel" and intel_until > day:
		return "you still have fresh intel"
	if not can_afford(d.get("cost", {})):
		return "not enough " + _missing(d.get("cost", {}))
	return ""


## "30 Gilt", "-15 standing", etc: what a deal costs and gives, in one line.
func deal_summary(fid: String, kind: String) -> String:
	var d := deal(fid, kind)
	var parts := []
	if not d.get("cost", {}).is_empty():
		parts.append("costs " + cost_text(d["cost"]))
	match kind:
		"gift":
			parts.append("%+d standing" % int(d["standing"]))
		"intel":
			parts.append("+%d Insight, +1 surge warning for %d days" % [int(d.get("insight", 0)), int(d.get("warning_days", 5))])
		"trade":
			parts.append("then %s a day" % output_text(d["daily"]))
		"aid":
			parts.append("surge lands at half, %d standing" % int(d["standing"]))
		"cede":
			parts.append("%s becomes yours, %d standing" % [territory().find(faction(fid)["province"]).get("name", "?"), int(d["standing"])])
	return ", ".join(parts)


## Makes a deal. Returns what happened, for the screen to say (or "" if it couldn't).
func make_deal(fid: String, kind: String) -> String:
	if deal_blocker(fid, kind) != "":
		return ""
	var fa := faction(fid)
	var d := deal(fid, kind)
	spend(d.get("cost", {}))
	if d.has("cooldown"):
		deal_ready[fid + ":" + kind] = day + int(d["cooldown"])
	match kind:
		"gift":
			change_standing(fid, int(d["standing"]), d["name"], true)
		"intel":
			gain("insight", int(d.get("insight", 0)))
			intel_until = day + int(d.get("warning_days", 5))
			diplo_log.push_front({"day": day, "faction": fid, "text": d["name"] + ": +%d Insight" % int(d.get("insight", 0)), "change": 0})
		"trade":
			pacts.append(fid)
			diplo_log.push_front({"day": day, "faction": fid, "text": "Trade pact signed: " + d["name"], "change": 0})
		"aid":
			surge["aid"] = fid
			change_standing(fid, int(d["standing"]), d["name"], true)
		"cede":
			var p := territory().find(fa["province"])
			p["owner"] = "you"
			change_standing(fid, int(d["standing"]), d["name"], true)
			notice.emit("%s is yours. Post a governor there (G) before it frays." % p["name"], false)
	if diplo_log.size() > DIPLO_LOG_KEPT:
		diplo_log.resize(DIPLO_LOG_KEPT)
	return d["text"]


## A faction reacts to something you did (or something that happened next to their land).
func faction_react(fid: String, amount: int, why: String) -> void:
	change_standing(fid, amount, why)


## Factions whose own province borders a province: claims, erasures and lamps there get noticed.
func _react_near(pid: String, key: String) -> void:
	var t := territory()
	var p := t.find(pid)
	if p.is_empty():
		return
	for fid in faction_ids():
		var fa := faction(fid)
		var amount := int(fa.get("react", {}).get(key, 0))
		if amount == 0:
			continue
		var home := t.find(fa["province"])
		if home.is_empty() or home["owner"] != fid or home["id"] == pid:
			continue
		if home["index"] in t.neighbors[p["index"]]:
			change_standing(fid, amount, "%s (%s)" % [fa["react"].get("why_" + key.get_slice("_", 0), "Noticed"), p["name"]])


## Trade pacts (and a Friendly Concord) pay at dawn like everything else: ledger lines.
func _diplomacy_ledger(lines: Array) -> void:
	for fid in faction_ids():
		if fid in pacts:
			var d := deal(fid, "trade")
			var line := {"label": "%s: %s" % [faction(fid)["short"], d["name"]], "note": "trade pact"}
			for k in RESOURCES:
				line[k] = int(d["daily"].get(k, 0))
			lines.append(line)
	if has_perk("concord"):
		lines.append({"label": "Concord: Tithe Road tolls go easy", "gilt": 2, "supplies": 0, "ink": 0, "note": "Friendly"})


## Dawn: standing drifts, the Concord makes trouble.
func _advance_diplomacy() -> void:
	for fid in faction_ids():
		var fa := faction(fid)
		var rate := standing_rate(fid)
		if rate == 0:
			continue
		var target := standing_of(fid) + rate
		if rate < 0 and envoy_of(fid) == "":
			target = maxi(target, mini(standing_of(fid), int(fa.get("floor", -100))))
		change_standing(fid, target - standing_of(fid), "", true)
	_concord_trouble()


func _concord_trouble() -> void:
	var fa := faction("concord")
	var tr: Dictionary = fa.get("trouble", {})
	if tr.is_empty():
		return
	var tier := tier_of("concord")
	if not tier in ["hostile", "wary"]:
		next_trouble_day = maxi(next_trouble_day, day + int(tr["hostile_gap"][0]))
		return
	if day < next_trouble_day:
		return
	var gap: Array = tr["hostile_gap"] if tier == "hostile" else tr["wary_gap"]
	next_trouble_day = day + rng.randi_range(int(gap[0]), int(gap[1]))
	var pool: Array = tr["events"].filter(func(e): return tier in e["tiers"])
	if pool.is_empty():
		return
	var e: Dictionary = pool[rng.randi_range(0, pool.size() - 1)]
	var yours := territory().provinces.filter(func(p): return p["owner"] == "you")
	if yours.is_empty():
		return
	var text := ""
	match e["kind"]:
		"fine":
			var g := mini(_roll_amount(e["gilt"]), int(res["gilt"]))
			res["gilt"] -= g
			text = e["text"] % g
		"seize":
			var s := mini(_roll_amount(e["supplies"]), int(res["supplies"]))
			res["supplies"] -= s
			text = e["text"] % [s, yours[rng.randi_range(0, yours.size() - 1)]["name"]]
		"writ":
			var p: Dictionary = yours[rng.randi_range(0, yours.size() - 1)]
			p["fray"] = mini(int(p["fray"]) + int(e["fray"]), 100)
			text = e["text"] % [p["name"], int(e["fray"])]
	diplo_log.push_front({"day": day, "faction": "concord", "text": text, "change": 0, "trouble": true})
	if diplo_log.size() > DIPLO_LOG_KEPT:
		diplo_log.resize(DIPLO_LOG_KEPT)
	notice.emit(text, true)


## "The Concord will make trouble in about 3 days" for the screen, or "".
func trouble_text() -> String:
	if not tier_of("concord") in ["hostile", "wary"]:
		return ""
	var d := next_trouble_day - day
	return "Expect Concord trouble %s." % ("at dawn" if d <= 1 else "in about %d days" % d)


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
			var tap := 1 if has_research("ink_tap") else 0
			var ink := level + _stat_sum(staff, "craft", 3) + held + tap
			var extras := []
			if held > 0:
				extras.append("%d from Ink provinces" % held)
			if tap > 0:
				extras.append("1 from Spring Tapping")
			return {"ink": ink, "text": "+%d Ink a day" % ink + (" (%s)" % ", ".join(extras) if not extras.is_empty() else "")}
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
	return int(current_effect("command_table").get("warning", SURGE_WARNING_DAYS)) + (1 if has_research("ward_longwatch") else 0) \
		+ (1 if intel_until > day else 0) + bond_perk_total("surge_warning")


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
	return days_left_text(float(job["finish"]) - (day + day_t))


func days_left_text(days: float) -> String:
	var hours := ceili(maxf(days, 0.0) * 24.0)
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
			notice.emit("The %s is finished. Give it staff on the Buildings screen%s." % [b["name"], Prompts.tag("buildings")], false)
		else:
			notice.emit("The %s is now level %d." % [b["name"], level_of(id)], false)
		building_finished.emit(id)
	for pid in lamp_jobs.keys():
		if now >= float(lamp_jobs[pid]["finish"]):
			lamp_jobs.erase(pid)
			lamps[pid] = int(lamps.get(pid, 0)) + 1
			var p := territory().find(pid)
			notice.emit("The Wardlamp in %s is lit%s." % [p.get("name", "?"), "" if int(lamps[pid]) == 1 else " brighter (level %d)" % int(lamps[pid])], false)
			if int(lamps[pid]) == 1:
				_react_near(pid, "lamp_near")


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
		"blank_plans": blank_plans,
		"buildings": buildings, "construction": construction, "lamps": lamps, "lamp_jobs": lamp_jobs,
		"expeditions": expeditions, "reports": reports, "job_ready": job_ready,
		"research_done": research_done, "research_progress": research_progress, "research_active": research_active,
		"research_paid": research_paid,
		"standing": standing, "pacts": pacts, "deal_ready": deal_ready, "intel_until": intel_until,
		"next_trouble_day": next_trouble_day, "diplo_log": diplo_log,
		"bonds": bonds,
		"visitors": visitors,
		"missions_cleared": missions_cleared,
		"progress": progress,
		"dialogue": Dialogue.seen,
		"satchel": satchel, "ai_presets": ai_presets,
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
				if not ROLE_NAMES.has(recruits[id]["role"]):  # a job that no longer exists: back to idle
					recruits[id]["role"] = "idle"
					recruits[id]["target"] = ""
	surge = d.get("surge", {})
	next_surge_day = int(d.get("next_surge_day", 4))
	blank_plans = BlankPlans.from_save(d.get("blank_plans", null), day)
	var saved_satchel = d.get("satchel", null)
	if typeof(saved_satchel) == TYPE_DICTIONARY:
		for k in saved_satchel:
			satchel[k] = int(saved_satchel[k])
	var saved_ai = d.get("ai_presets", {})
	if typeof(saved_ai) == TYPE_DICTIONARY:
		ai_presets = saved_ai.duplicate()
	var saved_seen = d.get("dialogue", {})
	Dialogue.seen = saved_seen.duplicate() if typeof(saved_seen) == TYPE_DICTIONARY else {}
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
	for e in d.get("expeditions", []):
		if job_data.has(e.get("job", "")):
			var squad: Array = e.get("squad", []).filter(func(id): return recruits.has(id))
			expeditions.append({"job": e["job"], "squad": squad, "start": float(e["start"]), "finish": float(e["finish"])})
	for id in recruits:  # nobody is "away" without a squad to be away with
		if recruits[id]["role"] == "expedition" and expedition_running(recruits[id]["target"]).is_empty():
			recruits[id]["role"] = "idle"
			recruits[id]["target"] = ""
	for r in d.get("reports", []):
		if typeof(r) == TYPE_DICTIONARY:
			reports.append(r)
	var saved_jr: Dictionary = d.get("job_ready", {})
	for jid in saved_jr:
		job_ready[jid] = int(saved_jr[jid])
	for rid in d.get("research_done", []):
		if research_data.has(rid) and not rid in research_done:
			research_done.append(rid)
	for rid in d.get("research_paid", []):
		if research_data.has(rid) and not rid in research_paid:
			research_paid.append(rid)
	var saved_rp: Dictionary = d.get("research_progress", {})
	for rid in saved_rp:
		if research_data.has(rid):
			research_progress[rid] = float(saved_rp[rid])
	var ra: String = d.get("research_active", "")
	if research_data.has(ra) and not ra in research_done:
		research_active = ra
	var saved_st: Dictionary = d.get("standing", {})
	for fid in saved_st:
		if faction_data.has(fid):
			standing[fid] = clampi(int(saved_st[fid]), -100, 100)
	for fid in d.get("pacts", []):
		if faction_data.has(fid) and not fid in pacts:
			pacts.append(fid)
	var saved_dr: Dictionary = d.get("deal_ready", {})
	for k in saved_dr:
		deal_ready[k] = int(saved_dr[k])
	intel_until = int(d.get("intel_until", 0))
	next_trouble_day = int(d.get("next_trouble_day", day + 5))
	for mid in d.get("missions_cleared", []):
		if not mid in missions_cleared:
			missions_cleared.append(str(mid))
	for e in d.get("diplo_log", []):
		if typeof(e) == TYPE_DICTIONARY:
			diplo_log.append(e)
	for id in recruits:  # an envoy to a faction that no longer exists goes home
		if recruits[id]["role"] == "envoy" and not faction_data.has(recruits[id]["target"]):
			recruits[id]["role"] = "idle"
			recruits[id]["target"] = ""
	var saved_bonds: Dictionary = d.get("bonds", {})
	for id in saved_bonds:
		if bond_cast().has(id):
			var b: Dictionary = saved_bonds[id]
			bonds[id] = {"points": maxi(int(b.get("points", 0)), 0), "rank": clampi(int(b.get("rank", 0)), 0, 5),
				"talk_day": int(b.get("talk_day", 0)), "personal_done": bool(b.get("personal_done", false))}
	_load_visitors(d)
	progress = Progress.from_save(d.get("progress", {}))
	if d.has("rng_state"):
		rng.state = int(d["rng_state"])
	for saved in d.get("provinces", []):
		var p := territory().find(saved["id"])
		if not p.is_empty():
			p["owner"] = saved["owner"]
			p["fray"] = saved["fray"]
			p["scar"] = int(saved.get("scar", 0))


# ---------------------------------------------------------------- bonds

const BOND_MAX := 5


func _load_bond_data() -> void:
	if not bond_data.is_empty():
		return
	var f := FileAccess.open("res://data/bonds.json", FileAccess.READ)
	bond_data = JSON.parse_string(f.get_as_text())


func bond_cast() -> Dictionary:
	_load_bond_data()
	return bond_data["cast"]


func bond_info(id: String) -> Dictionary:
	return bond_cast().get(id, {})


## Is this someone Ash can bond with (core cast, on the roster)?
func has_bond(id: String) -> bool:
	return bond_cast().has(id) and recruits.has(id)


## The core cast who have joined, in roster order.
func bond_ids() -> Array:
	return roster_ids().filter(func(id): return bond_cast().has(id))


func _bond(id: String) -> Dictionary:
	if not bonds.has(id):
		bonds[id] = {"points": 0, "rank": 0, "talk_day": 0, "personal_done": false}
	return bonds[id]


func bond_rank(id: String) -> int:
	return int(bonds.get(id, {}).get("rank", 0))


func bond_points(id: String) -> int:
	return int(bonds.get(id, {}).get("points", 0))


func bond_threshold(rank: int) -> int:
	_load_bond_data()
	var r: Array = bond_data["ranks"]
	return int(r[clampi(rank, 0, r.size() - 1)])


func bond_rank_name(rank: int) -> String:
	_load_bond_data()
	return bond_data["rank_names"][clampi(rank, 0, BOND_MAX)]


func personal_job(id: String) -> String:
	_load_expedition_data()
	for jid in job_data:
		if job_data[jid].get("personal", "") == id:
			return jid
	return ""


func personal_done(id: String) -> bool:
	return bool(bonds.get(id, {}).get("personal_done", false))


## A personal job only shows on the board once its person is at rank 4 and has not done it yet.
func personal_open(jid: String) -> bool:
	var who: String = job(jid).get("personal", "")
	if who == "":
		return true
	return has_bond(who) and bond_rank(who) >= 4 and not personal_done(who)


## Why this squad can't take this job ("" = it can).
func squad_rule(jid: String, squad: Array) -> String:
	var who: String = job(jid).get("personal", "")
	if who != "" and not who in squad:
		return "it's personal: %s has to go" % short_name(who)
	return ""


## The rank scene waiting to be seen (1-5), or 0.
func bond_next_scene(id: String) -> int:
	if not has_bond(id):
		return 0
	var rank := bond_rank(id)
	if rank >= BOND_MAX:
		return 0
	if bond_points(id) < bond_threshold(rank + 1):
		return 0
	if rank + 1 == BOND_MAX and not personal_done(id):
		return 0
	return rank + 1


func bond_ready_ids() -> Array:
	return bond_ids().filter(func(id): return bond_next_scene(id) > 0)


## What stands between this person and their next rank, in words.
func bond_next_text(id: String) -> String:
	var rank := bond_rank(id)
	if rank >= BOND_MAX:
		return "Bound. Nothing left to prove."
	if bond_next_scene(id) > 0:
		return "Wants a word. Talk to them in Hollowmark (or %s here)." % ("tap them" if Prompts.touch() else "press " + Prompts.confirm())
	var need := bond_threshold(rank + 1) - bond_points(id)
	if rank == BOND_MAX - 1 and not personal_done(id):
		var pj := personal_job(id)
		if not expedition_running(pj).is_empty():
			return "Away on their personal job. Back in %s." % job_left_text(expedition_running(pj))
		return "Rank 5 needs their personal job: \"%s\" on the Guildhall board%s. They have to go on it." % [job(pj).get("name", "?"), Prompts.tag("expeditions")]
	if need > 0:
		return "%d more bond point%s to rank %d." % [need, "" if need == 1 else "s", rank + 1]
	return ""


## Can the scene be played right now (they are in Hollowmark)?
func bond_scene_blocker(id: String) -> String:
	if role_of(id) == "expedition":
		return "%s is away on an expedition" % short_name(id)
	return ""


## Add bond points. They never drop below the current rank and stop at the next rank until its scene is seen.
func bond_gain(id: String, amount: int, why := "", quiet := false) -> int:
	if not has_bond(id) or amount == 0:
		return 0
	var b := _bond(id)
	var rank := int(b["rank"])
	var was_ready := bond_next_scene(id) > 0
	var cap := bond_threshold(mini(rank + 1, BOND_MAX))
	var before := int(b["points"])
	b["points"] = clampi(before + amount, bond_threshold(rank), maxi(cap, before))
	var gained := int(b["points"]) - before
	if not was_ready and bond_next_scene(id) > 0:
		notice.emit("%s wants a word with Ash. Find them in Hollowmark (Bonds: H)." % short_name(id), false)
		bond_ready.emit(id)
	elif gained != 0 and why != "" and not quiet:
		notice.emit("%s: bond %+d (%s)." % [short_name(id), gained, why], false)
	return gained


## The first chat of the day in Hollowmark counts. Returns the points gained.
func bond_talk(id: String) -> int:
	if not has_bond(id):
		return 0
	var b := _bond(id)
	if int(b["talk_day"]) == day:
		return 0
	b["talk_day"] = day
	return bond_gain(id, int(bond_data["points"]["talk"]), "", true)


func talked_today(id: String) -> bool:
	return int(bonds.get(id, {}).get("talk_day", 0)) == day


## "likes", "dislikes" or "" for what they are doing right now.
func role_mood(id: String) -> String:
	var st: Dictionary = recruits.get(id, {})
	if st.is_empty():
		return ""
	return role_mood_for(id, st["role"], st["target"])


## Would they like or dislike this role? (for the roster's role list)
func role_mood_for(id: String, role: String, target: String) -> String:
	var info := bond_info(id)
	if info.is_empty():
		return ""
	var keys := [role, "%s:%s" % [role, target]]
	for k in keys:
		if k in info.get("likes", []):
			return "likes"
	for k in keys:
		if k in info.get("dislikes", []):
			return "dislikes"
	return ""


func _advance_bonds() -> void:
	for id in bond_ids():
		match role_mood(id):
			"likes":
				bond_gain(id, int(bond_data["points"]["liked_role"]), "", true)
			"dislikes":
				bond_gain(id, int(bond_data["points"]["disliked_role"]), "", true)


## Called by the mission scene on every kill: party members with bonds earn a little per few kills.
func bond_fought(kills: int, ids: Array) -> void:
	_load_bond_data()
	var p: Dictionary = bond_data["points"]
	if kills <= 0 or kills % int(p["kill_step"]) != 0 or mission_kills_bonded >= int(p["mission_cap"]):
		return
	mission_kills_bonded += 1
	for id in ids:
		if has_bond(id):
			bond_gain(id, int(p["mission"]), "", true)


func bond_scene(id: String, rank: int) -> Dictionary:
	for sc in bond_info(id).get("scenes", []):
		if int(sc["rank"]) == rank:
			return sc
	return {}


## Seen scenes can be replayed from the Bonds screen.
func bond_seen_scenes(id: String) -> Array:
	return bond_info(id).get("scenes", []).filter(func(sc): return int(sc["rank"]) <= bond_rank(id))


## The scene for the next rank was watched: rank up, then add what the choice was worth.
## Returns any perk this rank unlocked ({} if none).
func finish_bond_scene(id: String, rank: int, choice := -1) -> Dictionary:
	if bond_next_scene(id) != rank:
		return {}
	var b := _bond(id)
	b["rank"] = rank
	var sc := bond_scene(id, rank)
	var opts: Array = sc.get("choice", [])
	if choice >= 0 and choice < opts.size():
		bond_gain(id, int(opts[choice].get("bond", 0)), "", true)
	var perk: Dictionary = bond_info(id).get("perks", {}).get(str(rank), {})
	var msg := "%s is now %s (bond rank %d)." % [short_name(id), bond_rank_name(rank), rank]
	if not perk.is_empty():
		msg += " Perk: %s, %s" % [perk["name"], perk["desc"]]
	if rank == 4 and personal_job(id) != "":
		msg += " Their personal job is on the Guildhall board."
	notice.emit(msg, false)
	return perk


## Every perk unlocked so far: [{"id", "rank", "name", "desc", "effect"}].
func bond_perks() -> Array:
	var out := []
	for id in bond_ids():
		var perks: Dictionary = bond_info(id).get("perks", {})
		for r in perks:
			if bond_rank(id) >= int(r):
				var pk: Dictionary = perks[r].duplicate()
				pk["id"] = id
				pk["rank"] = int(r)
				out.append(pk)
	return out


func bond_perks_with(key: String) -> Array:
	return bond_perks().filter(func(pk): return pk["effect"].has(key))


func bond_perk_total(key: String) -> int:
	var t := 0
	for pk in bond_perks_with(key):
		t += int(pk["effect"][key])
	return t


## Ledger lines for perks that pay out daily.
func bond_perk_lines() -> Array:
	var out := []
	for pk in bond_perks():
		var e: Dictionary = pk["effect"]
		if not (e.has("gilt") or e.has("supplies") or e.has("ink") or e.has("insight")):
			continue
		out.append({"label": "%s (%s)" % [pk["name"], short_name(pk["id"])], "gilt": int(e.get("gilt", 0)),
			"supplies": int(e.get("supplies", 0)), "ink": int(e.get("ink", 0)),
			"note": ("+%d Insight" % int(e["insight"])) if e.has("insight") else "bond"})
	return out


# ---------------------------------------------------------------- newcomers (recruit leads)
## Everyone who is not on the starting roster has a "join" hook in data/recruits.json: claim a province,
## build something, reach a faction tier, finish research, earn Renown, or get close to someone.
## When the hook is met they turn up at Hollowmark's south gate and wait there until you take them on
## (talk to them in town, or Enter on the Newcomers screen, N) for their "hire" price.
## Rescue hooks are only listed: the rescue expedition brings that person in by itself.

signal lead_arrived(id: String)

## Visitors waiting at the gate: id -> the day they turned up.
var visitors := {}


func join_hook(id: String) -> Dictionary:
	return recruit(id).get("join", {})


## Everyone who could still join, waiting visitors first, then in roster order.
func lead_ids() -> Array:
	_load_recruit_data()
	var out := recruit_data.keys().filter(func(id): return not recruits.has(id) and not join_hook(id).is_empty())
	var waiting := out.filter(func(id): return visitors.has(id))
	return waiting + out.filter(func(id): return not visitors.has(id))


func is_visitor(id: String) -> bool:
	return visitors.has(id) and not recruits.has(id)


func hire_cost(id: String) -> Dictionary:
	return recruit(id).get("hire", {})


## Has this person's hook been met? (Rescues never are: the expedition handles those.)
func hook_met(id: String) -> bool:
	var h := join_hook(id)
	match h.get("type", ""):
		"claim":
			return territory().find(h.get("province", "")).get("owner", "") == "you"
		"building":
			return level_of(h.get("building", "")) >= int(h.get("level", 1))
		"standing":
			return faction_data.has(h.get("faction", "")) and at_least(h["faction"], h.get("tier", "friendly"))
		"research":
			return has_research(h.get("node", ""))
		"renown":
			return int(res.get("renown", 0)) >= int(h.get("amount", 1))
		"bond":
			return recruits.has(h.get("who", "")) and bond_rank(h["who"]) >= int(h.get("rank", 1))
	return false


## What you need to do, as one short sentence with the key to press.
func hook_text(id: String) -> String:
	var h := join_hook(id)
	match h.get("type", ""):
		"claim":
			return "Claim %s (G on the Command Table)." % territory().find(h.get("province", "")).get("name", "?")
		"building":
			var lv := int(h.get("level", 1))
			var bn: String = building(h.get("building", "")).get("name", "?")
			return ("Build the %s%s." % [bn, Prompts.tag("buildings")]) if lv <= 1 else ("Raise the %s to level %d%s." % [bn, lv, Prompts.tag("buildings")])
		"standing":
			return "Reach %s with the %s%s." % [tier_name(h.get("tier", "friendly")), faction(h.get("faction", "")).get("short", "?"), Prompts.tag("diplomacy")]
		"research":
			return "Finish %s at the Scriptorium%s." % [research_node(h.get("node", "")).get("name", "?"), Prompts.tag("research")]
		"renown":
			return "Reach %d Renown (expeditions, missions)." % int(h.get("amount", 1))
		"bond":
			return "Reach bond rank %d with %s%s." % [int(h.get("rank", 1)), short_name(h.get("who", "")), Prompts.tag("bonds")]
		"rescue":
			return "Send a squad on \"%s\" from the Guildhall%s." % [job(h.get("job", "")).get("name", "?"), Prompts.tag("expeditions")]
	return ""


## Where you stand on it right now: [text, good?].
func hook_progress(id: String) -> Array:
	var h := join_hook(id)
	if visitors.has(id):
		return ["Waiting at the south gate since day %d." % int(visitors[id]), true]
	match h.get("type", ""):
		"claim":
			var p := territory().find(h.get("province", ""))
			var owner: String = p.get("owner", "")
			if owner == "erased":
				return ["%s has been erased. Reclaim it first." % p.get("name", "?"), false]
			if owner == "free":
				return ["%s is unclaimed%s." % [p.get("name", "?"), "" if borders_yours(p.get("id", "")) else ", and not next to your land yet"], false]
			return ["%s is held by %s." % [p.get("name", "?"), faction(owner).get("short", owner)], false]
		"building":
			var bid: String = h.get("building", "")
			var lv := level_of(bid)
			var s := ("%s: level %d." % [building(bid).get("name", "?"), lv]) if lv > 0 else ("%s: not built yet." % building(bid).get("name", "?"))
			if construction.get("id", "") == bid:
				s += " Under construction."
			return [s, false]
		"standing":
			var fid: String = h.get("faction", "")
			return ["%s standing %d (%s). %s at %d." % [faction(fid).get("short", fid), standing_of(fid), tier_name(tier_of(fid)),
				tier_name(h.get("tier", "friendly")), tier_min(h.get("tier", "friendly"))], false]
		"research":
			var nid: String = h.get("node", "")
			var st := research_state(nid)
			if st == "active" or st == "shelved":
				return ["%d%% studied%s." % [int(research_fraction(nid) * 100.0), "" if st == "active" else ", shelved"], false]
			return ["Not started%s." % ("" if level_of("scriptorium") > 0 else "; needs a Scriptorium" + Prompts.tag("buildings")), false]
		"renown":
			return ["Renown %d of %d." % [int(res.get("renown", 0)), int(h.get("amount", 1))], false]
		"bond":
			var who: String = h.get("who", "")
			if not recruits.has(who):
				return ["%s hasn't joined yet." % recruit(who).get("name", "?"), false]
			return ["%s: bond rank %d of %d." % [short_name(who), bond_rank(who), int(h.get("rank", 1))], false]
		"rescue":
			var jid: String = h.get("job", "")
			if not expedition_running(jid).is_empty():
				return ["A squad is on its way.", true]
			var why := job_blocker(jid)
			return [("Can't send yet: %s." % why) if why != "" else "On the Guildhall board now.", why == ""]
	return ["", false]


## Why a visitor can't be taken on right now ("" = they can).
func hire_blocker(id: String) -> String:
	if recruits.has(id):
		return "already on the roster"
	if not visitors.has(id):
		return "not here yet"
	var short := _missing(hire_cost(id))
	return ("not enough " + short) if short != "" else ""


func hire(id: String) -> bool:
	if hire_blocker(id) != "" or not spend(hire_cost(id)):
		return false
	visitors.erase(id)
	recruits[id] = {"role": "idle", "target": "", "injured": 0}
	notice.emit("%s joins your roster. Give them a job%s." % [recruit(id)["name"], Prompts.tag("roster")], false)
	return true


## Checked every frame (cheap): anyone whose hook was just met turns up at the gate.
func _check_leads() -> void:
	for id in recruit_data:
		if recruits.has(id) or visitors.has(id) or not hook_met(id):
			continue
		visitors[id] = day
		var r := recruit(id)
		notice.emit("%s, %s, is waiting at Hollowmark's south gate. Talk to them in town, or open Newcomers%s." % [r["name"], r.get("title", ""), (" (" + Prompts.key("newcomers") + ")") if Prompts.key("newcomers") != "" else " from the menu"], false)
		lead_arrived.emit(id)


func _load_visitors(d: Dictionary) -> void:
	var saved: Dictionary = d.get("visitors", {})
	for id in saved:
		if recruit_data.has(id) and not recruits.has(id):
			visitors[id] = int(saved[id])
