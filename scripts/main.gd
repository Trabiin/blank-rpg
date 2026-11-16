extends Node2D
## Prototype: the Frayed Meadow. Builds the area in code, spawns the party
## (Ash + Bran), Nibblers that crawl out of the Blank, and the HUD.

const HeroScript := preload("res://scripts/hero.gd")
const EnemyScript := preload("res://scripts/enemy.gd")
const PropScript := preload("res://scripts/prop.gd")
const GroundScript := preload("res://scripts/ground.gd")
const BlankScript := preload("res://scripts/blank.gd")
const HudScript := preload("res://scripts/hud.gd")
const TouchScript := preload("res://scripts/touch.gd")

const WORLD := Vector2(1280, 960)
const MAX_ENEMIES := 7
const RESPAWN_TIME := 6.0

var heroes: Array = []
var leader: Hero
var entities: Node2D
var blank: Blank
var camera: Camera2D
var hud  # hud.gd
var touch  # touch.gd
var props: Array = []
var kills := 0
var shake_amount := 0.0
var respawn_t := 0.0
var blank_tick := 0.0
var game_over := false
var banter_queue: Array = []
var banter_t := 1.0
var said_low_power := false
var said_first_kill := false


func _ready() -> void:
	randomize()
	_setup_input()

	var ground = GroundScript.new()
	ground.size = WORLD
	add_child(ground)

	blank = Blank.new()
	blank.height = WORLD.y
	blank.width = WORLD.x
	add_child(blank)
	ground.blank_x = blank.base_x

	entities = Node2D.new()
	entities.y_sort_enabled = true
	add_child(entities)

	_build_walls()
	_build_props()

	var ash := _make_hero("Ash", Vector2(220, 470), {
		"skin": Color("e8b796"), "hair": Color("d9d4e8"), "outfit": Color("3b3f6b"),
		"trim": Color("9fb7ff"), "weapon": Color("dfe8f0"), "boots": Color("2a2433"),
	})
	ash.base_damage = 10
	var bran := _make_hero("Bran", Vector2(190, 500), {
		"skin": Color("c98e6a"), "hair": Color("8a3b22"), "outfit": Color("5a4a3a"),
		"trim": Color("b84a3a"), "weapon": Color("a9a9a9"), "boots": Color("2e2620"),
	})
	bran.body_scale = 1.15
	bran.has_beard = true
	bran.max_hp = 60
	bran.hp = 60
	bran.move_speed = 74.0
	bran.base_damage = 14
	bran.power_rate = 0.75
	bran.reach = 32.0
	_set_leader(ash)

	for i in 5:
		_spawn_enemy(Vector2(randf_range(600, 1000), randf_range(140, 820)))

	camera = Camera2D.new()
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 7.0
	camera.limit_left = 0
	camera.limit_top = 0
	camera.limit_right = int(WORLD.x)
	camera.limit_bottom = int(WORLD.y)
	add_child(camera)
	camera.global_position = leader.global_position
	camera.reset_smoothing()

	var layer := CanvasLayer.new()
	add_child(layer)
	hud = HudScript.new()
	hud.party = self
	layer.add_child(hud)
	touch = TouchScript.new()
	layer.add_child(touch)

	banter_queue = [
		["Bran", "Huh. A person. Or a very convincing smudge."],
		["Bran", "You crawled out of the Blank? Nobody does that. Nobody's paid me to see that, either."],
		["Bran", "Those white things eat. Hit them when your gauge is full. Or don't, and I'll bill your corpse."],
	]


func _setup_input() -> void:
	_add_action("move_left", [KEY_A, KEY_LEFT], [JOY_BUTTON_DPAD_LEFT], JOY_AXIS_LEFT_X, -1.0)
	_add_action("move_right", [KEY_D, KEY_RIGHT], [JOY_BUTTON_DPAD_RIGHT], JOY_AXIS_LEFT_X, 1.0)
	_add_action("move_up", [KEY_W, KEY_UP], [JOY_BUTTON_DPAD_UP], JOY_AXIS_LEFT_Y, -1.0)
	_add_action("move_down", [KEY_S, KEY_DOWN], [JOY_BUTTON_DPAD_DOWN], JOY_AXIS_LEFT_Y, 1.0)
	_add_action("attack", [KEY_J, KEY_SPACE, KEY_Z], [JOY_BUTTON_A, JOY_BUTTON_X])
	_add_action("swap", [KEY_TAB, KEY_Q], [JOY_BUTTON_Y])
	_add_action("restart", [KEY_R], [JOY_BUTTON_START])


func _add_action(action: String, keys: Array, buttons: Array, axis := -1, axis_value := 0.0) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action, 0.3)
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event(action, ev)
	for b in buttons:
		var jb := InputEventJoypadButton.new()
		jb.button_index = b
		InputMap.action_add_event(action, jb)
	if axis >= 0:
		var jm := InputEventJoypadMotion.new()
		jm.axis = axis
		jm.axis_value = axis_value
		InputMap.action_add_event(action, jm)


func _build_walls() -> void:
	var walls := StaticBody2D.new()
	walls.collision_layer = 1
	add_child(walls)
	var t := 40.0
	for r in [
		Rect2(-t, -t, WORLD.x + 2 * t, t),
		Rect2(-t, WORLD.y, WORLD.x + 2 * t, t),
		Rect2(-t, 0, t, WORLD.y),
		Rect2(WORLD.x, 0, t, WORLD.y),
	]:
		var shape := RectangleShape2D.new()
		shape.size = r.size
		var col := CollisionShape2D.new()
		col.shape = shape
		col.position = r.position + r.size / 2.0
		walls.add_child(col)


func _build_props() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var placed := 0
	var tries := 0
	while placed < 70 and tries < 2000:
		tries += 1
		var p := Vector2(rng.randf_range(30, WORLD.x - 60), rng.randf_range(30, WORLD.y - 20))
		var path_y := 480.0 + sin(p.x * 0.006) * 90.0 + sin(p.x * 0.017) * 20.0
		if absf(p.y - path_y) < 40.0 or p.distance_to(Vector2(210, 480)) < 90.0:
			continue
		var ok := true
		for q in props:
			if (q as Node2D).position.distance_to(p) < 34.0:
				ok = false
				break
		if not ok:
			continue
		_add_prop("tree" if rng.randf() < 0.75 else "rock", p, rng.randi())
		placed += 1
	var sign1 = _add_prop("sign", Vector2(300, 440), 0)
	sign1.text = "WELCOME TO THE FRAYED MEADOW\npop. 212   pop. 40   pop. ?"
	var sign2 = _add_prop("sign", Vector2(960, 515), 0)
	sign2.text = "HOLLOWMARK  ->  (east)\n(east is gone)"


func _add_prop(kind: String, p: Vector2, seed_v: int):
	var prop = PropScript.new()
	prop.kind = kind
	prop.position = p
	prop.seed_v = seed_v
	prop.erased = clampf((p.x - (blank.base_x - 220.0)) / 220.0, 0.0, 0.85)
	entities.add_child(prop)
	props.append(prop)
	return prop


func _make_hero(hero_name: String, pos: Vector2, palette: Dictionary) -> Hero:
	var h: Hero = HeroScript.new()
	h.hero_name = hero_name
	h.palette = palette
	h.party = self
	h.position = pos
	h.add_to_group("heroes")
	entities.add_child(h)
	heroes.append(h)
	h.died.connect(_on_hero_died)
	return h


func _spawn_enemy(pos: Vector2) -> void:
	var e: Enemy = EnemyScript.new()
	e.position = pos
	entities.add_child(e)
	e.died.connect(_on_enemy_died)


func _set_leader(h: Hero) -> void:
	leader = h
	for other in heroes:
		(other as Hero).controlled = other == h


func shake(amount: float) -> void:
	shake_amount = maxf(shake_amount, amount)


func touch_active() -> bool:
	return touch != null and touch.visible


func _on_enemy_died(_e: Actor) -> void:
	kills += 1
	if not said_first_kill:
		said_first_kill = true
		banter_queue.append(["Bran", "It popped. Like a thought you weren't supposed to have."])
	if kills == 10:
		banter_queue.append(["Bran", "Ten. I'm charging by the head, by the way. You owe me... a number."])


func _on_hero_died(a: Actor) -> void:
	var alive := heroes.filter(func(h): return not h.dead)
	if alive.is_empty():
		game_over = true
		hud.center_text = "The party was erased.\nPress R / Start / tap to try again"
		return
	if a == leader:
		_set_leader(alive[0])
		hud.say("%s is down! You now control %s." % [(a as Hero).hero_name, leader.hero_name], 3.0)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("restart") or (game_over and event is InputEventScreenTouch and event.pressed):
		get_tree().reload_current_scene()
		return
	if event.is_action_pressed("swap") and not game_over:
		_swap()


func _swap() -> void:
	var idx := heroes.find(leader)
	for i in range(1, heroes.size()):
		var h: Hero = heroes[(idx + i) % heroes.size()]
		if not h.dead:
			_set_leader(h)
			return


func _process(delta: float) -> void:
	# The touch Swap button presses the action directly, which _unhandled_input does not see.
	if touch_active() and Input.is_action_just_pressed("swap") and not game_over:
		_swap()

	if camera and leader:
		camera.global_position = leader.global_position + Vector2(0, -10)
		shake_amount = maxf(shake_amount - 20.0 * delta, 0.0)
		camera.offset = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * shake_amount

	_update_blank_contact(delta)
	_update_revive(delta)
	_update_respawn(delta)
	_update_banter(delta)
	_update_signs()


func _update_blank_contact(delta: float) -> void:
	blank_tick -= delta
	for h in heroes:
		var hero: Hero = h
		if hero.dead:
			continue
		var edge := blank.edge_x(hero.global_position.y)
		if hero.global_position.x > edge - 4.0:
			hero.knockback = Vector2(-160, 0)
			if blank_tick <= 0.0:
				hero.invuln_t = 0.0
				hero.take_hit(3, hero.global_position + Vector2(10, 0), 160.0)
				if hero == leader:
					hud.say("The Blank bites. It does not want you back. Yet.", 2.5)
	if blank_tick <= 0.0:
		blank_tick = 0.6


func _update_revive(delta: float) -> void:
	if leader == null or leader.dead:
		return
	var enemies_near := false
	for e in get_tree().get_nodes_in_group("enemies"):
		if (e as Node2D).global_position.distance_to(leader.global_position) < 110.0:
			enemies_near = true
			break
	for h in heroes:
		var hero: Hero = h
		if not hero.dead:
			continue
		if not enemies_near and hero.global_position.distance_to(leader.global_position) < 28.0:
			hero.revive_progress += delta
			if hero.revive_progress >= Hero.REVIVE_TIME:
				hero.revive()
				hud.say("%s is back on their feet." % hero.hero_name, 2.5)
		else:
			hero.revive_progress = maxf(hero.revive_progress - delta, 0.0)


func _update_respawn(delta: float) -> void:
	var count := get_tree().get_nodes_in_group("enemies").filter(func(e): return not e.is_queued_for_deletion()).size()
	if count >= MAX_ENEMIES:
		return
	respawn_t -= delta
	if respawn_t <= 0.0:
		respawn_t = RESPAWN_TIME
		var y := randf_range(80, WORLD.y - 80)
		_spawn_enemy(Vector2(blank.edge_x(y) - 16.0, y))


func _update_banter(delta: float) -> void:
	if game_over:
		return
	if not said_low_power and leader and leader.power < 0.5 and leader.swing_t > 0.0 and leader.swing_power < 0.5:
		said_low_power = true
		banter_queue.push_front(["Bran", "Swinging at half power? Bold. Wait for the gauge, smudge."])
	banter_t -= delta
	if banter_t <= 0.0 and not banter_queue.is_empty():
		var line: Array = banter_queue.pop_front()
		hud.say("%s: %s" % [line[0], line[1]], 4.0)
		banter_t = 4.6


func _update_signs() -> void:
	var txt := ""
	if leader:
		for p in props:
			if p.kind == "sign" and (p as Node2D).global_position.distance_to(leader.global_position) < 34.0:
				txt = p.text
	hud.sign_text = txt
