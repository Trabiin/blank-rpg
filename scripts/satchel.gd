class_name Satchel
extends RefCounted
## The party's field items (issues #6, #112): data in data/items.json, counts in Empire.satchel
## (saved with the empire). Used from the quick menu (quick_menu.gd). The satchel's size, what is
## packed into it and the town stores behind it live in scripts/armory.gd; cures and boons in
## scripts/status.gd.

static var _data := {}


static func data() -> Dictionary:
	if _data.is_empty():
		var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/items.json"))
		_data = parsed.get("items", {}) if typeof(parsed) == TYPE_DICTIONARY else {}
	return _data


static func ids() -> Array:
	return data().keys()


static func item(id: String) -> Dictionary:
	return data().get(id, {})


static func count(id: String) -> int:
	return int(Empire.satchel.get(id, 0))


## What a fresh campaign starts with, and what the satchel is topped back up to after a mission.
static func start_stock() -> Dictionary:
	var out := {}
	for id in data():
		out[id] = int(data()[id].get("start", 0))
	return out


## After a mission: the satchel is repacked from free rations and the town stores, extras go to the
## stores (scripts/armory.gd). rations=false repacks in town without the free rations.
static func restock(rations := true) -> void:
	Armory.restock(rations)


## Picks up one mid-mission. Returns false when the satchel has no room (the caller sends it home).
static func add(id: String, n := 1) -> bool:
	if item(id).is_empty():
		return false
	for i in n:
		if not Armory.satchel_room(id):
			return false
		Empire.satchel[id] = count(id) + 1
	return true


## Rolls a drop from a defeated enemy. Returns the item id, or "".
static func roll_drop() -> String:
	for id in data():
		if randf() < float(data()[id].get("drop", 0.0)):
			return id
	return ""


## The items to show in the quick menu: whatever is in the satchel, in data order.
static func carried() -> Array:
	return ids().filter(func(id): return count(id) > 0)


## Does using this item ask who it's for?
static func needs_target(id: String) -> bool:
	return not str(item(id).get("target", "hurt")) in ["party", "throw"]


## Can this item be used on this hero right now?
static func can_target(id: String, h: Hero) -> bool:
	var it := item(id)
	match str(it.get("target", "hurt")):
		"hurt":
			return not h.dead and (h.hp < h.max_hp or Status.cured_by(h, it.get("cures", [])))
		"downed":
			return h.dead
		"ink":
			return not h.dead and ((h.max_ink > 0.0 and h.ink < h.max_ink) or Status.cured_by(h, it.get("cures", [])))
		"cure":
			return not h.dead and Status.cured_by(h, it.get("cures", []))
		"hero", "party":
			return not h.dead
		"throw":
			return not h.dead and h.controlled
	return false


## Why the item can't be used on anyone right now, or "" if it can.
static func blocker(id: String, heroes: Array) -> String:
	if count(id) <= 0:
		return "none left"
	var it := item(id)
	if str(it.get("target", "")) == "throw":
		var leader: Hero = null
		for h in heroes:
			if (h as Hero).controlled and not (h as Hero).dead:
				leader = h
		if leader == null:
			return "nobody to throw it"
		if not it.get("throw", {}).get("self", false) and Status.nearest_enemy(leader, float(it.get("range", 160))) == null:
			return "no enemy in range"
		return ""
	for h in heroes:
		if can_target(id, h):
			return ""
	match str(it.get("target", "hurt")):
		"hurt":
			return "everyone is at full HP"
		"downed":
			return "nobody is down"
		"ink":
			return "everyone's Ink is full"
		"cure":
			return "nobody needs it"
	return "nobody can use it"


## Uses one item on `h` (ignored for party and thrown items). Returns a line for the menu, or "" if
## nothing happened.
static func use(id: String, h: Hero, heroes: Array) -> String:
	var it := item(id)
	if count(id) <= 0:
		return ""
	var tgt := str(it.get("target", "hurt"))
	if tgt == "throw":
		var thrower: Hero = null
		for x in heroes:
			if (x as Hero).controlled and not (x as Hero).dead:
				thrower = x
		if thrower == null:
			return ""
		var caught := Status.throw_item(it, thrower)
		if caught < 0:
			return ""
		_spend(id)
		return "%s: %s." % [str(it.get("name", id)), "caught %d" % caught if caught > 0 else "nothing caught"]
	var targets: Array = heroes.filter(func(x): return can_target(id, x)) if tgt == "party" else [h]
	targets = targets.filter(func(x): return x != null and can_target(id, x))
	if targets.is_empty():
		return ""
	for t in targets:
		var hero: Hero = t
		if hero.dead:
			hero.revive()
			hero.hp = maxi(1, roundi(hero.max_hp * float(it.get("revive_pct", 0.5))))
		if it.has("cures"):
			Status.cure(hero, it["cures"])
			Status.grant_immunity(hero, Status.AILMENTS if "all" in it["cures"] else it["cures"], float(it.get("immune", 0)))
		if it.has("heal"):
			var amount := mini(int(it["heal"]), hero.max_hp - hero.hp)
			hero.hp += amount
			if amount > 0:
				Fx.damage_number(hero.get_parent(), hero.global_position + Vector2(0, -18), "+%d" % amount, Color("9fe07a"))
		if it.has("ink") and hero.max_ink > 0.0:
			hero.ink = minf(hero.max_ink, hero.ink + float(it["ink"]))
		if it.has("power"):
			hero.power = minf(1.0, hero.power + float(it["power"]))
		if it.has("buff"):
			Status.apply(hero, str(it["buff"].get("id", "")), float(it["buff"].get("time", 20)))
		Fx.burst(hero.get_parent(), hero.global_position + Vector2(0, -10), [Color("9fbf6a"), Color("dff5b0")], 10, 40.0)
	_spend(id)
	var who := "the party" if targets.size() > 1 else (targets[0] as Hero).hero_name
	return "%s: %s." % [str(it.get("name", id)), who]


static func _spend(id: String) -> void:
	Empire.satchel[id] = count(id) - 1
	if int(Empire.satchel[id]) <= 0:
		Empire.satchel.erase(id)
