class_name OptionsView
extends Control
## The options screen (issue #14). Opened from the title screen, every pause menu and the quick
## menu's Options tab with OptionsView.popup(scene). Values are kept by Settings and saved as soon
## as they change, so there is no Apply button.
##
## Keyboard: Up/Down pick a row, Left/Right change it, J/Enter also steps it (or opens Controls),
##   X/Esc goes back. Gamepad: d-pad/stick, A, B. Mouse/touch: tap the < > arrows or a row.
## Controls page: pick an action, then press the new key or gamepad button (Esc or Start cancels).

signal closed

const GOLD := Color("ffd166")
const TEXT := Color(0.92, 0.9, 0.86)
const DIM := Color(0.55, 0.55, 0.58)
const SOFT := Color(0.68, 0.66, 0.64)
const GOOD := Color("9fe07a")
const PANEL := Color(0.06, 0.05, 0.09, 0.98)
const W := 440.0
const ROW_H := 22.0
const ROW_H_CONTROLS := 17.0  # the Controls page has more rows

var page := "main"  # "main" or "controls"
var sel := 0
var listening := ""  # action id waiting for a new key/button
var note := ""
var note_t := 0.0
var _listen_frame := -1
var _opened_frame := -1
var _t := 0.0
var _rows: Array = []  # {"id", "label", "value", "detail", "kind": "cycle"|"slider"|"open"|"bind"|"button"}
var _row_rects: Array = []
var _left_rects: Array = []
var _right_rects: Array = []
var _panel := Rect2()


## Opens the options over whatever scene is running, on its own top layer. The returned view
## emits `closed` and frees itself when the player backs out.
static func popup(host: Node) -> OptionsView:
	var layer := CanvasLayer.new()
	layer.layer = 20
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	host.add_child(layer)
	var view := OptionsView.new()
	layer.add_child(view)
	view.closed.connect(layer.queue_free)
	view.open()
	return view


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS


func open() -> void:
	Settings.load_settings()
	visible = true
	page = "main"
	sel = 0
	listening = ""
	_opened_frame = Engine.get_process_frames()
	_rebuild()


func close() -> void:
	visible = false
	listening = ""
	closed.emit()


# ---------------------------------------------------------------- rows

func _rebuild() -> void:
	_rows = []
	if page == "main":
		_rows.append({"id": "battle_speed", "kind": "cycle", "label": "Battle speed", "value": Settings.battle_speed_name(),
			"detail": "How fast fights run. The Command clock is not affected."})
		_rows.append({"id": "difficulty", "kind": "cycle", "label": "Difficulty", "value": Settings.DIFFICULTIES[Settings.difficulty],
			"detail": Settings.DIFFICULTY_INFO[Settings.difficulty] + "  Change it any time."})
		_rows.append({"id": "text_speed", "kind": "cycle", "label": "Text speed", "value": Dialogue.speed_name(),
			"detail": "Typewriter speed in conversations (Tab also changes it there)."})
		_rows.append({"id": "shake", "kind": "cycle", "label": "Screen shake", "value": Settings.SHAKES[Settings.shake_i],
			"detail": "Camera shake on heavy hits and techs."})
		for bus in Settings.BUSES:
			var label: String = {"Master": "Master volume", "Music": "Music volume", "SFX": "Sound effects volume"}[bus]
			_rows.append({"id": "vol:" + bus, "kind": "slider", "label": label, "value": "%d%%" % Settings.volumes[bus],
				"level": Settings.volumes[bus], "detail": ""})
		_rows.append({"id": "controls", "kind": "open", "label": "Controls", "value": "remap keys and buttons",
			"detail": ""})
		_rows.append({"id": "back", "kind": "button", "label": "Back", "value": "", "detail": ""})
	else:
		for a in Settings.REMAPPABLE:
			var id: String = a[0]
			if not InputMap.has_action(id):
				continue
			_rows.append({"id": id, "kind": "bind", "label": a[1], "key": Settings.key_name(id), "pad": Settings.pad_name(id)})
		_rows.append({"id": "reset", "kind": "button", "label": "Reset to defaults", "value": "", "detail": ""})
		_rows.append({"id": "controls_back", "kind": "button", "label": "Back", "value": "", "detail": ""})
	sel = clampi(sel, 0, _rows.size() - 1)


## Left/right (step -1/+1) on a value row.
func _step(i: int, step: int) -> void:
	if i < 0 or i >= _rows.size():
		return
	var id: String = _rows[i]["id"]
	match id:
		"battle_speed":
			Settings.battle_speed_i = clampi(Settings.battle_speed_i + step, 0, Settings.BATTLE_SPEEDS.size() - 1)
			Settings.refresh_time_scale()
		"difficulty":
			Settings.difficulty = clampi(Settings.difficulty + step, 0, Settings.DIFFICULTIES.size() - 1)
		"text_speed":
			_set_text_speed(clampi(Dialogue.speed_index() + step, 0, Dialogue.SPEEDS.size() - 1))
		"shake":
			Settings.shake_i = clampi(Settings.shake_i + step, 0, Settings.SHAKES.size() - 1)
		_:
			if id.begins_with("vol:"):
				var bus := id.substr(4)
				Settings.volumes[bus] = clampi(int(Settings.volumes[bus]) + step * 10, 0, 100)
				Settings.apply_audio()
			else:
				return
	Settings.save()
	_rebuild()


## Text speed stays where Dialogue has always kept it (user://settings.cfg, [dialogue]).
func _set_text_speed(i: int) -> void:
	Dialogue._speed = i
	var cfg := ConfigFile.new()
	cfg.load(Settings.PATH)
	cfg.set_value("dialogue", "text_speed", i)
	cfg.save(Settings.PATH)


## Accept on a row.
func _activate(i: int) -> void:
	if i < 0 or i >= _rows.size():
		return
	sel = i
	var r: Dictionary = _rows[i]
	match r["kind"]:
		"cycle":
			# Step forward, wrapping round, so one button is enough on touch and gamepad.
			var before := _value_index(r["id"])
			_step(i, 1)
			if _value_index(r["id"]) == before:
				_step(i, -999)
		"slider":
			_step(i, 1)
			if int(_rows[i].get("level", 0)) == int(r.get("level", 0)):
				_step(i, -10)
		"open":
			page = "controls"
			sel = 0
			_rebuild()
		"bind":
			listening = r["id"]
			_listen_frame = Engine.get_process_frames()
		"button":
			match r["id"]:
				"back":
					close()
				"controls_back":
					_back()
				"reset":
					Settings.reset_bindings()
					_say("Controls are back to the defaults.")
					_rebuild()


func _value_index(id: String) -> int:
	match id:
		"battle_speed": return Settings.battle_speed_i
		"difficulty": return Settings.difficulty
		"text_speed": return Dialogue.speed_index()
		"shake": return Settings.shake_i
	return -1


func _back() -> void:
	if listening != "":
		listening = ""
	elif page == "controls":
		page = "main"
		sel = 7
		_rebuild()
	else:
		close()


func _say(s: String) -> void:
	note = s
	note_t = 3.0


# ---------------------------------------------------------------- input

func _input(event: InputEvent) -> void:
	if not visible:
		return
	if listening != "":
		_listen(event)
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion:
		for i in _row_rects.size():
			if (_row_rects[i] as Rect2).has_point(event.position):
				sel = i
		return
	var tap: bool = (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT) \
		or (event is InputEventScreenTouch and event.pressed)
	if tap:
		_tap(event.position)
	elif event is InputEventScreenTouch or event is InputEventMouseButton or event is InputEventScreenDrag:
		pass
	elif Engine.get_process_frames() == _opened_frame:
		pass  # the press that opened us
	elif event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause"):
		_back()
	elif event.is_action_pressed("ui_down", true):
		sel = posmod(sel + 1, _rows.size())
	elif event.is_action_pressed("ui_up", true):
		sel = posmod(sel - 1, _rows.size())
	elif event.is_action_pressed("ui_left", true) or _key(event, KEY_A):
		_step(sel, -1)
	elif event.is_action_pressed("ui_right", true) or _key(event, KEY_D):
		_step(sel, 1)
	elif event.is_action_pressed("ui_accept"):
		_activate(sel)
	if is_inside_tree():
		get_viewport().set_input_as_handled()  # nothing reaches the menu or the game underneath


func _key(event: InputEvent, k: Key) -> bool:
	return event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == k


func _listen(event: InputEvent) -> void:
	if Engine.get_process_frames() == _listen_frame:
		return
	var id := listening
	var swapped := ""
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_ESCAPE:
			listening = ""
			return
		swapped = Settings.bind_key(id, int(event.physical_keycode))
		_say("%s: %s" % [Settings.action_label(id), Settings.key_name(id)])
	elif event is InputEventJoypadButton and event.pressed:
		if event.button_index == JOY_BUTTON_START:
			listening = ""
			return
		swapped = Settings.bind_pad(id, {"b": int(event.button_index)})
		_say("%s: %s" % [Settings.action_label(id), Settings.pad_name(id)])
	elif event is InputEventJoypadMotion and absf(event.axis_value) > 0.6:
		swapped = Settings.bind_pad(id, {"a": int(event.axis), "v": signf(event.axis_value)})
		_say("%s: %s" % [Settings.action_label(id), Settings.pad_name(id)])
	elif (event is InputEventMouseButton or event is InputEventScreenTouch) and event.pressed:
		listening = ""  # a tap cancels
		return
	else:
		return
	if swapped != "":
		_say("%s  (swapped with %s)" % [note, Settings.action_label(swapped)])
	listening = ""
	_rebuild()


func _tap(p: Vector2) -> void:
	for i in _row_rects.size():
		if i < _left_rects.size() and (_left_rects[i] as Rect2).has_point(p):
			sel = i
			_step(i, -1)
			return
		if i < _right_rects.size() and (_right_rects[i] as Rect2).has_point(p):
			sel = i
			_step(i, 1)
			return
	for i in _row_rects.size():
		if (_row_rects[i] as Rect2).has_point(p):
			_activate(i)
			return
	if not _panel.grow(6).has_point(p):
		_back()


# ---------------------------------------------------------------- drawing

func _process(delta: float) -> void:
	if not visible:
		return
	var real := delta / maxf(Engine.time_scale, 0.01)
	_t += real
	note_t = maxf(note_t - real, 0.0)
	queue_redraw()


func _str(font: Font, pos: Vector2, s: String, fsize: int, col: Color) -> void:
	draw_string(font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, col)


func _str_w(font: Font, s: String, fsize: int) -> float:
	return font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x


func _marker(x: float, y: float) -> void:
	var mx := x + sin(_t * 5.0) * 1.5
	draw_circle(Vector2(mx, y - 4.0), 3.0, GOLD)
	draw_colored_polygon(PackedVector2Array([Vector2(mx - 2.6, y - 5.5), Vector2(mx + 2.6, y - 5.5), Vector2(mx, y - 10.5)]), GOLD)


func _draw() -> void:
	var vs := get_viewport_rect().size
	var font := ThemeDB.fallback_font
	draw_rect(Rect2(Vector2.ZERO, vs), Color(0.04, 0.03, 0.07, 0.75))
	var w := minf(W, vs.x - 16.0)
	var row_h := ROW_H if page == "main" else ROW_H_CONTROLS
	var h := 40.0 + _rows.size() * row_h + 40.0
	_panel = Rect2((vs.x - w) / 2.0, maxf(6.0, (vs.y - h) / 2.0), w, minf(h, vs.y - 12.0))
	draw_rect(_panel, PANEL)
	draw_rect(_panel, Color(1, 1, 1, 0.18), false, 1.0)
	var x0 := _panel.position.x + 24.0
	var x1 := _panel.end.x - 14.0
	_str(font, Vector2(x0 - 8, _panel.position.y + 22), "Options" if page == "main" else "Controls", 16, Color("f3f1ea"))
	if page == "controls":
		_str(font, Vector2(x1 - 168, _panel.position.y + 22), "Keyboard", 9, SOFT)
		_str(font, Vector2(x1 - 70, _panel.position.y + 22), "Gamepad", 9, SOFT)

	_row_rects.clear()
	_left_rects.clear()
	_right_rects.clear()
	var y := _panel.position.y + 40.0
	for i in _rows.size():
		var r: Dictionary = _rows[i]
		var rr := Rect2(_panel.position.x + 4, y, w - 8, row_h - 2)
		_row_rects.append(rr)
		var on_row := i == sel
		if on_row:
			draw_rect(rr, Color(1, 1, 1, 0.06))
			_marker(x0 - 12.0, y + 14)
		var col := GOLD if on_row else TEXT
		_str(font, Vector2(x0, y + 14), str(r["label"]), 11, col)
		match r["kind"]:
			"cycle", "slider":
				var vx := x1 - 150.0
				var lr := Rect2(vx - 4, y, 18, row_h - 2)
				var rgt := Rect2(x1 - 14, y, 18, row_h - 2)
				_left_rects.append(lr)
				_right_rects.append(rgt)
				_str(font, Vector2(vx, y + 14), "<", 11, col)
				_str(font, Vector2(x1 - 8, y + 14), ">", 11, col)
				if r["kind"] == "slider":
					var bar := Rect2(vx + 14, y + 7, 92, 6)
					draw_rect(bar, Color(1, 1, 1, 0.12))
					draw_rect(Rect2(bar.position, Vector2(bar.size.x * float(r["level"]) / 100.0, bar.size.y)), col)
					_str(font, Vector2(vx + 110, y + 14), str(r["value"]), 9, col)
				else:
					var vs_text := str(r["value"])
					var tw := _str_w(font, vs_text, 10)
					_str(font, Vector2(vx + 70 - tw / 2.0, y + 14), vs_text, 10, col)
			"open":
				_left_rects.append(Rect2())
				_right_rects.append(Rect2())
				var t := str(r["value"]) + "  >"
				_str(font, Vector2(x1 - _str_w(font, t, 9), y + 14), t, 9, col if on_row else SOFT)
			"bind":
				_left_rects.append(Rect2())
				_right_rects.append(Rect2())
				var waiting: bool = listening == r["id"]
				var kcol := col
				if waiting:
					var blink := Color(GOOD, 0.55 + 0.45 * sin(_t * 8.0))
					_str(font, Vector2(x1 - 168, y + 14), "press a key or button...", 9, blink)
				else:
					_str(font, Vector2(x1 - 168, y + 14), str(r["key"]), 10, kcol)
					_str(font, Vector2(x1 - 70, y + 14), str(r["pad"]), 10, kcol)
			_:
				_left_rects.append(Rect2())
				_right_rects.append(Rect2())
		y += row_h

	# Footer: the highlighted row's explanation, a result, or how to drive it.
	var fy := _panel.end.y - 22.0
	var detail := ""
	if sel < _rows.size():
		detail = str(_rows[sel].get("detail", ""))
	if note_t > 0.0:
		_str(font, Vector2(x0 - 8, fy), note, 9, GOOD)
	elif listening != "":
		_str(font, Vector2(x0 - 8, fy), "Press the new key or gamepad input for %s.  Esc / Start: cancel." % Settings.action_label(listening), 9, SOFT)
	elif detail != "":
		_str(font, Vector2(x0 - 8, fy), detail, 9, SOFT)
	var hint := "Up/Down: pick    Left/Right: change    X/B: back" if page == "main" \
		else "J/A: rebind (keyboard key or gamepad input)    X/B: back"
	_str(font, Vector2(x0 - 8, fy + 13), hint, 8, DIM)
