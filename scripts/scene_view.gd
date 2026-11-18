extends Control
## Bond scenes, visual-novel style: a big character card on the left, a text box along the bottom,
## and (usually) one choice for Ash, who never speaks: the choices are what Ash does.
##
## Placeholder art: the card is a bust drawn in code from the character's paper-doll colours, until
## the AI portraits (#12) replace it. Enter / J / click / tap moves on (finishing the line first if it
## is still typing); Up/Down pick a choice; Esc skips ahead to the choice (or closes a replay).
## The first time through, finishing the scene raises the bond rank (Empire.finish_bond_scene).

signal finished(id: String, rank: int)

const GOLD := Color("ffd166")
const TEXT := Color("ece6da")
const SOFT := Color(0.66, 0.64, 0.66)
const CHARS_PER_SEC := 70.0

var id := ""
var rank := 0
var replay := false
var closed_frame := -1
var opened_frame := -1
var _lines: Array = []  # [speaker, text] still to show; the current one is _lines[_at]
var _at := 0
var _shown := 0.0  # characters revealed of the current line
var _stage := "lines"  # lines -> choice -> reply -> done
var _choice := 0
var _picked := -1
var _choice_rects: Array = []
var _outro := ""  # the closing card: new rank and perk
var font: Font


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	font = ThemeDB.fallback_font


## Play the scene for this person and rank. replay = already seen (no bond changes).
func play(who: String, r: int, is_replay := false) -> void:
	id = who
	rank = r
	replay = is_replay
	var sc := Empire.bond_scene(id, rank)
	if sc.is_empty():
		return
	position = Vector2.ZERO
	size = get_viewport_rect().size
	visible = true
	opened_frame = Engine.get_process_frames()
	_lines = sc["lines"].duplicate()
	_at = 0
	_shown = 0.0
	_stage = "lines"
	_choice = 0
	_picked = -1
	_outro = ""


func _scene() -> Dictionary:
	return Empire.bond_scene(id, rank)


func _close() -> void:
	visible = false
	closed_frame = Engine.get_process_frames()
	finished.emit(id, rank)


func _current() -> Array:
	return _lines[_at] if _at < _lines.size() else ["", ""]


func _typing() -> bool:
	return _stage in ["lines", "reply"] and _shown < float(String(_current()[1]).length())


func _advance() -> void:
	match _stage:
		"lines", "reply":
			if _typing():
				_shown = 99999.0
				return
			_at += 1
			_shown = 0.0
			if _at < _lines.size():
				return
			if _stage == "lines" and not _scene().get("choice", []).is_empty():
				_stage = "choice"
			else:
				_finish()
		"choice":
			_pick(_choice)
		"done":
			_close()


func _pick(i: int) -> void:
	var opts: Array = _scene().get("choice", [])
	if i < 0 or i >= opts.size():
		return
	_picked = i
	_lines = opts[i].get("reply", []).duplicate() + _scene().get("end", []).duplicate()
	_at = 0
	_shown = 0.0
	_stage = "reply"
	if _lines.is_empty():
		_finish()


func _finish() -> void:
	_stage = "done"
	if replay:
		_outro = "Memory: %s" % _scene().get("title", "")
		return
	var perk := Empire.finish_bond_scene(id, rank, _picked)
	_outro = "%s is now %s.  Bond rank %d." % [Empire.short_name(id), Empire.bond_rank_name(Empire.bond_rank(id)), Empire.bond_rank(id)]
	if not perk.is_empty():
		_outro += "\nPerk unlocked: %s. %s" % [perk["name"], perk["desc"]]
	if rank == 4 and Empire.personal_job(id) != "":
		_outro += "\nPersonal job on the Guildhall board: %s." % Empire.job(Empire.personal_job(id)).get("name", "?")


func _process(delta: float) -> void:
	if not visible:
		return
	if _stage in ["lines", "reply"]:
		_shown += delta * CHARS_PER_SEC
	queue_redraw()
	if Engine.get_process_frames() == opened_frame:
		return
	var opts: Array = _scene().get("choice", [])
	if _stage == "choice":
		if Input.is_action_just_pressed("move_up") or Input.is_action_just_pressed("ui_up"):
			_choice = posmod(_choice - 1, opts.size())
		elif Input.is_action_just_pressed("move_down") or Input.is_action_just_pressed("ui_down"):
			_choice = posmod(_choice + 1, opts.size())
	if Input.is_action_just_pressed("ui_accept") or Input.is_action_just_pressed("attack"):
		_advance()
	elif Input.is_action_just_pressed("ui_cancel") or Input.is_action_just_pressed("pause"):
		if replay or _stage == "done":
			_close()
		elif _stage == "lines":  # skip ahead to the choice
			_at = _lines.size() - 1
			_shown = 99999.0
			_advance()
		elif _stage == "reply":
			_at = _lines.size() - 1
			_shown = 99999.0
			_advance()


func _gui_input(event: InputEvent) -> void:
	var pos := Vector2.INF
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		pos = event.position
	elif event is InputEventScreenTouch and event.pressed:
		pos = event.position
	elif event is InputEventMouseMotion and _stage == "choice":
		for i in _choice_rects.size():
			if (_choice_rects[i] as Rect2).has_point(event.position):
				_choice = i
		return
	if pos == Vector2.INF or Engine.get_process_frames() == opened_frame:
		return
	if _stage == "choice":
		for i in _choice_rects.size():
			if (_choice_rects[i] as Rect2).has_point(pos):
				_pick(i)
				return
		return
	_advance()


# ---------------------------------------------------------------- drawing

func _col(look: Dictionary, keys: Array, fallback: String) -> Color:
	var cols: Dictionary = look.get("colors", {})
	for k in keys:
		if cols.has(k):
			return Color(cols[k])
	return Color(fallback)


## A big head-and-shoulders card in the character's colours. Placeholder for the AI portraits.
func _draw_card(r: Rect2, who: String) -> void:
	var info := Empire.bond_info(who)
	var accent := Color(info.get("color", "c9c3b6"))
	draw_rect(r, accent.darkened(0.78))
	for i in 12:  # soft vertical wash
		var t := float(i) / 12.0
		draw_rect(Rect2(r.position.x, r.position.y + r.size.y * t, r.size.x, r.size.y / 12.0 + 1), Color(accent, 0.05 + 0.1 * t))
	var look: Dictionary = Empire.recruit(who).get("look", {})
	var skin := _col(look, ["skin"], "d9a07a")
	var cloth := _col(look, ["cloth", "metal"], "5a4a6a")
	var trim := _col(look, ["trim", "accent", "metal"], "c9c3b6")
	var hair := _col(look, ["leather", "boots"], "3a2c22")
	var c := Vector2(r.get_center().x, r.end.y)
	# shoulders and chest
	var w := r.size.x * 0.86
	draw_colored_polygon(PackedVector2Array([c + Vector2(-w / 2, 0), c + Vector2(-w / 2 + 8, -r.size.y * 0.3),
		c + Vector2(-w * 0.18, -r.size.y * 0.36), c + Vector2(w * 0.18, -r.size.y * 0.36),
		c + Vector2(w / 2 - 8, -r.size.y * 0.3), c + Vector2(w / 2, 0)]), cloth)
	draw_colored_polygon(PackedVector2Array([c + Vector2(-w * 0.12, -r.size.y * 0.36), c + Vector2(w * 0.12, -r.size.y * 0.36),
		c + Vector2(0, -r.size.y * 0.22)]), skin.darkened(0.15))
	draw_line(c + Vector2(-w * 0.18, -r.size.y * 0.36), c + Vector2(0, -r.size.y * 0.2), trim, 2.0)
	draw_line(c + Vector2(w * 0.18, -r.size.y * 0.36), c + Vector2(0, -r.size.y * 0.2), trim, 2.0)
	# neck and head
	var head := c + Vector2(0, -r.size.y * 0.56)
	var hr := r.size.x * 0.2
	draw_rect(Rect2(head.x - hr * 0.35, head.y + hr * 0.6, hr * 0.7, r.size.y * 0.1), skin.darkened(0.1))
	draw_circle(head + Vector2(0, -hr * 0.12), hr * 1.08, hair)
	draw_circle(head + Vector2(0, hr * 0.1), hr, skin)
	draw_rect(Rect2(head.x - hr, head.y - hr * 0.9, hr * 2, hr * 0.55), hair)
	draw_circle(head + Vector2(-hr * 0.38, hr * 0.12), 2.0, Color(0.1, 0.08, 0.1))
	draw_circle(head + Vector2(hr * 0.38, hr * 0.12), 2.0, Color(0.1, 0.08, 0.1))
	draw_rect(r, accent.darkened(0.2), false, 2.0)
	var name_s: String = Empire.recruit(who).get("name", who)
	var nw := font.get_string_size(name_s, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
	draw_rect(Rect2(r.position.x, r.end.y - 18, r.size.x, 18), Color(0, 0, 0, 0.55))
	draw_string(font, Vector2(r.get_center().x - nw / 2, r.end.y - 6), name_s, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, TEXT)


func _draw() -> void:
	var vs := size
	draw_rect(Rect2(Vector2.ZERO, vs), Color(0.03, 0.025, 0.05, 0.94))
	var sc := _scene()
	if sc.is_empty():
		return
	# Header: whose scene, which rank
	var head := "%s  ·  Bond rank %d: %s%s" % [Empire.short_name(id), rank, sc.get("title", ""), "   (memory)" if replay else ""]
	draw_string(font, Vector2(12, 18), head, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(Empire.bond_info(id).get("color", "c9c3b6")).lightened(0.2))
	var card := Rect2(24, 30, 150, vs.y - 30 - 102)
	_draw_card(card, id)

	var box := Rect2(12, vs.y - 96, vs.x - 24, 86)
	draw_rect(box, Color(0.07, 0.06, 0.09, 0.97))
	draw_rect(box, Color(0.45, 0.4, 0.3), false, 1.0)
	_choice_rects.clear()
	match _stage:
		"lines", "reply":
			var cur := _current()
			var speaker: String = cur[0]
			var text: String = cur[1]
			var shown := text.substr(0, int(_shown))
			var tx := box.position.x + 12
			var ty := box.position.y + 20
			if speaker != "":
				var nm := Empire.short_name(speaker)
				var nw := font.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
				draw_rect(Rect2(box.position.x + 8, box.position.y - 9, nw + 14, 16), Color(0.14, 0.11, 0.08))
				draw_rect(Rect2(box.position.x + 8, box.position.y - 9, nw + 14, 16), GOLD, false, 1.0)
				draw_string(font, Vector2(box.position.x + 15, box.position.y + 3), nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, GOLD)
				ty += 4
			draw_multiline_string(font, Vector2(tx, ty), shown, HORIZONTAL_ALIGNMENT_LEFT, box.size.x - 24, 11, -1,
				TEXT if speaker != "" else SOFT)
			if not _typing() and int(Time.get_ticks_msec() / 400) % 2 == 0:
				var tip := box.end - Vector2(14, 10)
				draw_colored_polygon(PackedVector2Array([tip + Vector2(-4, -4), tip + Vector2(4, -4), tip]), GOLD)
		"choice":
			draw_string(font, box.position + Vector2(12, 14), "Ash...", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, SOFT)
			var opts: Array = sc.get("choice", [])
			var y := box.position.y + 20
			for i in opts.size():
				var rr := Rect2(box.position.x + 10, y, box.size.x - 20, 17)
				_choice_rects.append(rr)
				var on := i == _choice
				draw_rect(rr, Color(0.17, 0.14, 0.09) if on else Color(0.1, 0.09, 0.12))
				if on:
					draw_rect(rr, GOLD, false, 1.0)
				draw_string(font, rr.position + Vector2(10, 12), opts[i]["label"], HORIZONTAL_ALIGNMENT_LEFT, rr.size.x - 20, 10, GOLD if on else TEXT)
				y += 20
		"done":
			draw_multiline_string(font, box.position + Vector2(12, 22), _outro, HORIZONTAL_ALIGNMENT_LEFT, box.size.x - 24, 10, -1, Color("9fd18b"))
	var hint := "Enter / tap: next    Esc: skip" if _stage != "choice" else "Up/Down choose    Enter / tap: pick"
	if _stage == "done":
		hint = "Enter / tap: close"
	draw_string(font, Vector2(vs.x - font.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 7).x - 14, vs.y - 3), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 7, Color(0.5, 0.48, 0.52))
