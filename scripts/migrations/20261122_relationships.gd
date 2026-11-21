extends RefCounted
## Romance, rivalries and fates arrive (issue #116, scripts/relationships.gd): the campaign gains
## empire.relations = {"partner", "romance", "ended_seen", "pairs", "fates"}.
##
## Dated after 20261121_journal on purpose: it reads the journal's history, which that step builds for
## saves older than the journal.
##
## An older save has no romance and no pair history: nobody has been asked yet, and rivals start
## counting towards a truce from zero. Anyone already past rank 3 with a romanceable character simply
## gets asked next time (Relationships.moment_ready). What the save does remember goes into the fates
## the epilogues read:
##   - Lost: every "<name> did not come back" line in the history and the reports kept, with its day
##     and the job, for people no longer on the roster.
##   - Injuries: every "<name> came back hurt" and "<name> was dragged back from the white" line.
##     Someone hurt right now with no line left on record (reports roll off after 12) counts once.
##   - Personal missions already done count as one try.
## Missions fought were never counted per person, so they start at 0.
## A save that already has relations, or has no campaign, is left alone.


static func migrate(save: Dictionary) -> Dictionary:
	var empire = save.get("empire", {})
	if typeof(empire) != TYPE_DICTIONARY or empire.is_empty() or empire.has("relations"):
		return save
	var names := _names()
	var roster = empire.get("recruits", {})
	if typeof(roster) != TYPE_DICTIONARY:
		roster = {}
	var fates := {}
	# History entries (the journal) plus any report the journal doesn't hold (saves from before it).
	var entries := []
	var seen := {}
	var jl = empire.get("journal", {})
	if typeof(jl) == TYPE_DICTIONARY and typeof(jl.get("log")) == TYPE_ARRAY:
		for e in jl["log"]:
			if typeof(e) == TYPE_DICTIONARY and str(e.get("kind", "")) == "expedition":
				entries.append(e)
				seen["%d|%s" % [int(e.get("day", 0)), str(e.get("title", ""))]] = true
	if typeof(empire.get("reports")) == TYPE_ARRAY:
		for r in empire["reports"]:
			if typeof(r) == TYPE_DICTIONARY and not seen.has("%d|%s" % [int(r.get("day", 0)), str(r.get("title", ""))]):
				entries.append(r)
	for e in entries:
		var lines = e.get("lines", [])
		if typeof(lines) != TYPE_ARRAY:
			continue
		for l in lines:
			var line := str(l)
			for id in names:
				for n in names[id]:
					if line.begins_with(n + " did not come back") and not roster.has(id):
						var f := _fate(fates, id)
						f["lost_day"] = maxi(int(e.get("day", 1)), 1)
						f["lost_where"] = str(e.get("title", "")).get_slice(":", 0)
					elif line.begins_with(n + " came back hurt") or line.begins_with(n + " was dragged back from the white"):
						var hurt := _fate(fates, id)
						hurt["injuries"] = int(hurt["injuries"]) + 1
	for id in roster:
		var st = roster[id]
		if typeof(st) == TYPE_DICTIONARY and int(st.get("injured", 0)) > 0 and int(_fate(fates, id)["injuries"]) == 0:
			fates[id]["injuries"] = 1
	var bonds = empire.get("bonds", {})
	if typeof(bonds) == TYPE_DICTIONARY:
		for id in bonds:
			if typeof(bonds[id]) == TYPE_DICTIONARY and bool(bonds[id].get("personal_done", false)):
				_fate(fates, id)["personal_tries"] = 1
	# Drop the empty records _fate() made along the way.
	for id in fates.keys():
		var f: Dictionary = fates[id]
		if int(f["injuries"]) == 0 and int(f["lost_day"]) == 0 and int(f["personal_tries"]) == 0:
			fates.erase(id)
	empire["relations"] = {"partner": "", "romance": {}, "ended_seen": {}, "pairs": {}, "fates": fates}
	return save


static func _fate(fates: Dictionary, id: String) -> Dictionary:
	if not fates.has(id):
		fates[id] = {"missions": 0, "wins": 0, "injuries": 0, "lost_day": 0, "lost_where": "", "personal_tries": 0,
			"personal_day": 0, "choices": {}}
	return fates[id]


## id -> the names reports use for them: the full name and the short one (as Empire.short_name makes it).
static func _names() -> Dictionary:
	var out := {}
	var f := FileAccess.open("res://data/recruits.json", FileAccess.READ)
	if f == null:
		return out
	var d = JSON.parse_string(f.get_as_text())
	if typeof(d) != TYPE_DICTIONARY:
		return out
	for r in d.get("recruits", []):
		var n := str(r.get("name", ""))
		if n == "":
			continue
		var short := n.get_slice(" ", 0)
		for title in ["Old ", "Mother ", "Sister ", "Corporal ", "Mr. ", "The ", "Big "]:
			if n.begins_with(title):
				short = n.get_slice(" ", 1) if title in ["Corporal ", "Big "] else n
				break
		out[str(r["id"])] = [n] if short == n else [n, short]
	return out
