extends Node
## Autoload "Controls": defines every input action in code (keyboard, gamepad; touch
## buttons press these same actions). Runs before any scene so menus and gameplay share it.


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_add_action("move_left", [KEY_A, KEY_LEFT], [JOY_BUTTON_DPAD_LEFT], JOY_AXIS_LEFT_X, -1.0)
	_add_action("move_right", [KEY_D, KEY_RIGHT], [JOY_BUTTON_DPAD_RIGHT], JOY_AXIS_LEFT_X, 1.0)
	_add_action("move_up", [KEY_W, KEY_UP], [JOY_BUTTON_DPAD_UP], JOY_AXIS_LEFT_Y, -1.0)
	_add_action("move_down", [KEY_S, KEY_DOWN], [JOY_BUTTON_DPAD_DOWN], JOY_AXIS_LEFT_Y, 1.0)
	_add_action("attack", [KEY_J, KEY_SPACE, KEY_Z], [JOY_BUTTON_A, JOY_BUTTON_X])
	_add_action("swap", [KEY_TAB, KEY_Q], [JOY_BUTTON_Y])
	_add_action("pause", [KEY_ESCAPE, KEY_P], [JOY_BUTTON_START])
	# Menus use Godot's ui_* actions; also let WASD, J and the stick drive them.
	_extend("ui_up", [KEY_W], JOY_AXIS_LEFT_Y, -1.0)
	_extend("ui_down", [KEY_S], JOY_AXIS_LEFT_Y, 1.0)
	_extend("ui_accept", [KEY_J, KEY_Z], -1, 0.0)
	_extend("ui_cancel", [KEY_X], -1, 0.0)


func _add_action(action: String, keys: Array, buttons: Array, axis := -1, axis_value := 0.0) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action, 0.3)
	_extend(action, keys, axis, axis_value)
	for b in buttons:
		var jb := InputEventJoypadButton.new()
		jb.button_index = b
		InputMap.action_add_event(action, jb)


func _extend(action: String, keys: Array, axis: int, axis_value: float) -> void:
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event(action, ev)
	if axis >= 0:
		var jm := InputEventJoypadMotion.new()
		jm.axis = axis
		jm.axis_value = axis_value
		InputMap.action_add_event(action, jm)
