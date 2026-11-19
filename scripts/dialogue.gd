class_name Dialogue
extends RefCounted
## Shared dialogue data and helpers (issue #11). Everything here is static, so any scene can use it
## without an autoload: Dialogue.talk("meadow_intro"), Dialogue.portrait("bran", "smug"), ...
##
## data/dialogue.json holds the words: conversations ("talks"), first chats in town ("first_talk"),
## event banter ("events") and walking banter zones per map ("banter"). See its _comment.
##
## A line is [speaker, text] or [speaker, text, expression]. Speaker is a recruit id, a key from
## "speakers" (characters who are not recruits) or "" for narration. Lines are normalised to
## [speaker, text, expression] by line().
##
## Portraits: assets/portraits/<id>_<expression>.png, then assets/portraits/<id>.png. When neither
## exists the boxes draw a placeholder bust from the character's colours (draw_bust).
##
## Seen conversations and banter zones are saved with the campaign (Empire.to_dict "dialogue").
## Text speed is a per-device setting kept in user://settings.cfg.

const DATA_PATH := "res://data/dialogue.json"
const PORTRAIT_DIR := "res://assets/portraits/"
const SETTINGS_PATH := "user://settings.cfg"
## Typewriter speeds in characters per second. 0 = whole line at once.
const SPEEDS := [["Slow", 28.0], ["Normal", 60.0], ["Fast", 120.0], ["Instant", 0.0]]

static var seen := {}  # "talk:<id>" / "banter:<id>" / "event:<id>" -> true
static var _data := {}
static var _portraits := {}  # "<id>|<expr>" -> Texture2D or null
static var _speed := -1


static func data() -> Dictionary:
	if _data.is_empty():
		var f := FileAccess.open(DATA_PATH, FileAccess.READ)
		if f:
			var parsed = JSON.parse_string(f.get_as_text())
			if typeof(parsed) == TYPE_DICTIONARY:
				_data = parsed
		# The main story's talks and speakers (data/story.json, issue #18) play like any others.
		for k in ["speakers", "talks"]:
			if not _data.has(k):
				_data[k] = {}
			_data[k].merge(Story.data().get(k, {}))
	return _data


## [speaker, text, expression] from either list or {"who", "text", "expr"} form.
static func line(l) -> Array:
	if typeof(l) == TYPE_DICTIONARY:
		return [String(l.get("who", "")), String(l.get("text", "")), String(l.get("expr", ""))]
	var a: Array = l
	return [String(a[0]) if a.size() > 0 else "", String(a[1]) if a.size() > 1 else "", String(a[2]) if a.size() > 2 else ""]


static func lines(raw: Array) -> Array:
	return raw.map(func(l): return line(l))


## A whole conversation's lines, normalised. Empty when the id is unknown.
static func talk(id: String) -> Array:
	var t = data().get("talks", {}).get(id, {})
	if typeof(t) == TYPE_DICTIONARY:
		return lines(t.get("lines", []))
	return lines(t)


static func talk_title(id: String) -> String:
	var t = data().get("talks", {}).get(id, {})
	return String(t.get("title", "")) if typeof(t) == TYPE_DICTIONARY else ""


## The conversation someone starts the first time Ash talks to them in town ("" when none is left).
static func first_talk(who: String) -> String:
	var id := String(data().get("first_talk", {}).get(who, ""))
	if id == "" or is_seen("talk:" + id) or talk(id).is_empty():
		return ""
	return id


static func is_seen(key: String) -> bool:
	return seen.has(key)


static func mark_seen(key: String) -> void:
	seen[key] = true


# ---------------------------------------------------------------- who is speaking

static func speaker_info(who: String) -> Dictionary:
	return data().get("speakers", {}).get(who, {})


static func display_name(who: String) -> String:
	if who == "":
		return ""
	var info := speaker_info(who)
	if info.has("name"):
		return String(info["name"])
	if Empire.recruit_data.has(who):
		return Empire.short_name(who)
	return who.capitalize()


## The accent colour for name tags and card backgrounds.
static func accent(who: String) -> Color:
	var info := speaker_info(who)
	if info.has("color"):
		return Color(info["color"])
	var b: Dictionary = Empire.bond_info(who)
	if b.has("color"):
		return Color(b["color"])
	var cols := _colors(who)
	for k in ["accent", "cloth", "metal", "trim"]:
		if cols.has(k):
			return Color(cols[k])
	return Color("c9c3b6")


static func _colors(who: String) -> Dictionary:
	var info := speaker_info(who)
	if info.has("colors"):
		return info["colors"]
	return Empire.recruit(who).get("look", {}).get("colors", {}) if Empire.recruit_data.has(who) else {}


static func _col(cols: Dictionary, keys: Array, fallback: String) -> Color:
	for k in keys:
		if cols.has(k):
			return Color(cols[k])
	return Color(fallback)


## The portrait image for this speaker and expression, or null (draw a placeholder bust instead).
static func portrait(who: String, expr := "") -> Texture2D:
	if who == "":
		return null
	var key := "%s|%s" % [who, expr]
	if _portraits.has(key):
		return _portraits[key]
	var tex: Texture2D = null
	var tries := []
	if expr != "":
		tries.append("%s%s_%s.png" % [PORTRAIT_DIR, who, expr])
	tries.append("%s%s.png" % [PORTRAIT_DIR, who])
	for p in tries:
		if ResourceLoader.exists(p):
			tex = load(p) as Texture2D
			if tex:
				break
	_portraits[key] = tex
	return tex


## Draw this speaker into r: the portrait scaled to fit (feet on the bottom edge), or a placeholder
## head-and-shoulders bust in their colours. dim darkens it (for whoever is not talking).
## Portraits face the viewer's left; flip = mirror them to face right (for the left side of the stage).
static func draw_portrait(ci: CanvasItem, r: Rect2, who: String, expr := "", dim := 0.0, flip := false) -> void:
	var tex := portrait(who, expr)
	var tint := Color(1, 1, 1).darkened(dim)
	if tex:
		var ts := tex.get_size()
		var s := minf(r.size.x / ts.x, r.size.y / ts.y)
		var sz := ts * s
		var cx := r.get_center().x
		if flip:
			ci.draw_set_transform(Vector2(2.0 * cx, 0), 0.0, Vector2(-1, 1))
		ci.draw_texture_rect(tex, Rect2(Vector2(cx - sz.x / 2.0, r.end.y - sz.y), sz), false, tint)
		if flip:
			ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	else:
		draw_bust(ci, r, who, dim)


## Just the face, for small banter portraits: the top part of the portrait image, or a small bust.
static func draw_face(ci: CanvasItem, r: Rect2, who: String, expr := "") -> void:
	var tex := portrait(who, expr)
	ci.draw_rect(r, accent(who).darkened(0.7))
	if tex:
		var ts := tex.get_size()
		var side := ts.x * 0.62  # a square around the head, roughly the top third of a 2:3 portrait
		var src := Rect2((ts.x - side) / 2.0, ts.y * 0.04, side, side)
		ci.draw_texture_rect_region(tex, r, src)
	else:
		draw_bust(ci, Rect2(r.position + Vector2(-r.size.x * 0.25, 0), Vector2(r.size.x * 1.5, r.size.y * 1.7)), who, 0.0, r)
	ci.draw_rect(r, accent(who).lightened(0.1), false, 1.0)


## Placeholder bust drawn in code from the paper-doll colours, until the AI portraits (#12) land.
## clip: only draw inside this rect (used by draw_face, which zooms in on the head).
static func draw_bust(ci: CanvasItem, r: Rect2, who: String, dim := 0.0, clip := Rect2()) -> void:
	var cols := _colors(who)
	var skin := _col(cols, ["skin"], "d9a07a").darkened(dim)
	var cloth := _col(cols, ["cloth", "metal"], "5a4a6a").darkened(dim)
	var trim := _col(cols, ["trim", "accent", "metal"], "c9c3b6").darkened(dim)
	var hair := _col(cols, ["hair", "leather", "boots"], "3a2c22").darkened(dim)
	var c := Vector2(r.get_center().x, r.end.y)
	var w := r.size.x * 0.86
	var h := r.size.y
	var parts := []  # [kind, data, color]
	parts.append(["poly", PackedVector2Array([c + Vector2(-w / 2, 0), c + Vector2(-w / 2 + 8, -h * 0.3),
		c + Vector2(-w * 0.18, -h * 0.36), c + Vector2(w * 0.18, -h * 0.36),
		c + Vector2(w / 2 - 8, -h * 0.3), c + Vector2(w / 2, 0)]), cloth])
	parts.append(["poly", PackedVector2Array([c + Vector2(-w * 0.12, -h * 0.36), c + Vector2(w * 0.12, -h * 0.36),
		c + Vector2(0, -h * 0.22)]), skin.darkened(0.15)])
	var head := c + Vector2(0, -h * 0.56)
	var hr := r.size.x * 0.2
	parts.append(["rect", Rect2(head.x - hr * 0.35, head.y + hr * 0.6, hr * 0.7, h * 0.1), skin.darkened(0.1)])
	parts.append(["circle", [head + Vector2(0, -hr * 0.12), hr * 1.08], hair])
	parts.append(["circle", [head + Vector2(0, hr * 0.1), hr], skin])
	parts.append(["rect", Rect2(head.x - hr, head.y - hr * 0.9, hr * 2, hr * 0.55), hair])
	parts.append(["circle", [head + Vector2(-hr * 0.38, hr * 0.12), maxf(1.0, hr * 0.08)], Color(0.1, 0.08, 0.1)])
	parts.append(["circle", [head + Vector2(hr * 0.38, hr * 0.12), maxf(1.0, hr * 0.08)], Color(0.1, 0.08, 0.1)])
	for p in parts:
		match p[0]:
			"poly":
				var pts: PackedVector2Array = p[1]
				if clip.has_area():
					pts = _clip_poly(pts, clip)
				if pts.size() >= 3:
					ci.draw_colored_polygon(pts, p[2])
			"rect":
				var rr: Rect2 = p[1]
				if clip.has_area():
					rr = rr.intersection(clip)
				if rr.has_area():
					ci.draw_rect(rr, p[2])
			"circle":
				var cc: Vector2 = p[1][0]
				var rad: float = p[1][1]
				if clip.has_area():
					var poly := PackedVector2Array()
					for i in 20:
						poly.append(cc + Vector2.from_angle(TAU * i / 20.0) * rad)
					poly = _clip_poly(poly, clip)
					if poly.size() >= 3:
						ci.draw_colored_polygon(poly, p[2])
				else:
					ci.draw_circle(cc, rad, p[2])
	if not clip.has_area():
		ci.draw_line(c + Vector2(-w * 0.18, -h * 0.36), c + Vector2(0, -h * 0.2), trim, 2.0)
		ci.draw_line(c + Vector2(w * 0.18, -h * 0.36), c + Vector2(0, -h * 0.2), trim, 2.0)


static func _clip_poly(pts: PackedVector2Array, clip: Rect2) -> PackedVector2Array:
	var box := PackedVector2Array([clip.position, Vector2(clip.end.x, clip.position.y), clip.end, Vector2(clip.position.x, clip.end.y)])
	var res := Geometry2D.intersect_polygons(pts, box)
	return res[0] if not res.is_empty() else PackedVector2Array()


# ---------------------------------------------------------------- text speed (per device)

static func speed_index() -> int:
	if _speed < 0:
		_speed = 1
		var cfg := ConfigFile.new()
		if cfg.load(SETTINGS_PATH) == OK:
			_speed = clampi(int(cfg.get_value("dialogue", "text_speed", 1)), 0, SPEEDS.size() - 1)
	return _speed


static func speed_name() -> String:
	return SPEEDS[speed_index()][0]


## Characters per second for typewriter text (0 = show the whole line at once).
static func chars_per_sec() -> float:
	return SPEEDS[speed_index()][1]


static func cycle_speed() -> void:
	_speed = (speed_index() + 1) % SPEEDS.size()
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("dialogue", "text_speed", _speed)
	cfg.save(SETTINGS_PATH)


# ---------------------------------------------------------------- banter

## Walking banter zones for a map id (the map file's name, e.g. "frayed_meadow").
static func banter_zones(map_id: String) -> Array:
	return data().get("banter", {}).get(map_id, [])


## Lines for a named event ("first_kill", "low_power", ...), or [] if it already played and is once-only.
static func event_lines(id: String) -> Array:
	var e = data().get("events", {}).get(id, {})
	if typeof(e) != TYPE_DICTIONARY or e.is_empty():
		return []
	if e.get("once", true) and is_seen("event:" + id):
		return []
	return lines(e.get("lines", []))
