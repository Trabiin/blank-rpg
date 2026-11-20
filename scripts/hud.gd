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
	if Empire.missions_cleared.size() >= 2:  # control hints only for the first missions
		help_t = 0.0


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


const INK_COL := Color("6aa8ff")


## The leader's abilities, bottom-right: key, name, Ink cost, cooldown sweep.
func _draw_ability_bar(hero: Hero, vs: Vector2) -> void:
	var n := hero.abilities.size()
	if n == 0:
		return
	var has_icons := UiSkin.icon(str(hero.abilities[0].get("id", ""))) != null
	var w := 94.0 if has_icons else 84.0
	var x := vs.x - 8.0 - n * (w + 4.0) + 4.0
	var y := vs.y - 38.0
	_text(Vector2(x, y - 4), "Ink %d / %d" % [floori(hero.ink), int(hero.max_ink)], 8, INK_COL)
	for i in n:
		var a: Dictionary = hero.abilities[i]
		var why := Abilities.blocker(hero, i)
		var r := Rect2(x, y, w, 32)
		UiSkin.panel(self, r, "button", Color.WHITE if why == "" else Color(0.6, 0.6, 0.65))
		var col := Abilities.color_of(a)
		var cd: float = hero.cooldowns[i]
		if cd > 0.0:
			draw_rect(Rect2(x, y, w * cd / float(a.get("cooldown", 1.0)), 32), Color(1, 1, 1, 0.08))
		draw_rect(Rect2(x + 2, y + 3, 2, 26), col if why == "" else Color(col, 0.35))  # the ability's colour, as a ribbon
		var txt_col := Color.WHITE if why == "" else Color(0.6, 0.6, 0.6)
		var ox := 0.0  # text starts after the ability's icon
		if UiSkin.draw_icon(self, str(a.get("id", "")), Rect2(x + 7, y + 6, 20, 20), Color.WHITE if why == "" else Color(0.5, 0.5, 0.55)):
			ox = 24.0
		var k := Prompts.key("ability_%d" % (i + 1))  # 1-4, or LB / RB / LT / RT on a pad
		if k == "":
			k = str(i + 1)
		_text(Vector2(x + 4 + ox, y + 10), k, 9, col, false)
		var kw := ThemeDB.fallback_font.get_string_size(k, HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x
		_text(Vector2(x + 8 + ox + kw, y + 10), str(a.get("name", "")), 8, txt_col, false)
		var cost_col := INK_COL if why != "ink" else Color("ff6b6b")
		_text(Vector2(x + 4 + ox, y + 22), "%d Ink" % int(a.get("cost", 0)), 8, cost_col, false)
		if cd > 0.0:
			_text(Vector2(x + 44 + ox, y + 22), "%.1fs" % cd, 8, Color(0.8, 0.8, 0.85), false)
		x += w + 4.0


func _draw() -> void:
	if party == null:
		return
	var vs := size_px()
	# Party panels, bottom-left
	var x := 8.0
	for h in party.heroes:
		var hero: Hero = h
		var y := vs.y - 38.0
		# Art pass heroes get a face icon cut from their sprite; the plate grows to fit it.
		var face: Texture2D = hero.art.face() if hero.art != null else null
		var fw := 24.0 if face != null else 0.0
		var panel := Rect2(x, y, 112 + fw, 32)
		UiSkin.panel(self, panel, "ledger")
		if hero.controlled:
			UiSkin.highlight(self, panel)
		if face != null:
			draw_rect(Rect2(x + 3, y + 6, 20, 20), Color(0.16, 0.15, 0.2, 0.9))
			draw_texture_rect(face, Rect2(x + 3, y + 6, 20, 20), false, Color(0.45, 0.45, 0.45) if hero.dead else Color.WHITE)
			x += fw
		var name_col := Color(0.6, 0.6, 0.6) if hero.dead else Color.WHITE
		_text(Vector2(x + 5, y + 10), hero.hero_name + ("  (down)" if hero.dead else ""), 9, name_col, false)
		var pct := int(round(hero.power * 100.0))
		var pcol := Color("ffd166") if pct >= 100 else Color(0.8, 0.8, 0.85)
		if not hero.charge_ready:  # a ready charged tech shows TECH here instead
			_text(Vector2(x + 82, y + 10), "%d%%" % pct, 9, pcol, false)
		_text(Vector2(x + 58, y + 10), "Lv%d" % Progress.level(hero.hero_id), 8, Color(0.75, 0.72, 0.6), false)
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
		if hero.charging and hero.charge_t >= Techs.TAP:  # charged tech filling (issue #8)
			var tcol := Techs.color_of(hero)
			draw_rect(Rect2(x + 5, y + 20, 102.0 * Techs.charge_ratio(hero), 4), tcol.lightened(0.6) if hero.charge_ready else Color(tcol, 0.8))
			if hero.charge_ready:
				UiSkin.draw_icon(self, "tech_" + hero.hero_id, Rect2(x + 99, y + 2, 10, 10))
				_text(Vector2(x + 80, y + 10), "TECH", 9, tcol.lightened(0.3), false)
		# Ink (abilities, issue #7)
		if hero.max_ink > 0.0:
			draw_rect(Rect2(x + 5, y + 25, 102, 3), Color(0, 0, 0, 0.6))
			draw_rect(Rect2(x + 5, y + 25, 102.0 * hero.ink / hero.max_ink, 3), INK_COL)
		x += 118.0
	if party.leader and not party.touch_active():
		_draw_ability_bar(party.leader, vs)

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
		UiSkin.panel(self, Rect2(vs.x / 2.0 - 124, yy - 18, 248, 16.0 * lines.size() + 14), "paper")
		for line in lines:
			_text_centered(yy, line, 10, UiSkin.PAPER_INK)
			yy += 16.0
	if help_t > 0.0 and not party.touch_active():
		var a2 := clampf(help_t / 1.0, 0.0, 1.0)
		# Matches the device in use (issue #23): keys on a keyboard, button names on a pad.
		var pad := Prompts.pad()
		var abil := "%s %s %s %s" % [Prompts.key("ability_1"), Prompts.key("ability_2"), Prompts.key("ability_3"), Prompts.key("ability_4")]
		var lines_h := [
			"Move: " + ("left stick / D-pad" if pad else "WASD / arrows"),
			"Attack: %s, hold when full: tech" % Prompts.key("attack"),
			"Swap hero: " + Prompts.key("swap"),
			"Pause: " + Prompts.key("pause"),
			"Abilities: " + (abil if pad else "1-4"),
			"Quick menu: " + Prompts.key("quick_menu"),
		]
		for li in lines_h.size():
			_text(Vector2(vs.x - 150, 96 + 11 * li), lines_h[li], 8, Color(1, 1, 1, a2))  # clear of the banter panel
	if center_text != "":
		draw_rect(Rect2(Vector2.ZERO, vs), Color(0.95, 0.94, 0.9, 0.55))
		var lines2 := center_text.split("\n")
		var y2 := vs.y / 2.0 - 8.0 * lines2.size()
		for line in lines2:
			_text_centered(y2, line, 14, Color.WHITE)
			y2 += 20.0
