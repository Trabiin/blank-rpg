class_name AllyAI
extends RefCounted
## Ally AI presets (issue #9). Hero._ai() handles leader catch-up and getting unstuck, then asks
## steer() where to move. Set per hero from the quick menu's Party tab (Empire.ai_presets keeps the
## choice between missions); defaults come from data/heroes.json "ai". Names and blurbs: heroes.json "styles".
##
## commit: power gauge needed before swinging; seek: how far around the leader it looks for enemies;
## leash: drops a target that strays this far from the leader; back_off: how close it lets the target get
## while the gauge refills; follow: how far behind the leader it walks when nothing is around.

const PRESETS := {
	"aggressive": {"commit": 0.55, "seek": 240.0, "leash": 300.0, "back_off": 0.0, "follow": -14.0},
	"balanced": {"commit": 0.95, "seek": 170.0, "leash": 210.0, "back_off": 44.0, "follow": 22.0},
	"distance": {"commit": 1.0, "seek": 190.0, "leash": 240.0, "back_off": 62.0, "follow": 34.0},
	"support": {"commit": 0.95, "seek": 80.0, "leash": 100.0, "back_off": 30.0, "follow": 14.0},
}
## Older saves and data used these names before the presets existed.
const LEGACY := {"steady": "balanced", "reckless": "aggressive", "guard": "support", "healer": "support"}
const KITE_FAR := 92.0  # Keep Distance closes in again past this
const KITE_LEASH := 150.0  # ... and never kites further than this from the leader
const SUPPORT_HEAL_SPEEDUP := 0.5  # a Support hero's passive poultice runs 1.5x as often


static func preset_id(style: String) -> String:
	if PRESETS.has(style):
		return style
	return str(LEGACY.get(style, "balanced"))


## Where this ally wants to move this frame (the length is the speed, up to 1).
static func steer(h: Hero, leader: Hero, delta: float) -> Vector2:
	var id := preset_id(h.ai_style)
	var p: Dictionary = PRESETS[id]

	if not h.abilities.is_empty():
		h.ai_ability_t -= delta
		if h.ai_ability_t <= 0.0:
			h.ai_ability_t = Abilities.AI_THINK
			var pick := pick_ability(h, id, leader)
			if pick >= 0 and Abilities.use(h, pick):
				return Vector2.ZERO
	if id == "support" and h.heal_every > 0.0:
		h.heal_t -= delta * SUPPORT_HEAL_SPEEDUP

	var t: Enemy = h.ai_target
	if t == null or not is_instance_valid(t) or t.dead \
			or t.global_position.distance_to(leader.global_position) > float(p["leash"]):
		# Keep Distance picks from where it stands; everyone else guards the leader's surroundings.
		var from := h.global_position if id == "distance" else leader.global_position
		h.ai_target = h._nearest_enemy(from, float(p["seek"]))
		t = h.ai_target
	if t == null:
		return _follow(h, leader, float(p["follow"]))

	var to_t := t.global_position - h.global_position
	var d := to_t.length()
	var in_reach := d <= h.reach + t.radius - 6.0
	match id:
		"aggressive":
			# Rolls a new (often low) gauge threshold after every swing: hits early and often, gets hit too.
			if h.power < 0.05 or not h.has_meta("ai_commit"):
				h.set_meta("ai_commit", randf_range(0.3, float(p["commit"])) if randf() < 0.6 else float(p["commit"]))
			if in_reach:
				h.facing = to_t.normalized()
				if h.power >= float(h.get_meta("ai_commit")):
					h.try_attack()
				return Vector2.ZERO
			return to_t.normalized()
		"distance":
			# Hit and run: only goes in with a full gauge, then backs off and circles at range.
			if h.power >= float(p["commit"]):
				if in_reach:
					h.facing = to_t.normalized()
					h.try_attack()
					return Vector2.ZERO
				return to_t.normalized()
			h.facing = to_t.normalized()
			var away := -to_t.normalized()
			var strafe := to_t.normalized().orthogonal() * h.ai_side
			var off_leash := h.global_position.distance_to(leader.global_position) > KITE_LEASH
			if off_leash:
				return (leader.global_position - h.global_position).normalized()
			if d < float(p["back_off"]):
				return (away + strafe * 0.4).normalized()
			if d > KITE_FAR:
				return to_t.normalized() * 0.6
			return strafe * 0.45
		"support":
			# Stands between the leader and the threat; swings only at what reaches the leader.
			var near_leader := t.global_position.distance_to(leader.global_position) < 70.0
			if near_leader and h.power >= float(p["commit"]):
				if in_reach:
					h.facing = to_t.normalized()
					h.try_attack()
					return Vector2.ZERO
				return to_t.normalized()
			h.facing = to_t.normalized()
			var guard_spot := leader.global_position + (t.global_position - leader.global_position).normalized() * 16.0
			var to_g := guard_spot - h.global_position
			if d < float(p["back_off"]) and not near_leader:
				return -to_t.normalized() * 0.8
			if to_g.length() < 6.0:
				return Vector2.ZERO
			return to_g.normalized() * clampf(to_g.length() / 30.0, 0.35, 1.0)
	# Balanced: waits for a full gauge, strikes, backs off while it refills (the original ally AI).
	if h.power >= float(p["commit"]):
		if in_reach:
			h.facing = to_t.normalized()
			h.try_attack()
			return Vector2.ZERO
		return to_t.normalized()
	h.facing = to_t.normalized()
	if d < float(p["back_off"]):
		return -to_t.normalized() * 0.8
	return Vector2.ZERO


## Walks behind the leader (a negative distance walks ahead of them).
static func _follow(h: Hero, leader: Hero, behind: float) -> Vector2:
	var side := leader.facing.orthogonal() * 14.0 * h.ai_side
	var dest := leader.global_position - leader.facing * behind + side
	var to_d := dest - h.global_position
	if to_d.length() < 12.0:
		return Vector2.ZERO
	return to_d.normalized() * clampf(to_d.length() / 36.0, 0.35, 1.0)


# ---------------------------------------------------------------- abilities

## Which ability this preset reaches for right now, or -1. Balanced uses each ability's own
## "ai" rule from data/abilities.json; the others bend those rules their way.
static func pick_ability(h: Hero, id: String, leader: Hero) -> int:
	if id == "balanced":
		return Abilities.ai_pick(h)
	for i in h.abilities.size():
		if Abilities.blocker(h, i) != "":
			continue
		var a: Dictionary = h.abilities[i]
		var rule: Dictionary = a.get("ai", {})
		var kind := str(a.get("kind", ""))
		var below := float(rule.get("below", 0.5))
		var rng := float(rule.get("range", 40))
		match id:
			"aggressive":  # spends Ink on damage the moment anything is in range; heals only in a pinch
				match kind:
					"heal":
						if _hurt_near(h, float(a.get("radius", 60)), below * 0.6):
							return i
					"arc":
						if _face_nearest(h, rng):
							return i
					"dash":
						if _target_within(h, rng * 1.3, 12.0):
							return i
					"taunt":
						if Abilities._count_near(h, h.global_position, float(a.get("radius", 100)) * 0.5) >= 1:
							return i
			"distance":  # shoves off whatever gets close, dashes away when crowded, never taunts
				match kind:
					"heal":
						if _hurt_near(h, float(a.get("radius", 60)), below + 0.1):
							return i
					"arc":
						if _face_nearest(h, rng):
							return i
					"dash":
						if Abilities._count_near(h, h.global_position, 40.0) >= 2:
							h.facing = _away_from_crowd(h, 40.0)
							return i
			"support":  # tops people up early and pulls threats off the leader; no dashing off
				match kind:
					"heal":
						if _hurt_near(h, float(a.get("radius", 60)), minf(below + 0.3, 0.9)):
							return i
					"taunt":
						if leader and Abilities._count_near(h, leader.global_position, rng) >= 1 \
								and leader.global_position.distance_to(h.global_position) < float(a.get("radius", 100)):
							return i
					"arc":
						if leader and Abilities._count_near(h, leader.global_position, 50.0) >= 2 and _face_nearest(h, rng):
							return i
	return -1


static func _hurt_near(h: Hero, r: float, below: float) -> bool:
	for o in h.get_tree().get_nodes_in_group("heroes"):
		var other := o as Hero
		if other and not other.dead and other.party == h.party \
				and other.global_position.distance_to(h.global_position) <= r \
				and float(other.hp) / other.max_hp < below:
			return true
	return false


static func _target_within(h: Hero, r: float, min_d: float) -> bool:
	var t: Enemy = h.ai_target
	if t == null or not is_instance_valid(t) or t.dead:
		return false
	var d := t.global_position.distance_to(h.global_position)
	if d <= r and d > min_d:
		h.facing = (t.global_position - h.global_position).normalized()
		return true
	return false


## Turns to the nearest enemy within r (arcs swing where the hero faces). False if none.
static func _face_nearest(h: Hero, r: float) -> bool:
	var e: Enemy = h._nearest_enemy(h.global_position, r)
	if e == null:
		return false
	h.facing = (e.global_position - h.global_position).normalized()
	return true


static func _away_from_crowd(h: Hero, r: float) -> Vector2:
	var sum := Vector2.ZERO
	for e in h.get_tree().get_nodes_in_group("enemies"):
		var enemy := e as Enemy
		if enemy and not enemy.dead and enemy.global_position.distance_to(h.global_position) <= r:
			sum += enemy.global_position - h.global_position
	if sum.length() < 0.01:
		return -h.facing
	return -sum.normalized()
