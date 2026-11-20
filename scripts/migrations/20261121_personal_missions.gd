extends RefCounted
## Personal jobs become personal missions (issue #113).
##
## Before #113, bond rank 4 opened a personal job on the Guildhall board (expedition ids "personal_<who>").
## Those jobs are gone: each one is now a hand-built mission on the Command Table. A save can hold one
## of them half done, a squad out on the road. That squad comes home (the loader frees anyone whose job
## no longer exists), so this step gives back the rations the squad paid, files a report that says where
## the story went, and forgets the old jobs' cooldowns. Nothing about the bond itself changes: the rank
## is kept, and the mission is waiting in the character's province.

const PREFIX := "personal_"
const RATIONS := 2  # every personal job cost 2 Supplies per squad member


static func migrate(save: Dictionary) -> Dictionary:
	var empire = save.get("empire", {})
	if typeof(empire) != TYPE_DICTIONARY:
		return save
	var kept := []
	var reports: Array = empire.get("reports", []) if typeof(empire.get("reports")) == TYPE_ARRAY else []
	var day := int(empire.get("day", 1))
	for e in empire.get("expeditions", []):
		if typeof(e) != TYPE_DICTIONARY or not str(e.get("job", "")).begins_with(PREFIX):
			kept.append(e)
			continue
		var squad: Array = e.get("squad", []) if typeof(e.get("squad")) == TYPE_ARRAY else []
		var refund := RATIONS * squad.size()
		var res = empire.get("res", {})
		if typeof(res) == TYPE_DICTIONARY:
			res["supplies"] = int(res.get("supplies", 0)) + refund
		var who := str(e["job"]).trim_prefix(PREFIX)
		var name := _short(who)
		var where := _province_name(who)
		reports.push_front({"day": day, "job": str(e["job"]), "title": "%s's errand: called back" % name, "outcome": "success",
			"squad": squad, "chance": 100, "read": false, "lines": [
				"The squad turned round on the road. %s won't have this settled by proxy." % name,
				"It's a mission now: %s is waiting at %s on the Command Table, and is coming in person." % [name, where],
				"The %d Supplies the squad took were returned to the stores." % refund]})
		for rid in squad:
			var r = empire.get("recruits", {}).get(rid)
			if typeof(r) == TYPE_DICTIONARY:
				r["role"] = "idle"
				r["target"] = ""
	empire["expeditions"] = kept
	empire["reports"] = reports
	var jr = empire.get("job_ready", {})
	if typeof(jr) == TYPE_DICTIONARY:
		for jid in jr.keys():
			if str(jid).begins_with(PREFIX):
				jr.erase(jid)
	return save


static func _short(who: String) -> String:
	if Empire.recruit_data.is_empty():  # Saves checks the slots at start-up, before Empire is ready
		Empire._load_recruit_data()
	return Empire.short_name(who) if Empire.recruit_data.has(who) else who.capitalize()


static func _province_name(who: String) -> String:
	var pid := str(PersonalMissions.def_for(who).get("province", ""))
	for p in JSON.parse_string(FileAccess.get_file_as_string("res://data/provinces.json")).get("provinces", []):
		if typeof(p) == TYPE_DICTIONARY and p.get("id", "") == pid:
			return str(p.get("name", pid))
	return "their home province"
