extends RefCounted
## Items, Forge and Market (issue #112): the satchel gets a capacity.
##
## Before #112 the satchel had no limit: Hollowmark topped it back up to 3 Tonics, 1 Salts and 1 Draught
## after every mission and kept anything extra you found, so a long campaign could carry a dozen of each.
## Now the satchel holds 10 (more with satchel upgrades), each item has its own carry limit, and what you
## don't pack waits in Hollowmark's stores (empire.progress.armory). This step gives old saves the starting
## pack and moves every extra above it into the stores, so nothing found is lost; the Satchel screen lets
## the player pack differently. A save made mid-mission keeps its satchel as it was until the mission ends.


static func migrate(save: Dictionary) -> Dictionary:
	var empire = save.get("empire", {})
	if typeof(empire) != TYPE_DICTIONARY:
		return save
	if typeof(empire.get("progress")) != TYPE_DICTIONARY:
		empire["progress"] = {}
	var progress: Dictionary = empire["progress"]
	if typeof(progress.get("armory")) == TYPE_DICTIONARY and not (progress["armory"] as Dictionary).is_empty():
		return save  # already has one (a build from this branch wrote it)
	var pack: Dictionary = Armory.fresh()["pack"]
	var stores := {}
	var satchel = empire.get("satchel", {})
	if typeof(satchel) != TYPE_DICTIONARY:
		satchel = {}
	var mid_mission := str(save.get("scene", "")).ends_with("main.tscn")
	for id in satchel.keys():
		var n := int(satchel[id])
		if Satchel.item(str(id)).is_empty() or n <= 0:
			continue
		var keep := mini(n, int(pack.get(id, 0)))
		if mid_mission:
			continue  # restocked (and the extras stored) when the mission ends
		if n > keep:
			stores[id] = n - keep
			satchel[id] = keep
		if int(satchel[id]) <= 0:
			satchel.erase(id)
	empire["satchel"] = satchel
	progress["armory"] = {"mats": {}, "stores": stores, "pack": pack, "jobs": [], "upgrades": [],
		"market": {"seed": int(empire.get("day", 1)) * 7919 % 1000000, "rotation": -1, "bought": {}}}
	return save
