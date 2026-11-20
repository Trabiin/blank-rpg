extends RefCounted
## Named a day later than the other steps on purpose: steps run in file-name order and this one needs a
## campaign to exist (20261120_save_format_v2 gives first-build saves one).
##
## The journal arrives (issue #114, scripts/journal.gd): it saves enemies met and beaten, a history
## log, and which codex entries were read.
##
## A save from before it has none of that, but it does say where the party has been. So:
##   - Enemies: every kind on the roster of a province where a mission was cleared counts as met
##     and beaten once (you cannot clear a mission there without meeting them), so their codex
##     entries and weaknesses are open. The Auditor counts as beaten once auditor_duel is cleared.
##     Exact kill counts were never kept, so they start at 1.
##   - History: the expedition reports the save still holds (the last 12) become history entries.
##     Missions cleared before the journal get one entry each, marked day 0 ("before the journal
##     was kept"), in the order they were cleared.
##   - Read markers start empty: nothing in the codex has been read yet.
## A save that already has a journal, or has no campaign, is left alone.


static func migrate(save: Dictionary) -> Dictionary:
	var empire = save.get("empire", {})
	if typeof(empire) != TYPE_DICTIONARY or empire.is_empty() or empire.has("journal"):
		return save
	var cleared: Array = []
	for m in empire.get("missions_cleared", []):
		cleared.append(str(m))
	var enemies := {}
	var rosters: Dictionary = EnemyKinds.data().get("rosters", {})
	for mid in cleared:
		var m := Missions.find(mid)
		var roster = m.get("enemies", rosters.get(str(m.get("province", "")), {}))
		if typeof(roster) != TYPE_DICTIONARY:
			continue
		for kind in roster:
			enemies[str(kind)] = {"seen": 0, "kills": 1}
	if "auditor_duel" in cleared:
		enemies["auditor"] = {"seen": 0, "kills": 1}
	var log := []
	for r in empire.get("reports", []):
		if typeof(r) != TYPE_DICTIONARY:
			continue
		var lines := []
		for l in r.get("lines", []):
			if lines.size() < 6:
				lines.append(str(l))
		log.append({"day": int(r.get("day", 0)), "kind": "expedition", "title": str(r.get("title", "Expedition")),
			"outcome": str(r.get("outcome", "")), "lines": lines, "province": ""})
	var before := []
	for mid in cleared:
		var m := Missions.find(mid)
		if m.is_empty():
			continue  # cut content or a runtime mission (defense_, reclaim_...): nothing to name it by
		before.push_front({"day": 0, "kind": "mission", "title": str(m.get("name", mid)), "outcome": "success",
			"lines": ["Cleared before the journal was kept."], "province": str(m.get("province", ""))})
	log.append_array(before)  # newest first, like the journal keeps it
	empire["journal"] = {"enemies": enemies, "log": log, "read": {}}
	return save
