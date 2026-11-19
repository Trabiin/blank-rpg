extends Control
## HUD for Hollowmark: day and clock, resources, what the attack button would do,
## talk lines, dawn toasts and Blank notices. Tap or click Roster and Menu on touch screens.

var hub  # hub.gd
var banter_text := ""
var banter_t := 0.0
var sign_text := ""
var toast_text := ""
var toast_warn := ""
var toast_t := 0.0
var notices: Array = []  # [text, warning, time left]
var help_t := 10.0
var font: Font


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	font = ThemeDB.fallback_font


func say(text: String, duration := 3.5) -> void:
	banter_text = text
	banter_t = duration


func toast(text: String, warn := "") -> void:
	toast_text = text
	toast_warn = warn
	toast_t = 3.5


## A one-off line from town (not from the Empire): shown in the alert tray, never kept (issue #22).
func notice(text: String, warning: bool) -> void:
	Alerts.inst().say(text, warning)


func _process(delta: float) -> void:
	banter_t = maxf(banter_t - delta, 0.0)
	toast_t = maxf(toast_t - delta, 0.0)
	help_t = maxf(help_t - delta, 0.0)
	for n in notices:
		n[2] -= delta
	notices = notices.filter(func(n): return n[2] > 0.0)
	queue_redraw()


func _vs() -> Vector2:
	return get_viewport_rect().size


func roster_rect() -> Rect2:
	return Rect2(_vs().x - 112, 6, 58, 16)


func buildings_rect() -> Rect2:
	return Rect2(_vs().x - 186, 6, 70, 16)


func menu_rect() -> Rect2:
	return Rect2(_vs().x - 50, 6, 44, 16)


## Taps and clicks on the two buttons. Touch does not emulate the mouse in this project.
func _input(event: InputEvent) -> void:
	if hub == null or get_tree().paused or hub.roster_view.visible or hub.buildings_view.visible \
			or hub.expedition_view.visible or hub.research_view.visible or hub.diplomacy_view.visible \
			or hub.bonds_view.visible or hub.scene_view.visible or hub.newcomers_view.visible:
		return
	var pos := Vector2.INF
	if event is InputEventScreenTouch and event.pressed:
		pos = event.position
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		pos = event.position
	if pos == Vector2.INF:
		return
	if roster_rect().has_point(pos):
		hub.roster_view.open()
		get_viewport().set_input_as_handled()
	elif buildings_rect().has_point(pos):
		hub.buildings_view.open()
		get_viewport().set_input_as_handled()
	elif menu_rect().has_point(pos):
		hub.open_menu()
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenTouch and not hub.target.is_empty() and _prompt_rect().has_point(pos):
		hub._use(hub.target)
		get_viewport().set_input_as_handled()


func _text(pos: Vector2, s: String, size := 10, col := Color.WHITE, outline := true) -> void:
	if outline:
		draw_string_outline(font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 3, Color(0, 0, 0, col.a * 0.85))
	draw_string(font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


func _centered(y: float, s: String, size := 10, col := Color.WHITE) -> void:
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	_text(Vector2((_vs().x - w) / 2.0, y), s, size, col)


func _button(r: Rect2, label: String) -> void:
	draw_rect(r, Color(0.07, 0.06, 0.09, 0.85))
	draw_rect(r, Color(0.45, 0.4, 0.3), false, 1.0)
	var w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x
	draw_string(font, r.position + Vector2((r.size.x - w) / 2.0, 11), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(0.85, 0.82, 0.76))


func _prompt_rect() -> Rect2:
	var vs := _vs()
	return Rect2(vs.x / 2.0 - 90, vs.y - 34, 180, 20)


func _draw() -> void:
	if hub == null:
		return
	if (hub.dialogue_box and hub.dialogue_box.visible) or (hub.chapter_card and hub.chapter_card.visible):
		return  # conversations and story cards have the screen to themselves
	var vs := _vs()
	# Top-left: where, when, how fast.
	draw_rect(Rect2(6, 6, 226, 30), Color(0.06, 0.05, 0.08, 0.78))
	_text(Vector2(12, 18), "Hollowmark", 10, Color("f3efe4"), false)
	var spd: int = Empire.SPEEDS[Empire.speed]
	var clock := "Day %d   %s   %s" % [Empire.day, Empire.clock_text(), "paused" if spd == 0 else "%dx" % spd]
	_text(Vector2(80, 18), clock, 9, Color(0.78, 0.75, 0.7) if spd > 0 else Color("ffb36b"), false)
	var x := 12.0
	for k in Empire.RESOURCES:
		var s := "%s %d" % [Empire.RES_NAMES[k], int(Empire.res[k])]
		var col := Color("ff9b8a") if k == "supplies" and Empire.hungry else Color(0.85, 0.83, 0.78)
		_text(Vector2(x, 31), s, 8, col, false)
		x += font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x + 14.0
	_button(roster_rect(), ("Roster  " + Prompts.key("roster")).strip_edges())
	_button(buildings_rect(), ("Buildings  " + Prompts.key("buildings")).strip_edges())
	_button(menu_rect(), "Menu")

	# What the attack button does right now.
	if not hub.target.is_empty():
		var key := "Tap" if hub.touch_active() else Prompts.key("attack")
		var r := _prompt_rect()
		draw_rect(r, Color(0.06, 0.05, 0.08, 0.8))
		draw_rect(r, Color("ffd166"), false, 1.0)
		var label := "%s:  %s" % [key, hub.target["label"]]
		var w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x
		draw_string(font, r.position + Vector2((r.size.x - w) / 2.0, 14), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color("ffd166"))

	if banter_t > 0.0:
		var a := clampf(banter_t / 0.4, 0.0, 1.0)
		var lines := _wrap_lines(banter_text, 420.0, 10)
		var y := vs.y - 70.0 - 13.0 * (lines.size() - 1)
		draw_rect(Rect2(vs.x / 2.0 - 220, y - 13, 440, 13.0 * lines.size() + 8), Color(0.05, 0.04, 0.07, 0.75 * a))
		for line in lines:
			_centered(y, line, 10, Color(1, 1, 1, a))
			y += 13.0
	if sign_text != "":
		var sl := sign_text.split("\n")
		var yy := vs.y * 0.3
		draw_rect(Rect2(vs.x / 2.0 - 120, yy - 14, 240, 16.0 * sl.size() + 8), Color(0.12, 0.09, 0.06, 0.85))
		for line in sl:
			_centered(yy, line, 10, Color("f3e3c3"))
			yy += 16.0
	if toast_t > 0.0:
		var a2 := clampf(toast_t / 0.5, 0.0, 1.0)
		_centered(64, toast_text, 13, Color(1, 0.95, 0.85, a2))
		if toast_warn != "":
			_centered(80, toast_warn, 9, Color(1, 0.6, 0.5, a2))
	# The story goal, alerts and notices are drawn by the alert tray (alert_tray.gd, issue #22).
	if help_t > 0.0 and not hub.touch_active():
		var a4 := clampf(help_t, 0.0, 1.0)
		_text(Vector2(vs.x - 236, 36), "Walk: WASD / arrows / stick", 8, Color(1, 1, 1, a4))
		_text(Vector2(vs.x - 236, 47), "Talk / use: " + Prompts.key("attack"), 8, Color(1, 1, 1, a4))
		if Prompts.pad():  # issue #23: the prompts follow the device in use
			_text(Vector2(vs.x - 236, 58), "Clock: %s / %s   Menu: %s" % [Prompts.key("clock_slower"), Prompts.key("clock_faster"), Prompts.key("pause")], 8, Color(1, 1, 1, a4))
			_text(Vector2(vs.x - 236, 69), "Roster %s  Buildings %s  Expeditions %s" % [Prompts.key("roster"), Prompts.key("buildings"), Prompts.key("expeditions")], 8, Color(1, 1, 1, a4))
			_text(Vector2(vs.x - 236, 80), "Everything else: the Menu", 8, Color(1, 1, 1, a4))
		else:
			_text(Vector2(vs.x - 236, 58), "Clock: 1-4   Menu: Esc", 8, Color(1, 1, 1, a4))
			_text(Vector2(vs.x - 236, 69), "Roster R  Buildings B  Research T  Factions F  Bonds H", 8, Color(1, 1, 1, a4))
			_text(Vector2(vs.x - 236, 80), "Newcomers N", 8, Color(1, 1, 1, a4))


func _wrap_lines(s: String, width: float, size: int) -> PackedStringArray:
	var out := PackedStringArray()
	var cur := ""
	for word in s.split(" "):
		var test := word if cur == "" else cur + " " + word
		if font.get_string_size(test, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > width and cur != "":
			out.append(cur)
			cur = word
		else:
			cur = test
	if cur != "":
		out.append(cur)
	return out
