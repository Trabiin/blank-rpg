extends RefCounted
## Weapon and Ink skill levels arrive (issue #24, scripts/skills.gd).
##
## Saves from before skills have heroes who may already be level 10 or more, and it would be odd for a
## veteran to swing like a recruit. So each field hero in the save starts with skill points for the
## fighting they have done: SEED_WEAPON per character level past 1 on their weapon, SEED_INK in every
## Ink colour their abilities use. Like the Barracks, this only goes up to the drill cap (weapon level 3,
## Ink level 3): the last techs and tiers are earned in real fights. Picked techs start as "by hold
## length". Heroes with no progress yet (or saves with no campaign) are left alone: they start at 1.

const SEED_WEAPON := 30
const SEED_INK := 10
const CAP := 3


static func migrate(save: Dictionary) -> Dictionary:
	var empire = save.get("empire", {})
	if typeof(empire) != TYPE_DICTIONARY:
		return save
	var progress = empire.get("progress", {})
	if typeof(progress) != TYPE_DICTIONARY or typeof(progress.get("heroes")) != TYPE_DICTIONARY:
		return save
	var weapon_xs: Array = Progress.data().get("skills", {}).get("weapon_xp", [80, 180, 320, 520])
	var ink_xs: Array = Abilities.data().get("ink_skill", {}).get("xp", [30, 70, 120, 190])
	for id in progress["heroes"]:
		var h = progress["heroes"][id]
		if typeof(h) != TYPE_DICTIONARY or h.has("weapon"):
			continue
		var past := maxi(int(h.get("level", 1)) - 1, 0)
		h["weapon"] = _levels(past * SEED_WEAPON, weapon_xs)
		var inks := {}
		for c in _colors(str(id)):
			inks[c] = _levels(past * SEED_INK, ink_xs)
		h["inks"] = inks
		h["tech"] = ""
	return save


## {"xp", "level"} reached with this many points, no higher than CAP.
static func _levels(points: int, xs: Array) -> Dictionary:
	var lvl := 1
	while lvl < CAP and lvl - 1 < xs.size() and points >= int(xs[lvl - 1]):
		points -= int(xs[lvl - 1])
		lvl += 1
	if lvl >= CAP or lvl - 1 >= xs.size():
		points = mini(points, int(xs[lvl - 1]) - 1) if lvl - 1 < xs.size() else 0
	return {"xp": points, "level": lvl}


static func _colors(id: String) -> Array:
	var out := []
	for a in Abilities.for_ids(PartyPicker.hero_data(id).get("abilities", [])):
		var c := str(a.get("ink", ""))
		if c != "" and not c in out:
			out.append(c)
	return out
