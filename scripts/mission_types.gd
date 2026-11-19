class_name MissionTypes
extends RefCounted
## The three Act 1 mission types the Command Table offers on its own (#51), built at runtime
## from the empire's state rather than written into data/missions.json:
##   Defense  - a surge is gathering against a province: go and hold the line.
##   Reclaim  - a province has been erased: push in, break its Blot, pay Ink to rewrite it.
##   Rescue   - someone the rumours talk about is stuck somewhere dangerous: fetch them in person.
##
## Each one is an ordinary mission dict (the same shape Missions.launch takes) with an
## "objective" that Objective hands to MissionObjectives, plus "effects": the type's change to
## the empire, applied by apply() when the results screen settles the mission.

const MAP := "res://maps/frayed_meadow.txt"
const RECLAIM_INK := 3
const RECLAIM_FRAY := 60  # what a rewritten province starts at: thin, but standing
const DEFENSE_FRAY := -5  # the line you held stays a little firmer
const TYPE_NAMES := {"defense": "Defense", "reclaim": "Reclaim", "rescue": "Rescue"}
const TYPE_COLORS := {"defense": Color("ff8a6a"), "reclaim": Color("eeebe2"), "rescue": Color("8ad1ff")}

## Where things stand on the reused Frayed Meadow map (tiles). The Blank's wall is at tile 69.
const WARD_AT := [50, 31]
const BLOT_AT := [64, 30]
const RESCUE_SPOTS := [[60, 9], [60, 50], [59, 22]]


## Every type-mission on offer for a province right now, each with a "blocker"
## ("" = it can be launched). Defense first: it has a deadline.
static func for_province(pid: String) -> Array:
	var p := Empire.territory().find(pid)
	if p.is_empty():
		return []
	var out := []
	if Empire.surge.get("id", "") == pid and p["owner"] != "erased":
		out.append(defense(p))
	if p["owner"] == "erased":
		out.append(reclaim(p))
	for jid in Empire.job_ids():
		var j := Empire.job(jid)
		if j.get("kind", "") == "Rescue" and j.get("province", "") == pid and j.get("recruit", "") != "":
			out.append(rescue(jid))
	return out


static func defense(p: Dictionary) -> Dictionary:
	var days := Empire.surge_days_left()
	var hard := clampi(int(p["fray"]) / 25, 0, 3)  # worn-thin land is harder to hold
	return {
		"id": "defense_" + p["id"], "type": "defense", "effects": true, "province": p["id"], "map": MAP,
		"name": "Defend %s" % p["name"],
		"brief": "The Blank is gathering against %s. Hold the wardstone until the surge breaks and it never lands. Every Nibbler you disperse pushes the white back a little. Lands in %d day%s if you do nothing." \
			% [p["name"], days, "" if days == 1 else "s"],
		"objective": {"kind": "defense", "seconds": 70 + 10 * hard, "ward": WARD_AT, "ward_hp": 100,
			"creep": 3.0 + hard, "push": 7.0, "spawn_every": maxf(2.0, 3.2 - 0.3 * hard)},
		"rewards": {"renown": 1, "supplies": 4},
		"blocker": "",
	}


static func reclaim(p: Dictionary) -> Dictionary:
	var blocker := ""
	var t := Empire.territory()
	var reachable := false
	for n in t.neighbors[p["index"]]:
		reachable = reachable or t.provinces[n]["owner"] != "erased"
	if not reachable:
		blocker = "nothing standing borders it: reclaim a neighbour first"
	elif int(Empire.res.get("ink", 0)) < RECLAIM_INK:
		blocker = "needs %d Ink to rewrite (you have %d)" % [RECLAIM_INK, int(Empire.res.get("ink", 0))]
	return {
		"id": "reclaim_" + p["id"], "type": "reclaim", "effects": true, "province": p["id"], "map": MAP,
		"name": "Reclaim %s" % p["name"],
		"brief": "Push into the white and break the Blot that holds %s. It spits Nibblers while it lives. Win, and %d Ink rewrites the land: it comes back unclaimed at %d Fray." \
			% [p["name"], RECLAIM_INK, RECLAIM_FRAY],
		"cost_text": "%d Ink on success" % RECLAIM_INK,
		"objective": {"kind": "reclaim", "blot": BLOT_AT, "hp": 220, "spawn_every": 4.0},
		"rewards": {"renown": 2},
		"blocker": blocker,
	}


static func rescue(jid: String) -> Dictionary:
	var j := Empire.job(jid)
	var rid: String = j["recruit"]
	var p := Empire.territory().find(j["province"])
	var blocker := ""
	if p.get("owner", "") == "erased":
		blocker = "%s has been erased" % p.get("name", "?")
	elif not Empire.expedition_running(jid).is_empty():
		blocker = "a squad is already out after them"
	var spot: Array = RESCUE_SPOTS[absi(hash(rid)) % RESCUE_SPOTS.size()]
	return {
		"id": "rescue_" + rid, "type": "rescue", "effects": true, "province": j["province"], "map": MAP, "job": jid,
		"name": "Rescue: %s" % Empire.recruit(rid).get("name", rid),
		"brief": "%s Go yourself instead of sending a squad: find %s before the white closes over them, then bring them back to where you came in." \
			% [j.get("blurb", ""), Empire.short_name(rid)],
		"objective": {"kind": "rescue", "who": rid, "at": spot, "creep": 2.0, "guards": 4},
		"rewards": _flat(j.get("reward", {})),
		"blocker": blocker,
	}


## Expedition rewards can be [min, max] ranges; a mission pays the middle.
static func _flat(r: Dictionary) -> Dictionary:
	var out := {}
	for k in r:
		out[k] = (int(r[k][0]) + int(r[k][1])) / 2 if r[k] is Array else int(r[k])
	return out


## What a settled mission does to the empire. outcome: "success", "retreat" or "wiped".
## Returns lines for the results screen. dry = only say what would happen (Missions.settle
## shows the lines before the player confirms; Missions.apply then calls this for real).
static func apply(m: Dictionary, outcome: String, dry := false) -> Array:
	var lines := []
	var p := Empire.territory().find(m.get("province", ""))
	if p.is_empty():
		return lines
	var won := outcome == "success"
	match m.get("type", ""):
		"defense":
			if won:
				if Empire.surge.get("id", "") == p["id"]:
					lines.append("The surge against %s broke before it landed." % p["name"])
					if not dry:
						Empire.surge = {}
						Empire.next_surge_day = Empire.day + Empire.rng.randi_range(Empire.SURGE_GAP[0], Empire.SURGE_GAP[1])
				lines.append("%s's Fray %d (the line holds firmer)." % [p["name"], DEFENSE_FRAY])
				if not dry:
					p["fray"] = clampi(int(p["fray"]) + DEFENSE_FRAY, 0, 100)
			elif Empire.surge.get("id", "") == p["id"]:
				lines.append("The surge still lands on %s in %d day%s." % [p["name"], Empire.surge_days_left(), "" if Empire.surge_days_left() == 1 else "s"])
		"reclaim":
			if won and p["owner"] == "erased":
				lines.append("%d Ink rewrites %s: back on the map, unclaimed, Fray %d." % [RECLAIM_INK, p["name"], RECLAIM_FRAY])
				lines.append("Claim it from the Command Table with a governor%s." % Prompts.tag("govern"))
				if not dry:
					Empire.res["ink"] = maxi(int(Empire.res.get("ink", 0)) - RECLAIM_INK, 0)
					p["owner"] = "free"
					p["fray"] = RECLAIM_FRAY
					p["scar"] = 0
					Empire.notice.emit("%s has been reclaimed from the Blank." % p["name"], false)
			elif not won:
				lines.append("The Blot still stands. %s stays erased. No Ink was spent." % p["name"])
		"rescue":
			var rid: String = m.get("objective", {}).get("who", "")
			var jid: String = m.get("job", "")
			if won and rid != "" and not Empire.recruits.has(rid):
				if not dry:
					Empire.recruits[rid] = {"role": "idle", "target": "", "injured": 0}
				lines.append("%s joins your roster. Find them in Hollowmark or give them a job%s." % [Empire.recruit(rid).get("name", rid), Prompts.tag("roster")])
				var j := Empire.job(jid)
				for fid in j.get("standing", {}):
					if not dry:
						Empire.change_standing(fid, int(j["standing"][fid]), j["name"], true)
					lines.append("%s standing %+d." % [Empire.faction(fid).get("short", fid), int(j["standing"][fid])])
			elif not won:
				lines.append("%s is still out there. The rumour will keep." % Empire.short_name(rid))
	return lines
