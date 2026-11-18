class_name PartyPicker
extends Control
## Before a mission: pick up to three field heroes to take along (issue #10).
##
## Ash always leads. Anyone else needs to be a field hero who has joined, is not injured,
## and is not busy governing, staffing, envoying or out on an expedition (free them in the
## Roster first; R jumps there). Picks are the same "party" role the Roster uses, so they stick
## between missions. Combat stats come from data/heroes.json, looks from data/recruits.json.
## The static helpers at the bottom are what main.gd uses to put the party on the field.

signal confirmed(mission: Dictionary)
signal closed
signal roster_requested

const HEROES_FILE := "res://data/heroes.json"
const GOLD := Color("ffd166")
const PAPER := Color("f3efe4")
const ROW_H := 40.0
const LIST_X := 8.0
const LIST_W := 300.0
const DETAIL_X := 322.0
const DOLL_SCALE := 3.0

static var _data := {}

var mission := {}
var sel := 0
var closed_frame := -1
var opened_frame := -1
var flash := ""
var flash_t := 0.0
var font: Font
var _row_rects: Array = []
var _go_rect := Rect2()
var _back_rect := Rect2()
var _dolls: Array = []  # [body Sprite2D, outfit Sprite2D] per preview slot
var _doll_ids: Array = []
var t := 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	font = ThemeDB.fallback_font
	for i in Empire.PARTY_SIZE:
		var pair := []
		for k in 2:
			var s := Sprite2D.new()
			s.hframes = 24
			s.vframes = 8
			s.scale = Vector2(DOLL_SCALE, DOLL_SCALE)
			s.visible = false
			add_child(s)
			pair.append(s)
		_dolls.append(pair)
		_doll_ids.append("")


func open(m: Dictionary) -> void:
	mission = m
	position = Vector2.ZERO
	size = get_viewport_rect().size
	visible = true
	opened_frame = Engine.get_process_frames()
	sel = clampi(sel, 0, _ids().size())


## Back from the Roster: same mission, fresh availability.
func reopen() -> void:
	open(mission)


func close() -> void:
	visible = false
	closed_frame = Engine.get_process_frames()
	closed.emit()


## Every field hero in the game, joined or not, in roster order (Ash first).
func _ids() -> Array:
	var out := []
	for id in Empire.recruit_data:
		if Empire.recruit_data[id].get("tier", "") == "field":
			out.append(id)
	return out


func _process(delta: float) -> void:
	if not visible:
		return
	t += delta
	flash_t = maxf(flash_t - delta, 0.0)
	_update_dolls()
	queue_redraw()
	if Engine.get_process_frames() == opened_frame:
		return  # the key that opened the picker must not also act inside it
	var n := _ids().size() + 1  # the last row is "Set out"
	if Input.is_action_just_pressed("move_up") or Input.is_action_just_pressed("ui_up"):
		sel = posmod(sel - 1, n)
	elif Input.is_action_just_pressed("move_down") or Input.is_action_just_pressed("ui_down"):
		sel = posmod(sel + 1, n)
	if Input.is_action_just_pressed("ui_accept"):
		_press(sel)
	elif Input.is_action_just_pressed("roster"):
		_to_roster()
	elif Input.is_action_just_pressed("ui_cancel") or Input.is_action_just_pressed("pause"):
		close()


func _press(i: int) -> void:
	var ids := _ids()
	if i >= ids.size():
		_set_out()
	else:
		_toggle(ids[i])


func _toggle(id: String) -> void:
	var nm := short_of(id)
	if not Empire.recruits.has(id):
		_say("%s hasn't joined yet." % Empire.recruit(id)["name"])
	elif Empire.recruit(id).get("locked_party", false):
		_say("Ash always leads.")
	elif Empire.role_of(id) == "party":
		Empire.assign(id, "idle")
		_say("%s stays in Hollowmark." % nm)
	elif blocker(id) != "":
		_say("%s can't come: %s." % [nm, blocker(id)])
	elif Empire.party_ids().size() >= Empire.PARTY_SIZE:
		_say("The party is full. Leave someone behind first.")
	elif Empire.assign(id, "party"):
		_say("%s is in." % nm)


func _set_out() -> void:
	if mission_party().is_empty():
		_say("Nobody can go.")
		return
	visible = false
	closed_frame = Engine.get_process_frames()
	confirmed.emit(mission)


func _to_roster() -> void:
	visible = false
	closed_frame = Engine.get_process_frames()
	roster_requested.emit()


func _say(s: String) -> void:
	flash = s
	flash_t = 2.8


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		for i in _row_rects.size():
			if (_row_rects[i] as Rect2).has_point(event.position):
				sel = i
		if _go_rect.has_point(event.position):
			sel = _ids().size()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		for i in _row_rects.size():
			if (_row_rects[i] as Rect2).has_point(event.position):
				sel = i
				_press(i)
				return
		if _go_rect.has_point(event.position):
			_set_out()
		elif _back_rect.has_point(event.position):
			close()


# ---------------------------------------------------------------- drawing

func _text(pos: Vector2, s: String, fsize: int, col: Color) -> void:
	draw_string(font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, col)


func _wrap(pos: Vector2, s: String, width: float, fsize: int, col: Color) -> float:
	draw_multiline_string(font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, width, fsize, -1, col)
	return font.get_multiline_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, width, fsize).y


## What the row under a hero's name says.
func _status(id: String) -> Array:
	if not Empire.recruits.has(id):
		var how: Dictionary = Empire.recruit(id).get("join", {})
		var where := ""
		if how.get("type", "") == "rescue":
			where = "Rescue job on the Expeditions board (E): " + str(Empire.job(how.get("job", "")).get("name", "?"))
		return ["Not found yet. " + where, Color(0.45, 0.44, 0.47)]
	if Empire.recruit(id).get("locked_party", false):
		return ["Leads the party", GOLD]
	if Empire.role_of(id) == "party":
		return ["Coming along", Color("9fe07a")]
	var b := blocker(id)
	if b != "":
		return ["Busy: %s  (R: Roster)" % b, Color("ff9b8a")]
	return ["Ready, stays home unless picked", Color(0.75, 0.72, 0.7)]


func _draw() -> void:
	var vs := size
	draw_rect(Rect2(Vector2.ZERO, vs), Color(0.05, 0.04, 0.07, 0.985))
	_text(Vector2(LIST_X, 20), "Choose your party", 15, PAPER)
	var party := mission_party()
	_text(Vector2(LIST_X + 148, 19), "%s   %d/%d" % [mission.get("name", "Mission"), party.size(), Empire.PARTY_SIZE], 9, Color(0.75, 0.7, 0.55))

	var ids := _ids()
	_row_rects.clear()
	for i in ids.size():
		var id: String = ids[i]
		var r := Empire.recruit(id)
		var row := Rect2(LIST_X, 32 + i * ROW_H, LIST_W, ROW_H - 4)
		_row_rects.append(row)
		var on := i == sel
		var joined := Empire.recruits.has(id)
		draw_rect(row, Color(0.16, 0.13, 0.09) if on else Color(0.09, 0.08, 0.11))
		if on:
			draw_rect(row, GOLD, false, 1.0)
		var box := Rect2(row.position + Vector2(8, 11), Vector2(12, 12))
		var picked := id in party
		draw_rect(box, Color(0.05, 0.04, 0.07))
		draw_rect(box, GOLD if picked else Color(0.35, 0.32, 0.38), false, 1.0)
		if picked:
			draw_rect(box.grow(-3), GOLD)
		var name_col := (GOLD if on else Color("ece6da")) if joined else Color(0.45, 0.44, 0.47)
		_text(row.position + Vector2(28, 15), r["name"], 10, name_col)
		var nw := font.get_string_size(r["name"], HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
		_text(row.position + Vector2(34 + nw, 15), r["title"], 8, Color(0.6, 0.58, 0.6) if joined else Color(0.38, 0.37, 0.4))
		var st := _status(id)
		draw_string(font, row.position + Vector2(28, 28), st[0], HORIZONTAL_ALIGNMENT_LEFT, LIST_W - 34, 8, st[1])

	var gy := 32 + ids.size() * ROW_H + 4
	_go_rect = Rect2(LIST_X, gy, 150, 22)
	var go_on := sel == ids.size()
	draw_rect(_go_rect, Color(0.26, 0.2, 0.08) if go_on else Color(0.16, 0.13, 0.08))
	draw_rect(_go_rect, GOLD, false, 2.0 if go_on else 1.0)
	_text(_go_rect.position + Vector2(10, 15), "Set out with %d" % party.size(), 10, GOLD)
	_back_rect = Rect2(LIST_X + 158, gy, 70, 22)
	draw_rect(_back_rect, Color(0.1, 0.09, 0.12))
	draw_rect(_back_rect, Color(0.3, 0.27, 0.33), false, 1.0)
	_text(_back_rect.position + Vector2(12, 15), "Back", 9, Color(0.75, 0.72, 0.7))

	# Detail: how the highlighted hero fights
	var x := DETAIL_X
	var w := vs.x - DETAIL_X - 8
	if sel < ids.size():
		var id: String = ids[sel]
		var r := Empire.recruit(id)
		var hd := hero_data(id)
		_text(Vector2(x, 46), r["name"], 13, PAPER)
		_text(Vector2(x, 58), "Weapon: " + str(hd.get("weapon", "?")), 9, Color("e8c66a"))
		var y := 70.0
		for bar in [["HP", float(hd.get("hp", 40)), 70.0], ["Damage", float(hd.get("damage", 10)), 16.0],
				["Reach", float(hd.get("reach", 20)), 30.0], ["Speed", float(hd.get("speed", 68)), 80.0],
				["Recovery", float(hd.get("power_rate", 0.95)) * 100.0, 110.0]]:
			_text(Vector2(x, y + 7), bar[0], 8, Color(0.72, 0.7, 0.72))
			var bw := 120.0
			draw_rect(Rect2(x + 52, y, bw, 7), Color(0.18, 0.16, 0.2))
			draw_rect(Rect2(x + 52, y, bw * clampf(bar[1] / bar[2], 0.05, 1.0), 7), Color(0.85, 0.78, 0.6))
			_text(Vector2(x + 178, y + 7), str(int(bar[1])), 8, Color(0.85, 0.83, 0.78))
			y += 11
		var style: Dictionary = _load().get("styles", {}).get(hd.get("ai", "steady"), {})
		y += 6
		_text(Vector2(x, y + 8), "As an ally: " + str(style.get("name", "?")), 9, Color("8fa7e8"))
		y += _wrap(Vector2(x, y + 19), str(style.get("desc", "")), w, 8, Color(0.68, 0.66, 0.68)) + 14
		_wrap(Vector2(x, y + 9), str(hd.get("special", "")), w, 8, Color("cfe0b0"))
	else:
		_text(Vector2(x, 46), "Ready?", 13, PAPER)
		_wrap(Vector2(x, 62), "The clock stops while you are out. Whoever stays home keeps working their post.", w, 8, Color(0.68, 0.66, 0.68))

	# The party, standing in a row
	var py := vs.y - 76
	draw_rect(Rect2(x, py - 10, w, 64), Color(0.08, 0.07, 0.1))
	draw_rect(Rect2(x, py - 10, w, 64), Color(0.25, 0.22, 0.28), false, 1.0)
	for i in Empire.PARTY_SIZE:
		var cx := x + w * (i + 0.5) / Empire.PARTY_SIZE
		if i < party.size():
			_text(Vector2(cx - font.get_string_size(short_of(party[i]), HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x / 2.0, py + 50), short_of(party[i]), 8, Color("ece6da"))
		else:
			draw_string(font, Vector2(cx - 30, py + 24), "empty", HORIZONTAL_ALIGNMENT_CENTER, 60, 8, Color(0.35, 0.33, 0.38))

	var help := "Up/Down choose   Enter pick or drop   R roster   Esc back"
	_text(Vector2(DETAIL_X, vs.y - 4), help, 7, Color(0.5, 0.48, 0.52))
	if flash_t > 0.0:
		var a := clampf(flash_t / 0.4, 0.0, 1.0)
		_text(Vector2(LIST_X, vs.y - 6), flash, 9, Color(1, 0.9, 0.7, a))


func _update_dolls() -> void:
	var party := mission_party()
	var x := DETAIL_X
	var w := size.x - DETAIL_X - 8
	var py := size.y - 76
	var ids := _ids()
	var hl: String = ids[sel] if sel < ids.size() else ""
	for i in _dolls.size():
		var body: Sprite2D = _dolls[i][0]
		var outfit: Sprite2D = _dolls[i][1]
		var id: String = party[i] if i < party.size() else ""
		if id != _doll_ids[i]:
			_doll_ids[i] = id
			if id != "":
				var look: Dictionary = Empire.recruit(id).get("look", {})
				var cols := look_colors(look)
				var o: String = look.get("outfit", "archer")
				body.texture = Art.BODY
				body.material = Art.recolor_material("body", cols)
				outfit.texture = Art.OUTFITS.get(o, Art.OUTFITS["archer"])
				outfit.material = Art.recolor_material(o, cols)
		var pos := Vector2(x + w * (i + 0.5) / Empire.PARTY_SIZE, py + 18)
		# The highlighted hero walks on the spot; everyone else stands.
		var col := int(t * 8.0) % 4 if id == hl or hl == "" else 0
		for s in [body, outfit]:
			(s as Sprite2D).visible = id != ""
			(s as Sprite2D).position = pos
			(s as Sprite2D).frame = col


# ---------------------------------------------------------------- shared helpers

static func _load() -> Dictionary:
	if _data.is_empty():
		var f := FileAccess.open(HEROES_FILE, FileAccess.READ)
		if f:
			var d = JSON.parse_string(f.get_as_text())
			if d is Dictionary:
				_data = d
	return _data


static func hero_data(id: String) -> Dictionary:
	return _load().get("heroes", {}).get(id, {})


static func short_of(id: String) -> String:
	return str(hero_data(id).get("short", Empire.short_name(id)))


static func look_colors(look: Dictionary) -> Dictionary:
	var cols := {}
	for k in look.get("colors", {}):
		cols[k] = Color(look["colors"][k])
	return cols


## Why a joined field hero can't come right now ("" if they can).
static func blocker(id: String) -> String:
	if not Empire.recruits.has(id):
		return "not joined"
	if Empire.recruit(id).get("tier", "") != "field":
		return "not a fighter"
	var st: Dictionary = Empire.recruits[id]
	if int(st.get("injured", 0)) > 0:
		return "injured, %d days" % int(st["injured"])
	match st.get("role", "idle"):
		"idle", "party":
			return ""
		"expedition":
			return "on an expedition"
		"governor":
			return "governing " + str(Empire.territory().find(st.get("target", "")).get("name", "a province"))
		"staff":
			return "working the " + str(Empire.building(st.get("target", "")).get("name", "town"))
		"envoy":
			return "envoy to the " + str(Empire.faction(st.get("target", "")).get("short", "?"))
		_:
			return Empire.role_label(id).to_lower()


## Who actually goes out: Ash first, then the rest of the party who can fight today.
static func mission_party() -> Array:
	var out := []
	for id in Empire.party_ids():
		if blocker(id) == "" and Empire.recruit(id).get("tier", "") == "field":
			if Empire.recruit(id).get("locked_party", false):
				out.push_front(id)
			else:
				out.append(id)
	if out.is_empty() and Empire.recruits.has("ash"):
		out.append("ash")
	return out.slice(0, Empire.PARTY_SIZE)


## Dresses and arms a freshly made Hero as recruit `id`.
static func apply(h: Hero, id: String) -> void:
	var hd := hero_data(id)
	var look: Dictionary = Empire.recruit(id).get("look", {})
	h.hero_id = id
	h.hero_name = short_of(id)
	h.outfit = look.get("outfit", "archer")
	h.colors = look_colors(look)
	h.max_hp = int(hd.get("hp", 40))
	h.hp = h.max_hp
	h.move_speed = float(hd.get("speed", 68))
	h.base_damage = int(hd.get("damage", 10))
	h.power_rate = float(hd.get("power_rate", 0.95))
	h.reach = float(hd.get("reach", 20))
	h.arc = deg_to_rad(float(hd.get("arc", 70)))
	h.ai_style = str(hd.get("ai", "steady"))
	var heal: Dictionary = hd.get("heal", {})
	if not heal.is_empty():
		h.heal_every = float(heal.get("every", 6.0))
		h.heal_amount = int(heal.get("amount", 6))
		h.heal_range = float(heal.get("range", 80))
