extends Node2D
## Prototype: the Frayed Meadow. Builds the area in code, spawns the party
## (Ash + Bran), Nibblers that crawl out of the Blank, and the HUD.

const HeroScript := preload("res://scripts/hero.gd")
const EnemyScript := preload("res://scripts/enemy.gd")
const PropScript := preload("res://scripts/prop.gd")
const BlankScript := preload("res://scripts/blank.gd")
const HudScript := preload("res://scripts/hud.gd")
const TouchScript := preload("res://scripts/touch.gd")

const MAP := "res://maps/frayed_meadow.txt"
const TITLE_SCENE := "res://scenes/title.tscn"
const MAX_ENEMIES := 7
const RESPAWN_TIME := 6.0
const AUTOSAVE_EVERY := 60.0

var heroes: Array = []
var leader: Hero
var entities: Node2D
var blank: Blank
var camera: Camera2D
var hud  # hud.gd
var touch  # touch.gd
var area: Area
var world := Vector2.ZERO
var kills := 0
var shake_amount := 0.0
var respawn_t := 0.0
var blank_tick := 0.0
var game_over := false
var pause_menu: InkMenu
var over_menu: InkMenu
var banter_queue: Array = []
var banter_t := 1.0
var said_low_power := false
var said_first_kill := false
var autosave_t := 3.0  # first autosave a few seconds into a new game
var slot_menu: InkMenu
var slot_mode := ""  # "save" or "load"


func _ready() -> void:
	randomize()

	entities = Node2D.new()
	entities.y_sort_enabled = true
	area = Area.new()
	add_child(area)
	area.build(MAP, entities)
	world = area.world_size()

	blank = Blank.new()
	blank.base_x = area.blank_x
	blank.height = world.y
	blank.width = world.x
	add_child(blank)
	Art.world_material().set_shader_parameter("blank_x", blank.base_x)

	add_child(entities)
	_build_walls()

	var start := area.party_start
	# Same body and animation rig for everyone; outfit layer + colors make the hero.
	var ash := _make_hero("Ash", start, "archer", {
		"skin": Color("efd2bd"), "cloth": Color("4b4f86"), "leather": Color("3b3346"),
		"boots": Color("2a2433"), "trim": Color("dcd8ee"),
	})
	ash.base_damage = 10
	var bran := _make_hero("Bran", start + Vector2(-20, 14), "warrior", {
		"skin": Color("c98e6a"), "metal": Color("8c7f72"), "accent": Color("b0442f"),
		"boots": Color("3a2c22"),
	})
	bran.max_hp = 60
	bran.hp = 60
	bran.move_speed = 62.0
	bran.base_damage = 14
	bran.power_rate = 0.75
	bran.reach = 21.0
	# The Barracks sends the party out tougher.
	for h in [ash, bran]:
		h.max_hp += Empire.party_hp_bonus()
		h.hp = h.max_hp
	_set_leader(ash)

	banter_queue = [
		["Bran", "Huh. A person. Or a very convincing smudge."],
		["Bran", "You crawled out of the Blank? Nobody does that. Nobody's paid me to see that, either."],
		["Bran", "Those white things eat. Hit them when your gauge is full. Or don't, and I'll bill your corpse."],
	]

	camera = Camera2D.new()
	camera.zoom = Vector2(2, 2)
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 7.0
	camera.limit_left = 0
	camera.limit_top = 0
	camera.limit_right = int(world.x)
	camera.limit_bottom = int(world.y)
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

	# Menus live on their own layer above the HUD and keep running while the tree is paused.
	var menu_layer := CanvasLayer.new()
	menu_layer.layer = 5
	menu_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(menu_layer)
	pause_menu = InkMenu.new()
	pause_menu.visible = false
	menu_layer.add_child(pause_menu)
	pause_menu.setup("Paused", _pause_items(), "")
	pause_menu.chosen.connect(_on_pause_choice)
	slot_menu = InkMenu.new()
	slot_menu.visible = false
	slot_menu.top = 0.2
	menu_layer.add_child(slot_menu)
	slot_menu.chosen.connect(_on_slot_choice)
	over_menu = InkMenu.new()
	over_menu.visible = false
	over_menu.dim = 0.55
	menu_layer.add_child(over_menu)
	over_menu.chosen.connect(_on_over_choice)

	var loaded := not Saves.pending.is_empty()
	if loaded:
		_apply_snapshot(Saves.pending)
		Saves.pending = {}
		camera.global_position = leader.global_position
		camera.reset_smoothing()
	for p in area.spawns:
		# A loaded game can put the party anywhere: don't drop Nibblers on top of them.
		if not loaded or p.distance_to(leader.global_position) > 120.0:
			_spawn_enemy(p)


func _build_walls() -> void:
	var walls := StaticBody2D.new()
	walls.collision_layer = 1
	add_child(walls)
	var t := 40.0
	for r in [
		Rect2(-t, -t, world.x + 2 * t, t),
		Rect2(-t, world.y, world.x + 2 * t, t),
		Rect2(-t, 0, t, world.y),
		Rect2(world.x, 0, t, world.y),
	]:
		var shape := RectangleShape2D.new()
		shape.size = r.size
		var col := CollisionShape2D.new()
		col.shape = shape
		col.position = r.position + r.size / 2.0
		walls.add_child(col)


func _make_hero(hero_name: String, pos: Vector2, outfit: String, colors: Dictionary) -> Hero:
	var h: Hero = HeroScript.new()
	h.hero_name = hero_name
	h.outfit = outfit
	h.colors = colors
	h.move_speed = 68.0
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
		get_tree().create_timer(1.2).timeout.connect(_show_game_over)
		return
	if a == leader:
		_set_leader(alive[0])
		hud.say("%s is down! You now control %s." % [(a as Hero).hero_name, leader.hero_name], 3.0)


func _show_game_over() -> void:
	var has_auto := Saves.exists("auto")
	over_menu.setup("The party was erased.", [
		{"id": "retry", "label": "Try again", "detail": "from the last autosave" if has_auto else "from the start of the area"},
		{"id": "load", "label": "Load game", "enabled": Saves.latest_slot() != ""},
		{"id": "title", "label": "Quit to title"},
	], "The Blank does not keep receipts.")
	over_menu.visible = true


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") and not game_over:
		set_paused(true)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("swap") and not game_over:
		_swap()


func set_paused(on: bool) -> void:
	get_tree().paused = on
	pause_menu.visible = on
	slot_menu.visible = false
	if on:
		pause_menu.setup("Paused", _pause_items(), "")
		touch.release_all()


func _pause_items() -> Array:
	return [
		{"id": "resume", "label": "Resume"},
		{"id": "save", "label": "Save game"},
		{"id": "load", "label": "Load game", "enabled": Saves.latest_slot() != "", "note": "(no saves yet)"},
		{"id": "restart", "label": "Restart area"},
		{"id": "title", "label": "Quit to title"},
	]


func _on_pause_choice(id: String) -> void:
	match id:
		"resume", "cancel":
			set_paused(false)
		"save", "load":
			_open_slots(id, pause_menu)
		"restart":
			get_tree().paused = false
			get_tree().reload_current_scene()
		"title":
			autosave()
			get_tree().paused = false
			get_tree().change_scene_to_file(TITLE_SCENE)


func _on_over_choice(id: String) -> void:
	match id:
		"retry":
			if not Saves.load_and_play("auto"):
				get_tree().reload_current_scene()
		"load":
			_open_slots("load", over_menu)
		"title":
			get_tree().change_scene_to_file(TITLE_SCENE)


var _slot_return: InkMenu


func _open_slots(mode: String, from: InkMenu) -> void:
	slot_mode = mode
	_slot_return = from
	from.visible = false
	slot_menu.setup("Save to which slot?" if mode == "save" else "Load which save?", Saves.slot_items(mode == "save"))
	slot_menu.visible = true


func _on_slot_choice(id: String) -> void:
	if id == "back" or id == "cancel":
		slot_menu.visible = false
		_slot_return.visible = true
		return
	if slot_mode == "load":
		Saves.load_and_play(id)
		return
	var ok := Saves.save(id, snapshot())
	slot_menu.visible = false
	_slot_return.visible = true
	pause_menu.setup("Paused", _pause_items(), ("Saved to %s." % Saves.slot_label(id)) if ok else "Saving failed. Your browser may be blocking storage.")
	pause_menu.selected = 0


# ---------------------------------------------------------------- saving

## Everything needed to put the player back where they were. Enemies are not saved:
## the area's Nibblers respawn on load, like any action RPG's screen refresh.
func snapshot() -> Dictionary:
	var hs := []
	for h in heroes:
		var hero: Hero = h
		hs.append({"name": hero.hero_name, "hp": hero.hp, "x": hero.global_position.x, "y": hero.global_position.y,
			"dead": hero.dead, "power": hero.power})
	return {
		"map": MAP,
		"area_name": area.area_name,
		"scene": "res://scenes/main.tscn",
		"kills": kills,
		"leader": heroes.find(leader),
		"heroes": hs,
		"banter": banter_queue,
		"said_first_kill": said_first_kill,
		"said_low_power": said_low_power,
	}


func _apply_snapshot(d: Dictionary) -> void:
	kills = int(d.get("kills", 0))
	banter_queue = d.get("banter", [])
	said_first_kill = bool(d.get("said_first_kill", false))
	said_low_power = bool(d.get("said_low_power", false))
	var hs: Array = d.get("heroes", [])
	for i in mini(hs.size(), heroes.size()):
		var hero: Hero = heroes[i]
		var hd: Dictionary = hs[i]
		hero.global_position = Vector2(float(hd["x"]), float(hd["y"]))
		hero.hp = clampi(int(hd["hp"]), 0, hero.max_hp)
		hero.power = float(hd.get("power", 1.0))
		if bool(hd.get("dead", false)) or hero.hp <= 0:
			hero.hp = 0
			hero.dead = true
			hero._on_death()
	var li := int(d.get("leader", 0))
	if li >= 0 and li < heroes.size() and not heroes[li].dead:
		_set_leader(heroes[li])
	autosave_t = AUTOSAVE_EVERY
	banter_t = 1.5
	hud.say("Loaded. The Blank kept your place.", 2.5)


## Autosaves only when it is safe to drop back in: nobody down and no Nibbler close.
func can_autosave() -> bool:
	if game_over or leader == null:
		return false
	for h in heroes:
		if (h as Hero).dead:
			return false
	for e in get_tree().get_nodes_in_group("enemies"):
		if (e as Node2D).global_position.distance_to(leader.global_position) < 110.0:
			return false
	return true


func autosave() -> void:
	if can_autosave():
		Saves.save("auto", snapshot())


func _notification(what: int) -> void:
	# Switching away from the tab (or closing it) usually blurs the page first.
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_CLOSE_REQUEST:
		autosave()


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
	if touch_active() and Input.is_action_just_pressed("pause") and not game_over and not get_tree().paused:
		set_paused(true)

	if camera and leader:
		camera.global_position = leader.global_position + Vector2(0, -10)
		shake_amount = maxf(shake_amount - 20.0 * delta, 0.0)
		camera.offset = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * shake_amount

	Empire.playtime += delta
	autosave_t -= delta
	if autosave_t <= 0.0:
		if can_autosave():
			autosave()
			autosave_t = AUTOSAVE_EVERY
		else:
			autosave_t = 5.0  # try again soon, once things calm down
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
		var y := randf_range(80, world.y - 80)
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
		for p in area.props:
			if p.kind == "sign" and (p as Node2D).global_position.distance_to(leader.global_position) < 34.0:
				txt = p.text
	hud.sign_text = txt
