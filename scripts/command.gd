extends Control
## The Command Table: the territory map of the Inklands, a panel for the selected province,
## and the day clock (which only runs while this scene is open and unpaused).
##
## The map is rasterised from Territory at half resolution and shown at 2x, so it reads as
## pixel art. Owner colours, borders, the Blank's whitening (Fray) and roads are all baked or
## drawn in code. Keyboard, gamepad, mouse and touch all select provinces.

const TITLE_SCENE := "res://scenes/title.tscn"
const CELL := 2  # screen pixels per map cell
const MAP_ORIGIN := Vector2(4, 22)
const MAP_CELLS := Empire.MAP_CELLS
const AUTOSAVE_EVERY := 60.0
const PANEL_X := 440.0

const OWNER_NAMES := {
	"you": "Held by you", "free": "Unclaimed", "concord": "The Gilded Concord",
	"coven": "The Gutterwood Coven", "guild": "The Mercenary Guild", "erased": "Erased by the Blank",
}
const OWNER_COLORS := {
	"you": Color("6f9a5a"), "free": Color("7a7060"), "concord": Color("a8833e"),
	"coven": Color("4d6e66"), "guild": Color("8a5a4a"), "erased": Color("eeebe2"),
}
const SEA_COLOR := Color("15111b")
const BORDER_COLOR := Color("1c1722")
const PAPER := Color("eeebe2")
const GOLD := Color("ffd166")
const RES_NAMES := {"gilt": "Gilt", "supplies": "Supplies", "ink": "Ink"}

var territory: Territory
var map_tex: ImageTexture
var selected := 0
var hovered := -1
var outlines: Array = []  # per province: PackedVector2Array of border cells
var blank_edge := PackedVector2Array()  # white cells touching colour: where static crawls
var t := 0.0
var font: Font
var menu: InkMenu
var slot_menu: InkMenu
var slot_mode := ""
var menu_closed_frame := -1
var toast := ""
var toast2 := ""  # second, warning line (hunger and the like)
var toast_t := 0.0
var show_ledger := false
var ledger_hover := false
var deltas := {}  # resource -> net change shown floating by the bar after dawn
var deltas_t := 0.0
var notices: Array = []  # [text, warning, time left]
var over_menu: InkMenu
var brief_menu: InkMenu  # mission briefing: Go / Back
var brief_mission := {}
var roster_view
const RosterView := preload("res://scripts/roster_view.gd")
const BuildingsView := preload("res://scripts/buildings_view.gd")
var buildings_view
const GovernorView := preload("res://scripts/governor_view.gd")
var governor_view
const ExpeditionView := preload("res://scripts/expedition_view.gd")
var expedition_view
const ResearchView := preload("res://scripts/research_view.gd")
var research_view
const DiplomacyView := preload("res://scripts/diplomacy_view.gd")
var diplomacy_view
const BondsView := preload("res://scripts/bonds_view.gd")
var bonds_view
const NewcomersView := preload("res://scripts/newcomers_view.gd")
var newcomers_view
var autosave_t := AUTOSAVE_EVERY


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	get_tree().paused = false
	font = ThemeDB.fallback_font
	territory = Empire.territory()
	_bake()
	var hm := territory.find("hollowmark")
	selected = hm.get("index", 0)
	Saves.pending = {}  # Empire.from_dict already restored everything Command needs
	Empire.day_passed.connect(_on_day_passed)
	Empire.ledger_settled.connect(_on_ledger_settled)
	Empire.notice.connect(_on_notice)
	Empire.hollowmark_lost.connect(_on_hollowmark_lost)

	var roster_layer := CanvasLayer.new()
	roster_layer.layer = 4
	add_child(roster_layer)
	roster_view = RosterView.new()  # opened from the map or carried over from town
	roster_view.visible = false
	roster_layer.add_child(roster_view)
	buildings_view = BuildingsView.new()
	buildings_view.visible = false
	roster_layer.add_child(buildings_view)
	governor_view = GovernorView.new()
	governor_view.visible = false
	roster_layer.add_child(governor_view)
	governor_view.closed.connect(_bake)  # a claim recolours the map
	expedition_view = ExpeditionView.new()
	expedition_view.visible = false
	roster_layer.add_child(expedition_view)
	expedition_view.closed.connect(_bake)  # scouting can lower a province's Fray
	research_view = ResearchView.new()
	research_view.visible = false
	roster_layer.add_child(research_view)
	diplomacy_view = DiplomacyView.new()
	diplomacy_view.visible = false
	roster_layer.add_child(diplomacy_view)
	diplomacy_view.closed.connect(_bake)  # a ceded province changes colour
	bonds_view = BondsView.new()
	bonds_view.visible = false
	roster_layer.add_child(bonds_view)
	newcomers_view = NewcomersView.new()
	newcomers_view.visible = false
	roster_layer.add_child(newcomers_view)

	var layer := CanvasLayer.new()
	layer.layer = 5
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(layer)
	menu = InkMenu.new()
	menu.visible = false
	layer.add_child(menu)
	menu.chosen.connect(_on_menu)
	slot_menu = InkMenu.new()
	slot_menu.visible = false
	slot_menu.top = 0.2
	layer.add_child(slot_menu)
	slot_menu.chosen.connect(_on_slot)
	over_menu = InkMenu.new()
	over_menu.visible = false
	over_menu.dim = 0.6
	layer.add_child(over_menu)
	over_menu.chosen.connect(_on_over)
	brief_menu = InkMenu.new()
	brief_menu.visible = false
	brief_menu.top = 0.24
	brief_menu.title_size = 18
	layer.add_child(brief_menu)
	brief_menu.chosen.connect(_on_brief)
	if Empire.territory().find("hollowmark").get("owner", "") == "erased":
		call_deferred("_show_lost")  # lost while walking around town


func _on_day_passed(d: int) -> void:
	_bake()  # the Blank moved: re-whiten the map
	toast = "Day %d begins." % d
	toast2 = "Supplies ran out. People are going hungry." if Empire.hungry else ""
	toast_t = 3.5 if toast2 == "" else 5.0


func _on_notice(text: String, warning: bool) -> void:
	notices.append([text, warning, 7.0])
	if notices.size() > 4:
		notices.pop_front()


func _on_hollowmark_lost() -> void:
	# Defer: this arrives mid-tick, and the menu pauses the tree.
	call_deferred("_show_lost")


func _show_lost() -> void:
	over_menu.setup("Hollowmark has been erased.", [
		{"id": "load", "label": "Load game", "enabled": Saves.latest_slot() != ""},
		{"id": "title", "label": "Quit to title"},
	], "No town, no table, no one left to write you down.")
	over_menu.visible = true
	get_tree().paused = true


func _on_over(id: String) -> void:
	match id:
		"load":
			over_menu.visible = false
			slot_mode = "load"
			slot_menu.setup("Load which save?", Saves.slot_items(false))
			slot_menu.visible = true
		"title":
			get_tree().paused = false
			get_tree().change_scene_to_file(TITLE_SCENE)  # no autosave: the town is gone


func _on_ledger_settled(net: Dictionary) -> void:
	deltas = net
	deltas_t = 2.5


# ---------------------------------------------------------------- menu and saving

func _menu_items(note := "") -> void:
	menu.setup("Command", [
		{"id": "resume", "label": "Resume"},
		{"id": "town", "label": "Back to Hollowmark", "detail": "walk around town"},
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


func _open_menu() -> void:
	_menu_items()
	menu.visible = true
	get_tree().paused = true


func _close_menu() -> void:
	menu.visible = false
	slot_menu.visible = false
	get_tree().paused = false
	menu_closed_frame = Engine.get_process_frames()  # the closing key must not also act on the map


func _on_menu(id: String) -> void:
	match id:
		"resume", "cancel":
			_close_menu()
		"save", "load":
			slot_mode = id
			menu.visible = false
			slot_menu.setup("Save to which slot?" if id == "save" else "Load which save?", Saves.slot_items(id == "save"))
			slot_menu.visible = true
		"town":
			_leave(Saves.HUB_SCENE)
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
		"title":
			_leave(TITLE_SCENE)


func _on_slot(id: String) -> void:
	if id == "back" or id == "cancel":
		slot_menu.visible = false
		(over_menu if Empire.territory().find("hollowmark")["owner"] == "erased" else menu).visible = true
		return
	if slot_mode == "load":
		Saves.load_and_play(id)
		return
	var ok := Saves.save(id, snapshot())
	slot_menu.visible = false
	_menu_items(("Saved to %s." % Saves.slot_label(id)) if ok else "Saving failed. Your browser may be blocking storage.")
	menu.visible = true


func snapshot() -> Dictionary:
	return {"scene": Saves.COMMAND_SCENE, "area_name": "Command Table"}


func autosave() -> void:
	Saves.save("auto", snapshot())


## Leaves Command for another scene, autosaving first so the empire is never lost.
func _leave(scene: String) -> void:
	autosave()
	get_tree().paused = false
	get_tree().change_scene_to_file(scene)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_CLOSE_REQUEST:
		if is_inside_tree():
			autosave()


func _map_rect() -> Rect2:
	return Rect2(MAP_ORIGIN, Vector2(MAP_CELLS * CELL))


func _province_screen_pos(p: Dictionary) -> Vector2:
	return MAP_ORIGIN + (p["center"] as Vector2) * Vector2(MAP_CELLS * CELL)


# ---------------------------------------------------------------- baking

func _bake() -> void:
	var w := MAP_CELLS.x
	var h := MAP_CELLS.y
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var grain := FastNoiseLite.new()
	grain.seed = 3
	grain.frequency = 0.09
	var patch := FastNoiseLite.new()
	patch.seed = 11
	patch.frequency = 0.06
	patch.fractal_octaves = 2
	# Bounding boxes, so Fray can whiten each province from its eastern (Blank-facing) side.
	var minx := []
	var maxx := []
	for p in territory.provinces:
		minx.append(1e9)
		maxx.append(-1e9)
	for y in h:
		for x in w:
			var r := territory.cell(x, y)
			if r >= 0:
				minx[r] = minf(minx[r], x)
				maxx[r] = maxf(maxx[r], x)
	outlines = []
	for p in territory.provinces:
		outlines.append(PackedVector2Array())
	var white := PackedByteArray()
	white.resize(w * h)
	for y in h:
		for x in w:
			var r := territory.cell(x, y)
			var g := grain.get_noise_2d(x, y)
			var col: Color
			var is_white := false
			# The Blank itself: a wobbling wall of paper down the far east edge, over land and sea.
			var edge := 0.94 + sin(y * 0.11) * 0.012 + sin(y * 0.031 + 1.0) * 0.02
			if float(x) / w > edge:
				col = PAPER
				is_white = true
			elif r == territory.SEA:
				col = SEA_COLOR.lightened(0.04 if int(x + y * 0.5 + g * 6.0) % 9 == 0 else 0.0)
			else:
				var p: Dictionary = territory.provinces[r]
				var fray: float = float(p["fray"]) / 100.0
				var east := (x - float(minx[r])) / maxf(float(maxx[r]) - float(minx[r]), 1.0)
				var n := (patch.get_noise_2d(x, y) + 1.0) * 0.5
				if p["owner"] == "erased" or fray >= 1.0 or fray > (1.0 - east) * 0.75 + n * 0.45:
					col = PAPER.darkened(0.05 if g > 0.3 else 0.0)
					is_white = true
				else:
					col = (OWNER_COLORS[p["owner"]] as Color).lightened(g * 0.08)
					# Fray also drains colour from the whole province, like the field shader does.
					var grey := col.get_luminance()
					col = col.lerp(Color(grey, grey, grey), fray * 0.6)
				if _is_border(x, y, r):
					col = BORDER_COLOR
					is_white = false
					outlines[r].append(Vector2(x, y))
			img.set_pixel(x, y, col)
			white[y * w + x] = 1 if is_white else 0
	blank_edge = PackedVector2Array()
	for y in range(1, h - 1):
		for x in range(1, w - 1):
			if white[y * w + x] == 1 and (white[y * w + x - 1] == 0 or white[y * w + x + 1] == 0 or white[(y - 1) * w + x] == 0 or white[(y + 1) * w + x] == 0):
				blank_edge.append(Vector2(x, y))
	map_tex = ImageTexture.create_from_image(img)


func _is_border(x: int, y: int, r: int) -> bool:
	for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if territory.cell(x + o.x, y + o.y) != r:
			return true
	return false


# ---------------------------------------------------------------- input

func _process(delta: float) -> void:
	t += delta
	Empire.tick(delta)
	Empire.playtime += delta
	toast_t = maxf(toast_t - delta, 0.0)
	deltas_t = maxf(deltas_t - delta, 0.0)
	for n in notices:
		n[2] -= delta
	notices = notices.filter(func(n): return n[2] > 0.0)
	autosave_t -= delta
	if autosave_t <= 0.0:
		autosave_t = AUTOSAVE_EVERY
		autosave()
	queue_redraw()
	var frame := Engine.get_process_frames()
	if frame == menu_closed_frame or roster_view.visible or frame == roster_view.closed_frame \
			or buildings_view.visible or frame == buildings_view.closed_frame \
			or governor_view.visible or frame == governor_view.closed_frame \
			or expedition_view.visible or frame == expedition_view.closed_frame \
			or research_view.visible or frame == research_view.closed_frame \
			or diplomacy_view.visible or frame == diplomacy_view.closed_frame \
			or bonds_view.visible or frame == bonds_view.closed_frame \
			or newcomers_view.visible or frame == newcomers_view.closed_frame:
		return
	if Input.is_action_just_pressed("roster"):
		roster_view.open()
		return
	if Input.is_action_just_pressed("buildings"):
		buildings_view.open()
		return
	if Input.is_action_just_pressed("govern"):
		_open_governor()
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
	if Input.is_action_just_pressed("ledger"):
		show_ledger = not show_ledger
	var dir := Vector2.ZERO
	if Input.is_action_just_pressed("move_left") or Input.is_action_just_pressed("ui_left"):
		dir = Vector2.LEFT
	elif Input.is_action_just_pressed("move_right") or Input.is_action_just_pressed("ui_right"):
		dir = Vector2.RIGHT
	elif Input.is_action_just_pressed("move_up") or Input.is_action_just_pressed("ui_up"):
		dir = Vector2.UP
	elif Input.is_action_just_pressed("move_down") or Input.is_action_just_pressed("ui_down"):
		dir = Vector2.DOWN
	if dir != Vector2.ZERO:
		_step(dir)
	if Input.is_action_just_pressed("ui_accept"):
		_activate(selected)
	elif Input.is_action_just_pressed("ui_cancel") or Input.is_action_just_pressed("pause"):
		_open_menu()


## Moves the selection to the best province in a direction: close, and roughly that way.
func _step(dir: Vector2) -> void:
	var from: Vector2 = territory.provinces[selected]["center"]
	var best := -1
	var best_score := 1e9
	for p in territory.provinces:
		if p["index"] == selected:
			continue
		var d: Vector2 = (p["center"] as Vector2) - from
		var cosang := d.normalized().dot(dir)
		if cosang < 0.35:
			continue
		var score := d.length() / (cosang * cosang)
		if score < best_score:
			best_score = score
			best = p["index"]
	if best >= 0:
		selected = best


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		hovered = _province_at(event.position)
		ledger_hover = _res_rect().has_point(event.position)
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var i := _province_at(event.position)
		if i >= 0:
			if i == selected:
				_activate(i)  # second tap on the selected province plays its mission
			selected = i
		elif _governor_button_rect().has_point(event.position) and _can_govern(selected):
			_open_governor()
		elif _play_rect().has_point(event.position):
			_activate(selected)
		elif _roster_button_rect().has_point(event.position):
			roster_view.open()
		elif _buildings_button_rect().has_point(event.position):
			buildings_view.open()
		elif _expeditions_button_rect().has_point(event.position):
			expedition_view.open()
		elif _research_button_rect().has_point(event.position):
			research_view.open()
		elif _diplomacy_button_rect().has_point(event.position):
			diplomacy_view.open()
		elif _town_button_rect().has_point(event.position):
			_leave(Saves.HUB_SCENE)
		elif _res_rect().has_point(event.position):
			show_ledger = not show_ledger
		elif _menu_button_rect().has_point(event.position):
			_open_menu()
		else:
			for sp in Empire.SPEEDS.size():
				if _speed_rect(sp).has_point(event.position):
					Empire.set_speed(sp)


func _province_at(pos: Vector2) -> int:
	if not _map_rect().has_point(pos):
		return -1
	var c := ((pos - MAP_ORIGIN) / CELL).floor()
	return territory.cell(int(c.x), int(c.y))


func _mission(i: int) -> Dictionary:
	return Missions.for_province(territory.provinces[i]["id"])


func _activate(i: int) -> void:
	var m := _mission(i)
	if not m.is_empty():
		_open_brief(m)


## The briefing: what the mission is, what it asks, what it pays. Go launches it.
func _open_brief(m: Dictionary) -> void:
	brief_mission = m
	var lines := []
	for line in _wrap_words(m.get("brief", ""), 64):
		lines.append(line)
	lines.append("")
	lines.append("Objective: " + Objective.describe(m.get("objective", {})))
	var rew := Missions.res_text(m.get("rewards", {}))
	if rew != "":
		lines.append("Reward: " + rew)
	if int(m.get("fray", 0)) < 0:
		lines.append("Pushes the Blank back: %d Fray in %s" % [int(m["fray"]), territory.find(m.get("province", "")).get("name", "")])
	lines.append("The clock stops while you are away.")
	brief_menu.setup(m.get("name", "Mission"), [
		{"id": "go", "label": "Set out"},
		{"id": "back", "label": "Back"},
	], "\n".join(lines))
	brief_menu.visible = true
	get_tree().paused = true


func _on_brief(id: String) -> void:
	brief_menu.visible = false
	get_tree().paused = false
	menu_closed_frame = Engine.get_process_frames()
	if id == "go":
		_launch_mission(brief_mission)


## Leaves for a mission: autosave the empire, then load the mission's map.
func _launch_mission(m: Dictionary) -> void:
	autosave()  # the clock stops here: missions take no Command time
	Missions.launch(m)


func _wrap_words(s: String, width: int) -> Array:
	var out := []
	var cur := ""
	for w in s.split(" "):
		if cur != "" and (cur + " " + w).length() > width:
			out.append(cur)
			cur = w
		else:
			cur = w if cur == "" else cur + " " + w
	if cur != "":
		out.append(cur)
	return out


func _open_governor() -> void:
	if _can_govern(selected):
		governor_view.open(territory.provinces[selected]["id"])


## The governor screen opens for your provinces and for unclaimed ones (to claim them).
func _can_govern(i: int) -> bool:
	return territory.provinces[i]["owner"] in ["you", "free"]


var _gov_button_y := -100.0  # set while drawing the panel


func _governor_button_rect() -> Rect2:
	return Rect2(Vector2(size.x - 92, _gov_button_y - 10), Vector2(86, 14))


func _roster_button_rect() -> Rect2:
	return Rect2(Vector2(MAP_ORIGIN.x + MAP_CELLS.x * CELL - 74, MAP_ORIGIN.y + 4), Vector2(70, 16))


func _buildings_button_rect() -> Rect2:
	var rb := _roster_button_rect()
	return Rect2(rb.position - Vector2(80, 0), Vector2(76, 16))


func _town_button_rect() -> Rect2:
	var bb := _buildings_button_rect()
	return Rect2(bb.position - Vector2(58, 0), Vector2(54, 16))


func _expeditions_button_rect() -> Rect2:
	var tb := _town_button_rect()
	return Rect2(tb.position - Vector2(86, 0), Vector2(82, 16))


## Second row, under Roster.
func _research_button_rect() -> Rect2:
	var rb := _roster_button_rect()
	return Rect2(Vector2(rb.end.x - 96, rb.end.y + 3), Vector2(96, 16))


## Second row, left of Research.
func _diplomacy_button_rect() -> Rect2:
	var rs := _research_button_rect()
	return Rect2(rs.position - Vector2(90, 0), Vector2(86, 16))


func _speed_rect(i: int) -> Rect2:
	return Rect2(Vector2(452 + i * 34, 3), Vector2(31, 15))


func _menu_button_rect() -> Rect2:
	return Rect2(Vector2(size.x - 46, 3), Vector2(42, 15))


func _play_rect() -> Rect2:
	return Rect2(PANEL_X, size.y - 34, size.x - PANEL_X - 6, 26)


# ---------------------------------------------------------------- drawing

func _text(pos: Vector2, s: String, fsize: int, col: Color, outline := 0) -> void:
	if outline > 0:
		draw_string_outline(font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, outline, Color(0, 0, 0, 0.85 * col.a))
	draw_string(font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, col)


func _text_c(center: Vector2, s: String, fsize: int, col: Color, outline := 0) -> void:
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x
	_text(center - Vector2(w / 2.0, 0), s, fsize, col, outline)


func _draw() -> void:
	var vs := size
	draw_rect(Rect2(Vector2.ZERO, vs), Color("0e0b12"))
	# Map
	draw_texture_rect(map_tex, _map_rect(), false)
	_draw_roads()
	_draw_static()
	_draw_outline(selected, GOLD)
	if hovered >= 0 and hovered != selected:
		_draw_outline(hovered, Color(1, 1, 1, 0.55))
	_draw_labels()
	draw_rect(_map_rect(), Color(0.3, 0.27, 0.33), false, 1.0)
	# Top bar
	_text(MAP_ORIGIN + Vector2(6, 14), "THE INKLANDS", 10, Color(0.85, 0.82, 0.76, 0.8), 3)
	_draw_resources()
	_draw_clock()
	var rb := _roster_button_rect()
	draw_rect(rb, Color(0.1, 0.09, 0.12, 0.92))
	draw_rect(rb, Color(0.45, 0.4, 0.48), false, 1.0)
	_text_c(Vector2(rb.get_center().x, rb.position.y + 12), "Roster (%d)  R" % Empire.recruits.size(), 9, Color(0.85, 0.82, 0.76))
	var bb := _buildings_button_rect()
	draw_rect(bb, Color(0.1, 0.09, 0.12, 0.92))
	draw_rect(bb, Color(0.45, 0.4, 0.48), false, 1.0)
	var busy := "" if Empire.construction.is_empty() else " *"
	_text_c(Vector2(bb.get_center().x, bb.position.y + 12), "Buildings%s  B" % busy, 9, GOLD if busy != "" else Color(0.85, 0.82, 0.76))
	var tb := _town_button_rect()
	draw_rect(tb, Color(0.1, 0.09, 0.12, 0.92))
	draw_rect(tb, Color(0.45, 0.4, 0.48), false, 1.0)
	_text_c(Vector2(tb.get_center().x, tb.position.y + 12), "To town", 9, Color(0.85, 0.82, 0.76))
	var eb := _expeditions_button_rect()
	draw_rect(eb, Color(0.1, 0.09, 0.12, 0.92))
	draw_rect(eb, Color(0.45, 0.4, 0.48), false, 1.0)
	var unread := Empire.unread_reports()
	var out := Empire.expeditions.size()
	var etext := "Expeditions  E"
	if unread > 0:
		etext = "Reports (%d)  E" % unread
	elif out > 0:
		etext = "Squads out: %d  E" % out
	_text_c(Vector2(eb.get_center().x, eb.position.y + 12), etext, 9, GOLD if unread > 0 else Color(0.85, 0.82, 0.76))
	var rsb := _research_button_rect()
	draw_rect(rsb, Color(0.1, 0.09, 0.12, 0.92))
	draw_rect(rsb, Color(0.45, 0.4, 0.48), false, 1.0)
	var rtext := "Research  T"
	var rcol := Color(0.85, 0.82, 0.76)
	if Empire.research_active != "":
		var stalled := float(Empire.research_pace()["pace"]) <= 0.0
		rtext = "Research %d%%%s  T" % [int(Empire.research_fraction(Empire.research_active) * 100), " (stalled)" if stalled else ""]
		rcol = Color(1, 0.55, 0.5) if stalled else Color("d7b8f0")
	_text_c(Vector2(rsb.get_center().x, rsb.position.y + 12), rtext, 9, rcol)
	var db := _diplomacy_button_rect()
	draw_rect(db, Color(0.1, 0.09, 0.12, 0.92))
	draw_rect(db, Color(0.45, 0.4, 0.48), false, 1.0)
	var dtext := "Diplomacy  F"
	var dcol := Color(0.85, 0.82, 0.76)
	if Empire.surge.get("id", "") != "" and Empire.surge.get("aid", "") == "" and Empire.territory().find(Empire.surge["id"]).get("owner", "") == "you" \
			and Empire.faction_ids().any(func(f): return Empire.deal_blocker(f, "aid") == ""):
		dtext = "Ask for aid!  F"
		dcol = GOLD
	_text_c(Vector2(db.get_center().x, db.position.y + 12), dtext, 9, dcol)
	_draw_legend()
	_draw_panel()
	if toast_t > 0.0:
		var a := clampf(toast_t / 0.5, 0.0, 1.0)
		_text_c(Vector2(_map_rect().get_center().x, MAP_ORIGIN.y + 22), toast, 12, Color(1, 0.95, 0.85, a), 4)
		if toast2 != "":
			_text_c(Vector2(_map_rect().get_center().x, MAP_ORIGIN.y + 36), toast2, 9, Color(1, 0.55, 0.5, a), 4)
	var ny := MAP_ORIGIN.y + (52.0 if toast_t > 0.0 else 22.0)
	for n in notices:
		var a := clampf(float(n[2]) / 0.6, 0.0, 1.0)
		_text_c(Vector2(_map_rect().get_center().x, ny), n[0], 9, Color(1, 0.62, 0.55, a) if n[1] else Color(0.92, 0.9, 0.84, a), 4)
		ny += 13.0
	if show_ledger or ledger_hover:
		_draw_ledger()
	if Empire.SPEEDS[Empire.speed] == 0:
		_text_c(Vector2(_map_rect().get_center().x, MAP_ORIGIN.y + MAP_CELLS.y * CELL - 24), "TIME PAUSED", 11, Color(1, 1, 1, 0.55 + 0.25 * sin(t * 3.0)), 4)


func _res_rect() -> Rect2:
	return Rect2(Vector2(2, 1), Vector2(222, 19))


const RES_COLORS := {"gilt": Color("e8c66a"), "supplies": Color("b7c98a"), "ink": Color("8fa7e8"), "renown": Color("e8a0c8")}


func _draw_res_icon(k: String, c: Vector2) -> void:
	var col: Color = RES_COLORS[k]
	match k:
		"gilt":  # a coin
			draw_circle(c, 4.0, col)
			draw_circle(c, 2.0, col.darkened(0.35))
		"supplies":  # a sack
			draw_rect(Rect2(c + Vector2(-3, -2), Vector2(6, 6)), col)
			draw_rect(Rect2(c + Vector2(-1.5, -4), Vector2(3, 2)), col.darkened(0.3))
		"ink":  # a drop
			draw_circle(c + Vector2(0, 1), 3.0, col)
			draw_colored_polygon(PackedVector2Array([c + Vector2(-2.6, 0), c + Vector2(2.6, 0), c + Vector2(0, -5)]), col)
		"renown":  # a star-ish diamond
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, -5), c + Vector2(4, 0), c + Vector2(0, 5), c + Vector2(-4, 0)]), col)


func _draw_resources() -> void:
	var net := Empire.daily_net()
	var x := 8.0
	for k in ["gilt", "supplies", "ink", "renown"]:
		_draw_res_icon(k, Vector2(x + 3, 10))
		var v := int(Empire.res[k])
		var col := Color("ece6da")
		if k == "supplies" and (Empire.hungry or v + int(net["supplies"]) < 0):
			col = Color("ff8a7a")
		_text(Vector2(x + 10, 15), str(v), 10, col)
		var w := font.get_string_size(str(v), HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
		if net.has(k) and int(net[k]) != 0:
			var n := int(net[k])
			_text(Vector2(x + 12 + w, 15), ("+%d" if n > 0 else "%d") % n, 8, Color("9fd18b") if n > 0 else Color("ff8a7a"))
		if deltas_t > 0.0 and deltas.has(k) and int(deltas[k]) != 0:
			var d := int(deltas[k])
			var rise := (2.5 - deltas_t) * 6.0
			_text(Vector2(x + 10, 30 - rise + 10), ("+%d" if d > 0 else "%d") % d, 10, Color(0.62, 0.82, 0.55, minf(deltas_t, 1.0)) if d > 0 else Color(1, 0.55, 0.5, minf(deltas_t, 1.0)), 3)
		x += 56.0


## The ledger: where every point of daily income and upkeep comes from.
func _draw_ledger() -> void:
	var lines := Empire.ledger()
	var r := Rect2(Vector2(6, 22), Vector2(300, 54 + 13 * lines.size()))
	draw_rect(r, Color(0.06, 0.05, 0.08, 0.95))
	draw_rect(r, Color(0.45, 0.4, 0.48), false, 1.0)
	var y := r.position.y + 14
	_text(Vector2(r.position.x + 8, y), "Daily ledger", 10, Color("f3efe4"))
	_text(Vector2(r.position.x + 150, y), "Gilt", 8, RES_COLORS["gilt"])
	_text(Vector2(r.position.x + 182, y), "Supplies", 8, RES_COLORS["supplies"])
	_text(Vector2(r.position.x + 226, y), "Ink", 8, RES_COLORS["ink"])
	y += 14
	for line in lines:
		_text(Vector2(r.position.x + 8, y), line["label"], 9, Color(0.85, 0.83, 0.78))
		if line["note"] != "":
			_text(Vector2(r.position.x + 248, y), line["note"], 7, Color(0.6, 0.58, 0.6))
		var cx := [150, 182, 226]
		var ks := ["gilt", "supplies", "ink"]
		for i in 3:
			var v := int(line[ks[i]])
			if v != 0:
				_text(Vector2(r.position.x + cx[i], y), ("+%d" if v > 0 else "%d") % v, 9, Color("9fd18b") if v > 0 else Color("ff8a7a"))
		y += 13
	draw_line(Vector2(r.position.x + 8, y - 8), Vector2(r.end.x - 8, y - 8), Color(0.3, 0.27, 0.33))
	var net := Empire.daily_net()
	_text(Vector2(r.position.x + 8, y + 3), "Each dawn", 9, Color("f3efe4"))
	var cx2 := [150, 182, 226]
	var ks2 := ["gilt", "supplies", "ink"]
	for i in 3:
		var v := int(net[ks2[i]])
		_text(Vector2(r.position.x + cx2[i], y + 3), ("+%d" if v >= 0 else "%d") % v, 9, Color("9fd18b") if v > 0 else (Color("ff8a7a") if v < 0 else Color(0.6, 0.58, 0.6)))
	_text(Vector2(r.position.x + 8, r.end.y - 6), "L / Back / tap the bar to toggle", 7, Color(0.5, 0.48, 0.52))


func _draw_clock() -> void:
	# Day and time, with a little sun or moon and a bar through the day.
	var x := 236.0
	var night := Empire.day_t < 0.25 or Empire.day_t > 0.83
	if night:
		draw_circle(Vector2(x, 10), 4.0, Color("d8d4e8"))
		draw_circle(Vector2(x + 2, 9), 3.5, Color("0e0b12"))
	else:
		draw_circle(Vector2(x, 10), 4.0, GOLD)
	_text(Vector2(x + 9, 15), "Day %d" % Empire.day, 11, Color("ece6da"))
	_text(Vector2(x + 58, 15), Empire.clock_text(), 9, Color(0.75, 0.72, 0.7))
	draw_rect(Rect2(x + 92, 8, 100, 4), Color(0.18, 0.16, 0.2))
	draw_rect(Rect2(x + 92, 8, 100 * Empire.day_t, 4), Color(0.75, 0.72, 0.68))
	for i in Empire.SPEEDS.size():
		var r := _speed_rect(i)
		var on := i == Empire.speed
		draw_rect(r, Color(0.22, 0.17, 0.08) if on else Color(0.1, 0.09, 0.12))
		draw_rect(r, GOLD if on else Color(0.3, 0.27, 0.33), false, 1.0)
		var label := "II" if i == 0 else "%dx" % Empire.SPEEDS[i]
		_text_c(Vector2(r.get_center().x, r.position.y + 11), label, 9, GOLD if on else Color(0.75, 0.72, 0.7))
	var mr := _menu_button_rect()
	draw_rect(mr, Color(0.1, 0.09, 0.12))
	draw_rect(mr, Color(0.3, 0.27, 0.33), false, 1.0)
	_text_c(Vector2(mr.get_center().x, mr.position.y + 11), "Menu", 9, Color(0.75, 0.72, 0.7))


func _draw_roads() -> void:
	var drawn := {}
	for p in territory.provinces:
		var a: int = p["index"]
		for b in territory.neighbors[a]:
			var key := Vector2i(mini(a, b), maxi(a, b))
			if drawn.has(key):
				continue
			drawn[key] = true
			var q: Dictionary = territory.provinces[b]
			var p1 := _province_screen_pos(p)
			var p2 := _province_screen_pos(q)
			var lost: bool = p["owner"] == "erased" or q["owner"] == "erased"
			var col := Color(0.12, 0.1, 0.14, 0.35 if lost else 0.75)
			# Dashed road.
			var n := int(p1.distance_to(p2) / 6.0)
			for i in n:
				if i % 2 == 0:
					draw_line(p1.lerp(p2, float(i) / n), p1.lerp(p2, float(i + 1) / n), col, 1.5)


func _draw_static() -> void:
	if blank_edge.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = int(t * 10.0)
	for i in 90:
		var c: Vector2 = blank_edge[rng.randi() % blank_edge.size()]
		var pos := MAP_ORIGIN + c * CELL + Vector2(rng.randf_range(-3, 3), rng.randf_range(-3, 3))
		var col := Color(0.06, 0.05, 0.07, 0.75) if rng.randf() < 0.5 else Color(0.98, 0.97, 0.94, 0.9)
		draw_rect(Rect2(pos, Vector2(2, 2)), col)


func _draw_outline(i: int, col: Color) -> void:
	var pulse := 0.75 + 0.25 * sin(t * 4.0) if col == GOLD else 1.0
	var c := Color(col, col.a * pulse)
	for cell in outlines[i]:
		draw_rect(Rect2(MAP_ORIGIN + cell * CELL, Vector2(CELL, CELL)), c)


func _draw_labels() -> void:
	for p in territory.provinces:
		var pos := _province_screen_pos(p)
		var col := Color("f3efe4")
		if p["owner"] == "erased":
			col = Color(0.35, 0.34, 0.36)
		if p["owner"] == "you":
			# A little ink-black tower for the capital.
			draw_rect(Rect2(pos + Vector2(-3, -15), Vector2(6, 8)), Color("15111b"))
			draw_colored_polygon(PackedVector2Array([pos + Vector2(-4, -15), pos + Vector2(4, -15), pos + Vector2(0, -20)]), Color("15111b"))
			draw_rect(Rect2(pos + Vector2(-1, -12), Vector2(2, 3)), GOLD)
		else:
			draw_circle(pos + Vector2(0, -9), 2.0, Color("15111b"))
		_text_c(pos + Vector2(0, 2), p["name"], 9, col, 0 if p["owner"] == "erased" else 4)
		if Empire.surge.get("id", "") == p["id"]:
			# A gathering surge: a pulsing red ring and a countdown.
			var pulse := 0.5 + 0.5 * sin(t * 5.0)
			draw_arc(pos + Vector2(0, -6), 14.0 + pulse * 3.0, 0, TAU, 32, Color(1, 0.35, 0.3, 0.5 + 0.4 * pulse), 2.0)
			var dl := Empire.surge_days_left()
			_text_c(pos + Vector2(0, 13), "Surge %s" % ("today" if dl <= 0 else "in %d day%s" % [dl, "" if dl == 1 else "s"]), 8, Color(1, 0.55, 0.5), 3)


func _draw_legend() -> void:
	var x := MAP_ORIGIN.x + 4
	var y := MAP_ORIGIN.y + MAP_CELLS.y * CELL - 8
	for k in ["you", "free", "concord", "coven", "guild"]:
		draw_rect(Rect2(x, y - 6, 6, 6), OWNER_COLORS[k])
		draw_rect(Rect2(x, y - 6, 6, 6), BORDER_COLOR, false, 1.0)
		var label: String = {"you": "Yours", "free": "Unclaimed", "concord": "Concord", "coven": "Coven", "guild": "Guild"}[k]
		_text(Vector2(x + 9, y), label, 8, Color(0.85, 0.83, 0.78), 3)
		x += 13 + font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x + 6


func _draw_panel() -> void:
	var p: Dictionary = territory.provinces[selected]
	var x := PANEL_X
	var w := size.x - PANEL_X - 6
	draw_rect(Rect2(x - 4, 22, w + 8, size.y - 26), Color(0.07, 0.06, 0.09))
	draw_rect(Rect2(x - 4, 22, w + 8, size.y - 26), Color(0.3, 0.27, 0.33), false, 1.0)
	var y := 42.0
	_text(Vector2(x, y), p["name"], 15, Color("f3efe4"))
	y += 15
	var owner: String = p["owner"]
	draw_rect(Rect2(x, y - 7, 7, 7), OWNER_COLORS[owner])
	_text(Vector2(x + 11, y), OWNER_NAMES[owner], 9, Color(0.8, 0.78, 0.74))
	if owner in Empire.faction_ids():
		var tier := Empire.tier_of(owner)
		_text(Vector2(x + 11, y + 11), "Standing: %s %+d   Diplomacy: F" % [Empire.tier_name(tier), Empire.standing_of(owner)], 8,
			Color("9fd18b") if Empire.has_perk(owner) else (Color("ff9b8a") if tier == "hostile" else Color(0.7, 0.68, 0.7)))
		y += 10
	y += 18

	# Fray
	var fray := int(p["fray"])
	var state := "Safe" if fray < 25 else ("Fraying" if fray < 60 else ("Unravelling" if fray < 100 else "Erased"))
	_text(Vector2(x, y), "Fray", 9, Color(0.7, 0.68, 0.7))
	_text(Vector2(x + 30, y), "%d / 100   %s" % [fray, state], 9, Color("f3efe4") if fray < 60 else Color("ff9b8a"))
	y += 5
	draw_rect(Rect2(x, y, w, 5), Color(0.15, 0.13, 0.17))
	draw_rect(Rect2(x, y, w * fray / 100.0, 5), Color(0.85, 0.84, 0.8).lerp(PAPER, fray / 100.0))
	y += 16
	if owner != "erased":
		var rate := Empire.fray_rate(p)
		var rcol := Color("ff8a7a") if rate > 0 else (Color("9fd18b") if rate < 0 else Color(0.7, 0.68, 0.7))
		var eta := ""
		if rate > 0:
			eta = "   erased in ~%d days" % ceili((100.0 - fray) / rate)
		_text(Vector2(x, y), "Per day: %s%d%s" % ["+" if rate > 0 else "", rate, eta], 9, rcol)
		y += 11
		for src in Empire.fray_sources(p):
			var v := int(src[1])
			_text(Vector2(x + 6, y), ("+%d" if v > 0 else "%d") % v, 8, Color("ff9b8a") if v > 0 else Color("9fd18b"))
			_text(Vector2(x + 24, y), src[0], 8, Color(0.7, 0.68, 0.7))
			y += 10
		if Empire.surge.get("id", "") == p["id"]:
			_text(Vector2(x, y + 1), "Surge gathering: +%d Fray when it lands" % Empire.surge_fray(), 8, Color(1, 0.55, 0.5))
			y += 11
		y += 6
	else:
		y += 2

	# Output
	var out: Dictionary = p.get("output", {})
	var parts := []
	for k in ["gilt", "supplies", "ink"]:
		if out.has(k):
			parts.append("+%d %s" % [out[k], RES_NAMES[k]])
	var out_label := "Lost output" if owner == "erased" else ("Output per day" if owner == "you" else "Would give")
	_text(Vector2(x, y), out_label, 9, Color(0.7, 0.68, 0.7))
	y += 12
	_text(Vector2(x, y), "   ".join(parts) if not parts.is_empty() else "nothing", 9, Color("e8d9a8") if owner != "erased" else Color(0.55, 0.54, 0.56))
	y += 17

	# Governor and sites
	_text(Vector2(x, y), "Governor", 9, Color(0.7, 0.68, 0.7))
	var gov := Empire.governor_of(p["id"])
	var gov_text := "-"
	var gov_col := Color(0.85, 0.83, 0.78)
	if owner == "you":
		if gov != "":
			gov_text = "%s (%s fit)" % [Empire.recruit(gov)["name"], Empire.governor_fit(gov, p["id"])]
		else:
			gov_text = "none posted!"
			gov_col = Color("ff9b8a")
	elif owner == "free":
		gov_text = "claim it to post one"
	_text(Vector2(x + 52, y), gov_text, 9, gov_col)
	_gov_button_y = y if _can_govern(selected) else -100.0
	if _can_govern(selected):
		y += 13
		var fav: String = p.get("favors", "charm")
		_text(Vector2(x, y), "Wants", 9, Color(0.7, 0.68, 0.7))
		_text(Vector2(x + 52, y), "high %s" % Empire.STAT_NAMES[fav], 9, Color(0.85, 0.83, 0.78))
		var gb := _governor_button_rect()
		gb.position.y += 13  # sits beside the "Wants" line, under the name
		_gov_button_y += 13
		draw_rect(gb, Color(0.22, 0.17, 0.08))
		draw_rect(gb, GOLD, false, 1.0)
		var label := ("Claim" if owner == "free" else ("Change" if gov != "" else "Post one")) + "  G"
		_text_c(Vector2(gb.get_center().x, gb.position.y + 10), label, 8, GOLD)
	y += 13
	var sites: Array = p.get("sites", [])
	_text(Vector2(x, y), "Sites", 9, Color(0.7, 0.68, 0.7))
	_text(Vector2(x + 52, y), ", ".join(sites) if not sites.is_empty() else "none left", 9, Color(0.85, 0.83, 0.78))
	y += 13
	var nb := []
	for b in territory.neighbors[selected]:
		nb.append(territory.provinces[b]["name"])
	_text(Vector2(x, y), "Borders", 9, Color(0.7, 0.68, 0.7))
	draw_multiline_string(font, Vector2(x + 52, y), ", ".join(nb), HORIZONTAL_ALIGNMENT_LEFT, w - 52, 9, -1, Color(0.85, 0.83, 0.78))
	y += 13 * ceilf(font.get_string_size(", ".join(nb), HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x / (w - 52)) + 8

	# Flavour
	draw_multiline_string(font, Vector2(x, y), p["blurb"], HORIZONTAL_ALIGNMENT_LEFT, w, 9, -1, Color(0.62, 0.6, 0.62))

	# Mission button
	var m := _mission(selected)
	var r := _play_rect()
	if not m.is_empty():
		draw_rect(r, Color(0.22, 0.17, 0.08))
		draw_rect(r, GOLD, false, 1.0)
		_text_c(Vector2(r.get_center().x, r.position.y + 12), "Play: " + m["name"], 9, GOLD)
		_text_c(Vector2(r.get_center().x, r.position.y + 22), "Enter / A / tap", 8, Color(0.75, 0.7, 0.55))
	else:
		var note := "Reclaim missions are coming soon" if owner == "erased" else "No missions here right now"
		_text_c(Vector2(r.get_center().x, r.position.y + 16), note, 8, Color(0.45, 0.44, 0.47))
