extends Control
## Title screen: the Blank slowly eating a black page, the Last Ink logo bleeding ink,
## and a plain list menu (Continue, New Game, Load Game, Options, Credits).

const GAME_SCENE := "res://scenes/main.tscn"
const KEY_ART: Texture2D = preload("res://assets/ui/title_keyart.jpg")

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
	menu.panel_alpha = 0.62
	menu.top = 0.42
	add_child(menu)
	var latest := Saves.latest_slot()
	var items := []
	if latest != "":
		items.append({"id": "continue", "label": "Continue", "detail": Saves.describe(latest)})
	items.append({"id": "new", "label": "New Game"})
	items.append({"id": "load", "label": "Load Game", "enabled": latest != "", "note": "(no saves yet)"})
	items.append({"id": "options", "label": "Options", "detail": "speed, difficulty, sound, controls"})
	items.append({"id": "report", "label": "Report a bug", "detail": "or send feedback"})
	items.append({"id": "credits", "label": "Credits"})
	# Testing shortcuts live one level down, and only in builds that ask for them (test_shortcuts_on).
	if test_shortcuts_on():
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

	_show_save_notices()


## Saves that could not be read were set aside at start-up (scripts/save.gd): say so once. Then the
## offer to report the last session's crash or errors, if there was one.
func _show_save_notices() -> void:
	var notes := Saves.take_notices()
	if notes.is_empty():
		_offer_report()
		return
	var notice := InkMenu.new()
	notice.dim = 0.85
	notice.top = 0.25
	add_child(notice)
	notice.setup("About your saves", [{"id": "ok", "label": "OK"}], "\n\n".join(notes))
	menu.visible = false
	notice.chosen.connect(func(_id):
		notice.queue_free()
		menu.visible = true
		_offer_report())


## The last session crashed or hit errors (Diag, issue #146): offer once to send a report about it.
## Nothing is sent unless the player goes on to press Send in the form.
func _offer_report() -> void:
	if not Diag.should_offer_report():
		return
	var prev: Dictionary = Diag.previous
	var n := int(prev.get("errors", 0))
	var what := "Last Ink closed unexpectedly last time." if prev.get("crashed", false) \
		else "Last Ink ran into %d error%s last time." % [n, "" if n == 1 else "s"]
	var offer := InkMenu.new()
	offer.dim = 0.85
	offer.top = 0.28
	add_child(offer)
	offer.setup("Sorry about that", [
		{"id": "send", "label": "Send report", "detail": "you see everything before it goes"},
		{"id": "logs", "label": "Download the logs" if OS.has_feature("web") else "Open log folder"},
		{"id": "later", "label": "Not now"},
		{"id": "mute", "label": "Don't ask again", "detail": "until the next update"},
	], what + " A report with the log from then helps fix it.")
	menu.visible = false
	Diag.previous = {}  # asked once per launch
	offer.chosen.connect(_on_offer.bind(offer, prev))


func _on_offer(id: String, offer: InkMenu, prev: Dictionary) -> void:
	match id:
		"send":
			offer.visible = false
			FeedbackView.popup(self, {"screenshot": false, "previous": prev}).closed.connect(func():
				offer.queue_free()
				menu.visible = true)
		"logs":
			Diag.open_log_folder()
		"mute":
			Diag.mute()
			offer.queue_free()
			menu.visible = true
		_:
			offer.queue_free()
			menu.visible = true


func _on_slot(id: String) -> void:
	if id in ["command", "boss_test", "heroes_test", "map_test", "error_test"]:
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
		"heroes_test":  # the four new field heroes, hired on day one, Ottoline and Jessamy in the party
			Saves.pending = {}
			Empire.reset()
			Empire.recruits["bran"]["role"] = "idle"
			for rid in ["ottoline", "jessamy", "odile", "velvette"]:
				Empire.recruits[rid] = {"role": "party" if rid in ["ottoline", "jessamy"] else "idle", "target": "", "injured": 0}
			get_tree().change_scene_to_file(Saves.HUB_SCENE)
		"map_test":  # the whole Inklands with every region open, as if the story were done (issue #53)
			Saves.pending = {}
			Empire.reset()
			for r in Empire.territory().regions:
				Empire.open_region(r["id"], true)
			Empire.res["gilt"] = 900
			Empire.res["supplies"] = 160
			get_tree().change_scene_to_file(Saves.COMMAND_SCENE)
		"options":
			menu.visible = false
			OptionsView.popup(self).closed.connect(func(): menu.visible = true)
		"report":  # issue #146
			menu.visible = false
			FeedbackView.popup(self, {"screenshot": false}).closed.connect(func(): menu.visible = true)
		"error_test":  # issue #146: something for the next launch's report offer to find
			push_error("Test error from the title screen's test shortcuts (issue #146).")
			Diag.toast("Logged a test error. Restart the game to see the report offer.")
		"credits":
			menu.visible = false
			credits.visible = true
		"tests":
			slots.setup("Test shortcuts", [
				{"id": "command", "label": "Hollowmark", "detail": "a fresh town and the Command Table"},
				{"id": "boss_test", "label": "Boss: The Auditor", "detail": "fresh level 6 party, straight into the fight"},
				{"id": "heroes_test", "label": "New heroes", "detail": "fresh town with Ottoline, Jessamy, Odile and Velvette already hired"},
				{"id": "map_test", "label": "Whole map", "detail": "Command Table with every region open, and coin to claim land"},
				{"id": "error_test", "label": "Log a test error", "detail": "the next launch offers to send a report"},
				{"id": "back", "label": "Back"}])
			menu.visible = false
			slots.visible = true


## The "Test shortcuts" submenu is for playtesting: on in the editor and in exports whose preset lists the
## custom feature "test_shortcuts" (the Web preset that publishes the playtest link does). A release
## preset leaves the feature out, and the entry and its shortcuts are gone.
static func test_shortcuts_on() -> bool:
	return OS.has_feature("editor") or OS.has_feature("test_shortcuts")


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
	_draw_key_art(vs)
	_draw_logo(vs)
	var ver := "v" + Saves.game_version()
	var font := ThemeDB.fallback_font
	var vw := font.get_string_size(ver, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
	draw_string(font, Vector2(vs.x - vw - 6, vs.y - 6), ver, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.75, 0.72, 0.7, 0.7))


## Painted key art (Phase 8), scaled to cover the screen, with a slow drift so the scene breathes.
func _draw_key_art(vs: Vector2) -> void:
	var ts := KEY_ART.get_size()
	var k := maxf(vs.x / ts.x, vs.y / ts.y) * 1.04
	var sz := ts * k
	var drift := Vector2(sin(t * 0.05) * 6.0, cos(t * 0.04) * 3.0)
	draw_texture_rect(KEY_ART, Rect2((vs - sz) * 0.5 + drift, sz), false)
	draw_rect(Rect2(Vector2.ZERO, vs), Color(0.03, 0.02, 0.05, 0.22))
	# Ink motes flaking off the erased edge on the right.
	var rng := RandomNumberGenerator.new()
	rng.seed = int(t * 6.0)
	for i in 30:
		var py := rng.randf_range(0, vs.y)
		var px := vs.x * rng.randf_range(0.6, 0.78)
		draw_rect(Rect2(px, py, 2, 2), Color(0, 0, 0, 0.7) if i % 2 else Color(0.97, 0.96, 0.93, 0.6))


func _draw_logo(vs: Vector2) -> void:
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
