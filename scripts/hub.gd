extends Node2D
## Hollowmark, the walkable hub town. Ash walks around, the people on your roster stand at
## their posts (and move when you reassign them), and the Command Table opens the territory map.
##
## The Command clock keeps running here: time in town is time the Blank gets to work.
## No fighting in town: the attack button talks and uses things instead.

const HeroScript := preload("res://scripts/hero.gd")
const HudScript := preload("res://scripts/hub_hud.gd")
const TouchScript := preload("res://scripts/touch.gd")
const RosterView := preload("res://scripts/roster_view.gd")

const MAP := "res://maps/hollowmark.txt"
const TITLE_SCENE := "res://scenes/title.tscn"
const AUTOSAVE_EVERY := 60.0
const TALK_RANGE := 26.0
const TABLE_SIZE := Vector2(46, 26)  # the Command Table, drawn in code (placeholder art)

var heroes: Array = []  # just Ash: in town you walk alone
var leader: Hero
var npcs := {}  # recruit id -> Hero (standing, not controlled)
var entities: Node2D
var camera: Camera2D
var area: Area
var world := Vector2.ZERO
var hud  # hub_hud.gd
var touch  # touch.gd
var roster_view
var menu: InkMenu
var slot_menu: InkMenu
var slot_mode := ""
var menu_closed_frame := -1
var table_pos := Vector2.ZERO  # bottom-centre of the Command Table
var table_body: StaticBody2D
var target := {}  # what the attack button would use: {"kind": "npc"/"table", "id", "pos", "label"}
var talk_index := {}  # recruit id -> next line to say
var autosave_t := AUTOSAVE_EVERY
var leaving := false


func _ready() -> void:
	get_tree().paused = false
	entities = Node2D.new()
	entities.y_sort_enabled = true
	area = Area.new()
	add_child(area)
	area.build(MAP, entities)
	world = area.world_size()
	Art.world_material().set_shader_parameter("blank_x", 1e9)  # no Blank inside the walls (yet)
	add_child(entities)
	_build_walls()
	_build_table()

	var look: Dictionary = Empire.recruit("ash").get("look", {})
	leader = _make_person("ash", area.party_start, look)
	leader.controlled = true
	leader.peaceful = true
	leader.party = self
	leader.collision_layer = 2
	heroes = [leader]
	_place_people()
	call_deferred("_add_pixellab_preview")  # TEMPORARY art test (V key); remove with scripts/pixellab_preview.gd

	var tags := Node2D.new()
	tags.z_index = 20
	add_child(tags)
	tags.draw.connect(_draw_tags.bind(tags))
	tags.set_process(true)
	set_meta("tags", tags)

	camera = Camera2D.new()
	camera.zoom = Vector2(2, 2)
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 7.0
	camera.limit_left = 0
	camera.limit_top = 0
	camera.limit_right = int(world.x)
	camera.limit_bottom = int(world.y)
	add_child(camera)

	var layer := CanvasLayer.new()
	add_child(layer)
	hud = HudScript.new()
	hud.hub = self
	layer.add_child(hud)
	touch = TouchScript.new()
	layer.add_child(touch)

	var roster_layer := CanvasLayer.new()
	roster_layer.layer = 4
	add_child(roster_layer)
	roster_view = RosterView.new()
	roster_view.visible = false
	roster_layer.add_child(roster_view)
	roster_view.closed.connect(_place_people)

	var menu_layer := CanvasLayer.new()
	menu_layer.layer = 5
	menu_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(menu_layer)
	menu = InkMenu.new()
	menu.visible = false
	menu_layer.add_child(menu)
	menu.chosen.connect(_on_menu)
	slot_menu = InkMenu.new()
	slot_menu.visible = false
	slot_menu.top = 0.2
	menu_layer.add_child(slot_menu)
	slot_menu.chosen.connect(_on_slot)

	Empire.day_passed.connect(_on_day_passed)
	Empire.notice.connect(_on_notice)
	Empire.hollowmark_lost.connect(_on_hollowmark_lost)

	if not Saves.pending.is_empty():
		var d: Dictionary = Saves.pending
		Saves.pending = {}
		if d.has("x"):
			leader.global_position = Vector2(float(d["x"]), float(d["y"]))
			leader.facing = Vector2.DOWN
		hud.say("Loaded. Hollowmark is still here. Mostly.", 2.5)
	camera.global_position = leader.global_position
	camera.reset_smoothing()
	if Empire.territory().find("hollowmark").get("owner", "") == "erased":
		_on_hollowmark_lost()


func _build_walls() -> void:
	var walls := StaticBody2D.new()
	walls.collision_layer = 1
	add_child(walls)
	var t := 40.0
	for r in [Rect2(-t, -t, world.x + 2 * t, t), Rect2(-t, world.y, world.x + 2 * t, t),
			Rect2(-t, 0, t, world.y), Rect2(world.x, 0, t, world.y)]:
		var shape := RectangleShape2D.new()
		shape.size = r.size
		var col := CollisionShape2D.new()
		col.shape = shape
		col.position = r.position + r.size / 2.0
		walls.add_child(col)


func _build_table() -> void:
	var spots: Array = area.markers.get("table", [])
	var tl: Vector2 = spots[0] if not spots.is_empty() else world / 2.0
	# The marker is the table's top-left tile; the table covers three tiles by two.
	table_pos = tl + Vector2(16, 20)
	table_body = StaticBody2D.new()
	table_body.collision_layer = 1
	table_body.position = table_pos
	var shape := RectangleShape2D.new()
	shape.size = Vector2(TABLE_SIZE.x, 14)
	var col := CollisionShape2D.new()
	col.shape = shape
	col.position = Vector2(0, -7)
	table_body.add_child(col)
	table_body.draw.connect(_draw_table)
	entities.add_child(table_body)


func _make_person(id: String, pos: Vector2, look: Dictionary) -> Hero:
	var h: Hero = HeroScript.new()
	h.hero_name = Empire.recruit(id).get("name", id)
	h.outfit = look.get("outfit", "archer")
	var cols := {}
	for k in look.get("colors", {}):
		cols[k] = Color(look["colors"][k])
	if not cols.is_empty():
		h.colors = cols
	h.move_speed = 70.0
	h.position = pos
	h.set_meta("id", id)
	entities.add_child(h)
	return h


## Where a recruit stands right now: the hall if they govern Hollowmark, the gate if they are
## in your party, the tavern while injured, otherwise their usual post.
func post_of(id: String) -> String:
	var st: Dictionary = Empire.recruits.get(id, {})
	if int(st.get("injured", 0)) > 0:
		return "tavern"
	if st.get("role", "") == "governor":
		return "hall" if st.get("target", "") == "hollowmark" else ""  # elsewhere: not in town
	if st.get("role", "") == "party":
		return "gate"
	return Empire.recruit(id).get("post", "tavern")


## Puts every recruit at their post. Called on start and whenever the roster closes.
func _place_people() -> void:
	var used := {}
	var seen := {}
	for id in Empire.roster_ids():
		if id == "ash":
			continue
		var post := post_of(id)
		var spots: Array = area.markers.get(post, [])
		if post == "" or spots.is_empty():
			if npcs.has(id):
				npcs[id].queue_free()
				npcs.erase(id)
			continue
		seen[id] = true
		var n: int = used.get(post, 0)
		used[post] = n + 1
		# Several people at one post stand side by side.
		var pos: Vector2 = spots[0] + Vector2([0, 18, -18, 36, -36][n % 5], 0)
		var npc: Hero = npcs.get(id)
		if npc == null:
			npc = _make_person(id, pos, Empire.recruit(id).get("look", {}))
			npc.collision_layer = 1  # Ash bumps into people instead of walking through them
			npc.collision_mask = 0
			npcs[id] = npc
		npc.global_position = pos
	for id in npcs.keys():
		if not seen.has(id):
			npcs[id].queue_free()
			npcs.erase(id)


func shake(_amount: float) -> void:
	pass


func touch_active() -> bool:
	return touch != null and touch.visible


# ---------------------------------------------------------------- talking and using things

func _find_target() -> Dictionary:
	var p := leader.global_position
	var best := {}
	var best_d := TALK_RANGE
	for id in npcs:
		var d: float = (npcs[id] as Node2D).global_position.distance_to(p)
		if d < best_d:
			best_d = d
			best = {"kind": "npc", "id": id, "pos": (npcs[id] as Node2D).global_position, "label": "Talk to " + Empire.recruit(id)["name"]}
	# The table is wide: measure to its nearest edge, not its middle.
	var tr := Rect2(table_pos - Vector2(TABLE_SIZE.x / 2.0, TABLE_SIZE.y), TABLE_SIZE)
	var nearest := Vector2(clampf(p.x, tr.position.x, tr.end.x), clampf(p.y, tr.position.y, tr.end.y))
	if nearest.distance_to(p) < minf(best_d, 18.0):
		best = {"kind": "table", "id": "table", "pos": table_pos, "label": "Use the Command Table"}
	return best


func _use(t: Dictionary) -> void:
	if t.is_empty():
		return
	if t["kind"] == "table":
		_leave(Saves.COMMAND_SCENE)
		return
	var id: String = t["id"]
	var r := Empire.recruit(id)
	var lines: Array = r.get("lines", [])
	var npc: Hero = npcs[id]
	npc.facing = (leader.global_position - npc.global_position).normalized()
	var short_name: String = r["name"].get_slice(" ", 0) if not r["name"].begins_with("Old") and not r["name"].begins_with("Mother") and not r["name"].begins_with("Sister") else r["name"]
	var line := "..."
	if int(Empire.recruits[id]["injured"]) > 0:
		line = "Still stitching myself back together. Ask me again in %d days." % int(Empire.recruits[id]["injured"])
	elif Empire.role_of(id) == "governor":
		line = "I keep the hall and the ledgers. Hollowmark holds while I'm here. Mostly."
	elif not lines.is_empty():
		var i: int = talk_index.get(id, 0)
		line = lines[i % lines.size()]
		talk_index[id] = i + 1
	hud.say("%s: %s" % [short_name, line], 4.5)


# ---------------------------------------------------------------- clock, notices, leaving

func _on_day_passed(d: int) -> void:
	hud.toast("Day %d begins." % d, "Supplies ran out. People are going hungry." if Empire.hungry else "")


func _on_notice(text: String, warning: bool) -> void:
	hud.notice(text, warning)


func _on_hollowmark_lost() -> void:
	# The Command Table shows the ending screen for a lost town.
	call_deferred("_go_command_unsaved")


func _go_command_unsaved() -> void:
	if leaving:
		return
	leaving = true
	get_tree().paused = false
	get_tree().change_scene_to_file(Saves.COMMAND_SCENE)


func snapshot() -> Dictionary:
	return {"scene": Saves.HUB_SCENE, "area_name": "Hollowmark",
		"x": leader.global_position.x, "y": leader.global_position.y}


func autosave() -> void:
	if not leaving and Empire.territory().find("hollowmark").get("owner", "") != "erased":
		Saves.save("auto", snapshot())


func _leave(scene: String) -> void:
	if leaving:
		return
	autosave()
	leaving = true
	get_tree().paused = false
	get_tree().change_scene_to_file(scene)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_CLOSE_REQUEST:
		if is_inside_tree() and leader:
			autosave()


# ---------------------------------------------------------------- menu

func open_menu(note := "") -> void:
	menu.setup("Hollowmark", [
		{"id": "resume", "label": "Resume"},
		{"id": "table", "label": "Command Table", "detail": "the territory map"},
		{"id": "roster", "label": "Roster"},
		{"id": "save", "label": "Save game"},
		{"id": "load", "label": "Load game", "enabled": Saves.latest_slot() != "", "note": "(no saves yet)"},
		{"id": "title", "label": "Quit to title"},
	], note)
	menu.visible = true
	get_tree().paused = true
	touch.release_all()


func _close_menu() -> void:
	menu.visible = false
	slot_menu.visible = false
	get_tree().paused = false
	menu_closed_frame = Engine.get_process_frames()


func _on_menu(id: String) -> void:
	match id:
		"resume", "cancel":
			_close_menu()
		"table":
			_leave(Saves.COMMAND_SCENE)
		"roster":
			_close_menu()
			roster_view.open()
		"save", "load":
			slot_mode = id
			menu.visible = false
			slot_menu.setup("Save to which slot?" if id == "save" else "Load which save?", Saves.slot_items(id == "save"))
			slot_menu.visible = true
		"title":
			_leave(TITLE_SCENE)


func _on_slot(id: String) -> void:
	if id == "back" or id == "cancel":
		slot_menu.visible = false
		menu.visible = true
		return
	if slot_mode == "load":
		Saves.load_and_play(id)
		return
	var ok := Saves.save(id, snapshot())
	slot_menu.visible = false
	open_menu(("Saved to %s." % Saves.slot_label(id)) if ok else "Saving failed. Your browser may be blocking storage.")


# ---------------------------------------------------------------- frame

func _process(delta: float) -> void:
	Empire.tick(delta)
	Empire.playtime += delta
	autosave_t -= delta
	if autosave_t <= 0.0:
		autosave_t = AUTOSAVE_EVERY
		autosave()
	camera.global_position = leader.global_position + Vector2(0, -10)
	# People turn to look at Ash when Ash comes close.
	for id in npcs:
		var npc: Hero = npcs[id]
		var to := leader.global_position - npc.global_position
		npc.facing = to.normalized() if to.length() < 70.0 else Vector2.DOWN
	target = _find_target()
	(get_meta("tags") as Node2D).queue_redraw()
	table_body.queue_redraw()

	var frame := Engine.get_process_frames()
	if roster_view.visible or frame == roster_view.closed_frame or frame == menu_closed_frame:
		leader.controlled = not roster_view.visible
		return
	leader.controlled = true
	if Input.is_action_just_pressed("pause"):
		open_menu()
		return
	if Input.is_action_just_pressed("roster"):
		roster_view.open()
		return
	for i in Empire.SPEEDS.size():
		if Input.is_action_just_pressed("clock_speed_%d" % i):
			Empire.set_speed(i)
	if Input.is_action_just_pressed("clock_slower"):
		Empire.set_speed(Empire.speed - 1)
	elif Input.is_action_just_pressed("clock_faster"):
		Empire.set_speed(Empire.speed + 1)
	if Input.is_action_just_pressed("attack") or Input.is_action_just_pressed("ui_accept"):
		_use(target)
	hud.sign_text = ""
	for p in area.props:
		if p.kind == "sign" and (p as Node2D).global_position.distance_to(leader.global_position) < 34.0:
			hud.sign_text = p.text


# ---------------------------------------------------------------- drawing

## The Command Table: a heavy plank table with the map of the Inklands pinned to it.
## Placeholder art, drawn in code until the PixelLab pass.
func _draw_table() -> void:
	var c := table_body
	var w := TABLE_SIZE.x
	var h := TABLE_SIZE.y
	var top := Rect2(-w / 2.0, -h, w, h - 8.0)
	c.draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.4))
	c.draw_circle(Vector2(0, 2), w * 0.55, Color(0, 0, 0, 0.25))
	c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	for lx in [-w / 2.0 + 3.0, w / 2.0 - 6.0]:
		c.draw_rect(Rect2(lx, -10, 3, 10), Color("4a3222"))
	c.draw_rect(Rect2(top.position.x, top.end.y, w, 3), Color("5a3c26"))
	c.draw_rect(top, Color("7a5434"))
	for i in range(1, 4):
		c.draw_line(Vector2(top.position.x, top.position.y + i * top.size.y / 4.0), Vector2(top.end.x, top.position.y + i * top.size.y / 4.0), Color("6a4628"), 1.0)
	# The map, with the Blank eating its right edge, and a candle.
	var m := Rect2(top.position + Vector2(6, 2), Vector2(w - 16, top.size.y - 4))
	c.draw_rect(m, Color("e6d8b4"))
	c.draw_rect(Rect2(m.position + Vector2(4, 3), Vector2(10, 6)), Color("8fa86a"))
	c.draw_rect(Rect2(m.position + Vector2(13, 6), Vector2(8, 5)), Color("c99a5a"))
	c.draw_rect(Rect2(m.position + Vector2(20, 2), Vector2(6, 6)), Color("7f8fc0"))
	c.draw_rect(Rect2(m.end.x - 5, m.position.y, 5, m.size.y), Color("fbfaf5"))
	c.draw_rect(m, Color("8a7350"), false, 1.0)
	c.draw_rect(Rect2(top.end.x - 7, top.position.y - 2, 3, 5), Color("efe6d0"))
	var flick := 0.6 + 0.4 * sin(Time.get_ticks_msec() * 0.013)
	c.draw_circle(Vector2(top.end.x - 5.5, top.position.y - 4), 1.6, Color(1.0, 0.8, 0.35, flick))
	if target.get("kind", "") == "table":
		c.draw_rect(top.grow(2), Color("ffd166"), false, 1.0)


func _draw_tags(canvas: Node2D) -> void:
	var font := ThemeDB.fallback_font
	for id in npcs:
		var npc: Hero = npcs[id]
		var d := npc.global_position.distance_to(leader.global_position)
		if d > 80.0:
			continue
		var a := clampf((80.0 - d) / 25.0, 0.0, 1.0)
		var r := Empire.recruit(id)
		var name_s: String = r["name"]
		var w := font.get_string_size(name_s, HORIZONTAL_ALIGNMENT_LEFT, -1, 6).x
		var p := npc.global_position + Vector2(-w / 2.0, -26)
		var col := Color("ffd166", a) if target.get("id", "") == id else Color(0.95, 0.93, 0.88, a)
		canvas.draw_string_outline(font, p, name_s, HORIZONTAL_ALIGNMENT_LEFT, -1, 6, 2, Color(0, 0, 0, 0.8 * a))
		canvas.draw_string(font, p, name_s, HORIZONTAL_ALIGNMENT_LEFT, -1, 6, col)
		if target.get("id", "") == id:
			var y := -33.0 + sin(Time.get_ticks_msec() * 0.006)
			var tip := npc.global_position + Vector2(0, y)
			canvas.draw_colored_polygon(PackedVector2Array([tip + Vector2(-2.5, -3), tip + Vector2(2.5, -3), tip]), Color("ffd166"))


## TEMPORARY art test: lets V swap Ash's paper doll for the PixelLab test sprite.
func _add_pixellab_preview() -> void:
	var preview = load("res://scripts/pixellab_preview.gd").new()
	preview.hero = leader
	preview.hud = hud
	add_child(preview)
