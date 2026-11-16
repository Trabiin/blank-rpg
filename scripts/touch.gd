extends Control
## On-screen controls for touch devices: a floating stick on the left half,
## Attack and Swap buttons on the right. They feed the normal input actions.

var stick_index := -1
var stick_origin := Vector2.ZERO
var stick_pos := Vector2.ZERO
var button_touches := {}  # touch index -> action name
const STICK_R := 34.0
const BTN_ATTACK_R := 30.0
const BTN_SWAP_R := 20.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = DisplayServer.is_touchscreen_available()


func _attack_center() -> Vector2:
	var vs := get_viewport_rect().size
	return Vector2(vs.x - 50, vs.y - 70)


func _swap_center() -> Vector2:
	var vs := get_viewport_rect().size
	return Vector2(vs.x - 110, vs.y - 40)


func _input(event: InputEvent) -> void:
	if event is InputEventKey or event is InputEventJoypadButton:
		if visible:
			_release_all()
			visible = false
		return
	if event is InputEventScreenTouch:
		visible = true
		var pos: Vector2 = event.position
		if event.pressed:
			if pos.distance_to(_attack_center()) < BTN_ATTACK_R + 10.0:
				button_touches[event.index] = "attack"
				Input.action_press("attack")
			elif pos.distance_to(_swap_center()) < BTN_SWAP_R + 10.0:
				button_touches[event.index] = "swap"
				Input.action_press("swap")
			elif pos.x < get_viewport_rect().size.x * 0.5 and stick_index == -1:
				stick_index = event.index
				stick_origin = pos
				stick_pos = pos
		else:
			if button_touches.has(event.index):
				Input.action_release(button_touches[event.index])
				button_touches.erase(event.index)
			if event.index == stick_index:
				stick_index = -1
				_apply_stick(Vector2.ZERO)
		queue_redraw()
	elif event is InputEventScreenDrag and event.index == stick_index:
		stick_pos = event.position
		var v: Vector2 = (stick_pos - stick_origin) / STICK_R
		if v.length() > 1.0:
			v = v.normalized()
		_apply_stick(v)
		queue_redraw()


func _apply_stick(v: Vector2) -> void:
	_set_axis("move_left", "move_right", v.x)
	_set_axis("move_up", "move_down", v.y)


func _set_axis(neg: String, pos: String, value: float) -> void:
	if value < -0.15:
		Input.action_press(neg, -value)
		Input.action_release(pos)
	elif value > 0.15:
		Input.action_press(pos, value)
		Input.action_release(neg)
	else:
		Input.action_release(neg)
		Input.action_release(pos)


func _release_all() -> void:
	for a in button_touches.values():
		Input.action_release(a)
	button_touches.clear()
	stick_index = -1
	_apply_stick(Vector2.ZERO)


func _draw() -> void:
	var a := _attack_center()
	draw_circle(a, BTN_ATTACK_R, Color(1, 1, 1, 0.18 if not button_touches.values().has("attack") else 0.4))
	draw_arc(a, BTN_ATTACK_R, 0, TAU, 32, Color(1, 1, 1, 0.5), 1.5)
	draw_string(ThemeDB.fallback_font, a + Vector2(-17, 4), "ATTACK", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(1, 1, 1, 0.8))
	var s := _swap_center()
	draw_circle(s, BTN_SWAP_R, Color(1, 1, 1, 0.18 if not button_touches.values().has("swap") else 0.4))
	draw_arc(s, BTN_SWAP_R, 0, TAU, 32, Color(1, 1, 1, 0.5), 1.5)
	draw_string(ThemeDB.fallback_font, s + Vector2(-12, 4), "SWAP", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(1, 1, 1, 0.8))
	if stick_index != -1:
		draw_circle(stick_origin, STICK_R, Color(1, 1, 1, 0.12))
		draw_arc(stick_origin, STICK_R, 0, TAU, 32, Color(1, 1, 1, 0.4), 1.5)
		var knob := stick_origin + (stick_pos - stick_origin).limit_length(STICK_R)
		draw_circle(knob, 12.0, Color(1, 1, 1, 0.35))
	else:
		var vs := get_viewport_rect().size
		draw_string(ThemeDB.fallback_font, Vector2(24, vs.y - 50), "drag here to move", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(1, 1, 1, 0.35))
