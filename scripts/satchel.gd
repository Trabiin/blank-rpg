class_name Satchel
extends RefCounted
## The party's field items (issue #6): data in data/items.json, counts in Empire.satchel
## (saved with the empire). Used from the quick menu (quick_menu.gd).

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


## Hollowmark's stores refill the satchel to its starting stock; extras you found are kept.
static func restock() -> void:
	var base := start_stock()
	for id in base:
		Empire.satchel[id] = maxi(count(id), int(base[id]))


static func add(id: String, n := 1) -> void:
	Empire.satchel[id] = count(id) + n


## Rolls a drop from a defeated enemy. Returns the item id, or "".
static func roll_drop() -> String:
	for id in data():
		if randf() < float(data()[id].get("drop", 0.0)):
			return id
	return ""


## Can this item be used on this hero right now?
static func can_target(id: String, h: Hero) -> bool:
	match str(item(id).get("target", "hurt")):
		"hurt":
			return not h.dead and h.hp < h.max_hp
		"downed":
			return h.dead
		"party":
			return not h.dead
	return false


## Why the item can't be used on anyone right now, or "" if it can.
static func blocker(id: String, heroes: Array) -> String:
	if count(id) <= 0:
		return "none left"
	for h in heroes:
		if can_target(id, h):
			return ""
	match str(item(id).get("target", "hurt")):
		"hurt":
			return "everyone is at full HP"
		"downed":
			return "nobody is down"
	return "nobody can use it"


## Uses one item on `h` (ignored for party items). Returns a line for the menu, or "" if nothing happened.
static func use(id: String, h: Hero, heroes: Array) -> String:
	var it := item(id)
	if count(id) <= 0:
		return ""
	var targets: Array = heroes.filter(func(x): return can_target(id, x)) if it.get("target") == "party" else [h]
	targets = targets.filter(func(x): return x != null and can_target(id, x))
	if targets.is_empty():
		return ""
	for t in targets:
		var hero: Hero = t
		if hero.dead:
			hero.revive()
			hero.hp = maxi(1, roundi(hero.max_hp * float(it.get("revive_pct", 0.5))))
		if it.has("heal"):
			var amount := mini(int(it["heal"]), hero.max_hp - hero.hp)
			hero.hp += amount
			if amount > 0:
				Fx.damage_number(hero.get_parent(), hero.global_position + Vector2(0, -18), "+%d" % amount, Color("9fe07a"))
		if it.has("power"):
			hero.power = minf(1.0, hero.power + float(it["power"]))
		Fx.burst(hero.get_parent(), hero.global_position + Vector2(0, -10), [Color("9fbf6a"), Color("dff5b0")], 10, 40.0)
	Empire.satchel[id] = count(id) - 1
	var who := "the party" if targets.size() > 1 else (targets[0] as Hero).hero_name
	return "%s: %s." % [str(it.get("name", id)), who]
