extends StaticBody2D
## One building plot in Hollowmark. Shows a staked-out empty plot, scaffolding while the
## builders work, and the finished building (with a name board and its level) once built.
## Origin = the bottom-centre of the 5x5-tile plot.
##
## Built looks are art pass sprites, res://assets/buildings/<look>_<level>.png, with a few code-drawn
## touches (smoke, candlelight). LOOKS keeps the collision box and the old CC0 look as a fallback.

const PLOT := Vector2(80, 80)
## look -> list of sprites [source rect in the overworld sheet, offset of its bottom-centre
## from the plot's bottom-centre], plus the collision box (width, depth) when built.
const LOOKS := {
	"barracks": {"parts": [[Rect2(176, 0, 80, 80), Vector2(4, 0)], [Rect2(80, 432, 32, 32), Vector2(-30, 2)]], "box": Vector2(72, 40)},
	"infirmary": {"parts": [[Rect2(96, 0, 80, 80), Vector2(0, 0)]], "box": Vector2(72, 40), "tint": Color(0.92, 0.95, 1.0)},
	"inkworks": {"parts": [[Rect2(0, 336, 48, 112), Vector2(-8, 0)]], "box": Vector2(42, 30), "tint": Color(0.72, 0.76, 0.92)},
	"scriptorium": {"parts": [[Rect2(48, 352, 48, 80), Vector2(0, 0)]], "box": Vector2(40, 26)},
	"guildhall": {"parts": [[Rect2(64, 496, 64, 56), Vector2(0, 0)], [Rect2(80, 432, 32, 32), Vector2(-26, 2)]], "box": Vector2(60, 30), "tint": Color(1.0, 0.95, 0.85)},
}
const ROMAN := ["", "I", "II", "III", "IV"]

var id := ""
var look := ""
var _built_level := -1
var _box: CollisionShape2D
var _sprites: Array = []
var _extras: Array = []
var highlight := false
var _has_art := false  # art pass sprite in use: skip the code-drawn flag, door and candle
## Chimney tops on the art pass sprites (offset from the plot's bottom-centre, per level), for the smoke.
const SMOKE := {}  # e.g. "inkworks_3": Vector2(x, y); empty: the current sprites draw their own chimney smoke
var _over: Node2D  # code-drawn parts above the sprites: plate, scaffolding, smoke


func _ready() -> void:
	collision_layer = 1
	look = Empire.building(id).get("look", "")
	_over = Node2D.new()
	_over.z_index = 1
	add_child(_over)
	_over.draw.connect(_draw_over)
	refresh()


func plot_rect() -> Rect2:
	return Rect2(global_position - Vector2(PLOT.x / 2.0, PLOT.y - 4.0), Vector2(PLOT.x, PLOT.y - 4.0))


## Where staff stand: in front of the door, side by side.
func post_pos(n: int) -> Vector2:
	return global_position + Vector2([0, 18, -18][n % 3] - 14, 14)


## Rebuilds sprites and collision when the level changes. Cheap to call every frame.
func refresh() -> void:
	var lv := Empire.level_of(id)
	if lv == _built_level:
		return
	_built_level = lv
	for s in _sprites + _extras:
		s.queue_free()
	_sprites.clear()
	_extras.clear()
	if _box:
		_box.queue_free()
		_box = null
	if lv <= 0 or not LOOKS.has(look):
		return
	var spec: Dictionary = LOOKS[look]
	var art_path := "res://assets/buildings/%s_%d.png" % [look, mini(lv, 3)]  # art pass: one sprite per level
	_has_art = ResourceLoader.exists(art_path)
	if _has_art:
		var spr := _sprite(load(art_path), Vector2.ZERO, Color.WHITE)
		spr.material = Art.art_world_material()
		_sprites.append(spr)
		var sh := Node2D.new()  # cast shadow, under the building
		var sw := float(spr.texture.get_width())
		var st := float(spr.texture.get_height())
		sh.draw.connect(func(): Art.draw_cast_shadow(sh, Vector2(0, 2), sw, st))
		add_child(sh)
		move_child(sh, 0)
		_sprites.append(sh)
		_sprites.append(Art.add_cast_shadow(self, spr.texture, 3.0))
	else:
		_old_parts(spec, lv)
	var rect := RectangleShape2D.new()
	rect.size = spec["box"]
	_box = CollisionShape2D.new()
	_box.shape = rect
	_box.position = Vector2(0, -rect.size.y / 2.0)
	add_child(_box)
	if _has_art:
		_sprites.append(Art.add_occluder(self, Vector2(rect.size.x * 0.9, rect.size.y * 0.5)))


## The CC0 placeholder look, kept for any building without art pass sprites.
func _old_parts(spec: Dictionary, lv: int) -> void:
	for part in spec["parts"]:
		_sprites.append(_sprite(Art.region(part[0]), part[1], spec.get("tint", Color.WHITE)))
	# Upgrades show: crates at level 2, barrels too at level 3.
	if lv >= 2:
		_extras.append(_sprite(Art.tile_region(30, 0, 2, 2), Vector2(30, 4), Color.WHITE))
	if lv >= 3:
		_extras.append(_sprite(Art.tile_region(33, 0, 2, 1), Vector2(-34, 8), Color.WHITE))


func _sprite(tex: Texture2D, off: Vector2, tint: Color) -> Sprite2D:
	var spr := Sprite2D.new()
	spr.texture = tex
	spr.centered = true
	spr.offset = off + Vector2(0, -tex.get_height() / 2.0 + 3.0)
	spr.material = Art.world_material()
	spr.modulate = tint
	add_child(spr)
	move_child(spr, 0)  # sprites under the code-drawn plate and scaffolding
	return spr


func _process(_delta: float) -> void:
	refresh()
	queue_redraw()
	_over.queue_redraw()


func _draw() -> void:
	if Empire.level_of(id) == 0:
		_draw_plot()


func _draw_over() -> void:
	var b := Empire.building(id)
	var lv := Empire.level_of(id)
	var job: Dictionary = Empire.construction if Empire.construction.get("id", "") == id else {}
	var font := ThemeDB.fallback_font
	if not job.is_empty():
		_draw_scaffold(lv == 0)
	if look == "inkworks" and lv > 0 and (not _has_art or SMOKE.has("%s_%d" % [look, lv])):
		_draw_smoke(SMOKE.get("%s_%d" % [look, lv], Vector2(-6, -112)))
	if look == "infirmary" and lv > 0 and not _has_art:
		# A white flag with a red mark by the door.
		_over.draw_line(Vector2(26, -2), Vector2(26, -26), Color("4a3222"), 1.0)
		_over.draw_rect(Rect2(27, -26, 9, 7), Color("f3efe4"))
		_over.draw_rect(Rect2(30.5, -25, 2, 5), Color("c0392b"))
		_over.draw_rect(Rect2(29, -23.5, 5, 2), Color("c0392b"))
	if look == "scriptorium" and lv > 0 and not _has_art:
		var flick := 0.6 + 0.4 * sin(Time.get_ticks_msec() * 0.009 + 1.3)
		_over.draw_rect(Rect2(-3, -30, 5, 6), Color(1.0, 0.82, 0.4, flick))
		_over.draw_rect(Rect2(-6, -15, 12, 13), Color("4a3222"))  # a door at the foot of the tower
		_over.draw_rect(Rect2(-5, -14, 10, 12), Color("6a4628"))
		_over.draw_circle(Vector2(2.5, -8), 0.8, Color("c9a46a"))
	# Name board: building name and level, or the plot's future use.
	var label: String = String(b.get("name", id)).to_upper()
	if lv > 0:
		label += " " + ROMAN[mini(lv, ROMAN.size() - 1)]
	elif not job.is_empty():
		label = "BUILDING: " + label
	else:
		label = "PLOT: " + label
	var w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 6).x + 8.0
	var y := -PLOT.y * 0.5 if lv > 0 else -10.0
	var r := Rect2(-w / 2.0, y - 7.0, w, 9.0)
	_over.draw_rect(r, Color("3a2a1c") if lv > 0 else Color(0.23, 0.17, 0.11, 0.85))
	_over.draw_rect(r, Color("ffd166") if highlight else Color("c9a46a"), false, 1.0)
	_over.draw_string(font, Vector2(r.position.x + 4.0, y), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 6, Color("f3e3c3"))
	if not job.is_empty():
		var by := y - 12.0
		_over.draw_rect(Rect2(-24, by, 48, 4), Color(0.1, 0.08, 0.12, 0.85))
		_over.draw_rect(Rect2(-24, by, 48 * Empire.job_progress(job), 4), Color("ffd166"))
		var t := Empire.job_left_text(job)
		var tw := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 6).x
		_over.draw_string_outline(font, Vector2(-tw / 2.0, by - 2), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 6, 2, Color(0, 0, 0, 0.8))
		_over.draw_string(font, Vector2(-tw / 2.0, by - 2), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 6, Color("ffd166"))


## Stakes and rope around an empty plot.
func _draw_plot() -> void:
	var r := Rect2(-PLOT.x / 2.0 + 6, -PLOT.y + 16, PLOT.x - 12, PLOT.y - 20)
	var rope := Color(0.85, 0.75, 0.55, 0.7)
	var corners := [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]
	for i in 4:
		draw_line(corners[i], corners[(i + 1) % 4], rope, 1.0)
	for c in corners:
		draw_rect(Rect2(c - Vector2(1, 5), Vector2(2, 6)), Color("5a3c26"))


## Wooden scaffolding with planks; covers the whole plot for a new building, one side for an upgrade.
func _draw_scaffold(full: bool) -> void:
	var x0 := -30.0 if full else 18.0
	var x1 := 30.0 if full else 40.0
	var top := -56.0 if full else -40.0
	var wood := Color("8a6a44")
	var dark := Color("5a3c26")
	var x := x0
	while x <= x1 + 0.1:
		_over.draw_rect(Rect2(x - 1, top, 2, -top), dark)
		x += (x1 - x0) / (3.0 if full else 1.0)
	var y := top + 6.0
	while y < -2.0:
		_over.draw_rect(Rect2(x0 - 2, y, x1 - x0 + 4, 3), wood)
		y += 14.0
	_over.draw_line(Vector2(x0, -2), Vector2(x1, top + 4), dark, 1.0)
	if full:
		# A half-done wall rising with progress.
		var prog := Empire.job_progress(Empire.construction)
		var h := 40.0 * prog
		_over.draw_rect(Rect2(-26, -2 - h, 52, h), Color(0.55, 0.42, 0.3, 0.9))
		_over.draw_rect(Rect2(-36, -8, 10, 8), Color("7a5434"))  # a stack of planks


func _draw_smoke(top: Vector2) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	for i in 4:
		var k := fmod(t * 0.35 + i * 0.25, 1.0)
		var p := top + Vector2(sin(k * 6.0 + i) * 4.0, -k * 26.0)
		_over.draw_circle(p, 3.0 + k * 4.0, Color(0.12, 0.12, 0.2, 0.55 * (1.0 - k)))
