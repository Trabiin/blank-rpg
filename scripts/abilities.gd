class_name Abilities
extends RefCounted
## Hotkeyed abilities and Ink (issue #7). Data lives in data/abilities.json; heroes list theirs
## in data/heroes.json. A Hero keeps its own Ink and cooldowns; this file holds what each kind does
## and when the ally AI reaches for one. Using an ability never pauses the fight.

const PATH := "res://data/abilities.json"
const MAX_SLOTS := 4
const REGEN := 0.4  # Ink per second, everyone
const HIT_GAIN := 1.0  # Ink for a full-power swing that lands
const AI_THINK := 0.3  # seconds between an ally's ability checks

static var _data := {}


static func _load() -> Dictionary:
	if _data.is_empty():
		var f := FileAccess.open(PATH, FileAccess.READ)
		if f:
			var parsed = JSON.parse_string(f.get_as_text())
			if parsed is Dictionary:
				_data = parsed
	return _data


static func get_def(id: String) -> Dictionary:
	var d: Dictionary = _load().get("abilities", {}).get(id, {})
	if d.is_empty():
		return {}
	var out := d.duplicate(true)
	out["id"] = id
	return out


## The ability dictionaries a hero brings, from its list of ids (unknown ids are skipped).
static func for_ids(ids: Array) -> Array:
	var out := []
	for id in ids:
		var d := get_def(str(id))
		if not d.is_empty() and out.size() < MAX_SLOTS:
			out.append(d)
	return out


static func color_of(a: Dictionary) -> Color:
	return Color(str(a.get("color", "9fd8ff")))


## Why an ability can't be used right now ("" = it can).
static func blocker(h: Hero, i: int) -> String:
	if i < 0 or i >= h.abilities.size():
		return "none"
	if h.dead:
		return "down"
	if h.cooldowns[i] > 0.0:
		return "cooldown"
	if h.ink < float(h.abilities[i].get("cost", 0)):
		return "ink"
	if h.dash_t > 0.0 or h.swing_t > 0.0:
		return "busy"
	return ""


## Spend the Ink and do the thing. Returns false (and does nothing) if it can't be used.
static func use(h: Hero, i: int) -> bool:
	if blocker(h, i) != "":
		return false
	var a: Dictionary = h.abilities[i]
	h.ink -= float(a.get("cost", 0))
	h.cooldowns[i] = float(a.get("cooldown", 1.0))
	h.cast_t = Hero.SWING_TIME
	h.cast_color = color_of(a)
	var parent := h.get_parent()
	match str(a.get("kind", "")):
		"heal":
			_heal(h, a, parent)
		"arc":
			_arc(h, a, parent)
		"dash":
			h.start_dash(a)
		"taunt":
			_taunt(h, a, parent)
	Fx.damage_number(parent, h.global_position + Vector2(0, -26), str(a.get("name", "")), color_of(a))
	return true


static func _heal(h: Hero, a: Dictionary, parent: Node) -> void:
	var r := float(a.get("radius", 56))
	var col := color_of(a)
	Fx.ring(parent, h.global_position, r, col)
	for o in h.get_tree().get_nodes_in_group("heroes"):
		var other := o as Hero
		if other == null or other.dead or other.global_position.distance_to(h.global_position) > r:
			continue
		if other.party != h.party:
			continue  # hub townsfolk are Heroes too
		var amount := mini(int(a.get("heal", 0)), other.max_hp - other.hp)
		other.hp += amount
		if amount > 0:
			Fx.damage_number(parent, other.global_position + Vector2(0, -18), "+%d" % amount, Color("9fe07a"))
		if int(a.get("shield", 0)) > 0:
			other.shield_hp = int(a["shield"])
			other.shield_t = float(a.get("shield_time", 5.0))
		Fx.burst(parent, other.global_position + Vector2(0, -10), [col, Color.WHITE], 10, 40.0)


static func _arc(h: Hero, a: Dictionary, parent: Node) -> void:
	var reach := float(a.get("reach", 30))
	var half := deg_to_rad(float(a.get("arc", 90)))
	var dmg := int(a.get("damage", 10))
	var col := color_of(a)
	Fx.sweep(parent, h.global_position + Vector2(0, -6), h.facing.angle(), half, reach, col)
	var hit_any := false
	for e in h.get_tree().get_nodes_in_group("enemies"):
		var enemy := e as Enemy
		if enemy == null or enemy.dead:
			continue
		var to := enemy.global_position - h.global_position
		if to.length() <= reach + enemy.radius and absf(h.facing.angle_to(to)) <= half:
			if enemy.take_hit(dmg, h.global_position, float(a.get("knock", 220))):
				hit_any = true
	if hit_any and h.party:
		h.party.shake(3.0)


static func _taunt(h: Hero, a: Dictionary, parent: Node) -> void:
	var r := float(a.get("radius", 100))
	var t := float(a.get("time", 4))
	Fx.ring(parent, h.global_position, r, color_of(a))
	h.guard_t = t
	h.guard_cut = float(a.get("guard", 0.5))
	for e in h.get_tree().get_nodes_in_group("enemies"):
		var enemy := e as Enemy
		if enemy == null or enemy.dead:
			continue
		if enemy.global_position.distance_to(h.global_position) <= r:
			enemy.taunt(h, t)


## Enemies a dash runs through (each one once per dash).
static func dash_hits(h: Hero) -> void:
	for e in h.get_tree().get_nodes_in_group("enemies"):
		var enemy := e as Enemy
		if enemy == null or enemy.dead or h.dash_hit.has(enemy):
			continue
		if enemy.global_position.distance_to(h.global_position) <= h.radius + enemy.radius + 8.0:
			h.dash_hit.append(enemy)
			enemy.take_hit(int(h.dash_ability.get("damage", 10)), h.global_position - h.dash_dir * 6.0,
				float(h.dash_ability.get("knock", 180)))
			if h.party:
				h.party.shake(2.0)


# ---------------------------------------------------------------- ally AI

## Which ability an AI-driven ally wants to use right now, or -1.
static func ai_pick(h: Hero) -> int:
	var leader: Hero = h.party.leader if h.party else null
	for i in h.abilities.size():
		if blocker(h, i) != "":
			continue
		var rule: Dictionary = h.abilities[i].get("ai", {})
		match str(rule.get("when", "")):
			"hurt":
				var r := float(h.abilities[i].get("radius", 60))
				for o in h.get_tree().get_nodes_in_group("heroes"):
					var other := o as Hero
					if other and not other.dead and other.party == h.party \
							and other.global_position.distance_to(h.global_position) <= r \
							and float(other.hp) / other.max_hp < float(rule.get("below", 0.5)):
						return i
			"crowd":
				if _count_near(h, h.global_position, float(rule.get("range", 32))) >= int(rule.get("count", 2)):
					return i
			"target":
				var tgt: Enemy = h.ai_target
				if tgt and is_instance_valid(tgt) and not tgt.dead:
					var d := tgt.global_position.distance_to(h.global_position)
					if d <= float(rule.get("range", 60)) and d > 20.0:
						h.facing = (tgt.global_position - h.global_position).normalized()
						return i
			"threat":
				if leader and _count_near(h, leader.global_position, float(rule.get("range", 60))) >= int(rule.get("count", 2)):
					return i
	return -1


static func _count_near(h: Hero, at: Vector2, r: float) -> int:
	var n := 0
	for e in h.get_tree().get_nodes_in_group("enemies"):
		var enemy := e as Enemy
		if enemy and not enemy.dead and enemy.global_position.distance_to(at) <= r:
			n += 1
	return n
