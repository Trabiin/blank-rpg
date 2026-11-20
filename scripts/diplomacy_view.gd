extends Control
## Diplomacy screen. Opened with F, from the menus, or the Diplomacy button on the Command Table.
##
## One list (Up/Down, Enter, Esc; mouse and touch tap): for each faction, its envoy and the deals
## you can make. Enter on the envoy row opens a picker (who to send, with the standing they would
## win per day); Enter on a deal makes it. The right panel explains the selected row: standing,
## why it moves, what the faction's tiers do, and what happened lately.

signal closed

const GOLD := Color("ffd166")
const GOOD := Color("9fd18b")
const BAD := Color("ff9b8a")
const TEXT := Color("ece6da")
const DIM := Color(0.42, 0.41, 0.44)
const SOFT := Color(0.62, 0.6, 0.62)
const ROW_H := 13.0
const HEAD_H := 25.0
const LIST_W := 300.0
const FACTION_COLORS := {"guild": Color("c98a74"), "coven": Color("7fb0a4"), "concord": Color("d9b25e")}
const TIER_COLORS := {"hostile": Color("ff7b6b"), "wary": Color("e8a86a"), "neutral": Color("c9c3b6"),
	"friendly": Color("9fd18b"), "allied": Color("7fd6c2")}

var page := "list"  # "list" or "envoy" (picking who to send)
var sel := 0
var pick_faction := ""
var closed_frame := -1
var opened_frame := -1
var flash := ""
var flash_t := 0.0
var _rows: Array = []  # {"kind": envoy|deal|person|recall, "faction", "id"}
var _row_rects: Array = []
var _list_sel := 0  # where to come back to from the picker
var font: Font


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	font = ThemeDB.fallback_font


func open() -> void:
	position = Vector2.ZERO
	size = get_viewport_rect().size
	visible = true
	opened_frame = Engine.get_process_frames()
	_go("list")
	sel = 0
	# Start on the first thing you can do (a deal you can make, else an empty envoy post).
	for i in _rows.size():
		var r: Dictionary = _rows[i]
		if r["kind"] == "deal" and Empire.deal_blocker(r["faction"], r["id"]) == "":
			sel = i
			return
	for i in _rows.size():
		if _rows[i]["kind"] == "envoy" and Empire.envoy_of(_rows[i]["faction"]) == "":
			sel = i
			return


func close() -> void:
	visible = false
	closed_frame = Engine.get_process_frames()
	closed.emit()


func _go(p: String) -> void:
	page = p
	_rows.clear()
	if page == "list":
		for fid in Empire.faction_ids():
			_rows.append({"kind": "envoy", "faction": fid, "id": ""})
			for k in Empire.deal_ids(fid):
				_rows.append({"kind": "deal", "faction": fid, "id": k})
		sel = clampi(_list_sel, 0, _rows.size() - 1)
	else:
		_rows.append({"kind": "recall", "faction": pick_faction, "id": ""})
		var ids := Empire.roster_ids()
		ids.sort_custom(func(a, b):
			var fa := _person_blocker(a) == ""
			var fb := _person_blocker(b) == ""
			if fa != fb:
				return fa
			return int(Empire.envoy_effect(a, pick_faction)["drift"]) > int(Empire.envoy_effect(b, pick_faction)["drift"]))
		for id in ids:
			_rows.append({"kind": "person", "faction": pick_faction, "id": id})
		sel = 0
		var cur := Empire.envoy_of(pick_faction)
		for i in _rows.size():
			if _rows[i]["id"] == cur and cur != "":
				sel = i


func _person_blocker(id: String) -> String:
	for o in Empire.role_options(id):
		if o["role"] == "envoy" and o["target"] == pick_faction:
			return o["note"] if not o["enabled"] else ""
	return Empire.role_label(id).to_lower()  # away on an expedition: no envoy option at all


func _process(delta: float) -> void:
	if not visible:
		return
	flash_t = maxf(flash_t - delta, 0.0)
	queue_redraw()
	if Engine.get_process_frames() == opened_frame or _rows.is_empty():
		return
	if Input.is_action_just_pressed("move_up") or Input.is_action_just_pressed("ui_up"):
		sel = posmod(sel - 1, _rows.size())
	elif Input.is_action_just_pressed("move_down") or Input.is_action_just_pressed("ui_down"):
		sel = posmod(sel + 1, _rows.size())
	if Input.is_action_just_pressed("ui_accept"):
		_pick(sel)
	elif Input.is_action_just_pressed("diplomacy"):
		close()
	elif Input.is_action_just_pressed("ui_cancel") or Input.is_action_just_pressed("pause"):
		_back()


func _back() -> void:
	if page == "envoy":
		_go("list")
	else:
		close()


func _say(s: String) -> void:
	flash = s
	flash_t = 3.2


func _pick(i: int) -> void:
	var r: Dictionary = _rows[i]
	var fid: String = r["faction"]
	var fa := Empire.faction(fid)
	match r["kind"]:
		"envoy":
			_list_sel = i
			pick_faction = fid
			_go("envoy")
		"deal":
			var why := Empire.deal_blocker(fid, r["id"])
			if why != "":
				_say("Can't: %s." % why)
				return
			var said := Empire.make_deal(fid, r["id"])
			if said != "":
				_say(said)
		"recall":
			var cur := Empire.envoy_of(fid)
			if cur != "":
				Empire.assign(cur, "idle")
				_say("%s is back from the %s." % [Empire.short_name(cur), fa["short"]])
			_go("list")
		"person":
			var why := _person_blocker(r["id"])
			if why != "":
				_say("Can't: %s." % why)
				return
			if Empire.envoy_of(fid) == r["id"]:
				_go("list")
				return
			if Empire.assign(r["id"], "envoy", fid):
				_say("%s goes to the %s: standing %+d a day." % [Empire.short_name(r["id"]), fa["short"], Empire.standing_rate(fid)])
				_go("list")


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		for i in _row_rects.size():
			if (_row_rects[i] as Rect2).has_point(event.position):
				sel = i
	elif Prompts.tapped(event):
		for i in _row_rects.size():
			if (_row_rects[i] as Rect2).has_point(event.position):
				if sel == i:
					_pick(i)  # tap to select, tap again to act (touch friendly)
				else:
					sel = i
				return
		if _close_rect().has_point(event.position):
			_back()


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


## A -100..100 standing bar with tier marks.
func _standing_bar(r: Rect2, v: int) -> void:
	draw_rect(r, Color(0.14, 0.12, 0.16))
	var mid := r.position.x + r.size.x * 0.5
	var x := r.position.x + r.size.x * (float(v) + 100.0) / 200.0
	var col: Color = TIER_COLORS[Empire.tier_for(v)]
	draw_rect(Rect2(Vector2(minf(mid, x), r.position.y), Vector2(absf(x - mid), r.size.y)), col)
	for t in ["wary", "neutral", "friendly", "allied"]:
		var tx := r.position.x + r.size.x * (float(Empire.tier_min(t)) + 100.0) / 200.0
		draw_line(Vector2(tx, r.position.y - 1), Vector2(tx, r.end.y + 1), Color(0.05, 0.04, 0.07), 1.0)
	draw_line(Vector2(mid, r.position.y - 2), Vector2(mid, r.end.y + 2), Color(0.8, 0.78, 0.72, 0.7), 1.0)


func _draw() -> void:
	var vs := size
	UiSkin.screen(self, vs)
	var cr := _close_rect()
	UiSkin.panel(self, cr, "button")
	_text(cr.position + Vector2(9, 12), "Back" if page == "envoy" else "Close", 9, Color(0.75, 0.72, 0.7))
	_row_rects.clear()
	if page == "envoy":
		_draw_picker(vs)
	else:
		_draw_list(vs)
	var help := Prompts.help([["updown", "choose"], ["ui_accept", "send"], ["ui_cancel", "back"]], "Tap an envoy, tap again to send   Close: back") if page == "envoy" else Prompts.help([["updown", "choose"], ["ui_accept", "pick envoy / make deal"], [["ui_cancel", "diplomacy"], "close"]], "Tap a row, tap again to act")
	_text(Vector2(8, vs.y - 8), help, 7, Color(0.5, 0.48, 0.52))
	if flash_t > 0.0:
		var a := clampf(flash_t / 0.4, 0.0, 1.0)
		var w := minf(font.get_string_size(flash, HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x, vs.x - 40)
		draw_rect(Rect2(vs.x - w - 18, vs.y - 21, w + 12, 15), Color(0.1, 0.08, 0.06, 0.95 * a))
		_text(Vector2(vs.x - w - 12, vs.y - 10), flash, 9, Color(1, 0.9, 0.7, a), w)


func _draw_list(vs: Vector2) -> void:
	_text(Vector2(8, 20), "Diplomacy", 15, Color("f3efe4"))
	var trouble := Empire.trouble_text()
	var sub := "Post an envoy to win standing each day. Deals unlock as standing rises."
	if Empire.intel_until > Empire.day:
		sub = "Fresh intel: +1 day of surge warning for %d more day%s." % [Empire.intel_until - Empire.day, "" if Empire.intel_until - Empire.day == 1 else "s"]
	_text(Vector2(90, 20), sub, 8, GOLD)
	if trouble != "":
		_text(Vector2(8, 34), trouble + " Get them to Neutral (-9) to stop it.", 8, BAD)
	var y := 38.0
	var last := ""
	for i in _rows.size():
		var r: Dictionary = _rows[i]
		var fid: String = r["faction"]
		var fa := Empire.faction(fid)
		if fid != last:
			last = fid
			y += 4
			var v := Empire.standing_of(fid)
			var tier := Empire.tier_of(fid)
			draw_rect(Rect2(8, y, 3, HEAD_H - 6), FACTION_COLORS.get(fid, TEXT))
			var fx := 15.0
			if UiSkin.draw_icon(self, fid, Rect2(14, y - 1, 12, 12)):
				fx = 29.0
			_text(Vector2(fx, y + 9), fa["name"], 10, FACTION_COLORS.get(fid, TEXT))
			_text_r(Vector2(8 + LIST_W, y + 9), "%s %+d" % [Empire.tier_name(tier), v], 9, TIER_COLORS[tier])
			var rate := Empire.standing_rate(fid)
			_standing_bar(Rect2(15, y + 13, LIST_W - 70, 4), v)
			_text_r(Vector2(8 + LIST_W, y + 18), "%+d/day" % rate, 8, GOOD if rate > 0 else (BAD if rate < 0 else SOFT))
			y += HEAD_H
		var rr := Rect2(14, y, LIST_W - 6, ROW_H - 1)
		_row_rects.append(rr)
		var on := i == sel
		draw_rect(rr, Color(0.16, 0.13, 0.09) if on else Color(0.09, 0.08, 0.11))
		if on:
			draw_rect(rr, GOLD, false, 1.0)
		var base := rr.position + Vector2(6, 9)
		if r["kind"] == "envoy":
			var env := Empire.envoy_of(fid)
			_text(base, "Envoy", 8, SOFT)
			if env == "":
				_text(base + Vector2(44, 0), "nobody posted", 9, GOLD if on else Color("e8a86a"))
			else:
				_text(base + Vector2(44, 0), Empire.recruit(env)["name"], 9, GOLD if on else TEXT, 150)
				var hurt := int(Empire.recruits[env]["injured"]) > 0
				_text_r(base + Vector2(LIST_W - 18, 0), "injured" if hurt else "%+d/day" % int(Empire.envoy_effect(env, fid)["drift"]), 8, BAD if hurt else GOOD)
		else:
			var k: String = r["id"]
			var d := Empire.deal(fid, k)
			var why := Empire.deal_blocker(fid, k)
			var active: bool = k == "trade" and fid in Empire.pacts
			var col := TEXT if why == "" else DIM
			if active:
				col = GOOD
			_text(base, d["name"], 9, GOLD if on and why == "" else col, 160)
			var right := ""
			var rc := SOFT
			if active:
				right = "active: %s/day" % Empire.output_text(d["daily"])
				rc = GOOD
			elif why == "":
				right = Empire.cost_text(d["cost"]) if d.has("cost") else "%d standing" % int(d.get("standing", 0))
				rc = GOLD
			elif not Empire.at_least(fid, Empire.DEAL_TIER[k]):
				right = Empire.tier_name(Empire.DEAL_TIER[k])
				rc = DIM
			elif why == "post an envoy first":
				right = "needs envoy"
				rc = Color("e8a86a")
			else:
				right = "not now"
				rc = DIM
			_text_r(base + Vector2(LIST_W - 18, 0), right, 8, rc)
		y += ROW_H
	_draw_details(vs)


func _draw_details(vs: Vector2) -> void:
	if _rows.is_empty():
		return
	var r: Dictionary = _rows[sel]
	var fid: String = r["faction"]
	var fa := Empire.faction(fid)
	var x := LIST_W + 26
	var w := vs.x - x - 10
	var top := 38.0
	draw_rect(Rect2(x - 8, top, w + 16, vs.y - top - 24), Color(0.08, 0.07, 0.1))
	draw_rect(Rect2(x - 8, top, 3, vs.y - top - 24), FACTION_COLORS.get(fid, TEXT))
	var y := top + 14
	if r["kind"] == "deal":
		var k: String = r["id"]
		var d := Empire.deal(fid, k)
		_text(Vector2(x, y), d["name"], 12, Color("f3efe4"), w)
		y += 4
		y += _wrap(Vector2(x, y + 9), d["text"], w, 8, Color(0.82, 0.8, 0.76)) + 4
		var summ := Empire.deal_summary(fid, k)
		y += _wrap(Vector2(x, y + 9), summ.substr(0, 1).to_upper() + summ.substr(1) + ".", w, 8, GOLD) + 2
		var need: String = Empire.DEAL_TIER[k]
		_text(Vector2(x, y + 9), "Needs %s standing%s." % [Empire.tier_name(need), "" if k == "trade" else " and an envoy posted"] if need != "hostile" else "Any standing, with an envoy posted.", 8, SOFT, w)
		y += 12
		if k == "trade":
			_text(Vector2(x, y + 9), "The pact holds while standing stays at %d or more." % Empire.trade_breaks, 8, SOFT, w)
			y += 12
		var why := Empire.deal_blocker(fid, k)
		if k == "trade" and fid in Empire.pacts:
			_text(Vector2(x, y + 9), "Active. Paying %s every dawn (see the ledger, L)." % Empire.output_text(d["daily"]), 8, GOOD, w)
		elif why != "":
			y += _wrap(Vector2(x, y + 9), "Can't yet: %s." % why, w, 8, BAD)
		else:
			_text(Vector2(x, y + 9), "Ready. %s to send." % Prompts.confirm(), 8, GOOD, w)
		y += 22
	else:
		_text(Vector2(x, y), fa["name"], 12, Color("f3efe4"), w)
		y += 4
		y += _wrap(Vector2(x, y + 9), "Wants: " + fa["wants"], w, 8, GOLD) + 2
		y += _wrap(Vector2(x, y + 9), fa["blurb"], w, 8, Color(0.78, 0.76, 0.74)) + 6
	# Standing and why it moves
	var v := Empire.standing_of(fid)
	var tier := Empire.tier_of(fid)
	_text(Vector2(x, y), "Standing", 8, Color(0.75, 0.72, 0.7))
	_text_r(Vector2(x + w, y), "%s %+d" % [Empire.tier_name(tier), v], 9, TIER_COLORS[tier])
	y += 4
	_standing_bar(Rect2(x, y, w, 5), v)
	y += 8
	var srcs := Empire.standing_sources(fid)
	if srcs.is_empty():
		_text(Vector2(x, y + 9), "Not moving. Post an envoy (they respect %s)." % Empire.STAT_NAMES[fa["respects"]], 8, Color("e8a86a"), w)
		y += 11
	for s in srcs:
		_text(Vector2(x, y + 9), "%+d" % int(s[1]), 8, GOOD if int(s[1]) > 0 else BAD)
		_text(Vector2(x + 22, y + 9), s[0], 8, SOFT, w - 22)
		y += 11
	if r["kind"] == "envoy" and Empire.envoy_of(fid) != "":
		for wy in Empire.envoy_effect(Empire.envoy_of(fid), fid)["why"]:
			_text(Vector2(x + 22, y + 9), wy[0], 7, Color(0.55, 0.53, 0.56), w - 22)
			y += 9
	y += 6
	var perk_col := GOOD if Empire.has_perk(fid) else DIM
	y += _wrap(Vector2(x, y + 9), ("Friendly perk (on): " if Empire.has_perk(fid) else "At Friendly: ") + fa["perk"]["text"] + ".", w, 8, perk_col) + 6
	# Lately
	var log := Empire.diplo_log.filter(func(e): return e["faction"] == fid)
	if not log.is_empty() and y < vs.y - 50:
		_text(Vector2(x, y + 2), "Lately", 8, Color(0.75, 0.72, 0.7))
		y += 4
		for e in log.slice(0, 4):
			if y > vs.y - 40:
				break
			var change := int(e.get("change", 0))
			var line := "Day %d: %s%s" % [int(e["day"]), e["text"], "" if change == 0 else " (%+d)" % change]
			y += _wrap(Vector2(x, y + 9), line, w, 7, BAD if change < 0 or e.get("trouble", false) else SOFT) + 1


func _draw_picker(vs: Vector2) -> void:
	var fa := Empire.faction(pick_faction)
	_text(Vector2(8, 20), "Envoy to %s" % fa["name"], 13, FACTION_COLORS.get(pick_faction, TEXT))
	_text(Vector2(8, 34), "They respect %s. Charm always helps. The envoy lives with them, away from Hollowmark." % Empire.STAT_NAMES[fa["respects"]], 8, GOLD)
	var y := 44.0
	for i in _rows.size():
		var r: Dictionary = _rows[i]
		var rr := Rect2(8, y, LIST_W, ROW_H + 1)
		_row_rects.append(rr)
		var on := i == sel
		draw_rect(rr, Color(0.16, 0.13, 0.09) if on else Color(0.09, 0.08, 0.11))
		if on:
			draw_rect(rr, GOLD, false, 1.0)
		var base := rr.position + Vector2(6, 10)
		if r["kind"] == "recall":
			var cur := Empire.envoy_of(pick_faction)
			_text(base, "Nobody (recall %s)" % Empire.short_name(cur) if cur != "" else "Nobody", 9, GOLD if on else SOFT)
		else:
			var id: String = r["id"]
			var why := _person_blocker(id)
			var here := Empire.envoy_of(pick_faction) == id
			var col := TEXT if why == "" else DIM
			_text(base, Empire.recruit(id)["name"] + ("  (here now)" if here else ""), 9, GOLD if on and why == "" else col, 160)
			if why != "":
				_text_r(base + Vector2(LIST_W - 12, 0), why, 8, DIM)
			else:
				var role := Empire.role_of(id)
				if role != "idle" and not here:
					var tag: String = Empire.ROLE_NAMES.get(role, role)
					if role == "envoy":
						tag = "Envoy, %s" % Empire.faction(Empire.recruits[id]["target"]).get("short", "?")
					_text(base + Vector2(165, 0), tag, 7, Color("e8a86a"))
				_text_r(base + Vector2(LIST_W - 12, 0), "%+d/day" % int(Empire.envoy_effect(id, pick_faction)["drift"]), 9, GOOD)
		y += ROW_H + 2
	# Details for the highlighted person
	var r: Dictionary = _rows[sel]
	var x := LIST_W + 26
	var w := vs.x - x - 10
	var top := 44.0
	draw_rect(Rect2(x - 8, top, w + 16, vs.y - top - 24), Color(0.08, 0.07, 0.1))
	draw_rect(Rect2(x - 8, top, 3, vs.y - top - 24), FACTION_COLORS.get(pick_faction, TEXT))
	var yy := top + 14
	var env := "" if r["kind"] == "recall" else String(r["id"])
	if env == "":
		_text(Vector2(x, yy), "No envoy", 12, Color("f3efe4"))
		yy += 4
		yy += _wrap(Vector2(x, yy + 9), "Nobody talks to the %s for you. Standing only moves through what you do, and you can't make deals." % fa["short"], w, 8, SOFT) + 6
	else:
		var rec := Empire.recruit(env)
		_text(Vector2(x, yy), rec["name"], 12, Color("f3efe4"), w)
		yy += 12
		var st: Dictionary = rec["stats"]
		var parts := []
		for k in ["might", "craft", "lore", "charm", "grit"]:
			parts.append("%s %d" % [Empire.STAT_NAMES[k], int(st[k])])
		_text(Vector2(x, yy), "   ".join(parts), 8, SOFT, w)
		yy += 6
		var traits := []
		for t in rec.get("traits", []):
			traits.append(Empire.trait_data.get(t, {}).get("name", t))
		if not traits.is_empty():
			_text(Vector2(x, yy + 8), ", ".join(traits), 8, Color("d7b8f0"), w)
			yy += 10
		yy += 6
		_text(Vector2(x, yy + 8), "As envoy:", 8, Color(0.75, 0.72, 0.7))
		yy += 10
		for wy in Empire.envoy_effect(env, pick_faction)["why"]:
			yy += _wrap(Vector2(x, yy + 9), wy[0], w, 8, GOOD if wy[1] else BAD) + 1
		var role := Empire.role_of(env)
		if role != "idle" and Empire.envoy_of(pick_faction) != env:
			yy += _wrap(Vector2(x, yy + 9), "Leaves their post: %s." % Empire.role_label(env), w, 8, Color("e8a86a")) + 1
		var cur := Empire.envoy_of(pick_faction)
		if cur != "" and cur != env:
			yy += _wrap(Vector2(x, yy + 9), "Replaces %s, who comes home idle." % Empire.short_name(cur), w, 8, SOFT) + 1
	yy += 8
	var rate := Empire.standing_rate(pick_faction, env)
	_text(Vector2(x, yy + 9), "Standing would move %+d a day (now %+d)." % [rate, Empire.standing_rate(pick_faction)], 9, GOOD if rate > 0 else BAD)
