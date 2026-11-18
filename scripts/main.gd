extends Node2D
## Prototype: the Frayed Meadow. Builds the area in code, spawns the party
## (picked on the Command Table, Ash leads), Nibblers that crawl out of the Blank, and the HUD.

const HeroScript := preload("res://scripts/hero.gd")
const EnemyScript := preload("res://scripts/enemy.gd")
const PropScript := preload("res://scripts/prop.gd")
const BlankScript := preload("res://scripts/blank.gd")
const HudScript := preload("res://scripts/hud.gd")
const TouchScript := preload("res://scripts/touch.gd")
const DialogueBox := preload("res://scripts/dialogue_box.gd")
const BanterScript := preload("res://scripts/banter.gd")
const ResultsView := preload("res://scripts/results_view.gd")

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
var boosts := {"damage": 0, "hp": 0, "revive": 1.0, "guard": 0.0, "power_rate": 1.0, "ink_regen": 1.0, "lines": []}  # from research
var over_menu: InkMenu
var banter  # banter.gd: walking banter at the top of the screen
var dialogue_box  # dialogue_box.gd: conversations (the game pauses while one plays)
var autosave_t := 3.0  # first autosave a few seconds into a new game
var slot_menu: InkMenu
var slot_mode := ""  # "save" or "load"
var map_path := "res://maps/frayed_meadow.txt"
var mission := {}  # the mission being played (scripts/missions.gd)
var objective: Objective
var found := {}  # what the party picked up on the way: resource -> amount
var found_flash := 0.0  # seconds the HUD's "Found" line stays lit after a pickup
var mission_time := 0.0
var ending := false  # the results screen is up (or about to be)
var results_view  # results_view.gd
var quick_menu: QuickMenu  # quick_menu.gd: items, abilities, party, equip with time slowed (issue #6)
var quick_open := false  # heroes read this: the menu has the controls while it is up


func _ready() -> void:
	randomize()
	# Which mission: a loaded save brings its own; otherwise the one launched from the map.
	mission = Saves.pending.get("mission", {}) if not Saves.pending.is_empty() else {}
	if mission.is_empty():
		mission = Missions.current()
	Empire.active_mission = mission
	map_path = mission.get("map", map_path)
	objective = Objective.new()
	objective.setup(mission.get("objective", {}), self)

	entities = Node2D.new()
	entities.y_sort_enabled = true
	area = Area.new()
	add_child(area)
	area.build(map_path, entities)
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
	# Whoever was picked on the Command Table (party_picker.gd); Ash always leads.
	# Same body and animation rig for everyone; outfit layer + colors make the hero.
	var offsets := [Vector2.ZERO, Vector2(-20, 14), Vector2(20, 14)]
	var ids := PartyPicker.mission_party()
	for i in ids.size():
		var look: Dictionary = Empire.recruit(ids[i]).get("look", {})
		var h := _make_hero(PartyPicker.short_of(ids[i]), start + offsets[i % offsets.size()],
			look.get("outfit", "archer"), PartyPicker.look_colors(look))
		PartyPicker.apply(h, ids[i])
		h.ai_style = str(Empire.ai_presets.get(ids[i], h.ai_style))  # picked in the quick menu's Party tab
	# The Barracks sends the party out tougher; research sharpens and armours them.
	boosts = Empire.mission_boosts()
	Empire.mission_kills_bonded = 0
	for h in heroes:
		h.max_hp += Empire.party_hp_bonus() + int(boosts["hp"])
		h.hp = h.max_hp
		h.base_damage += int(boosts["damage"])
		h.power_rate *= float(boosts["power_rate"])
		h.ink_regen *= float(boosts.get("ink_regen", 1.0))
	_set_leader(heroes[0])

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
	touch.party = self
	layer.add_child(touch)
	banter = BanterScript.new()
	banter.gap = 1.0
	layer.add_child(banter)

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
	dialogue_box = DialogueBox.new()
	dialogue_box.visible = false
	menu_layer.add_child(dialogue_box)
	dialogue_box.finished.connect(_on_dialogue_finished)
	results_view = ResultsView.new()
	results_view.visible = false
	menu_layer.add_child(results_view)
	results_view.confirmed.connect(_on_results_confirmed)
	quick_menu = QuickMenu.new()
	quick_menu.party = self
	menu_layer.add_child(quick_menu)
	quick_menu.closed.connect(func(): quick_open = false)

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
	if not loaded:  # the first time out, Bran finds Ash; after that he just grumbles
		if not Dialogue.is_seen("talk:meadow_intro") and "bran" in present():
			play_talk("meadow_intro")
		else:
			banter.event("mission_start", present())


## Who can speak right now: the party members still standing.
func present() -> Array:
	return heroes.filter(func(h): return not h.dead).map(func(h): return (h as Hero).hero_id)


## Play a conversation in the dialogue box. The fight waits until it is over.
func play_talk(talk_id: String) -> void:
	if dialogue_box.play(talk_id):
		quick_menu.close()
		get_tree().paused = true
		touch.release_all()


func _on_dialogue_finished(_id: String) -> void:
	get_tree().paused = false


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


## The quick menu's Party tab: take control of a standing hero.
func take_control(h: Hero) -> void:
	if h != null and not h.dead and h in heroes:
		_set_leader(h)


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
	Empire.bond_fought(kills, heroes.map(func(h): return (h as Hero).hero_id))  # fighting beside Ash builds bonds
	banter.event("first_kill", present())
	if not ending:
		objective.on_kill()
		var got := Missions.roll_loot(mission)
		for k in got:
			found[k] = int(found.get(k, 0)) + int(got[k])
		if not got.is_empty():
			found_flash = 1.5
		var item := Satchel.roll_drop()  # field items go straight into the satchel
		if item != "":
			Satchel.add(item)
			hud.say("Found: %s (quick menu)." % Satchel.item(item).get("name", item), 2.0)
	if kills == 10:
		banter.event("tenth_kill", present())


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
	if ending:
		return
	var has_auto := Saves.exists("auto")
	over_menu.setup("The party was erased.", [
		{"id": "retry", "label": "Try again", "detail": "from the last autosave" if has_auto else "from the start of the area"},
		{"id": "retreat", "label": "Limp back to Hollowmark", "detail": "end the mission and drop what you found"},
		{"id": "load", "label": "Load game", "enabled": Saves.latest_slot() != ""},
		{"id": "title", "label": "Quit to title"},
	], "The Blank does not keep receipts.")
	over_menu.visible = true


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") and not game_over and not ending:
		set_paused(true)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("swap") and not game_over:
		_swap()
	if event.is_action_pressed("quick_menu"):
		open_quick_menu()


## One button opens the quick menu mid-fight; time slows to 10% instead of stopping.
func open_quick_menu() -> void:
	if game_over or ending or get_tree().paused or quick_open:
		return
	touch.release_all()
	quick_open = true
	quick_menu.open()


func set_paused(on: bool) -> void:
	if on:
		quick_menu.close()
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
		{"id": "retreat", "label": "Retreat to Hollowmark", "detail": "end the mission, keep what you found"},
		{"id": "restart", "label": "Restart mission"},
		{"id": "title", "label": "Quit to title"},
	]


func _on_pause_choice(id: String) -> void:
	match id:
		"resume", "cancel":
			set_paused(false)
		"save", "load":
			_open_slots(id, pause_menu)
		"retreat":
			pause_menu.visible = false
			_end_mission("retreat")
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
		"retreat":
			over_menu.visible = false
			_end_mission("wiped")
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
			"dead": hero.dead, "power": hero.power, "ink": hero.ink})
	return {
		"map": map_path,
		"area_name": area.area_name,
		"scene": "res://scenes/main.tscn",
		"mission": mission,
		"objective": objective.to_save(),
		"found": found,
		"mission_time": mission_time,
		"kills": kills,
		"leader": heroes.find(leader),
		"heroes": hs,
		"banter": banter.to_save(),
	}


func _apply_snapshot(d: Dictionary) -> void:
	kills = int(d.get("kills", 0))
	objective.from_save(d.get("objective", {"progress": kills}))
	mission_time = float(d.get("mission_time", 0.0))
	var f: Dictionary = d.get("found", {})
	for k in f:
		found[k] = int(f[k])
	banter.from_save(d.get("banter", []))
	var hs: Array = d.get("heroes", [])
	for i in mini(hs.size(), heroes.size()):
		var hero: Hero = heroes[i]
		var hd: Dictionary = hs[i]
		hero.global_position = Vector2(float(hd["x"]), float(hd["y"]))
		hero.hp = clampi(int(hd["hp"]), 0, hero.max_hp)
		hero.power = float(hd.get("power", 1.0))
		hero.ink = clampf(float(hd.get("ink", hero.max_ink)), 0.0, hero.max_ink)
		if bool(hd.get("dead", false)) or hero.hp <= 0:
			hero.hp = 0
			hero.dead = true
			hero._on_death()
	var li := int(d.get("leader", 0))
	if li >= 0 and li < heroes.size() and not heroes[li].dead:
		_set_leader(heroes[li])
	autosave_t = AUTOSAVE_EVERY
	hud.say("Loaded. The Blank kept your place.", 2.5)


## Autosaves only when it is safe to drop back in: nobody down and no Nibbler close.
func can_autosave() -> bool:
	if game_over or ending or leader == null:
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
	if touch_active() and Input.is_action_just_pressed("quick_menu"):
		open_quick_menu()

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
	_update_mission(delta)
	_update_blank_contact(delta)
	_update_revive(delta)
	_update_respawn(delta)
	_update_banter(delta)
	_update_signs()


# ---------------------------------------------------------------- mission flow

func _update_mission(delta: float) -> void:
	found_flash = maxf(found_flash - delta, 0.0)
	if ending or game_over:
		return
	mission_time += delta
	objective.update(delta)
	if objective.done():
		ending = true
		hud.say("Objective complete!", 2.0)
		banter.event("mission_won", present())
		get_tree().create_timer(1.6).timeout.connect(_show_results.bind("success"))
	elif objective.failed():
		ending = true
		get_tree().create_timer(1.2).timeout.connect(_show_results.bind("wiped"))


## Ends the mission now: retreat from the pause menu, or the wiped party limping home.
func _end_mission(outcome: String) -> void:
	ending = true
	_show_results(outcome)


func _show_results(outcome: String) -> void:
	if not is_inside_tree():
		return
	quick_menu.close()
	get_tree().paused = true
	touch.release_all()
	var r := Missions.settle(mission, outcome, found, {"kills": kills, "time": mission_time, "objective": objective.text(), "fail": objective.fail_text()})
	results_view.open(r)


func _on_results_confirmed() -> void:
	Missions.go_home(results_view.result)


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
			hero.revive_progress += delta * float(boosts["revive"])
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


func _update_banter(_delta: float) -> void:
	if game_over:
		return
	if leader and leader.power < 0.5 and leader.swing_t > 0.0 and leader.swing_power < 0.5:
		banter.event("low_power", present())
	if leader:
		banter.check_zones(map_path.get_file().get_basename(), leader.global_position, present())


func _update_signs() -> void:
	var txt := ""
	if leader:
		for p in area.props:
			if p.kind == "sign" and (p as Node2D).global_position.distance_to(leader.global_position) < 34.0:
				txt = p.text
	hud.sign_text = txt
