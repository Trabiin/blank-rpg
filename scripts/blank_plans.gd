class_name BlankPlans
extends RefCounted
## Verity's plans (issue #33): pressure that aims the Blank at one province for a few days.
##
## Scripted plans come from data/blank.json and start on their day; after the list runs out a
## random plan repeats every few days. Story beats can add their own with Empire.add_pressure().
## Each active pressure is one more line in the province panel's Fray sources, with its
## counter (a governor halves it, a Wardlamp cancels it) spelled out, so the player can answer it.
##
## State lives in Empire.blank_plans (saved with the empire):
##   {"pressure": [{"id", "pid", "label", "per_day", "until", "counter"}], "next": index of the
##    next scripted plan, "repeat_day": day the next random plan lands (0 = not scheduled yet)}

const PATH := "res://data/blank.json"
const COUNTER_TEXT := {"governor": "halved by governor", "lamp": "cancelled by Wardlamp"}
const COUNTER_HINT := {"governor": "governor halves", "lamp": "Wardlamp cancels"}

static var _data: Dictionary = {}


static func data() -> Dictionary:
	if _data.is_empty():
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		_data = parsed if typeof(parsed) == TYPE_DICTIONARY else {"plans": [], "repeat_gap": [7, 10]}
	return _data


static func fresh() -> Dictionary:
	return {"pressure": [], "next": 0, "repeat_day": 0}


static func from_save(d, today := 1) -> Dictionary:
	var out := fresh()
	if typeof(d) != TYPE_DICTIONARY:
		# A save from before Verity's plans: don't fire every missed plan on consecutive dawns.
		for plan in data().get("plans", []):
			if int(plan.get("day", 0)) < today:
				out["next"] = int(out["next"]) + 1
		if int(out["next"]) >= data().get("plans", []).size():
			out["repeat_day"] = today + 3
		return out
	for e in d.get("pressure", []):
		if typeof(e) == TYPE_DICTIONARY and e.has("pid"):
			out["pressure"].append({"id": str(e.get("id", "")), "pid": str(e["pid"]), "label": str(e.get("label", "The Blank leans in")),
				"per_day": int(e.get("per_day", 1)), "until": int(e.get("until", 0)), "counter": str(e.get("counter", ""))})
	out["next"] = int(d.get("next", 0))
	out["repeat_day"] = int(d.get("repeat_day", 0))
	return out


## Aim the Blank at a province: +per_day Fray for the next `days` dawns. Adding the same id
## to the same province again extends it instead of stacking.
static func add(pid: String, label: String, per_day: int, days: int, counter := "", id := "") -> void:
	var p := Empire.territory().find(pid)
	if p.is_empty() or p["owner"] == "erased" or days <= 0:
		return
	if id == "":
		id = label
	var until := Empire.day + days
	for e in Empire.blank_plans["pressure"]:
		if e["pid"] == pid and e["id"] == id:
			e["until"] = maxi(int(e["until"]), until)
			e["per_day"] = per_day
			return
	Empire.blank_plans["pressure"].append({"id": id, "pid": pid, "label": label, "per_day": per_day, "until": until, "counter": counter})


## Active pressure on a province: [{"label", "per_day" (after counters), "days" left, "note"}].
## gov: as in Empire.fray_sources ("-" = as things stand, otherwise a what-if governor, "" = none).
static func on(p: Dictionary, gov := "-") -> Array:
	var out := []
	if p.get("owner", "") == "erased":
		return out
	var governed := false
	if gov == "-":
		governed = p["owner"] == "you" and Empire.governor_of(p["id"]) != ""
	else:
		governed = gov != ""
	for e in Empire.blank_plans["pressure"]:
		if e["pid"] != p["id"]:
			continue
		var left := int(e["until"]) - Empire.day
		if left <= 0:
			continue
		var v := int(e["per_day"])
		var note := ""
		match e["counter"]:
			"governor":
				if governed:
					v = v / 2
					note = COUNTER_TEXT["governor"]
			"lamp":
				if int(Empire.lamps.get(p["id"], 0)) > 0:
					v = 0
					note = COUNTER_TEXT["lamp"]
		if note == "" and COUNTER_HINT.has(e["counter"]):
			note = COUNTER_HINT[e["counter"]]
		out.append({"label": e["label"], "per_day": v, "days": left, "note": note})
	return out


## Lines for Empire.fray_sources(): [[label, change], ...].
static func sources(p: Dictionary, gov := "-") -> Array:
	var out := []
	for e in on(p, gov):
		var bits := ["%dd" % e["days"]]
		if e["note"] != "":
			bits.append(e["note"])
		out.append(["%s (%s)" % [e["label"], ", ".join(bits)], e["per_day"]])
	return out


## Province ids with any active pressure, for the map's markers.
static func targets() -> Array:
	var out := []
	for e in Empire.blank_plans["pressure"]:
		if int(e["until"]) > Empire.day and not e["pid"] in out:
			out.append(e["pid"])
	return out


## Dawn, after Fray has moved: spent pressure lifts, the next plan may start.
static func dawn() -> void:
	var t := Empire.territory()
	Empire.blank_plans["pressure"] = Empire.blank_plans["pressure"].filter(func(e):
		var p := t.find(e["pid"])
		return int(e["until"]) > Empire.day and not p.is_empty() and p["owner"] != "erased")
	var plans: Array = data().get("plans", [])
	if plans.is_empty():
		return
	var st: Dictionary = Empire.blank_plans
	var plan := {}
	if int(st["next"]) < plans.size():
		if Empire.day >= int(plans[st["next"]].get("day", 0)):
			plan = plans[st["next"]]
			st["next"] = int(st["next"]) + 1
			if int(st["next"]) >= plans.size():
				st["repeat_day"] = Empire.day + _gap()
	elif Empire.day >= int(st["repeat_day"]):
		plan = plans[Empire.rng.randi() % plans.size()]
		st["repeat_day"] = Empire.day + _gap()
	if plan.is_empty():
		return
	var pid := pick_target(str(plan.get("target", "exposed_frayest")))
	if pid == "":
		return
	add(pid, plan["label"], int(plan.get("per_day", 1)), int(plan.get("days", 3)), str(plan.get("counter", "")), plan["id"])
	var p := t.find(pid)
	Empire.notice.emit(str(plan.get("notice", "The Blank turns towards %s.")) % p["name"], p["owner"] == "you")


static func _gap() -> int:
	var g: Array = data().get("repeat_gap", [7, 10])
	return Empire.rng.randi_range(int(g[0]), int(g[1]))


## Resolves a plan's target rule to a province id ("" = nowhere sensible right now).
static func pick_target(rule: String) -> String:
	var t := Empire.territory()
	match rule:
		"concord_frayest":
			var c := _frayest(t.provinces.filter(func(p): return p["owner"] == "concord"))
			return c if c != "" else pick_target("exposed_frayest")
		"yours_frayest":
			var y := _frayest(t.provinces.filter(func(p): return p["owner"] == "you" and p["id"] != "hollowmark"))
			return y if y != "" else pick_target("hollowmark")
		"exposed_frayest":
			return _frayest(t.provinces.filter(func(p):
				if p["owner"] == "erased":
					return false
				if p.get("at_edge", false):
					return true
				for n in t.neighbors[p["index"]]:
					if t.provinces[n]["owner"] == "erased":
						return true
				return false))
		_:
			var p := t.find(rule)
			return rule if not p.is_empty() and p["owner"] != "erased" else ""


static func _frayest(list: Array) -> String:
	var best := ""
	var most := -1
	for p in list:
		if p["owner"] != "erased" and int(p["fray"]) > most:
			most = int(p["fray"])
			best = p["id"]
	return best
