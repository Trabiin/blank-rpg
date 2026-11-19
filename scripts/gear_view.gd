class_name GearView
extends Control
## Party gear screen (issue #15): levels, XP and equipment for each field hero, plus the
## Hollowmark shop. Opened with K in town and on the Command Table, and from the pause menu
## on a mission (no shop out there; changes take effect on the spot).
##
## Equip tab: Left/Right picks the hero, Up/Down the slot, Enter opens the list of spare gear
## for that slot (Up/Down, Enter puts it on, Esc goes back). Shop tab: Up/Down, Enter buys or
## sells. Tab/Q switches tabs. Mouse and touch: tap to select, tap again to act.

signal closed

const GOLD := Color("ffd166")
const GOOD := Color("9fd18b")
const BAD := Color("ff9b8a")
const TEXT := Color("ece6da")
const DIM := Color(0.42, 0.41, 0.44)
const SOFT := Color(0.62, 0.6, 0.62)
const XP_COL := Color("b9a0e8")
const PAPER := Color("f3efe4")
const SLOT_COLORS := {"weapon": Color("e89a8a"), "armor": Color("8fa7e8"), "trinket": Color("e8c66a")}

var party  # main.gd on a mission: live heroes get the new stats right away
var where := "town"  # "town" (shop open) or "mission"
var tab := "equip"
var hero_i := 0
var slot_i := 0
var picking := false
var pick_i := 0
var shop_i := 0
var closed_frame := -1
var opened_frame := -1
var flash := ""
var flash_t := 0.0
var font: Font
var _ids: Array = []
var _hero_rects: Array = []
var _slot_rects: Array = []
var _pick_rects: Array = []
var _shop_rects: Array = []
var _tab_rects := {}


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	font = ThemeDB.fallback_font


func open(at := "town") -> void:
	where = at
	position = Vector2.ZERO
	size = get_viewport_rect().size
	visible = true
	opened_frame = Engine.get_process_frames()
	_ids = Progress.field_ids()
	if party != null and where == "mission":
		_ids = party.heroes.map(func(h): return (h as Hero).hero_id)
	hero_i = clampi(hero_i, 0, maxi(_ids.size() - 1, 0))
	tab = "equip"
	picking = false


func close() -> void:
	visible = false
	closed_frame = Engine.get_process_frames()
	closed.emit()


func _shop_open() -> bool:
	return where == "town"


func _hero_id() -> String:
	return _ids[hero_i] if hero_i < _ids.size() else ""


func _slot() -> String:
	return Progress.SLOTS[slot_i]


## What the pick list offers for the current slot: "" (take it off) and the spare gear that fits.
func _choices() -> Array:
	var out := [""]
	out.append_array(Progress.options(_hero_id(), _slot()))
	return out


## Shop rows: ["buy", item] for the stock, then ["sell", item] for spare gear in the bag.
func _shop_rows() -> Array:
	var rows := []
	for k in Progress.shop_stock():
		rows.append(["buy", k])
	var spare := Progress.bag().keys()
	spare.sort()
	for k in spare:
		if Progress.sell_price(k) > 0:
			rows.append(["sell", k])
	return rows


func _process(delta: float) -> void:
	if not visible:
		return
	flash_t = maxf(flash_t - delta, 0.0)
	queue_redraw()
	if Engine.get_process_frames() == opened_frame or _ids.is_empty():
		return
	var up := Input.is_action_just_pressed("move_up") or Input.is_action_just_pressed("ui_up")
	var down := Input.is_action_just_pressed("move_down") or Input.is_action_just_pressed("ui_down")
	var left := Input.is_action_just_pressed("move_left") or Input.is_action_just_pressed("ui_left")
	var right := Input.is_action_just_pressed("move_right") or Input.is_action_just_pressed("ui_right")
	var back := Input.is_action_just_pressed("ui_cancel") or Input.is_action_just_pressed("pause")
	if Input.is_action_just_pressed("swap") and _shop_open() and not picking:
		_set_tab("shop" if tab == "equip" else "equip")
		return
	if tab == "shop":
		var n := _shop_rows().size()
		if n > 0:
			if up:
				shop_i = posmod(shop_i - 1, n)
			elif down:
				shop_i = posmod(shop_i + 1, n)
			shop_i = clampi(shop_i, 0, n - 1)
		if Input.is_action_just_pressed("ui_accept"):
			_shop_pick(shop_i)
		elif back or Input.is_action_just_pressed("gear"):
			close()
		return
	if picking:
		var n2 := _choices().size()
		if up:
			pick_i = posmod(pick_i - 1, n2)
		elif down:
			pick_i = posmod(pick_i + 1, n2)
		if Input.is_action_just_pressed("ui_accept"):
			_equip(pick_i)
		elif back:
			picking = false
		return
	if left:
		hero_i = posmod(hero_i - 1, _ids.size())
	elif right:
		hero_i = posmod(hero_i + 1, _ids.size())
	if up:
		slot_i = posmod(slot_i - 1, Progress.SLOTS.size())
	elif down:
		slot_i = posmod(slot_i + 1, Progress.SLOTS.size())
	if Input.is_action_just_pressed("ui_accept"):
		_start_pick()
	elif back or Input.is_action_just_pressed("gear"):
		close()


func _set_tab(t: String) -> void:
	tab = t
	picking = false


func _say(s: String) -> void:
	flash = s
	flash_t = 2.8


func _start_pick() -> void:
	picking = true
	pick_i = 0
	var cur := str(Progress.gear(_hero_id()).get(_slot(), ""))
	var ch := _choices()
	# Start on the first spare piece, if there is one; else on "take it off".
	pick_i = 1 if ch.size() > 1 else 0
	if ch.size() <= 1 and cur == "":
		picking = false
		_say("No spare %s for %s. The shop (Tab) or missions have more." % [Progress.SLOT_NAMES[_slot()].to_lower(), PartyPicker.short_of(_hero_id())])


func _equip(i: int) -> void:
	var id := _hero_id()
	var ch := _choices()
	if i < 0 or i >= ch.size():
		return
	var item_id: String = ch[i]
	var cur := str(Progress.gear(id).get(_slot(), ""))
	if item_id == "" and cur == "":
		picking = false
		return
	var before := Progress.bonus(id)
	if not Progress.equip(id, _slot(), item_id):
		_say("Can't: %s." % Progress.wear_blocker(id, item_id))
		return
	_apply_live(id, before)
	picking = false
	if item_id == "":
		_say("%s took off the %s." % [PartyPicker.short_of(id), Progress.item(cur)["name"]])
	else:
		_say("%s now uses the %s." % [PartyPicker.short_of(id), Progress.item(item_id)["name"]])


## On a mission, the hero standing in the field changes too.
func _apply_live(id: String, before: Dictionary) -> void:
	if party == null:
		return
	for h in party.heroes:
		if (h as Hero).hero_id == id:
			Progress.apply_delta(h, before, Progress.bonus(id))


func _shop_pick(i: int) -> void:
	var rows := _shop_rows()
	if i < 0 or i >= rows.size():
		return
	var kind: String = rows[i][0]
	var k: String = rows[i][1]
	var it := Progress.item(k)
	if kind == "buy":
		var why := Progress.shop_blocker(k)
		if why != "":
			_say("Can't: %s." % why)
			return
		Progress.buy(k)
		_say("Bought the %s for %d Gilt. It's in the bag: equip it on the Equip tab." % [it["name"], int(it["price"])])
	else:
		var price := Progress.sell_price(k)
		Progress.sell(k)
		_say("Sold the %s for %d Gilt." % [it["name"], price])
		shop_i = clampi(shop_i, 0, maxi(_shop_rows().size() - 1, 0))


func _gui_input(event: InputEvent) -> void:
	if Prompts.tapped(event):
		var p: Vector2 = event.position
		if _close_rect().has_point(p):
			close()
			return
		for t in _tab_rects:
			if (_tab_rects[t] as Rect2).has_point(p):
				_set_tab(t)
				return
		if tab == "shop":
			for i in _shop_rects.size():
				if (_shop_rects[i] as Rect2).has_point(p):
					if shop_i == i:
						_shop_pick(i)
					shop_i = i
					return
			return
		for i in _hero_rects.size():
			if (_hero_rects[i] as Rect2).has_point(p):
				hero_i = i
				picking = false
				return
		if picking:
			for i in _pick_rects.size():
				if (_pick_rects[i] as Rect2).has_point(p):
					if pick_i == i:
						_equip(i)
					pick_i = i
					return
		for i in _slot_rects.size():
			if (_slot_rects[i] as Rect2).has_point(p):
				if slot_i == i and not picking:
					_start_pick()
				else:
					slot_i = i
					picking = false
				return
		picking = false


func _close_rect() -> Rect2:
	return Rect2(Vector2(size.x - 56, 6), Vector2(50, 16))


# ---------------------------------------------------------------- drawing

func _text(pos: Vector2, s: String, fsize: int, col: Color, width := -1.0) -> void:
	draw_string(font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, width, fsize, col)


func _text_r(right: Vector2, s: String, fsize: int, col: Color) -> void:
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x
	_text(right - Vector2(w, 0), s, fsize, col)


func _wrap(pos: Vector2, s: String, width: float, fsize: int, col: Color) -> float:
	draw_multiline_string(font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, width, fsize, -1, col)
	return font.get_multiline_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, width, fsize).y


func _bar(r: Rect2, f: float, col: Color) -> void:
	draw_rect(r, Color(0.14, 0.12, 0.16))
	draw_rect(Rect2(r.position, Vector2(r.size.x * clampf(f, 0.0, 1.0), r.size.y)), col)


func _box(r: Rect2, on: bool) -> void:
	draw_rect(r, Color(0.16, 0.13, 0.09) if on else Color(0.09, 0.08, 0.11))
	if on:
		draw_rect(r, GOLD, false, 1.0)


func _draw() -> void:
	var vs := size
	draw_rect(Rect2(Vector2.ZERO, vs), Color(0.05, 0.04, 0.07, 0.985))
	var cr := _close_rect()
	draw_rect(cr, Color(0.1, 0.09, 0.12))
	draw_rect(cr, Color(0.3, 0.27, 0.33), false, 1.0)
	_text(cr.position + Vector2(9, 12), "Close", 9, Color(0.75, 0.72, 0.7))
	_text(Vector2(8, 20), "Party gear", 15, PAPER)
	# Tabs
	_tab_rects.clear()
	var tx := 100.0
	for t in (["equip", "shop"] if _shop_open() else ["equip"]):
		var label: String = "Equip" if t == "equip" else Progress.data().get("shop_name", "Shop")
		var w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x + 14
		var r := Rect2(tx, 8, w, 15)
		_tab_rects[t] = r
		_box(r, tab == t)
		_text(r.position + Vector2(7, 11), label, 9, GOLD if tab == t else SOFT)
		tx += w + 4
	_text(Vector2(tx + 8, 19), "Gilt: %d" % int(Empire.res.get("gilt", 0)), 9, GOLD)
	_hero_rects.clear()
	_slot_rects.clear()
	_pick_rects.clear()
	_shop_rects.clear()
	if _ids.is_empty():
		_text(Vector2(8, 50), "No field heroes on the roster.", 10, BAD)
		return
	if tab == "equip":
		_draw_equip(vs)
		var help := "Left/Right hero   Up/Down slot   Enter change   Esc or K close"
		if picking:
			help = "Up/Down choose   Enter put it on   Esc back"
		if _shop_open() and not picking:
			help += "   Tab shop"
		_text(Vector2(8, vs.y - 8), help, 7, Color(0.5, 0.48, 0.52))
	else:
		_draw_shop(vs)
		_text(Vector2(8, vs.y - 8), "Up/Down choose   Enter buy / sell   Tab equip   Esc or K close", 7, Color(0.5, 0.48, 0.52))
	if flash_t > 0.0:
		var a := clampf(flash_t / 0.4, 0.0, 1.0)
		var fw := font.get_string_size(flash, HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x
		draw_rect(Rect2(vs.x - fw - 18, vs.y - 21, fw + 12, 15), Color(0.1, 0.08, 0.06, 0.95 * a))
		_text(Vector2(vs.x - fw - 12, vs.y - 10), flash, 9, Color(1, 0.9, 0.7, a))


func _draw_equip(vs: Vector2) -> void:
	# Hero chips across the top
	var x := 8.0
	var cw := minf(96.0, (vs.x - 16.0 - 4.0 * (_ids.size() - 1)) / _ids.size())
	for i in _ids.size():
		var id: String = _ids[i]
		var r := Rect2(x, 30, cw, 24)
		_hero_rects.append(r)
		_box(r, i == hero_i)
		_text(r.position + Vector2(5, 10), PartyPicker.short_of(id), 9, GOLD if i == hero_i else TEXT, cw - 30)
		_text_r(r.position + Vector2(cw - 4, 10), "Lv%d" % Progress.level(id), 8, SOFT)
		_bar(Rect2(r.position + Vector2(5, 15), Vector2(cw - 10, 3)), Progress.xp_fraction(id), XP_COL)
		if Empire.role_of(id) == "party":
			draw_circle(r.position + Vector2(cw - 5, 19), 1.5, GOOD)
		x += cw + 4

	var id := _hero_id()
	var hd := PartyPicker.hero_data(id)
	var left := Rect2(8, 62, 300, vs.y - 62 - 18)
	draw_rect(left, Color(0.08, 0.07, 0.1))
	var y := left.position.y + 16
	_text(Vector2(16, y), Empire.recruit(id).get("name", PartyPicker.short_of(id)), 12, PAPER, 200)
	_text_r(Vector2(left.end.x - 8, y), "Level %d" % Progress.level(id), 10, GOLD)
	y += 12
	var need := Progress.xp_to_next(Progress.level(id))
	var xp_line := "Max level" if need <= 0 else "XP %d / %d to level %d" % [int(Progress.hero(id)["xp"]), need, Progress.level(id) + 1]
	_text(Vector2(16, y), xp_line, 8, XP_COL)
	var where_line := "In the party" if Empire.role_of(id) == "party" else "On the bench"
	if Empire.role_of(id) != "party" and Empire.level_of("barracks") > 0:
		where_line += ": Barracks drill, +%d XP a day" % Progress.barracks_xp()
	_text_r(Vector2(left.end.x - 8, y), where_line, 8, SOFT)
	y += 4
	_bar(Rect2(16, y, left.size.x - 16, 3), Progress.xp_fraction(id), XP_COL)
	y += 14

	# Stats, with a preview of the highlighted pick
	var now := Progress.stats(id)
	var preview := {}
	if picking:
		var ch := _choices()
		if pick_i < ch.size():
			preview = Progress.stats(id, {_slot(): ch[pick_i]})
	var rows := ["hp", "damage", "power_rate", "speed", "reach", "guard", "ink"]
	if int(now.get("heal", 0)) > 0:
		rows.append("heal")
	var col_w := (left.size.x - 16) / 2.0
	for j in rows.size():
		var k: String = rows[j]
		var sx := 16.0 + (j % 2) * col_w
		var sy := y + (j / 2) * 12.0
		_text(Vector2(sx, sy), Progress.STAT_NAMES[k], 8, SOFT)
		var val := _stat_shown(k, now[k])
		_text_r(Vector2(sx + col_w - 44, sy), val, 9, TEXT)
		if not preview.is_empty():
			var diff := float(preview[k]) - float(now[k])
			if absf(diff) > 0.001:
				var pv := _stat_shown(k, preview[k])
				_text(Vector2(sx + col_w - 40, sy), "> " + pv, 9, GOOD if diff > 0 else BAD)
	y += ceili(rows.size() / 2.0) * 12.0 + 2
	_text(Vector2(16, y), "%s. %s" % [hd.get("weapon", ""), hd.get("special", "")], 7, DIM, left.size.x - 16)
	y += 8

	# Slots
	var g := Progress.gear(id)
	for i in Progress.SLOTS.size():
		var s: String = Progress.SLOTS[i]
		var r := Rect2(16, y, left.size.x - 16, 26)
		_slot_rects.append(r)
		_box(r, i == slot_i)
		draw_rect(Rect2(r.position, Vector2(3, r.size.y)), SLOT_COLORS[s])
		_text(r.position + Vector2(8, 10), Progress.SLOT_NAMES[s].to_upper(), 7, SLOT_COLORS[s])
		var iid := str(g.get(s, ""))
		if iid == "":
			_text(r.position + Vector2(8, 21), "(nothing)", 9, DIM)
		else:
			_text(r.position + Vector2(8, 21), Progress.item(iid)["name"], 9, GOLD if i == slot_i else TEXT, 120)
			_text(r.position + Vector2(130, 21), Progress.item_text(iid), 8, GOOD if Progress.item(iid).get("stats", {}).size() > 0 else DIM, r.size.x - 134)
		var spare := Progress.options(id, s).size()
		if spare > 0:
			_text_r(r.position + Vector2(r.size.x - 6, 10), "%d spare" % spare, 7, GOOD)
		y += 30

	# Right side: the pick list, or about the highlighted slot
	var rx := 320.0
	var rw := vs.x - rx - 8
	var right := Rect2(rx, 62, rw, vs.y - 62 - 18)
	draw_rect(right, Color(0.08, 0.07, 0.1))
	var ry := right.position.y + 16
	if picking:
		_text(Vector2(rx + 8, ry), "%s for %s" % [Progress.SLOT_NAMES[_slot()], PartyPicker.short_of(id)], 10, PAPER)
		ry += 8
		var ch := _choices()
		for i in ch.size():
			var r := Rect2(rx + 6, ry, rw - 12, 22)
			_pick_rects.append(r)
			_box(r, i == pick_i)
			var k: String = ch[i]
			if k == "":
				_text(r.position + Vector2(6, 14), "Take it off" if str(g.get(_slot(), "")) != "" else "(leave empty)", 9, SOFT)
			else:
				_text(r.position + Vector2(6, 9), Progress.item(k)["name"], 9, GOLD if i == pick_i else TEXT)
				_text_r(r.position + Vector2(r.size.x - 6, 9), "x%d" % Progress.count(k), 8, SOFT)
				_text(r.position + Vector2(6, 19), Progress.item_text(k), 7, GOOD)
			ry += 24
		if pick_i < ch.size() and ch[pick_i] != "":
			_wrap(Vector2(rx + 8, ry + 10), Progress.item(ch[pick_i]).get("blurb", ""), rw - 16, 8, Color(0.78, 0.76, 0.74))
	else:
		var iid := str(g.get(_slot(), ""))
		_text(Vector2(rx + 8, ry), Progress.SLOT_NAMES[_slot()], 10, SLOT_COLORS[_slot()])
		ry += 14
		if iid == "":
			_text(Vector2(rx + 8, ry), "Nothing worn.", 9, DIM)
		else:
			_text(Vector2(rx + 8, ry), Progress.item(iid)["name"], 11, PAPER)
			ry += 12
			_text(Vector2(rx + 8, ry), Progress.item_text(iid), 8, GOOD, rw - 16)
			ry += 4
			ry += _wrap(Vector2(rx + 8, ry + 8), Progress.item(iid).get("blurb", ""), rw - 16, 8, Color(0.78, 0.76, 0.74))
		ry += 18
		var spare := Progress.options(id, _slot()).size()
		_text(Vector2(rx + 8, ry), ("Enter to swap: %d spare that fit." % spare) if spare > 0 else
			("Enter to take it off." if iid != "" else "No spare gear for this slot."), 8, GOLD if spare > 0 else SOFT, rw - 16)
		ry += 18
		_text(Vector2(rx + 8, ry), "Levels", 8, Color(0.75, 0.72, 0.7))
		ry += 2
		var gr := Progress.growth(id)
		var parts := []
		for k in Progress.STAT_ORDER:
			if gr.has(k) and float(gr[k]) > 0.0:
				var v := float(gr[k])
				parts.append(("+%d %s" % [int(v), Progress.STAT_NAMES[k]]) if v >= 1.0 else ("+1 %s every %d levels" % [Progress.STAT_NAMES[k], int(round(1.0 / v))]))
		ry += _wrap(Vector2(rx + 8, ry + 9), "Each level: " + ", ".join(parts) + ". XP comes from every enemy the party drops, shared by all three, plus a bonus for finishing the job. On missions the Barracks and research add their bonuses on top of these numbers.", rw - 16, 8, SOFT)


func _stat_shown(k: String, v) -> String:
	match k:
		"power_rate":
			return "%d%%" % int(round(float(v) * 100.0))
		"guard":
			return "%d%%" % int(round(float(v) * 100.0))
		_:
			return str(int(round(float(v))))


func _draw_shop(vs: Vector2) -> void:
	var d := Progress.data()
	_text(Vector2(8, 42), d.get("shop_blurb", ""), 8, SOFT, vs.x - 16)
	var rows := _shop_rows()
	var y := 52.0
	var lw := 330.0
	var last := ""
	var row_h := 14.0
	for i in rows.size():
		var kind: String = rows[i][0]
		var k: String = rows[i][1]
		var it := Progress.item(k)
		var head: String = Progress.SLOT_NAMES.get(it["slot"], "") if kind == "buy" else "sell"
		if head != last:
			last = head
			y += 10
			_text(Vector2(10, y - 2), ("SELL SPARE GEAR (half price)" if kind == "sell" else head.to_upper() + "S"), 7,
				SOFT if kind == "sell" else SLOT_COLORS.get(it["slot"], TEXT))
		var r := Rect2(8, y, lw, row_h - 2)
		_shop_rects.append(r)
		var on := i == shop_i
		_box(r, on)
		var why := Progress.shop_blocker(k) if kind == "buy" else ""
		var locked := why.begins_with("needs")
		var col := DIM if locked else (GOLD if on else TEXT)
		_text(r.position + Vector2(6, 9), it["name"], 8, col, 110)
		var owner := str(it.get("hero", ""))
		_text(r.position + Vector2(118, 9), PartyPicker.short_of(owner) if owner != "" else "anyone", 7, DIM if locked else SOFT, 50)
		_text(r.position + Vector2(170, 9), Progress.item_text(k), 7, DIM if locked else GOOD, 110)
		if kind == "buy":
			var have := Progress.count(k) + Progress.worn_by(k).size()
			if have > 0:
				_text_r(r.position + Vector2(lw - 46, 9), "have %d" % have, 7, SOFT)
			_text_r(r.position + Vector2(lw - 6, 9), "%d G" % int(it["price"]), 8, DIM if locked else (GOLD if why == "" else BAD))
		else:
			_text_r(r.position + Vector2(lw - 46, 9), "x%d" % Progress.count(k), 7, SOFT)
			_text_r(r.position + Vector2(lw - 6, 9), "+%d G" % Progress.sell_price(k), 8, GOOD)
		y += row_h
	if rows.is_empty():
		return
	shop_i = clampi(shop_i, 0, rows.size() - 1)
	var kind2: String = rows[shop_i][0]
	var k2: String = rows[shop_i][1]
	var it2 := Progress.item(k2)
	var rx := lw + 18
	var rw := vs.x - rx - 8
	draw_rect(Rect2(rx, 52, rw, vs.y - 52 - 18), Color(0.08, 0.07, 0.1))
	var ry := 68.0
	_text(Vector2(rx + 8, ry), it2["name"], 11, PAPER, rw - 16)
	ry += 12
	var owner2 := str(it2.get("hero", ""))
	_text(Vector2(rx + 8, ry), "%s, %s" % [Progress.SLOT_NAMES[it2["slot"]], ("for " + PartyPicker.short_of(owner2)) if owner2 != "" else "anyone can wear it"], 8, SLOT_COLORS.get(it2["slot"], TEXT))
	ry += 12
	_text(Vector2(rx + 8, ry), Progress.item_text(k2), 8, GOOD, rw - 16)
	ry += 4
	ry += _wrap(Vector2(rx + 8, ry + 8), it2.get("blurb", ""), rw - 16, 8, Color(0.78, 0.76, 0.74)) + 6
	# Compared with what each hero who could wear it has on now
	var who := _ids.filter(func(id): return Progress.wear_blocker(id, k2) == "")
	if not who.is_empty():
		_text(Vector2(rx + 8, ry + 8), "Compared with what they wear now", 8, Color(0.75, 0.72, 0.7))
		ry += 10
		for id in who:
			var now := Progress.stats(id)
			var then := Progress.stats(id, {it2["slot"]: k2})
			var parts := []
			for k in ["hp", "damage", "power_rate", "speed", "reach", "guard", "ink", "heal"]:
				var diff := float(then[k]) - float(now[k])
				if absf(diff) > 0.001:
					parts.append("%s%s %s" % ["+" if diff > 0 else "-", _stat_shown(k, absf(diff)).trim_prefix("+"), Progress.STAT_NAMES[k]])
			ry += 10
			var cur := str(Progress.gear(id).get(it2["slot"], ""))
			var line := "%s: %s" % [PartyPicker.short_of(id), ", ".join(parts) if not parts.is_empty() else "same as now"]
			_text(Vector2(rx + 8, ry + 2), line, 8, TEXT if cur != k2 else SOFT, rw - 16)
	ry += 20
	if kind2 == "buy":
		var why2 := Progress.shop_blocker(k2)
		_text(Vector2(rx + 8, ry), ("Enter to buy for %d Gilt." % int(it2["price"])) if why2 == "" else ("Can't buy: %s." % why2), 8, GOLD if why2 == "" else BAD, rw - 16)
	else:
		_text(Vector2(rx + 8, ry), "Enter to sell one for %d Gilt." % Progress.sell_price(k2), 8, GOLD, rw - 16)
