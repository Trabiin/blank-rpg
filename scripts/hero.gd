class_name Hero
extends Actor
## A party member. Either player-controlled or driven by the ally AI.
## Visuals are a code-drawn "paper doll": one shared body rig recolored from `palette`.

const SWING_TIME := 0.24
const REVIVE_TIME := 2.5

var hero_name := "Ash"
var palette := {
	"skin": Color("e8b796"), "hair": Color("2b2233"), "outfit": Color("3d5a80"),
	"trim": Color("e0c36b"), "weapon": Color("d8e3ec"), "boots": Color("3a2f2a"),
}
var body_scale := 1.0
var has_beard := false
var controlled := false
var party  # main.gd: gives access to leader, shake()

# Mana-style attack power gauge: refills after each swing; early swings hit weaker.
var power := 1.0
var power_rate := 0.95
var base_damage := 10
var reach := 30.0
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


func _ready() -> void:
	super._ready()
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

	if swing_t > 0.0:
		swing_t -= delta
		if not swing_hit_done and swing_t <= SWING_TIME * 0.6:
			swing_hit_done = true
			_apply_hit()
	else:
		power = min(power + power_rate * delta, 1.0)

	var dir := Vector2.ZERO
	if controlled:
		dir = Input.get_vector("move_left", "move_right", "move_up", "move_down")
		if Input.is_action_just_pressed("attack"):
			try_attack()
	else:
		dir = _ai(delta)

	if dir.length() > 0.1 and swing_t <= 0.0:
		facing = dir.normalized()
	var spd := move_speed * (0.3 if swing_t > 0.0 else 1.0)
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
	if hit_any and party:
		party.shake(1.5 + 2.0 * swing_power)


func _on_hit() -> void:
	invuln_t = 0.7
	if party:
		party.shake(3.0)


func _on_death() -> void:
	revive_progress = 0.0
	swing_t = 0.0


func revive() -> void:
	dead = false
	hp = max_hp / 2
	invuln_t = 1.0
	revive_progress = 0.0
	Fx.burst(get_parent(), global_position + Vector2(0, -12), [Color("ffe08a"), Color.WHITE], 16, 70.0)


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

	if ai_target == null or not is_instance_valid(ai_target) or ai_target.dead \
			or ai_target.global_position.distance_to(leader.global_position) > 210.0:
		ai_target = _nearest_enemy(leader.global_position, 170.0)

	if ai_target:
		var to_t := ai_target.global_position - global_position
		var d := to_t.length()
		# Smart ally: only commits when the power gauge is (nearly) full.
		if power >= 0.95:
			if d <= reach + ai_target.radius - 6.0:
				facing = to_t.normalized()
				try_attack()
				return Vector2.ZERO
			return to_t.normalized()
		facing = to_t.normalized()
		if d < 44.0:
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


# ---------------------------------------------------------------- drawing

func _draw() -> void:
	draw_shadow(7.0 * body_scale)
	if invuln_t > 0.0 and not dead and int(invuln_t * 20.0) % 2 == 0:
		modulate.a = 0.45
	else:
		modulate.a = 1.0

	if dead:
		draw_set_transform(Vector2(0, -4), PI / 2.0, Vector2.ONE * body_scale)
		_draw_body(false)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		if revive_progress > 0.0:
			draw_arc(Vector2(0, -10), 12.0, -PI / 2.0, -PI / 2.0 + TAU * revive_progress / REVIVE_TIME, 24, Color("ffe08a"), 2.0)
		return

	var bob := -absf(sin(anim_t * 12.0)) * 1.5 if moving else 0.0
	draw_set_transform(Vector2(0, bob), 0.0, Vector2.ONE * body_scale)
	var weapon_behind := facing.y < -0.3
	if weapon_behind:
		_draw_weapon()
	_draw_body(true)
	if not weapon_behind:
		_draw_weapon()
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	if controlled:
		var y := -34.0 * body_scale + sin(anim_t * 4.0) * 1.5
		draw_colored_polygon(PackedVector2Array([Vector2(-3, y - 4), Vector2(3, y - 4), Vector2(0, y)]), Color("ffd166"))


func _draw_body(alive: bool) -> void:
	var p := palette
	var step := sin(anim_t * 12.0) * 2.0 if moving else 0.0
	# legs / boots
	draw_rect(Rect2(-4, -7 + minf(step, 0.0), 3, 7), c(p["boots"]))
	draw_rect(Rect2(1, -7 + minf(-step, 0.0), 3, 7), c(p["boots"]))
	# torso
	draw_rect(Rect2(-5, -16, 10, 10), c(p["outfit"]))
	draw_rect(Rect2(-5, -9, 10, 2), c(p["trim"]))
	# arms
	draw_rect(Rect2(-7, -15, 2, 7), c(p["outfit"].darkened(0.2)))
	draw_rect(Rect2(5, -15, 2, 7), c(p["outfit"].darkened(0.2)))
	# head
	var head := Vector2(0, -21)
	draw_circle(head, 5.0, c(p["skin"]))
	var up := facing.y < -0.5
	if up:
		draw_circle(head, 5.2, c(p["hair"]))
	else:
		draw_arc(head + Vector2(0, -1), 4.6, PI, TAU, 12, c(p["hair"]), 3.0)
		if alive:
			var eye := Color("1a1420")
			if absf(facing.x) > 0.6:
				draw_rect(Rect2(signf(facing.x) * 2.0 - 0.5, -22, 1.5, 2), eye)
			else:
				draw_rect(Rect2(-2.5, -22, 1.5, 2), eye)
				draw_rect(Rect2(1.0, -22, 1.5, 2), eye)
		if has_beard:
			draw_rect(Rect2(-4, -19, 8, 4), c(p["hair"]))


func _draw_weapon() -> void:
	var wcol: Color = c(palette["weapon"])
	var hand := Vector2(0, -12)
	if swing_t > 0.0:
		var t := 1.0 - swing_t / SWING_TIME
		var a0 := facing.angle() - arc
		var ang := a0 + 2.0 * arc * t
		var tip := hand + Vector2.RIGHT.rotated(ang) * (reach - 4.0)
		draw_line(hand, tip, wcol, 2.0)
		# slash trail
		var trail := Color(1, 1, 1, 0.75 * (0.4 + 0.6 * swing_power))
		draw_arc(hand, reach - 6.0, a0, ang, 16, trail, 3.0)
		if swing_power >= 1.0:
			draw_arc(hand, reach - 2.0, a0, ang, 16, Color("ffe08a", 0.6), 1.5)
	else:
		var side := 1.0 if facing.x >= 0.0 else -1.0
		draw_line(Vector2(6 * side, -10), Vector2(9 * side, -22), wcol, 2.0)
