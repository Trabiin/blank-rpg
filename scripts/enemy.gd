class_name Enemy
extends Actor
## "Nibbler": a small hungry scrap of the Blank. Wanders, chases, and lunges
## after a clear wind-up so the player can always dodge by moving.

enum State { WANDER, CHASE, WINDUP, LUNGE, RECOVER, STAGGER }

const AGGRO := 110.0
const LOSE := 200.0
const LUNGE_RANGE := 30.0
const WINDUP_TIME := 0.5
const LUNGE_TIME := 0.22
const LUNGE_SPEED := 190.0
const DAMAGE := 6

var state: int = State.WANDER
var state_t := 0.0
var wander_dir := Vector2.ZERO
var target: Hero
var lunge_dir := Vector2.ZERO
var hit_this_lunge: Array = []
var home := Vector2.ZERO
var static_seed := 0
var sprite: Sprite2D
var overlay: Node2D
var dying_t := -1.0
## Something to go and eat when no hero is close (a Defense mission's wardstone). Needs nibble(amount).
var goal: Node2D = null
var nibble_t := 0.0
var xp := 3  # shared by the party when it falls (issue #15)
## Hold the Line (abilities.gd): for taunt_t seconds this enemy goes for taunter and nobody else.
var taunter: Hero = null
var taunt_t := 0.0

## Puny's green slime, recolored into a scrap of the Blank: paper-white with an ink-black core.
const SLIME_COLORS := {"body": Color("e4e1d8"), "core": Color("15101a"), "shine": Color("ffffff")}


func _ready() -> void:
	max_hp = 28
	move_speed = 40.0
	radius = 5.0
	super._ready()
	collision_layer = 4
	number_color = Color.WHITE
	add_to_group("enemies")
	home = global_position
	static_seed = randi()
	sprite = Sprite2D.new()
	sprite.texture = Art.SLIME
	sprite.hframes = 15
	sprite.offset = Vector2(0, -4)
	sprite.material = Art.recolor_material("slime", SLIME_COLORS)
	add_child(sprite)
	overlay = Node2D.new()
	add_child(overlay)
	overlay.draw.connect(_draw_overlay)


func _physics_process(delta: float) -> void:
	if dying_t >= 0.0:
		return
	anim_t += delta
	flash_t = max(flash_t - delta, 0.0)
	state_t -= delta
	taunt_t = maxf(taunt_t - delta, 0.0)
	var dir := Vector2.ZERO

	match state:
		State.WANDER:
			if state_t <= 0.0:
				state_t = randf_range(0.8, 2.0)
				wander_dir = Vector2.ZERO if randf() < 0.35 else Vector2.RIGHT.rotated(randf() * TAU)
				if global_position.distance_to(home) > 90.0:
					wander_dir = (home - global_position).normalized()
			dir = wander_dir * 0.5
			if goal != null and is_instance_valid(goal):
				var to_goal := goal.global_position - global_position
				dir = to_goal.normalized() if to_goal.length() > 16.0 else Vector2.ZERO
				facing = to_goal.normalized()
				nibble_t -= delta
				if to_goal.length() <= 18.0 and nibble_t <= 0.0:
					nibble_t = 1.0
					goal.nibble(DAMAGE)
			target = _find_target(AGGRO)
			if target:
				_set_state(State.CHASE, 0.0)
		State.CHASE:
			if target == null or target.dead or target.global_position.distance_to(global_position) > LOSE:
				target = _find_target(AGGRO)
				if target == null:
					_set_state(State.WANDER, 0.0)
			if target:
				var to := target.global_position - global_position
				dir = to.normalized()
				facing = dir
				if to.length() < LUNGE_RANGE:
					_set_state(State.WINDUP, WINDUP_TIME)
		State.WINDUP:
			if target and not target.dead:
				facing = (target.global_position - global_position).normalized()
			if state_t <= 0.0:
				lunge_dir = facing
				hit_this_lunge.clear()
				_set_state(State.LUNGE, LUNGE_TIME)
		State.LUNGE:
			velocity = lunge_dir * LUNGE_SPEED + knockback
			move_and_slide()
			_check_lunge_hits()
			if state_t <= 0.0:
				_set_state(State.RECOVER, 0.7)
			queue_redraw()
			return
		State.RECOVER, State.STAGGER:
			if state_t <= 0.0:
				_set_state(State.CHASE, 0.0)

	velocity = dir * move_speed + knockback
	knockback = knockback.move_toward(Vector2.ZERO, 700.0 * delta)
	move_and_slide()
	queue_redraw()


func _set_state(s: int, t: float) -> void:
	state = s
	state_t = t


## Drop everything and go for this hero for a while.
func taunt(h: Hero, time: float) -> void:
	taunter = h
	taunt_t = time
	target = h
	if state == State.WANDER:
		_set_state(State.CHASE, 0.0)


func _find_target(dist: float) -> Hero:
	if taunt_t > 0.0 and taunter != null and is_instance_valid(taunter) and not taunter.dead:
		return taunter
	var best: Hero = null
	var best_d := dist
	for h in get_tree().get_nodes_in_group("heroes"):
		var hero := h as Hero
		if hero == null or hero.dead:
			continue
		var d := hero.global_position.distance_to(global_position)
		if d < best_d:
			best_d = d
			best = hero
	return best


func _check_lunge_hits() -> void:
	for h in get_tree().get_nodes_in_group("heroes"):
		var hero := h as Hero
		if hero == null or hero.dead or hit_this_lunge.has(hero):
			continue
		if hero.global_position.distance_to(global_position) < radius + hero.radius + 4.0:
			hit_this_lunge.append(hero)
			hero.take_hit(Empire.damage_to_party(DAMAGE), global_position, 200.0)


func _on_hit() -> void:
	# Getting hit interrupts a wind-up (rewarding aggression) but not a lunge in progress.
	if state != State.LUNGE:
		_set_state(State.STAGGER, 0.35)


func _on_death() -> void:
	Fx.burst(get_parent(), global_position + Vector2(0, -6), [Color.WHITE, Color("d9d9d9"), Color.BLACK], 16, 80.0)
	remove_from_group("enemies")
	collision_layer = 0
	dying_t = 0.0


func _process(delta: float) -> void:
	# Slime sheet: 0-2 squish, 3-5 hop, 6 hurt flash, 7-8 land, 10-14 burst.
	var f := 0
	if dying_t >= 0.0:
		dying_t += delta
		f = 10 + int(dying_t * 14.0)
		if f > 14:
			queue_free()
			return
	elif flash_t > 0.0:
		f = 6
	else:
		match state:
			State.WINDUP:
				f = 2
			State.LUNGE:
				f = 3 + clampi(int((1.0 - state_t / LUNGE_TIME) * 3.0), 0, 2)
			State.RECOVER:
				f = 7 if state_t > 0.45 else 8
			_:
				f = [0, 1, 2, 1][int(anim_t * 6.0) % 4]
	sprite.frame = f
	sprite.position = Vector2(randf_range(-0.7, 0.7), 0) if state == State.WINDUP else Vector2.ZERO
	queue_redraw()
	overlay.queue_redraw()


func _draw() -> void:
	if dying_t < 0.0:
		draw_shadow(5.0)


func _draw_overlay() -> void:
	if dying_t >= 0.0:
		return
	# Static flecks: the Blank leaking out of it.
	var rng := RandomNumberGenerator.new()
	rng.seed = static_seed + int(anim_t * 12.0)
	for i in 3:
		var p := Vector2(rng.randf_range(-8, 8), rng.randf_range(-12, 2))
		overlay.draw_rect(Rect2(p, Vector2(1, 1)), Color(1, 1, 1, 0.9) if i % 2 else Color(0, 0, 0, 0.7))
	if taunt_t > 0.0:  # Hold the Line: a little orange tag shows who it is locked onto
		overlay.draw_rect(Rect2(-1.5, -19, 3, 3), Color("f2a65a"))
	if state == State.WINDUP:
		overlay.draw_string(ThemeDB.fallback_font, Vector2(-2, -12), "!", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("ff5d5d"))
	if hp < max_hp:
		overlay.draw_rect(Rect2(-6, -14, 12, 2), Color(0, 0, 0, 0.6))
		overlay.draw_rect(Rect2(-6, -14, 12.0 * hp / max_hp, 2), Color("ff6b6b"))
