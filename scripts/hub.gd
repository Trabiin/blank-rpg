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
const BuildingsView := preload("res://scripts/buildings_view.gd")
const ExpeditionView := preload("res://scripts/expedition_view.gd")
const ResearchView := preload("res://scripts/research_view.gd")
const DiplomacyView := preload("res://scripts/diplomacy_view.gd")
const BondsView := preload("res://scripts/bonds_view.gd")
const NewcomersView := preload("res://scripts/newcomers_view.gd")
const SceneView := preload("res://scripts/scene_view.gd")
const SiteScript := preload("res://scripts/building_site.gd")

const MAP := "res://maps/hollowmark.txt"
const TITLE_SCENE := "res://scenes/title.tscn"
const AUTOSAVE_EVERY := 60.0
const TALK_RANGE := 26.0
const TABLE_SIZE := Vector2(46, 26)  # the Command Table, drawn in code (placeholder art)
## What staff say about their building when you talk to them, before what it is doing right now.
const STAFF_LINES := {
	"command_table": "Every order crosses this table. I make sure fewer of them cost bread.",
	"barracks": "Up, down, up, down. They hate me. They'll live longer.",
	"infirmary": "Hold still. This will hurt, which is how you know it's working.",
	"inkworks": "Soot, gall, a little blood. Don't ask whose.",
	"scriptorium": "The margins are where the truth hides. I'm writing it down before the Blank does.",
	"guildhall": "Everybody wants something done and nobody wants to do it. That's my cut.",
}

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
var buildings_view
var expedition_view
var research_view
var diplomacy_view
var bonds_view
var newcomers_view
var scene_view  # bond scenes started by talking to someone in town
var sites := {}  # building id -> building_site.gd on its plot
var lamp: Node2D  # Hollowmark's own Wardlamp, drawn once it is lit
var menu: InkMenu
var slot_menu: InkMenu
var slot_mode := ""
var menu_closed_frame := -1
var table_pos := Vector2.ZERO  # bottom-centre of the Command Table
var table_body: StaticBody2D
var target := {}  # what the attack button would use: {"kind": "npc"/"table", "id", "pos", "label"}
var talk_index := {}  # recruit id -> next line to say
var pitched := {}  # visitor id -> true once they have made their pitch (talk again to take them on)
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
	_build_sites()

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
	buildings_view = BuildingsView.new()
	buildings_view.visible = false
	roster_layer.add_child(buildings_view)
	buildings_view.closed.connect(_place_people)
	expedition_view = ExpeditionView.new()
	expedition_view.visible = false
	roster_layer.add_child(expedition_view)
	expedition_view.closed.connect(_place_people)
	research_view = ResearchView.new()
	research_view.visible = false
	roster_layer.add_child(research_view)
	diplomacy_view = DiplomacyView.new()
	diplomacy_view.visible = false
	roster_layer.add_child(diplomacy_view)
	diplomacy_view.closed.connect(_place_people)  # envoys leave town
	bonds_view = BondsView.new()
	bonds_view.visible = false
	roster_layer.add_child(bonds_view)
	newcomers_view = NewcomersView.new()
	newcomers_view.visible = false
	roster_layer.add_child(newcomers_view)
	newcomers_view.closed.connect(_place_people)  # someone taken on leaves the gate
	Empire.lead_arrived.connect(func(_id): _place_people())
	scene_view = SceneView.new()
	scene_view.visible = false
	roster_layer.add_child(scene_view)
	Empire.expedition_returned.connect(func(_r): _place_people())

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


## Building plots from the map's site_<id> marks, and the spot for Hollowmark's Wardlamp.
func _build_sites() -> void:
	for id in Empire.building_ids():
		var mark: String = Empire.building(id).get("site", "")
		var spots: Array = area.markers.get(mark, [])
		if mark == "" or spots.is_empty():
			continue
		var site = SiteScript.new()
		site.id = id
		# The mark is the plot's top-left tile centre; the site's origin is the plot's bottom-centre.
		site.position = (spots[0] as Vector2) - Vector2(8, 8) + Vector2(40, 77)
		entities.add_child(site)
		sites[id] = site
	var lamp_spots: Array = area.markers.get("lamp", [])
	if not lamp_spots.is_empty():
		lamp = Node2D.new()
		lamp.position = lamp_spots[0]
		lamp.draw.connect(_draw_lamp)
		entities.add_child(lamp)


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
	if st.get("role", "") in ["expedition", "envoy"]:
		return ""  # out of town: with a squad, or living with a faction
	if st.get("role", "") == "staff":
		if st.get("target", "") == "command_table":
			return "table_side"
		return "bld:" + st.get("target", "") if sites.has(st.get("target", "")) else "tavern"
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
		if post.begins_with("bld:"):
			var n0: int = used.get(post, 0)
			spots = [sites[post.substr(4)].post_pos(n0) - Vector2([0, 18, -18, 36, -36][n0 % 5], 0)]
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
	# Newcomers waiting to be taken on stand just inside the south gate.
	var vspots: Array = area.markers.get("visitors", [])
	var vn := 0
	for id in Empire.visitors:
		if Empire.recruits.has(id) or vspots.is_empty():
			continue
		seen[id] = true
		var vpos: Vector2 = vspots[0] + Vector2([0, 18, -18, 36, -36, 54, 72][vn % 7], 0)
		vn += 1
		var vnpc: Hero = npcs.get(id)
		if vnpc == null:
			vnpc = _make_person(id, vpos, Empire.recruit(id).get("look", {}))
			vnpc.collision_layer = 1
			vnpc.collision_mask = 0
			npcs[id] = vnpc
		vnpc.global_position = vpos
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
			best = {"kind": "npc", "id": id, "pos": (npcs[id] as Node2D).global_position, "label": "Talk to " + Empire.recruit(id)["name"]
				+ ("  (wants a word)" if Empire.bond_next_scene(id) > 0 else "") + ("  (looking for work)" if Empire.is_visitor(id) else "")}
	# The table is wide: measure to its nearest edge, not its middle.
	var tr := Rect2(table_pos - Vector2(TABLE_SIZE.x / 2.0, TABLE_SIZE.y), TABLE_SIZE)
	var nearest := Vector2(clampf(p.x, tr.position.x, tr.end.x), clampf(p.y, tr.position.y, tr.end.y))
	if nearest.distance_to(p) < minf(best_d, 18.0):
		best = {"kind": "table", "id": "table", "pos": table_pos, "label": "Use the Command Table"}
		best_d = nearest.distance_to(p)
	for id in sites:
		var site = sites[id]
		site.highlight = false
		var sr: Rect2 = site.plot_rect()
		var np := Vector2(clampf(p.x, sr.position.x, sr.end.x), clampf(p.y, sr.position.y, sr.end.y))
		var d := np.distance_to(p)
		if d < minf(best_d, 14.0) and best.is_empty():
			var b := Empire.building(id)
			var lv := Empire.level_of(id)
			var verb := "Check on" if lv > 0 or Empire.construction.get("id", "") == id else "Plan"
			best = {"kind": "site", "id": id, "pos": site.global_position, "label": "%s the %s" % [verb, b["name"]]}
			best_d = d
	if best.get("kind", "") == "site":
		sites[best["id"]].highlight = true
	return best


func _use(t: Dictionary) -> void:
	if t.is_empty():
		return
	if t["kind"] == "table":
		_leave(Saves.COMMAND_SCENE)
		return
	if t["kind"] == "site":
		if t["id"] == "guildhall" and Empire.level_of("guildhall") > 0:
			expedition_view.open()  # the Guildhall's job board
		elif t["id"] == "scriptorium" and Empire.level_of("scriptorium") > 0:
			research_view.open()  # the Scriptorium's desks
		else:
			buildings_view.open(t["id"])
		touch.release_all()
		return
	var id: String = t["id"]
	if Empire.is_visitor(id):
		_talk_visitor(id)
		return
	var ready_rank := Empire.bond_next_scene(id)
	if ready_rank > 0:  # they have something to say: play their bond scene
		(npcs[id] as Hero).facing = (leader.global_position - (npcs[id] as Node2D).global_position).normalized()
		Empire.bond_talk(id)
		scene_view.play(id, ready_rank)
		touch.release_all()
		return
	var r := Empire.recruit(id)
	var lines: Array = r.get("lines", [])
	var npc: Hero = npcs[id]
	npc.facing = (leader.global_position - npc.global_position).normalized()
	var short_name := Empire.short_name(id)
	var line := "..."
	if int(Empire.recruits[id]["injured"]) > 0:
		line = "Still stitching myself back together. Ask me again in %d days." % int(Empire.recruits[id]["injured"])
	elif Empire.role_of(id) == "governor":
		line = "I keep the hall and the ledgers. Hollowmark holds while I'm here. Mostly."
	elif Empire.role_of(id) == "staff":
		var bid: String = Empire.recruits[id]["target"]
		line = "%s Right now: %s." % [STAFF_LINES.get(bid, "Working."), Empire.current_effect(bid)["text"].to_lower()]
	elif not lines.is_empty():
		var i: int = talk_index.get(id, 0)
		line = lines[i % lines.size()]
		talk_index[id] = i + 1
	var gained := Empire.bond_talk(id)
	if gained > 0:
		line += "   (bond +%d)" % gained
	hud.say("%s: %s" % [short_name, line], 4.5)


## A newcomer at the gate: the first chat is their pitch, the next one takes them on (if you can pay).
func _talk_visitor(id: String) -> void:
	var r := Empire.recruit(id)
	var npc: Hero = npcs[id]
	npc.facing = (leader.global_position - npc.global_position).normalized()
	var who := Empire.short_name(id)
	var cost := Empire.hire_cost(id)
	var price := "free" if cost.is_empty() else Empire.cost_text(cost)
	if not pitched.has(id):
		pitched[id] = true
		hud.say("%s: %s   (Talk again to take them on: %s.)" % [who, r.get("pitch", "Looking for work."), price], 6.0)
		return
	var why := Empire.hire_blocker(id)
	if why != "":
		hud.say("%s: Come back when you can afford me. (%s: %s.)" % [who, price, why], 4.5)
		return
	if Empire.hire(id):
		pitched.erase(id)
		hud.say("%s: %s" % [who, r.get("welcome", "Glad to be here.")], 5.0)
		_place_people()


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
		{"id": "roster", "label": "Roster", "detail": "R"},
		{"id": "buildings", "label": "Buildings", "detail": "B"},
		{"id": "expeditions", "label": "Expeditions", "detail": "E"},
		{"id": "research", "label": "Research", "detail": "T"},
		{"id": "diplomacy", "label": "Diplomacy", "detail": "F"},
		{"id": "bonds", "label": "Bonds", "detail": "H"},
		{"id": "newcomers", "label": "Newcomers", "detail": "N"},
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
		"buildings":
			_close_menu()
			buildings_view.open()
		"expeditions":
			_close_menu()
			expedition_view.open()
		"research":
			_close_menu()
			research_view.open()
		"diplomacy":
			_close_menu()
			diplomacy_view.open()
		"bonds":
			_close_menu()
			bonds_view.open()
		"newcomers":
			_close_menu()
			newcomers_view.open()
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
	if lamp:
		lamp.queue_redraw()

	var frame := Engine.get_process_frames()
	var screen_open: bool = roster_view.visible or buildings_view.visible or expedition_view.visible or research_view.visible \
			or diplomacy_view.visible or bonds_view.visible or scene_view.visible or newcomers_view.visible
	if screen_open or frame == roster_view.closed_frame or frame == buildings_view.closed_frame \
			or frame == expedition_view.closed_frame or frame == research_view.closed_frame \
			or frame == diplomacy_view.closed_frame or frame == bonds_view.closed_frame \
			or frame == scene_view.closed_frame or frame == newcomers_view.closed_frame or frame == menu_closed_frame:
		leader.controlled = not screen_open
		return
	leader.controlled = true
	if Input.is_action_just_pressed("pause"):
		open_menu()
		return
	if Input.is_action_just_pressed("roster"):
		roster_view.open()
		return
	if Input.is_action_just_pressed("buildings"):
		buildings_view.open()
		return
	if Input.is_action_just_pressed("expeditions"):
		expedition_view.open()
		return
	if Input.is_action_just_pressed("research"):
		research_view.open()
		return
	if Input.is_action_just_pressed("diplomacy"):
		diplomacy_view.open()
		return
	if Input.is_action_just_pressed("bonds"):
		bonds_view.open()
		return
	if Input.is_action_just_pressed("newcomers"):
		newcomers_view.open()
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


## Hollowmark's Wardlamp: an iron post with an ink-blue flame, brighter at level 2.
func _draw_lamp() -> void:
	var lv := int(Empire.lamps.get("hollowmark", 0))
	var going_up := Empire.lamp_jobs.has("hollowmark")
	if lv == 0 and not going_up:
		return
	var c := lamp
	c.draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.4))
	c.draw_circle(Vector2(0, 2), 6.0, Color(0, 0, 0, 0.25))
	c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var h := 30.0 if lv > 0 else 30.0 * Empire.job_progress(Empire.lamp_jobs["hollowmark"])
	c.draw_rect(Rect2(-1.5, -h, 3, h), Color("2e2a33"))
	c.draw_rect(Rect2(-4, -2, 8, 3), Color("2e2a33"))
	if lv > 0:
		var flick := 0.75 + 0.25 * sin(Time.get_ticks_msec() * 0.011)
		var glow := 10.0 + 6.0 * lv
		c.draw_circle(Vector2(0, -h - 4), glow, Color(0.55, 0.65, 1.0, 0.10 * flick))
		c.draw_circle(Vector2(0, -h - 4), glow * 0.5, Color(0.6, 0.7, 1.0, 0.18 * flick))
		c.draw_rect(Rect2(-4, -h - 9, 8, 8), Color("3a3442"))
		c.draw_rect(Rect2(-2.5, -h - 7.5, 5, 5), Color(0.75, 0.82, 1.0, flick))
		c.draw_colored_polygon(PackedVector2Array([Vector2(-5, -h - 9), Vector2(5, -h - 9), Vector2(0, -h - 13)]), Color("2e2a33"))


func _draw_tags(canvas: Node2D) -> void:
	var font := ThemeDB.fallback_font
	# The one Ash would talk to goes first; other names that would overlap a drawn one are skipped.
	var order: Array = npcs.keys()
	if order.has(target.get("id", "")):
		order.erase(target["id"])
		order.push_front(target["id"])
	var drawn: Array = []
	for id in order:
		var npc: Hero = npcs[id]
		var d := npc.global_position.distance_to(leader.global_position)
		if d > 80.0:
			continue
		var a := clampf((80.0 - d) / 25.0, 0.0, 1.0)
		var r := Empire.recruit(id)
		var name_s: String = r["name"]
		var w := font.get_string_size(name_s, HORIZONTAL_ALIGNMENT_LEFT, -1, 6).x
		var p := npc.global_position + Vector2(-w / 2.0, -26)
		if Empire.is_visitor(id) and target.get("id", "") != id:  # a gold "!" over newcomers looking for work
			var bob := sin(Time.get_ticks_msec() * 0.006)
			var bp := npc.global_position + Vector2(-1.5, -35 + bob)
			canvas.draw_string_outline(font, bp, "!", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, 2, Color(0, 0, 0, 0.8 * a))
			canvas.draw_string(font, bp, "!", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color("ffd166", a))
		var box := Rect2(p + Vector2(-2, -6), Vector2(w + 4, 8))
		if drawn.any(func(o): return (o as Rect2).intersects(box)):
			continue
		drawn.append(box)
		var col := Color("ffd166", a) if target.get("id", "") == id else Color(0.95, 0.93, 0.88, a)
		canvas.draw_string_outline(font, p, name_s, HORIZONTAL_ALIGNMENT_LEFT, -1, 6, 2, Color(0, 0, 0, 0.8 * a))
		canvas.draw_string(font, p, name_s, HORIZONTAL_ALIGNMENT_LEFT, -1, 6, col)
		if Empire.bond_next_scene(id) > 0:  # a heart: they want a word
			var hc := npc.global_position + Vector2(0, -38 + sin(Time.get_ticks_msec() * 0.005) * 1.5)
			Art.draw_heart(canvas, hc, 4.0, Color("ff8fa3"))
			continue
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
