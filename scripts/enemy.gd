class_name Enemy
extends Actor
## "Nibbler": a small hungry scrap of the Blank. Wanders, chases, and lunges
## after a clear wind-up so the player can always dodge by moving.

enum State { WANDER, CHASE, WINDUP, LUNGE, RECOVER, STAGGER }

const AGGRO := 130.0
const LOSE := 230.0
const LUNGE_RANGE := 42.0
const WINDUP_TIME := 0.5
const LUNGE_TIME := 0.22
const LUNGE_SPEED := 230.0
const DAMAGE := 6

var state: int = State.WANDER
var state_t := 0.0
var wander_dir := Vector2.ZERO
var target: Hero
var lunge_dir := Vector2.ZERO
var hit_this_lunge: Array = []
var home := Vector2.ZERO
var static_seed := 0


func _ready() -> void:
	max_hp = 28
	move_speed = 46.0
	radius = 6.0
	super._ready()
	collision_layer = 4
	number_color = Color.WHITE
	add_to_group("enemies")
	home = global_position
	static_seed = randi()


func _physics_process(delta: float) -> void:
	anim_t += delta
	flash_t = max(flash_t - delta, 0.0)
	state_t -= delta
	var dir := Vector2.ZERO

	match state:
		State.WANDER:
			if state_t <= 0.0:
				state_t = randf_range(0.8, 2.0)
				wander_dir = Vector2.ZERO if randf() < 0.35 else Vector2.RIGHT.rotated(randf() * TAU)
				if global_position.distance_to(home) > 90.0:
					wander_dir = (home - global_position).normalized()
			dir = wander_dir * 0.5
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


func _find_target(dist: float) -> Hero:
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
			hero.take_hit(DAMAGE, global_position, 200.0)


func _on_hit() -> void:
	# Getting hit interrupts a wind-up (rewarding aggression) but not a lunge in progress.
	if state != State.LUNGE:
		_set_state(State.STAGGER, 0.35)


func _on_death() -> void:
	Fx.burst(get_parent(), global_position + Vector2(0, -8), [Color.WHITE, Color("d9d9d9"), Color.BLACK], 22, 110.0)
	queue_free()


func _draw() -> void:
	draw_shadow(7.0)
	var shake := Vector2.ZERO
	if state == State.WINDUP:
		shake = Vector2(randf_range(-1, 1), 0)
	var squash := 1.0 + sin(anim_t * 9.0) * 0.08
	var center := Vector2(0, -8) + shake
	var body_col := c(Color("f4f1ea"))
	draw_set_transform(center, 0.0, Vector2(squash, 2.0 - squash))
	draw_circle(Vector2.ZERO, 8.0, Color.BLACK)
	draw_circle(Vector2.ZERO, 7.0, body_col)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# Mouth: a jagged black gash facing the target; gapes during wind-up.
	var open := 2.6 + absf(sin(anim_t * 6.0)) * 1.5
	if state == State.WINDUP:
		open = 4.0
	elif state == State.LUNGE:
		open = 5.0
	var m := center + facing * 2.5
	var w := 5.0
	var pts := PackedVector2Array()
	for i in 7:
		var x := -w + i * (2.0 * w / 6.0)
		pts.append(m + Vector2(x, -open * 0.5 + (0.8 if i % 2 == 0 else 0.0)))
	for i in 7:
		var x := w - i * (2.0 * w / 6.0)
		pts.append(m + Vector2(x, open * 0.5 - (0.8 if i % 2 == 0 else 0.0)))
	draw_colored_polygon(pts, Color("120d14"))

	# Static flecks: the Blank leaking out of it.
	var rng := RandomNumberGenerator.new()
	rng.seed = static_seed + int(anim_t * 12.0)
	for i in 4:
		var p := center + Vector2(rng.randf_range(-11, 11), rng.randf_range(-10, 8))
		draw_rect(Rect2(p, Vector2(1, 1)), Color(1, 1, 1, 0.8) if i % 2 else Color(0, 0, 0, 0.6))

	if state == State.WINDUP:
		draw_string(ThemeDB.fallback_font, center + Vector2(-2, -12), "!", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("ff5d5d"))
	if hp < max_hp:
		draw_rect(Rect2(-8, -22, 16, 2), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(-8, -22, 16.0 * hp / max_hp, 2), Color("ff6b6b"))
