class_name DisplayWatch
extends Node
## Lives on the root next to the autoloads (DisplaySettings._ensure_watch adds it), so it outlives
## scene changes. Handles Alt+Enter / F11 for fullscreen and the window gaining or losing focus
## (issue #145). Runs while the tree is paused, since that is exactly when it has to wake things up.


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _input(event: InputEvent) -> void:
	if not DisplaySettings.is_desktop():
		return  # a browser has its own fullscreen keys
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo:
		return
	var enter := k.keycode == KEY_ENTER or k.keycode == KEY_KP_ENTER
	if (enter and k.alt_pressed) or k.keycode == KEY_F11:
		DisplaySettings.toggle_fullscreen()
		get_viewport().set_input_as_handled()  # Alt+Enter must not also press a menu button


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_FOCUS_OUT:
			DisplaySettings.focus_lost()
		NOTIFICATION_APPLICATION_FOCUS_IN:
			DisplaySettings.focus_back()
