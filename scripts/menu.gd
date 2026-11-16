class_name InkMenu
extends Control
## A small code-drawn list menu used by the title screen, pause and game over.
## Works with keyboard/gamepad (ui_up/ui_down/ui_accept/ui_cancel), mouse and touch.
## No ring menus: just a clear vertical list.

signal chosen(id: String)

var title := ""
var subtitle := ""
var items: Array = []  # each: {"id": String, "label": String, "enabled": bool, "note": String}
var selected := 0
var dim := 0.7
var title_size := 22
var top := 0.34  # fraction of screen height where the title (or first item) starts
var _rects: Array = []
var _t := 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	_select_first_enabled()


func setup(p_title: String, p_items: Array, p_subtitle := "") -> void:
	title = p_title
	subtitle = p_subtitle
	items = p_items
	selected = 0
	_select_first_enabled()
	queue_redraw()


func _select_first_enabled() -> void:
	for i in items.size():
		if items[i].get("enabled", true):
			selected = i
			return


func _move(step: int) -> void:
	if items.is_empty():
		return
	for n in items.size():
		selected = posmod(selected + step, items.size())
		if items[selected].get("enabled", true):
			break
	queue_redraw()


func _choose(i: int) -> void:
	if i >= 0 and i < items.size() and items[i].get("enabled", true):
		chosen.emit(items[i]["id"])


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event is InputEventMouseMotion:
		var i := _hit(event.position)
		if i >= 0 and items[i].get("enabled", true) and i != selected:
			selected = i
			queue_redraw()
		return
	var pick := -2  # -2 = nothing, -1 = cancel, >= 0 = item index
	if event.is_action_pressed("ui_down"):
		_move(1)
	elif event.is_action_pressed("ui_up"):
		_move(-1)
	elif event.is_action_pressed("ui_accept"):
		pick = selected
	elif event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause"):
		pick = -1
	elif (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT) \
			or (event is InputEventScreenTouch and event.pressed):
		var i := _hit(event.position)
		if i < 0:
			return
		selected = i
		pick = i
	else:
		return
	# Mark handled before acting: a choice may change scene and free this menu.
	get_viewport().set_input_as_handled()
	if pick == -1:
		chosen.emit("cancel")
	elif pick >= 0:
		_choose(pick)


func _hit(p: Vector2) -> int:
	for i in _rects.size():
		if (_rects[i] as Rect2).grow(4).has_point(p):
			return i
	return -1


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _centered(font: Font, y: float, s: String, fsize: int, col: Color) -> float:
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x
	var x := (get_viewport_rect().size.x - w) / 2.0
	draw_string_outline(font, Vector2(x, y), s, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, 4, Color(0, 0, 0, col.a * 0.9))
	draw_string(font, Vector2(x, y), s, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, col)
	return w


func _draw() -> void:
	var vs := get_viewport_rect().size
	var font := ThemeDB.fallback_font
	if dim > 0.0:
		draw_rect(Rect2(Vector2.ZERO, vs), Color(0.04, 0.03, 0.07, dim))
	var y := vs.y * top
	if title != "":
		_centered(font, y, title, title_size, Color("f3f1ea"))
		y += 20.0
	if subtitle != "":
		for line in subtitle.split("\n"):
			_centered(font, y, line, 9, Color(0.8, 0.78, 0.74))
			y += 13.0
	y += 16.0
	_rects.clear()
	for i in items.size():
		var it: Dictionary = items[i]
		var enabled: bool = it.get("enabled", true)
		var col := Color("ffd166") if i == selected else Color(0.92, 0.9, 0.86)
		if not enabled:
			col = Color(0.5, 0.5, 0.52)
		var label: String = it["label"]
		var w := _centered(font, y, label, 12, col)
		var r := Rect2((vs.x - w) / 2.0, y - 12.0, w, 16.0)
		_rects.append(r)
		if i == selected:
			# An ink-drop marker that bobs gently beside the chosen item.
			var mx := r.position.x - 10.0 + sin(_t * 5.0) * 1.5
			draw_circle(Vector2(mx, y - 4.0), 3.0, Color("ffd166"))
			draw_colored_polygon(PackedVector2Array([Vector2(mx - 2.6, y - 5.5), Vector2(mx + 2.6, y - 5.5), Vector2(mx, y - 10.5)]), Color("ffd166"))
		if not enabled and it.get("note", "") != "":
			draw_string(font, Vector2(r.end.x + 6.0, y - 1.0), it["note"], HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(0.55, 0.55, 0.58))
		y += 20.0
