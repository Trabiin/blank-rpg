class_name AllyTechs
extends RefCounted
## Allies using their charged techs (data/techs.json; the blast itself lives in scripts/techs.gd).
## An ally under AI charges exactly like the player does: a full gauge, the same glow and ready chime,
## the same hold time, then the same blast. On top of that the area it is about to hit is drawn on
## the ground (Techs.draw_area) so the player can read it, and the ally steps where the blast will land.
##
## How it decides (each preset bends the same scoring):
##   score(spot, dir) = what the blast would hit if fired along dir from spot, using where enemies are
##   heading: 1 per enemy, more for elites and bosses, a bonus for finishing one off or interrupting a
##   wind-up (stun techs), less for hitting an Enforcer's Ledger, plus healing for Gristle's broth.
##   Spots tried: where the hero stands, and the right distance from each nearby enemy if it can walk
##   there during the wind-up (so Odile backs off to drop her seal on them, Daro lines up his pike).
##   It starts charging when the best is worth START[preset], walks to the spot while charging, fires
##   once ready if what it would hit from where it actually stands is worth FIRE[preset], and gives up
##   (keeping its gauge) if nothing is worth it within HOLD_MAX seconds, or to step out of a lunge.
##   While a tech looks worth it and the gauge is nearly full, the preset holds its normal swing
##   (saving()), so the gauge can fill; Aggressive only does that on every other gauge.
##
## Per hero, from the quick menu's Party tab (Empire.ai_techs keeps it between missions):
##   "auto"  the preset decides (default);
##   "call"  never on its own: saved for your call;
##   and "Unleash tech now" orders one tech at the best target, in either mode.
##
## Safety rules: abilities are checked first (a heal always beats a blast), Support won't plant its feet
## while the leader is badly hurt unless its tech heals, Keep Distance won't while it is hurt itself, and
## a hit before the tech is ready breaks an ally's charge (it keeps its gauge and tries again shortly).
## Several techs per hero (#24): techs_of() lists the ones it knows at its weapon skill level (or only the
## one picked in the quick menu's Techs tab), and pick() scores every one, weighing what each would hit
## against how long it takes to charge; the rest is per tech. Multi-hit, chained, spread and delayed
## techs are scored blast by blast (Techs.blasts), knives by what is in their range.

const MODES := ["auto", "call"]
const MODE_NAMES := {"auto": "Auto", "call": "On my call"}
## How each preset spends its tech, for the quick menu.
const PRESET_RULE := {
	"aggressive": "at anything in reach",
	"balanced": "on crowds, elites and kills",
	"distance": "from range, while healthy",
	"support": "to clear the leader's space",
}
const MODE_DESC := {
	"auto": "Fires its charged tech when the moment is right for its AI style.",
	"call": "Saves the charged tech until you order it from this menu.",
}
## Score needed to start charging, and to fire once the tech is ready.
const START := {"aggressive": 1.0, "balanced": 1.6, "distance": 1.8, "support": 1.5}
const FIRE := {"aggressive": 0.8, "balanced": 1.3, "distance": 1.3, "support": 1.1}
const ORDER_NEED := 0.5  # an ordered tech goes for anything it can reach
const ORDER_TIME := 10.0  # an order stands this long (waiting for the gauge, then for a target)
const HOLD_MAX := 1.6  # seconds a ready tech is held looking for its moment before the ally lets it go
const ORDER_HOLD_MAX := 4.0
const RETRY := 1.2  # after giving up, wait this long before charging again
const THINK := 0.15  # seconds between looks for a tech moment while the gauge fills
const SAVE_FROM := 0.7  # gauge at which a preset stops swinging to let a promising tech fill
const SAVE_MAX := 1.5  # ... but only for this long at a full gauge before swinging normally again
const REPOSITION := 30.0  # how far an ally will walk during the wind-up to line a tech up
const LEAD := 0.35  # seconds ahead an enemy's movement is predicted
const DODGE_R := 38.0  # a lunge or slam winding up at the ally from this close makes it think twice
const BREAK_HIT := 0.25  # a blow taking this much of an ally's max HP breaks its charge
const LONG_REACH := 50.0  # techs reaching this far are safe enough for Keep Distance to use on one enemy


static func preset_of(h: Hero) -> String:
	return AllyAI.preset_id(h.ai_style)


static func mode_of(h: Hero) -> String:
	return h.tech_mode if h.tech_mode in MODES else "auto"


## Persists and applies a hero's tech mode (quick menu Party tab).
static func set_mode(h: Hero, mode: String) -> void:
	h.tech_mode = mode if mode in MODES else "auto"
	Empire.ai_techs[h.hero_id] = h.tech_mode
	if h.tech_mode == "call" and h.ai_charging and h.ai_tech_order_t <= 0.0:
		_give_up(h, RETRY)  # stand down a charge that is already under way


## Every tech this hero can fire under AI: the one picked for it, or all it knows (weapon skill, #24).
static func techs_of(h: Hero) -> Array:
	return Techs.charge_options(h)


## The best tech and aim right now: {"tech", "dir", "score", "focus"}; score 0 if nothing is worth it.
static func pick(h: Hero, preset: String, leader: Hero, slack: float) -> Dictionary:
	var out := {"tech": {}, "dir": h.facing.normalized(), "score": 0.0, "focus": null, "spot": h.global_position}
	for t in techs_of(h):
		var aim := best_aim(h, t, preset, leader, slack, true)
		# Rank by how far past its bar, per second of charging: a bigger tech has to be worth the wait.
		var worth: float = (aim["score"] - (_start_need(h, preset, t) - 1.0)) / sqrt(Techs.charge_time(t))
		if aim["score"] > 0.0 and (out["tech"].is_empty() or worth > float(out.get("worth", -INF))):
			out = aim.duplicate()
			out["tech"] = t
			out["worth"] = worth
	return out


## A hit landed on the hero (Hero.take_hit): a heavy one (BREAK_HIT of its max HP or more) breaks an
## ally's charge unless the tech is already ready. Chip damage doesn't; Aggressive shrugs off anything.
static func interrupted(h: Hero, lost: int) -> void:
	if h.ai_charging and not h.charge_ready and float(lost) >= h.max_hp * BREAK_HIT \
			and preset_of(h) != "aggressive":
		Fx.damage_number(h.get_parent(), h.global_position + Vector2(0, -26), "broken", Color(0.8, 0.8, 0.85))
		_give_up(h, 0.6)


## Quick menu order: charge the tech as soon as the gauge allows, at the best target in reach.
static func order(h: Hero) -> void:
	h.ai_tech_order_t = ORDER_TIME
	h.ai_tech_cd = 0.0
	h.ai_think_t = 0.0


## Why an order can't be given now, or "" if it can.
static func order_blocker(h: Hero) -> String:
	if techs_of(h).is_empty():
		return "no tech"
	if h.dead:
		return "down"
	if h.controlled:
		return "you: hold Attack"
	if h.charging:
		return "charging"
	return ""


## Short state for menus: "ready", "charging", "gauge 60%".
static func state_text(h: Hero) -> String:
	if techs_of(h).is_empty():
		return "no tech"
	if h.charging:
		return "ready" if h.charge_ready else "charging"
	if h.ai_tech_order_t > 0.0:
		return "ordered"
	if h.power >= 1.0:
		return "gauge full"
	return "gauge %d%%" % int(h.power * 100.0)


## Called from AllyAI.steer() for an ally. Returns true (and appends the move) while the tech has the
## ally's attention; false lets the preset steer as usual.
static func steer(h: Hero, leader: Hero, preset: String, delta: float, move: Array) -> bool:
	h.ai_tech_cd = maxf(h.ai_tech_cd - delta, 0.0)
	if h.ai_tech_order_t > 0.0:
		h.ai_tech_order_t -= delta
	if h.peaceful or techs_of(h).is_empty():
		h.ai_tech_promise = false
		return false
	if h.charging:
		if not h.ai_charging:
			return false  # a charge the player started (control just changed hands); Techs.tick drops it
		move.append(_charge(h, leader, preset, delta))
		return true
	if h.power >= 1.0:
		h.ai_tech_full_t += delta
	else:
		h.ai_tech_full_t = 0.0
	h.ai_think_t -= delta
	if h.ai_think_t > 0.0 and not (h.power >= 1.0 and h.ai_tech_promise):
		return false
	h.ai_think_t = THINK
	if not _allowed(h, preset, leader):
		h.ai_tech_promise = false
		return false
	var best := pick(h, preset, leader, 14.0)
	var ordered := h.ai_tech_order_t > 0.0
	var need := ORDER_NEED if ordered else (_start_need(h, preset, best["tech"]) if not best["tech"].is_empty() else INF)
	h.ai_tech_promise = best["score"] >= need
	if ordered and not h.ai_tech_promise and h.power >= 1.0:
		best = _order_fallback(h, leader, best)  # nothing in reach yet: go to the nearest enemy
		h.ai_tech_promise = not best["tech"].is_empty()
	if not h.ai_tech_promise or h.power < 1.0 or h.swing_t > 0.0 or h.cast_t > 0.0 or h.dash_t > 0.0:
		return false
	h.ai_tech = best["tech"]
	h.charging = true
	h.ai_charging = true
	h.charge_t = 0.0
	h.charge_ready = false
	h.ai_tech_hold = 0.0
	h.ai_tech_promise = false
	h.ai_tech_dir = best["dir"]
	h.ai_tech_focus = best["focus"]
	h.ai_tech_spot = best["spot"]
	h.facing = best["dir"]
	move.append(Vector2.ZERO)
	return true


## True while the preset should hold its ordinary swing so the gauge can fill for a tech that looks
## worth it (checked by AllyAI before every swing).
static func saving(h: Hero, preset: String) -> bool:
	if not h.ai_tech_promise or h.ai_tech_cd > 0.0:
		return false
	if h.ai_tech_full_t > SAVE_MAX:
		return false  # waited long enough: swing
	if preset == "aggressive" and h.ai_tech_order_t <= 0.0:
		return h.get_meta("ai_tech_turn", false)  # every other gauge goes on a tech
	return h.power >= SAVE_FROM


## Aggressive rolls this after each swing or tech: true = let this gauge fill for a tech.
static func roll_turn(h: Hero) -> void:
	h.set_meta("ai_tech_turn", not h.get_meta("ai_tech_turn", false))


## Whether this ally may start a tech at all right now (mode, order, safety rules).
static func _allowed(h: Hero, preset: String, leader: Hero) -> bool:
	if h.ai_tech_cd > 0.0:
		return false
	if h.ai_tech_order_t > 0.0:
		return true
	if mode_of(h) == "call":
		return false
	if preset == "distance" and float(h.hp) / h.max_hp < 0.4:
		return false  # Keep Distance doesn't plant its feet while hurt
	if preset == "support" and leader and float(leader.hp) / leader.max_hp < 0.35 \
			and not techs_of(h).any(func(t): return int(t.get("heal", 0)) > 0):
		return false  # Support stays on guard while the leader is in trouble (unless its tech heals)
	return true


static func _start_need(_h: Hero, preset: String, t: Dictionary) -> float:
	var need := float(START.get(preset, 1.8))
	if preset == "distance" and _span(t) >= LONG_REACH:
		need = 1.0  # a long line is safe to throw at a single target from range
	return need


## An ordered tech with nothing in reach: charge anyway and walk to the nearest enemy while it fills.
static func _order_fallback(h: Hero, leader: Hero, best: Dictionary) -> Dictionary:
	var ts := techs_of(h)
	var from := leader.global_position if leader else h.global_position
	var e: Enemy = h._nearest_enemy(from, 200.0)
	if e == null or ts.is_empty():
		return {"tech": {}, "dir": best["dir"], "score": 0.0, "focus": null, "spot": h.global_position}
	var t: Dictionary = ts[0]
	var away := h.global_position - e.global_position
	if away.length() < 0.5:
		away = -h.facing
	return {"tech": t, "dir": -away.normalized(), "score": 0.0, "focus": e,
		"spot": e.global_position + away.normalized() * standoff(t)}


## One frame of an ally holding a charge: walk to the spot, re-aim, fire when ready, or give up.
static func _charge(h: Hero, leader: Hero, preset: String, delta: float) -> Vector2:
	var t: Dictionary = h.ai_tech
	var ordered := h.ai_tech_order_t > 0.0
	if _should_dodge(h, preset) and not ordered:
		_give_up(h, 0.8)
		return Vector2.ZERO
	h.charge_t += delta
	if not h.charge_ready and h.charge_t >= Techs.charge_time(t):
		h.charge_ready = true
		h.charge_stage = 1
		Techs.reached(h, int(t.get("level", 1)))  # flash and a chime as high as the tech
	# Where to stand and face (may still walk a little), and what it would hit from right here.
	var plan := best_aim(h, t, preset, leader, 0.0 if h.charge_ready else 8.0, true)
	if plan["focus"] != null:
		h.ai_tech_focus = plan["focus"]
		h.ai_tech_spot = plan["spot"]
	var aim_dir: Vector2 = plan["dir"] if plan["focus"] != null else h.ai_tech_dir
	h.ai_tech_dir = Vector2.from_angle(lerp_angle(h.ai_tech_dir.angle(), aim_dir.angle(), minf(delta * 10.0, 1.0)))
	h.facing = h.ai_tech_dir
	if h.charge_ready:
		h.ai_tech_hold += delta
		var here := best_aim(h, t, preset, leader, 0.0, false)
		var need := ORDER_NEED if ordered else float(FIRE.get(preset, 1.3))
		if here["score"] >= need:
			h.facing = here["dir"]
			h.ai_tech_dir = here["dir"]
			Techs.cancel(h)
			Techs.fire(h, t)
			h.ai_tech_order_t = 0.0
			h.ai_tech_full_t = 0.0
			if preset == "aggressive":
				roll_turn(h)
			return Vector2.ZERO
		if h.ai_tech_hold >= (ORDER_HOLD_MAX if ordered else HOLD_MAX):
			_give_up(h, RETRY)
			h.ai_tech_order_t = 0.0
			return Vector2.ZERO
	return _approach(h, leader, preset)


static func _give_up(h: Hero, cooldown: float) -> void:
	Techs.cancel(h)
	h.ai_tech_cd = cooldown
	h.ai_tech_promise = false


## Walks (at charging speed) to the spot the blast lands best from, staying near the leader.
static func _approach(h: Hero, leader: Hero, preset: String) -> Vector2:
	var leash := 150.0 if preset == "support" else 240.0
	if leader and h.global_position.distance_to(leader.global_position) > leash:
		return (leader.global_position - h.global_position).normalized()
	var to: Vector2 = h.ai_tech_spot - h.global_position
	if to.length() < 3.0:
		return Vector2.ZERO
	return to.normalized() * clampf(to.length() / 16.0, 0.3, 1.0)


## How far from its target a hero stands to land this tech: on the blast's centre for ring techs,
## a bit inside the reach for arcs and lines, the middle of a chain, inside the knives' range.
static func standoff(t: Dictionary) -> float:
	var k: Dictionary = t.get("knives", {})
	if float(t.get("mult", 1)) <= 0.0 and not k.is_empty():
		return float(k.get("range", 120)) * 0.4
	var ahead := float(t.get("step", 0)) + float(t.get("offset", 0)) + float(t.get("chain_gap", 0)) * (maxi(1, int(t.get("chain", 1))) - 1) * 0.5
	var reach := float(t.get("reach", 30))
	if float(t.get("arc", 90)) >= 179.0:
		return maxf(ahead, reach * 0.4)
	return clampf(ahead + reach * 0.55, 10.0, ahead + reach - 6.0)


## Furthest point the blast reaches in front of the hero.
static func _span(t: Dictionary) -> float:
	var k: Dictionary = t.get("knives", {})
	var knives := float(k.get("range", 0)) if not k.is_empty() else 0.0
	var chain := float(t.get("chain_gap", 0)) * (maxi(1, int(t.get("chain", 1))) - 1)
	var blast := float(t.get("step", 0)) + float(t.get("offset", 0)) + float(t.get("reach", 30)) + chain if float(t.get("mult", 1)) > 0.0 else 0.0
	return maxf(blast, knives)


## Stops charging to get out of a lunge or slam aimed at this ally (Aggressive stands and takes it).
static func _should_dodge(h: Hero, preset: String) -> bool:
	if preset == "aggressive" or h.charge_ready:
		return false
	var hp_ratio := float(h.hp) / h.max_hp
	var limit: float = {"balanced": 0.5, "distance": 0.75, "support": 0.35}.get(preset, 0.5)
	if hp_ratio >= limit:
		return false
	for e in h.get_tree().get_nodes_in_group("enemies"):
		var enemy := e as Enemy
		if enemy and not enemy.dead and enemy.state == Enemy.State.WINDUP and enemy.target == h \
				and enemy.global_position.distance_to(h.global_position) <= DODGE_R:
			return true
	return false


# ---------------------------------------------------------------- scoring

## The best place and direction to fire from: {"dir", "score", "focus", "spot"}. Tries where the hero
## stands (facing and a line to every enemy in range) and, with move, the right standoff from each
## enemy it can walk to during the wind-up. slack widens the reach a little (enemies keep coming).
static func best_aim(h: Hero, t: Dictionary, preset: String, leader: Hero, slack: float, move := false) -> Dictionary:
	var here := h.global_position
	var out := {"dir": h.facing.normalized(), "score": 0.0, "focus": null, "spot": here}
	var near: Array = []
	var span := _span(t) + slack + 24.0 + (REPOSITION if move else 0.0)
	for e in h.get_tree().get_nodes_in_group("enemies"):
		var enemy := e as Enemy
		if enemy and not enemy.dead and enemy.global_position.distance_to(here) <= span:
			near.append(enemy)
	if near.is_empty() and int(t.get("heal", 0)) <= 0:
		return out
	var tries: Array = [[here, out["dir"]]]
	var stand := standoff(t)
	for e in near:
		var p: Vector2 = _predict(e)
		var to: Vector2 = p - here
		if to.length() > 0.5:
			tries.append([here, to.normalized()])
		if move:
			var away := -to.normalized() if to.length() > 0.5 else -h.facing.normalized()
			var spot: Vector2 = p + away * stand
			if spot.distance_to(here) <= REPOSITION and (leader == null or spot.distance_to(leader.global_position) < 200.0):
				tries.append([spot, -away])
	for tr in tries:
		var r := score(h, t, tr[0], tr[1], preset, leader, near, slack)
		# Standing still beats walking for the same result.
		var v: float = r["score"] - (0.0 if tr[0] == here else 0.15)
		if v > out["score"]:
			out = {"dir": tr[1], "score": v, "focus": r["focus"], "spot": tr[0]}
	return out


## What firing along dir from origin (where the hero stands before its lunge) would be worth:
## {"score", "focus"}. Every blast the tech makes counts (Techs.blasts): an enemy caught by several
## takes all of their damage. Knives count what is in their range; heals what allies would get back.
static func score(h: Hero, t: Dictionary, origin: Vector2, dir: Vector2, preset: String, leader: Hero, near: Array, slack := 0.0) -> Dictionary:
	var bl := Techs.blasts(t, origin + dir * float(t.get("step", 0)), dir)
	var flags := t.duplicate()  # stun, mark, execute: from the tech or its last hit
	for key in t.get("last", {}):
		flags[key] = t["last"][key]
	var total := 0.0
	var focus: Enemy = null
	var focus_v := 0.0
	var k: Dictionary = t.get("knives", {})
	for e in near:
		var enemy: Enemy = e
		var at := _predict(enemy)
		var taken := 0.0
		var from := origin
		for b in bl:
			var grown: Dictionary = b.duplicate()
			grown["reach"] = float(b["reach"]) + slack
			if Techs.inside(grown, at, enemy.radius):
				taken += roundi(h.base_damage * float((b["p"] as Dictionary).get("mult", 2.0)))
				from = (b["at"] as Vector2) - (b["dir"] as Vector2) * 4.0
		if not k.is_empty() and at.distance_to(origin) <= float(k.get("range", 120)) + slack:
			taken += roundi(h.base_damage * float(k.get("mult", 1.0))) * 0.6  # not every blade finds it
		if taken <= 0.0:
			continue
		var v := _worth(enemy, flags, int(taken), from)
		if preset == "support" and leader:
			v *= 1.4 if enemy.global_position.distance_to(leader.global_position) < 80.0 else 0.4
		total += v
		if v > focus_v:
			focus_v = v
			focus = enemy
	if int(t.get("heal", 0)) > 0 and not bl.is_empty():
		var heal := float(t["heal"]) * maxi(1, int(t.get("hits", 1)))
		var b0: Dictionary = bl[0]
		for o in h.get_tree().get_nodes_in_group("heroes"):
			var other := o as Hero
			if other == null or other.dead or other.party != h.party:
				continue
			var at2 := origin if other == h else other.global_position
			if at2.distance_to(b0["at"]) > float(b0["reach"]) + slack + 8.0:
				continue
			var gain := minf(heal, float(other.max_hp - other.hp)) / heal
			total += gain * (1.2 if preset == "support" else 0.7)
	return {"score": total, "focus": focus}
## One enemy's worth to a blast: elites and bosses count more, a kill or an interrupted wind-up more
## still, hitting an Enforcer's Ledger head-on (half damage) and an already stunned target less.
static func _worth(enemy: Enemy, t: Dictionary, dmg: int, from: Vector2) -> float:
	if enemy.invuln_t > 0.1 or enemy.dying_t >= 0.0:
		return 0.0  # still flashing from the last hit (the blast would pass through) or already falling
	var v := 1.0
	if enemy.boss:
		v = 3.0
	elif enemy.max_hp >= 60:
		v = 1.6
	var dealt := float(dmg)
	if float(t.get("execute", 0)) > 0.0 and float(enemy.hp) <= enemy.max_hp * float(t["execute"]):
		dealt *= 2.0
	if enemy.marked():
		dealt *= enemy.mark_mult
	if enemy is Enforcer:
		var to_from := from - enemy.global_position
		if to_from.length() > 0.1 and enemy.facing.dot(to_from.normalized()) > 0.35:
			dealt *= 0.5
			v *= 0.7
	if dealt >= enemy.hp:
		v += 0.6
	if float(t.get("stun", 0)) > 0.0:
		if enemy.state == Enemy.State.WINDUP:
			v += 0.5  # knocks the lunge out of it
		elif enemy.stun_left() > 0.3:
			v -= 0.2
	if float(t.get("mark", 0)) > 0.0 and not enemy.marked() and dealt < enemy.hp:
		v += 0.2
	return v


static func _predict(e: Enemy) -> Vector2:
	return e.global_position + e.velocity * LEAD
