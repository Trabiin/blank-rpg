extends Control
## Code-drawn HUD: party HP and power gauges, banter line, banners.

var party  # main.gd
var banter_text := ""
var banter_t := 0.0
var center_text := ""
var sign_text := ""
var help_t := 14.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func say(text: String, duration := 3.5) -> void:
	banter_text = text
	banter_t = duration


func _process(delta: float) -> void:
	banter_t = maxf(banter_t - delta, 0.0)
	help_t = maxf(help_t - delta, 0.0)
	queue_redraw()


func _text(pos: Vector2, s: String, size := 10, col := Color.WHITE, outline := true) -> void:
	var font := ThemeDB.fallback_font
	if outline:
		draw_string_outline(font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 3, Color(0, 0, 0, col.a * 0.85))
	draw_string(font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


func _text_centered(y: float, s: String, size := 10, col := Color.WHITE) -> void:
	var w := ThemeDB.fallback_font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	_text(Vector2((size_px().x - w) / 2.0, y), s, size, col)


func size_px() -> Vector2:
	return get_viewport_rect().size


func _draw() -> void:
	if party == null:
		return
	var vs := size_px()
	# Party panels, bottom-left
	var x := 8.0
	for h in party.heroes:
		var hero: Hero = h
		var y := vs.y - 34.0
		var panel := Rect2(x, y, 112, 28)
		draw_rect(panel, Color(0.05, 0.04, 0.08, 0.72))
		if hero.controlled:
			draw_rect(panel, Color("ffd166"), false, 1.0)
		var name_col := Color(0.6, 0.6, 0.6) if hero.dead else Color.WHITE
		_text(Vector2(x + 5, y + 10), hero.hero_name + ("  (down)" if hero.dead else ""), 9, name_col, false)
		var pct := int(round(hero.power * 100.0))
		var pcol := Color("ffd166") if pct >= 100 else Color(0.8, 0.8, 0.85)
		_text(Vector2(x + 82, y + 10), "%d%%" % pct, 9, pcol, false)
		_text(Vector2(x + 58, y + 10), "Lv%d" % Progress.level(hero.hero_id), 7, Color(0.75, 0.72, 0.6), false)
		# XP sliver along the top edge of the panel
		draw_rect(Rect2(x, y, 112.0 * Progress.xp_fraction(hero.hero_id), 1), Color("b9a0e8"))
		# HP bar
		draw_rect(Rect2(x + 5, y + 14, 102, 5), Color(0, 0, 0, 0.6))
		var ratio := float(hero.hp) / hero.max_hp
		var hcol := Color("6bd88b") if ratio > 0.5 else (Color("f2c14e") if ratio > 0.25 else Color("ff6b6b"))
		draw_rect(Rect2(x + 5, y + 14, 102.0 * ratio, 5), hcol)
		# power gauge
		draw_rect(Rect2(x + 5, y + 21, 102, 2), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(x + 5, y + 21, 102.0 * hero.power, 2), pcol)
		x += 118.0

	# Mission name and objective, top-left
	_text(Vector2(8, 14), party.mission.get("name", party.area.area_name), 10, Color(0.9, 0.88, 0.8))
	var done: bool = party.objective.done()
	_text(Vector2(8, 26), party.objective.text() + ("  done" if done else ""), 9, Color("9fd3a8") if done else Color("ffd166"))
	var yy0 := 38.0
	var found := Missions.res_text(party.found)
	var gear_found: Array = party.found_items.map(func(i): return Progress.item(i).get("name", i))
	if not gear_found.is_empty():
		found = (found + ", " if found != "" else "") + ", ".join(gear_found)
	if found != "":
		var lit: bool = party.found_flash > 0.0
		_text(Vector2(8, yy0), "Found: " + found, 8, Color("ffe7a3") if lit else Color(0.75, 0.75, 0.75))
		yy0 += 12.0
	var perks: Array = party.boosts.get("lines", [])
	if not perks.is_empty():
		_text(Vector2(8, yy0), "Research: " + ", ".join(perks), 8, Color("d7b8f0"))

	if banter_t > 0.0:
		var a := clampf(banter_t / 0.4, 0.0, 1.0)
		_text_centered(58.0, banter_text, 10, Color(1, 1, 1, a))
	if sign_text != "":
		var lines := sign_text.split("\n")
		var yy := vs.y * 0.62
		draw_rect(Rect2(vs.x / 2.0 - 120, yy - 14, 240, 16.0 * lines.size() + 8), Color(0.12, 0.09, 0.06, 0.85))
		for line in lines:
			_text_centered(yy, line, 10, Color("f3e3c3"))
			yy += 16.0
	if help_t > 0.0 and not party.touch_active():
		var a2 := clampf(help_t / 1.0, 0.0, 1.0)
		_text(Vector2(vs.x - 236, 14), "Move: WASD / arrows / stick", 8, Color(1, 1, 1, a2))
		_text(Vector2(vs.x - 236, 25), "Attack: J / Space   (gamepad A)", 8, Color(1, 1, 1, a2))
		_text(Vector2(vs.x - 236, 36), "Swap hero: Tab / Q (gamepad Y)", 8, Color(1, 1, 1, a2))
		_text(Vector2(vs.x - 236, 47), "Pause: Esc / P (gamepad Start)", 8, Color(1, 1, 1, a2))
	if center_text != "":
		draw_rect(Rect2(Vector2.ZERO, vs), Color(0.95, 0.94, 0.9, 0.55))
		var lines2 := center_text.split("\n")
		var y2 := vs.y / 2.0 - 8.0 * lines2.size()
		for line in lines2:
			_text_centered(y2, line, 14, Color.WHITE)
			y2 += 20.0
