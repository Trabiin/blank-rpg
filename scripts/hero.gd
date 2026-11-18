class_name Hero
extends Actor
## A party member. Either player-controlled or driven by the ally AI.
## Visuals are a paper doll: CC0 Puny Characters body + outfit layers, recolored per hero.

const SWING_TIME := 0.24
const REVIVE_TIME := 2.5

var hero_name := "Ash"
var hero_id := "ash"  # recruit id (data/recruits.json, data/heroes.json); banter speakers use it
## Paper doll: the shared body layer plus one outfit layer, both recolored in code.
var outfit := "archer"
var colors := {
	"skin": Color("e9c4a6"), "cloth": Color("4a4f8a"), "leather": Color("5a4636"),
	"boots": Color("2e2838"), "trim": Color("d9d4e8"),
}
var body_sprite: Sprite2D
var outfit_sprite: Sprite2D
var overlay: Node2D
var controlled := false
var party  # main.gd or hub.gd: gives access to leader, shake()
var peaceful := false  # in town the attack button talks instead

# Mana-style attack power gauge: refills after each swing; early swings hit weaker.
var power := 1.0
var power_rate := 0.95
var base_damage := 10
var reach := 20.0
var arc := deg_to_rad(70.0)
var swing_t := 0.0
var swing_power := 1.0
var swing_hit_done := false
var moving := false

# AI state
var ai_target: Enemy
var ai_side := 1.0
var stuck_t := 0.0
var detour_t := 0.0
var detour_dir := Vector2.ZERO

var revive_progress := 0.0

## How the ally AI behaves (data/heroes.json picks one per hero).
## commit: gauge needed before charging in; seek: how far from the leader it looks for enemies;
## leash: drops a target that strays this far from the leader; back_off: retreats to this distance while recharging.
const AI_STYLES := {
	"steady": {"commit": 0.95, "seek": 170.0, "leash": 210.0, "back_off": 44.0},
	"guard": {"commit": 0.9, "seek": 95.0, "leash": 130.0, "back_off": 30.0},
	"reckless": {"commit": 0.55, "seek": 240.0, "leash": 300.0, "back_off": 0.0},
	"healer": {"commit": 0.95, "seek": 60.0, "leash": 90.0, "back_off": 64.0},
}
var ai_style := "steady"
# Passive poultice (Mother Gristle): every heal_every seconds, patch the most hurt ally in range.
var heal_every := 0.0
var heal_amount := 0
var heal_range := 80.0
var heal_t := 3.0
# Armor (issue #15): this fraction of every hit is blocked. Set by Progress.apply_to from gear.
var guard := 0.0

# Abilities and Ink (issue #7; what each one does lives in scripts/abilities.gd).
var abilities: Array = []  # ability dicts from data/abilities.json, slot i = key i+1
var cooldowns: Array = []  # seconds left per slot
var max_ink := 0.0
var ink := 0.0
var ink_regen := Abilities.REGEN
var cast_t := 0.0  # brief casting pose
var cast_color := Color.WHITE
var shield_hp := 0  # Rewrite: soaks this much damage
var shield_t := 0.0
var guard_t := 0.0  # Hold the Line: takes guard_cut less damage while > 0
var guard_cut := 0.0
var dash_t := 0.0  # Strikethrough / Long Thrust
var dash_dir := Vector2.ZERO
var dash_speed := 0.0
var dash_ability := {}
var dash_hit: Array = []
var ai_ability_t := 0.0


func _ready() -> void:
	radius = 5.0
	super._ready()
	build_doll()
	collision_layer = 2
	number_color = Color("ff6b6b")


func _physics_process(delta: float) -> void:
	anim_t += delta
	flash_t = max(flash_t - delta, 0.0)
	invuln_t = max(invuln_t - delta, 0.0)

	if dead:
		knockback = knockback.move_toward(Vector2.ZERO, 600.0 * delta)
		velocity = knockback
		move_and_slide()
		queue_redraw()
		return

	if heal_every > 0.0:
		_update_heal(delta)
	_update_abilities(delta)

	if dash_t > 0.0:
		dash_t -= delta
		velocity = dash_dir * dash_speed
		move_and_slide()
		Abilities.dash_hits(self)
		moving = true
		queue_redraw()
		return

	if swing_t > 0.0:
		swing_t -= delta
		if not swing_hit_done and swing_t <= SWING_TIME * 0.6:
			swing_hit_done = true
			_apply_hit()
	else:
		power = min(power + power_rate * delta, 1.0)

	var dir := Vector2.ZERO
	if controlled and party and party.get("quick_open") == true:
		dir = Vector2.ZERO  # the quick menu has the controls (time is slowed, not stopped)
	elif controlled:
		dir = Input.get_vector("move_left", "move_right", "move_up", "move_down")
		if Input.is_action_just_pressed("attack") and not peaceful:
			try_attack()
		if not peaceful:  # (the quick menu branch above already keeps these quiet while it is open)
			for i in abilities.size():
				if Input.is_action_just_pressed("ability_%d" % (i + 1)):
					Abilities.use(self, i)
	else:
		dir = _ai(delta)

	if dir.length() > 0.1 and swing_t <= 0.0:
		facing = dir.normalized()
	var spd := move_speed * (0.3 if swing_t > 0.0 or cast_t > 0.0 else 1.0)
	velocity = dir * spd + knockback
	knockback = knockback.move_toward(Vector2.ZERO, 900.0 * delta)
	move_and_slide()
	moving = dir.length() > 0.1

	if not controlled and dir.length() > 0.3 and get_real_velocity().length() < 8.0:
		stuck_t += delta
	else:
		stuck_t = 0.0
	queue_redraw()


func try_attack() -> void:
	if swing_t > 0.0 or dead:
		return
	swing_t = SWING_TIME
	swing_power = power
	power = 0.0
	swing_hit_done = false


func _apply_hit() -> void:
	var dmg := maxi(1, roundi(base_damage * swing_power))
	var hit_any := false
	for e in get_tree().get_nodes_in_group("enemies"):
		var enemy := e as Enemy
		if enemy == null or enemy.dead:
			continue
		var to := enemy.global_position - global_position
		if to.length() <= reach + enemy.radius and absf(facing.angle_to(to)) <= arc:
			if enemy.take_hit(dmg, global_position, 120.0 + 160.0 * swing_power):
				hit_any = true
	if hit_any and swing_power >= 1.0:
		ink = minf(ink + Abilities.HIT_GAIN, max_ink)  # a full-power hit that lands writes a little Ink
	if hit_any and party:
		party.shake(1.5 + 2.0 * swing_power)


## Rewrite's shield soaks first, then Hold the Line's guard cuts what's left.
func _adjust_damage(amount: int) -> int:
	if shield_hp > 0:
		var soaked := mini(shield_hp, amount)
		shield_hp -= soaked
		amount -= soaked
		if amount <= 0:
			Fx.damage_number(get_parent(), global_position + Vector2(0, -16), "blocked", Color("9fd8ff"))
			invuln_t = 0.3
			return 0
	if guard_t > 0.0:
		amount = maxi(1, roundi(amount * (1.0 - guard_cut)))
	if guard > 0.0:  # armor (issue #15)
		amount = maxi(1, roundi(amount * (1.0 - guard)))
	return amount


func set_abilities(ids: Array, ink_pool: float) -> void:
	abilities = Abilities.for_ids(ids)
	cooldowns = []
	cooldowns.resize(abilities.size())
	cooldowns.fill(0.0)
	max_ink = ink_pool
	ink = ink_pool


func start_dash(a: Dictionary) -> void:
	dash_ability = a
	dash_dir = facing.normalized()
	dash_t = 0.18
	dash_speed = float(a.get("distance", 70)) / dash_t
	dash_hit.clear()
	invuln_t = maxf(invuln_t, dash_t + 0.1)  # dashing through a lunge is the point
	swing_t = 0.0


func _update_abilities(delta: float) -> void:
	for i in cooldowns.size():
		cooldowns[i] = maxf(cooldowns[i] - delta, 0.0)
	if max_ink > 0.0:
		ink = minf(ink + ink_regen * delta, max_ink)
	cast_t = maxf(cast_t - delta, 0.0)
	guard_t = maxf(guard_t - delta, 0.0)
	if shield_t > 0.0:
		shield_t -= delta
		if shield_t <= 0.0:
			shield_hp = 0


func _on_hit() -> void:
	invuln_t = 0.7
	if party:
		party.shake(3.0)


func _on_death() -> void:
	revive_progress = 0.0
	swing_t = 0.0
	dash_t = 0.0
	shield_hp = 0
	guard_t = 0.0


func revive() -> void:
	dead = false
	hp = max_hp / 2
	invuln_t = 1.0
	revive_progress = 0.0
	Fx.burst(get_parent(), global_position + Vector2(0, -12), [Color("ffe08a"), Color.WHITE], 16, 70.0)


func _update_heal(delta: float) -> void:
	heal_t -= delta
	if heal_t > 0.0:
		return
	var best: Hero = null
	var best_ratio := 1.0
	for h in get_tree().get_nodes_in_group("heroes"):
		var other := h as Hero
		if other == null or other.dead or other.hp >= other.max_hp:
			continue
		if other.global_position.distance_to(global_position) > heal_range:
			continue
		var ratio := float(other.hp) / float(other.max_hp)
		if ratio < best_ratio and other.max_hp - other.hp >= mini(heal_amount, 3):
			best_ratio = ratio
			best = other
	if best == null:
		heal_t = 0.5  # nobody needs it: look again soon
		return
	var amount := mini(heal_amount, best.max_hp - best.hp)
	best.hp += amount
	Fx.damage_number(get_parent(), best.global_position + Vector2(0, -18), "+%d" % amount, Color("9fe07a"))
	Fx.burst(get_parent(), best.global_position + Vector2(0, -10), [Color("9fbf6a"), Color("dff5b0")], 10, 40.0)
	heal_t = heal_every


# ---------------------------------------------------------------- ally AI

func _ai(delta: float) -> Vector2:
	var leader: Hero = party.leader if party else null
	if leader == null or leader == self or leader.dead:
		return Vector2.ZERO
	var to_leader := leader.global_position - global_position
	if to_leader.length() > 380.0:
		global_position = leader.global_position - leader.facing * 18.0
		return Vector2.ZERO

	if detour_t > 0.0:
		detour_t -= delta
		return detour_dir
	if stuck_t > 0.35:
		stuck_t = 0.0
		detour_t = 0.4
		detour_dir = to_leader.normalized().rotated(PI / 2.0 * ai_side)
		ai_side = -ai_side
		return detour_dir

	var style: Dictionary = AI_STYLES.get(ai_style, AI_STYLES["steady"])
	if not abilities.is_empty():
		ai_ability_t -= delta
		if ai_ability_t <= 0.0:
			ai_ability_t = Abilities.AI_THINK
			var pick := Abilities.ai_pick(self)
			if pick >= 0 and Abilities.use(self, pick):
				return Vector2.ZERO
	if ai_target == null or not is_instance_valid(ai_target) or ai_target.dead \
			or ai_target.global_position.distance_to(leader.global_position) > float(style["leash"]):
		ai_target = _nearest_enemy(leader.global_position, float(style["seek"]))

	if ai_target:
		var to_t := ai_target.global_position - global_position
		var d := to_t.length()
		# Commits once the power gauge is full enough for this hero's style.
		if power >= float(style["commit"]):
			if d <= reach + ai_target.radius - 6.0:
				facing = to_t.normalized()
				try_attack()
				return Vector2.ZERO
			return to_t.normalized()
		facing = to_t.normalized()
		if d < float(style["back_off"]):
			return -to_t.normalized() * 0.8
		return Vector2.ZERO

	var side := leader.facing.orthogonal() * 14.0 * ai_side
	var dest := leader.global_position - leader.facing * 22.0 + side
	var to_d := dest - global_position
	if to_d.length() < 12.0:
		return Vector2.ZERO
	return to_d.normalized() * clampf(to_d.length() / 36.0, 0.35, 1.0)


func _nearest_enemy(from: Vector2, max_dist: float) -> Enemy:
	var best: Enemy = null
	var best_d := max_dist
	for e in get_tree().get_nodes_in_group("enemies"):
		var enemy := e as Enemy
		if enemy == null or enemy.dead:
			continue
		var d := enemy.global_position.distance_to(from)
		if d < best_d:
			best_d = d
			best = enemy
	return best


# ---------------------------------------------------------------- paper doll

func build_doll() -> void:
	body_sprite = _layer(Art.BODY, Art.recolor_material("body", colors))
	outfit_sprite = _layer(Art.OUTFITS[outfit], Art.recolor_material(outfit, colors))
	overlay = Node2D.new()
	add_child(overlay)
	overlay.draw.connect(_draw_overlay)


func _layer(tex: Texture2D, mat: ShaderMaterial) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = tex
	s.hframes = 24
	s.vframes = 8
	s.offset = Vector2(0, -7)  # feet of the 32x32 Puny frame sit on the node origin
	s.material = mat
	add_child(s)
	return s


## Puny Characters sheet: rows are 8 directions clockwise from facing down,
## columns 0-3 walk, 4-7 sword swing, 19 hurt flash, 22-23 knocked down.
static func dir_row(v: Vector2) -> int:
	return posmod(roundi((PI / 2.0 - v.angle()) / (PI / 4.0)), 8)


func _update_frame() -> void:
	if body_sprite == null:
		return
	var col := 0
	if dead:
		col = 23
	elif flash_t > 0.0:
		col = 19
	elif swing_t > 0.0:
		col = 4 + clampi(int((1.0 - swing_t / SWING_TIME) * 4.0), 0, 3)
	elif cast_t > 0.0:
		col = 4 + clampi(int((1.0 - cast_t / SWING_TIME) * 4.0), 0, 3)
	elif dash_t > 0.0:
		col = 5
	elif moving:
		col = int(anim_t * 9.0) % 4
	var frame := dir_row(facing) * 24 + col
	body_sprite.frame = frame
	outfit_sprite.frame = frame
	var blink := invuln_t > 0.0 and not dead and int(invuln_t * 20.0) % 2 == 0
	modulate.a = 0.45 if blink else 1.0


func _process(_delta: float) -> void:
	_update_frame()
	queue_redraw()
	if overlay:
		overlay.queue_redraw()


func _draw() -> void:
	# Drawn before the child sprites, so it sits underneath them.
	draw_shadow(5.5)


func _draw_overlay() -> void:
	if dead:
		if revive_progress > 0.0:
			overlay.draw_arc(Vector2(0, -6), 10.0, -PI / 2.0, -PI / 2.0 + TAU * revive_progress / REVIVE_TIME, 24, Color("ffe08a"), 1.5)
		return
	if shield_hp > 0:
		overlay.draw_arc(Vector2(0, -7), 11.0, 0, TAU, 24, Color("9fd8ff", 0.45 + 0.2 * sin(anim_t * 6.0)), 1.0)
	if guard_t > 0.0:
		overlay.draw_arc(Vector2(0, -7), 12.5, PI * 0.15, PI * 0.85, 12, Color("f2a65a", 0.7), 1.5)
	if cast_t > 0.0:
		overlay.draw_circle(Vector2(0, -22), 2.0 * cast_t / SWING_TIME + 0.5, Color(cast_color, 0.9))
	if dash_t > 0.0:
		for k in 3:
			var back := -dash_dir * (6.0 + 6.0 * k)
			overlay.draw_line(back + Vector2(0, -10), back + Vector2(0, -2), Color(1, 1, 1, 0.5 - 0.15 * k), 2.0)
	if controlled:
		var y := -21.0 + sin(anim_t * 4.0) * 1.0
		overlay.draw_colored_polygon(PackedVector2Array([Vector2(-2.5, y - 3), Vector2(2.5, y - 3), Vector2(0, y)]), Color("ffd166"))
	# A full-power swing gets a gold arc on top of the sprite's own slash.
	if swing_t > 0.0 and swing_power >= 1.0:
		var t := 1.0 - swing_t / SWING_TIME
		var a0 := facing.angle() - arc
		overlay.draw_arc(Vector2(0, -6), reach - 3.0, a0, a0 + 2.0 * arc * t, 16, Color("ffe08a", 0.7), 1.5)
