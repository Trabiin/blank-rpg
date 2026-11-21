extends RefCounted
## Skill trees arrive (issue #25, scripts/skill_tree.gd).
##
## Skill Points come from levels (one per level past 1), so a veteran from an older save already has every
## point they earned waiting to be spent: nothing is lost by the trees arriving late. This step writes the
## new "tree" list (empty) onto every hero in the save, so the shape is explicit for later renames. The
## Gear screen, the quick menu and the level-up toast all show unspent points, so veterans find the trees.

static func migrate(save: Dictionary) -> Dictionary:
	var empire = save.get("empire", {})
	if typeof(empire) != TYPE_DICTIONARY:
		return save
	var progress = empire.get("progress", {})
	if typeof(progress) != TYPE_DICTIONARY or typeof(progress.get("heroes")) != TYPE_DICTIONARY:
		return save
	for id in progress["heroes"]:
		var h = progress["heroes"][id]
		if typeof(h) != TYPE_DICTIONARY:
			continue
		if typeof(h.get("tree")) != TYPE_ARRAY:
			h["tree"] = []
	return save
