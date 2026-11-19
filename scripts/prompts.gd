class_name Prompts
extends RefCounted
## Button prompts that match the device in use (issue #23).
## Controls (the autoload) feeds every input event to Prompts.note(); screens then ask
## Prompts.key("ui_accept") for "Enter", "A", "Cross"... or build a whole help line with
## Prompts.help(). Labels are read from the InputMap when drawn, so remapped keys show up.

const KEYS := "keys"  # keyboard and mouse
const PAD := "pad"
const TOUCH := "touch"

static var device := KEYS
static var pad_style := "xbox"  # xbox, playstation or nintendo (face button names)

const PAD_NAMES := {
	"xbox": {JOY_BUTTON_A: "A", JOY_BUTTON_B: "B", JOY_BUTTON_X: "X", JOY_BUTTON_Y: "Y",
		JOY_BUTTON_BACK: "View", JOY_BUTTON_START: "Menu", JOY_BUTTON_LEFT_SHOULDER: "LB",
		JOY_BUTTON_RIGHT_SHOULDER: "RB", JOY_BUTTON_LEFT_STICK: "L3", JOY_BUTTON_RIGHT_STICK: "R3"},
	"playstation": {JOY_BUTTON_A: "Cross", JOY_BUTTON_B: "Circle", JOY_BUTTON_X: "Square",
		JOY_BUTTON_Y: "Triangle", JOY_BUTTON_BACK: "Share", JOY_BUTTON_START: "Options",
		JOY_BUTTON_LEFT_SHOULDER: "L1", JOY_BUTTON_RIGHT_SHOULDER: "R1", JOY_BUTTON_LEFT_STICK: "L3",
		JOY_BUTTON_RIGHT_STICK: "R3"},
	# Godot names buttons by position (A = bottom); Nintendo prints the letters swapped.
	"nintendo": {JOY_BUTTON_A: "B", JOY_BUTTON_B: "A", JOY_BUTTON_X: "Y", JOY_BUTTON_Y: "X",
		JOY_BUTTON_BACK: "-", JOY_BUTTON_START: "+", JOY_BUTTON_LEFT_SHOULDER: "L",
		JOY_BUTTON_RIGHT_SHOULDER: "R", JOY_BUTTON_LEFT_STICK: "L-stick", JOY_BUTTON_RIGHT_STICK: "R-stick"},
}
const TRIGGERS := {
	"xbox": ["LT", "RT"], "playstation": ["L2", "R2"], "nintendo": ["ZL", "ZR"],
}
const DPAD := {JOY_BUTTON_DPAD_UP: "Up", JOY_BUTTON_DPAD_DOWN: "Down",
	JOY_BUTTON_DPAD_LEFT: "Left", JOY_BUTTON_DPAD_RIGHT: "Right"}
const KEY_SHORT := {"Escape": "Esc", "Kp Enter": "Enter", "BackSpace": "Backspace"}


## Called by Controls for every input event: remembers what the player last touched.
## Moving the mouse alone never flips away from pad or touch prompts.
static func note(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		device = KEYS
	elif event is InputEventMouseButton and event.pressed:
		device = KEYS
	elif event is InputEventScreenTouch and event.pressed:
		device = TOUCH
	elif (event is InputEventJoypadButton and event.pressed) \
			or (event is InputEventJoypadMotion and absf(event.axis_value) > 0.5):
		if device != PAD:
			pad_style = style_of(Input.get_joy_name(event.device))
		device = PAD


static func style_of(joy_name: String) -> String:
	var n := joy_name.to_lower()
	if n.contains("ps3") or n.contains("ps4") or n.contains("ps5") or n.contains("dualshock") \
			or n.contains("dualsense") or n.contains("sony") or n.contains("playstation"):
		return "playstation"
	if n.contains("nintendo") or n.contains("switch") or n.contains("pro controller") or n.contains("joy-con"):
		return "nintendo"
	return "xbox"


static func pad() -> bool:
	return device == PAD


static func touch() -> bool:
	return device == TOUCH


## A short name for the button that triggers this action on the current device.
## Empty when the action has nothing bound there (or on touch: you tap things instead).
static func key(action: String, on := "") -> String:
	var dev := device if on == "" else on
	if dev == TOUCH or not InputMap.has_action(action):
		return ""
	for ev in InputMap.action_get_events(action):
		var s := _event_name(ev, dev)
		if s != "":
			return s
	return ""


static func _event_name(ev: InputEvent, dev: String) -> String:
	if dev == KEYS and ev is InputEventKey:
		var code: int = ev.physical_keycode if ev.physical_keycode != 0 else ev.keycode
		var s := OS.get_keycode_string(code)
		return KEY_SHORT.get(s, s)
	if dev == PAD and ev is InputEventJoypadButton:
		if DPAD.has(ev.button_index):
			return "D-pad " + str(DPAD[ev.button_index])
		return str(PAD_NAMES[pad_style].get(ev.button_index, ""))
	if dev == PAD and ev is InputEventJoypadMotion:
		if ev.axis == JOY_AXIS_TRIGGER_LEFT:
			return TRIGGERS[pad_style][0]
		if ev.axis == JOY_AXIS_TRIGGER_RIGHT:
			return TRIGGERS[pad_style][1]
		return "Stick"
	return ""


## The first non-empty key among several actions (e.g. ["research", "ui_cancel"]).
static func any_key(actions: Array) -> String:
	for a in actions:
		var s := key(a)
		if s != "":
			return s
	return ""


## A help line for the bottom of a screen. `parts` is a list of [what, verb] pairs, where
## `what` is an action name, a list of actions (keyboard shows them all, a pad the first one
## that is bound), or "updown" / "leftright" / "move" for the arrows or the stick.
## On touch the line is `touch_text` instead.
## Example: Prompts.help([["updown", "choose"], ["ui_accept", "pick"], ["ui_cancel", "close"]],
## "Tap a row, tap it again to act")
static func help(parts: Array, touch_text := "Tap to choose") -> String:
	if device == TOUCH:
		return touch_text
	var out := PackedStringArray()
	for p in parts:
		var what = p[0]
		var label := ""
		match what:
			"updown":
				label = "D-pad" if device == PAD else "Up/Down"
			"leftright":
				label = "D-pad Left/Right" if device == PAD else "Left/Right"
			"move":
				label = "Stick" if device == PAD else "WASD"
			_:
				label = _keys_of(what if what is Array else [what])
		if label != "":
			out.append("%s %s" % [label, p[1]])
	return "   ".join(out)


static func _keys_of(actions: Array) -> String:
	var seen := PackedStringArray()
	for a in actions:
		var s := key(a)
		if s != "" and not seen.has(s):
			seen.append(s)
			if device == PAD:
				break
	return " / ".join(seen)


## "Enter" / "A" / "Tap": what to press to go on (story cards, results, prompts).
static func confirm() -> String:
	return "Tap" if device == TOUCH else key("ui_accept")


## True for a left click or a finger touching down. Touch does not emulate the mouse in
## this project, so every tappable screen checks both.
static func tapped(event: InputEvent) -> bool:
	return (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT) \
		or (event is InputEventScreenTouch and event.pressed)
