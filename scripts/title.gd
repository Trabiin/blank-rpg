extends Control
## Title screen: the Blank slowly eating a black page, the Last Ink logo bleeding ink,
## and a plain list menu (Continue, New Game, Load Game, Options, Credits).

const GAME_SCENE := "res://scenes/main.tscn"

var menu: InkMenu
var credits: InkMenu
var slots: InkMenu
var t := 0.0
var drips: Array = []  # [x offset in logo, length, speed]


func _ready() -> void:
	Settings.apply_all()  # saved options: volume, key bindings (issue #14)
	set_anchors_preset(Control.PRESET_FULL_RECT)
	get_tree().paused = false
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for i in 14:
		drips.append([rng.randf_range(-110, 110), rng.randf_range(4, 26), rng.randf_range(2.0, 7.0)])

	menu = InkMenu.new()
	menu.dim = 0.0
	menu.top = 0.42
	add_child(menu)
	var latest := Saves.latest_slot()
	var items := []
	if latest != "":
		items.append({"id": "continue", "label": "Continue", "detail": Saves.describe(latest)})
	items.append({"id": "new", "label": "New Game"})
	items.append({"id": "load", "label": "Load Game", "enabled": latest != "", "note": "(no saves yet)"})
	items.append({"id": "options", "label": "Options", "detail": "speed, difficulty, sound, controls"})
	items.append({"id": "credits", "label": "Credits"})
	# Testing shortcuts live one level down, so the main menu reads like a finished game's.
	items.append({"id": "tests", "label": "Test shortcuts", "detail": "jump straight to the town or the Auditor"})
	menu.setup("", items)
	menu.chosen.connect(_on_choice)

	slots = InkMenu.new()
	slots.visible = false
	slots.dim = 0.85
	slots.top = 0.2
	add_child(slots)
	slots.chosen.connect(_on_slot)

	credits = InkMenu.new()
	credits.visible = false
	credits.dim = 0.92
	credits.title_size = 16
	add_child(credits)
	credits.setup("Credits", [{"id": "back", "label": "Back"}], _credit_lines())
	credits.chosen.connect(_close_credits)


func _on_slot(id: String) -> void:
	if id in ["command", "boss_test"]:
		_on_choice(id)
	elif id == "back" or id == "cancel":
		slots.visible = false
		menu.visible = true
	else:
		Saves.load_and_play(id)


func _close_credits(_id: String) -> void:
	credits.visible = false
	menu.visible = true


func _on_choice(id: String) -> void:
	match id:
		"new":
			Saves.pending = {}
			Empire.reset()
			Story.begin()  # New Game plays the story from the Prologue (issue #18)
			get_tree().change_scene_to_file(GAME_SCENE)
		"continue":
			Saves.load_and_play(Saves.latest_slot())
		"load":
			slots.setup("Load which save?", Saves.slot_items(false))
			menu.visible = false
			slots.visible = true
		"command":
			Saves.pending = {}
			Empire.reset()
			get_tree().change_scene_to_file(Saves.HUB_SCENE)
		"boss_test":  # Act 1's last fight without playing Act 1 first (issue #17)
			Saves.pending = {}
			Empire.reset()
			Progress.award(PartyPicker.mission_party(), 200)
			Dialogue.mark_seen("talk:meadow_intro")  # Bran already knows Ash by now
			Missions.launch(Missions.find("auditor_duel"))
		"options":
			menu.visible = false
			OptionsView.popup(self).closed.connect(func(): menu.visible = true)
		"credits":
			menu.visible = false
			credits.visible = true
		"tests":
			slots.setup("Test shortcuts", [
				{"id": "command", "label": "Hollowmark", "detail": "a fresh town and the Command Table"},
				{"id": "boss_test", "label": "Boss: The Auditor", "detail": "fresh level 6 party, straight into the fight"},
				{"id": "back", "label": "Back"}])
			menu.visible = false
			slots.visible = true


## Builds the credits text from CREDITS.md so there is one source of truth.
func _credit_lines() -> String:
	var lines := ["Design, code and story: Ojon and Claude", ""]
	var f := FileAccess.open("res://CREDITS.md", FileAccess.READ)
	if f:
		while not f.eof_reached():
			var row := f.get_line()
			if not row.begins_with("|") or row.begins_with("|---") or row.begins_with("| Asset"):
				continue
			var cols := row.split("|", false)
			if cols.size() >= 4:
				var asset := cols[0].strip_edges().get_slice(" (", 0)
				lines.append("%s  -  %s  (%s)" % [asset, cols[1].strip_edges(), cols[3].strip_edges()])
	lines.append("")
	lines.append("Made with Godot Engine")
	return "\n".join(lines)


func _process(delta: float) -> void:
	t += delta
	queue_redraw()


func _draw() -> void:
	var vs := get_rect().size
	draw_rect(Rect2(Vector2.ZERO, vs), Color("0e0b12"))
	# The Blank creeping in from the right edge.
	var pts := PackedVector2Array()
	var y := -10.0
	while y <= vs.y + 10.0:
		var x := vs.x * 0.86 + sin(y * 0.03 + t * 0.7) * 10.0 + sin(y * 0.09 - t * 1.4) * 4.0 - t * 0.6
		pts.append(Vector2(maxf(x, vs.x * 0.62), y))
		y += 10.0
	pts.append(Vector2(vs.x + 10, vs.y + 10))
	pts.append(Vector2(vs.x + 10, -10))
	draw_colored_polygon(pts, Color("f3f1ea"))
	var rng := RandomNumberGenerator.new()
	rng.seed = int(t * 12.0)
	for i in 60:
		var py := rng.randf_range(0, vs.y)
		var idx := clampi(int((py + 10.0) / 10.0), 0, pts.size() - 3)
		var px := pts[idx].x - rng.randf() * rng.randf() * 30.0
		draw_rect(Rect2(px, py, 2, 2), Color(0.97, 0.96, 0.93, 0.9) if i % 2 else Color(0, 0, 0, 0.8))

	# Logo
	var font := ThemeDB.fallback_font
	var logo_font: Font = UiSkin.TITLE_FONT  # the heading face, as on every screen title
	var logo := "Last Ink"  # blackletter capitals are hard to read, so title case
	var fs := 72
	var w := logo_font.get_string_size(logo, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var c := Vector2(vs.x * 0.5, vs.y * 0.24)
	var base := Vector2(c.x - w / 2.0, c.y)
	draw_string(logo_font, base + Vector2(2, 3), logo, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0, 0, 0, 0.6))
	draw_string(logo_font, base, logo, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color("ece6da"))
	# Ink drips bleeding off the bottom of the letters (only where a letter is, not out in the air).
	var ink_img := _logo_mask(logo_font, logo, fs, w)
	for d in drips:
		var dl: float = d[1] * (0.6 + 0.4 * sin(t * 0.8 + d[2]))
		var fx: float = (float(d[0]) + 110.0) / 220.0
		var col_x := int(fx * (w - 4.0)) + 2
		var foot: float = ink_img.get(col_x, -1.0)
		if foot < 0:
			continue
		var dx: float = base.x + col_x
		var top: float = base.y - foot
		draw_rect(Rect2(dx - 1, top, 2, dl), Color("ece6da"))
		draw_rect(Rect2(dx - 1.5, top + dl, 3, 2), Color("ece6da"))
	var tag := "Reality is being eaten. You were spat back out."
	var tw := font.get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
	draw_string(font, Vector2(c.x - tw / 2.0, c.y + 30), tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.75, 0.72, 0.7))


var _mask_cache := {}


## Pixel columns of the logo that sit under a letter (inside each glyph's advance, minus the side bearings), so
## drips start at the foot of a letter instead of out in the air.
func _logo_mask(f: Font, text: String, fs: int, _w: float) -> Dictionary:
	if _mask_cache.is_empty():
		var x := 0.0
		for ch in text:
			var adv := f.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			if ch != " ":
				for cx in range(int(x + adv * 0.2), int(x + adv * 0.8)):
					_mask_cache[cx] = 1.0
			x += adv
	return _mask_cache
