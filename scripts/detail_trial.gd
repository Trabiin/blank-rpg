extends Node2D
## TEMPORARY art test (ART_ROADMAP 1.1b): the same small meadow at two pixel detail levels, so
## Ojon can pick one on their own screen. Opened from the title screen ("Art detail trial").
##
##   Option A: 16 px tiles, Ash on a 32 px canvas, Nibbler 24 px, camera zoom 2 (today's density).
##   Option B: 32 px tiles, Ash on a 64 px canvas, Nibbler 48 px, camera zoom 1 (double density).
##
## Both show the same number of tiles on screen, so only the detail changes. Everything comes from
## PixelLab (assets/detail_trial/<a|b>/); lighting, shadows, the Blank edge and the HUD are code.
##
## Self-contained so it is easy to remove: delete this file, scenes/detail_trial.tscn,
## assets/detail_trial/ and the "trial" lines in title.gd. Nothing else depends on it.

const TITLE_SCENE := "res://scenes/title.tscn"
const ROOT := "res://assets/detail_trial/"
## Same order as Hero.dir_row(): clockwise starting from facing down.
const DIRS := ["south", "south-east", "east", "north-east", "north", "north-west", "west", "south-west"]
const OPTIONS := {
	"a": {"tile": 16, "zoom": 2.0, "name": "Option A: standard detail",
		"info": "16 px tiles  ·  Ash 32 px canvas  ·  Nibbler 24 px canvas  ·  zoom 2"},
	"b": {"tile": 32, "zoom": 1.0, "name": "Option B: double detail",
		"info": "32 px tiles  ·  Ash 64 px canvas  ·  Nibbler 48 px canvas  ·  zoom 1"},
}
## Map size in cells; the terrain lives on the (W+1) x (H+1) corner grid (Wang corner tiles).
const W := 40
const H := 24
## The Blank eats the meadow from this column eastward.
const BLANK_X := 31.0
const WALK_FPS := 10.0
const SPEED := 4.2  # tiles per second, the same feel in both options
const PAPER := Color("f3eee2")
const INK := Color("12141f")

static var option := "a"  # kept between visits

var tile := 16
var tiles := {}  # "LLUL" (NW NE SW SE, L = grass, U = dirt) -> Texture2D
var ash_rot: Array[Texture2D] = []
var ash_walk: Array = []  # per direction: Array[Texture2D]
var ash_walk_offset: Array[Vector2] = []
var ash_feet := Vector2.ZERO
var nib_rot: Array[Texture2D] = []
var nib_feet := Vector2.ZERO

var ground: Node2D
var blank: Node2D
var actors: Node2D
var ash: Node2D
var ash_sprite: Sprite2D
var camera: Camera2D
var hud: Control

var ash_pos := Vector2(9, 13)  # in tiles, so switching options keeps the spot
var ash_facing := Vector2.DOWN
var ash_moving := false
var anim_t := 0.0
var nibblers: Array = []  # {node, sprite, pos (tiles), vel, wait, hop}
var touch_target = null  # screen position while a finger / mouse button is held
var t := 0.0
var flakes: Array = []  # paper flakes drifting off the Blank edge: [pos tiles, vel, life]


func _ready() -> void:
	get_tree().paused = false
	var mod := CanvasModulate.new()
	mod.color = Color(1.0, 0.96, 0.9)  # warm late-afternoon light
	add_child(mod)
	ground = Node2D.new()
	ground.draw.connect(_draw_ground)
	add_child(ground)
	blank = Node2D.new()
	blank.draw.connect(_draw_blank)
	add_child(blank)
	actors = Node2D.new()
	actors.y_sort_enabled = true
	add_child(actors)
	camera = Camera2D.new()
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 8.0
	add_child(camera)

	var layer := CanvasLayer.new()
	add_child(layer)
	var vignette := TextureRect.new()
	vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vignette.stretch_mode = TextureRect.STRETCH_SCALE
	var grad := GradientTexture2D.new()
	grad.fill = GradientTexture2D.FILL_RADIAL
	grad.fill_from = Vector2(0.5, 0.5)
	grad.fill_to = Vector2(1.05, 1.05)
	grad.gradient = Gradient.new()
	grad.gradient.set_color(0, Color(0.05, 0.03, 0.08, 0.0))
	grad.gradient.set_color(1, Color(0.05, 0.03, 0.08, 0.55))
	vignette.texture = grad
	layer.add_child(vignette)
	hud = Control.new()
	hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.draw.connect(_draw_hud)
	layer.add_child(hud)

	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for spot in [Vector2(16, 6), Vector2(22, 9), Vector2(19, 17), Vector2(26, 14), Vector2(13, 19)]:
		nibblers.append({"node": null, "sprite": null, "pos": spot, "vel": Vector2.ZERO, "wait": rng.randf_range(0.2, 1.5), "hop": rng.randf() * TAU})
	_build()


## (Re)builds the world for the current option. Positions are kept in tiles.
func _build() -> void:
	var o: Dictionary = OPTIONS[option]
	tile = o.tile
	var dir := ROOT + option + "/"
	tiles.clear()
	for nw in "LU":
		for ne in "LU":
			for sw in "LU":
				for se in "LU":
					var key: String = nw + ne + sw + se
					tiles[key] = load(dir + "tiles/" + key + ".png")
	ash_rot.clear()
	ash_walk.clear()
	ash_walk_offset.clear()
	for d in DIRS:
		ash_rot.append(load(dir + "ash/" + d + ".png"))
	ash_feet = _feet_offset(ash_rot[0])
	for i in DIRS.size():
		var frames: Array[Texture2D] = []
		var n := 0
		while ResourceLoader.exists(dir + "ash/walk_%s_%d.png" % [DIRS[i], n]):
			frames.append(load(dir + "ash/walk_%s_%d.png" % [DIRS[i], n]))
			n += 1
		ash_walk.append(frames)
		# Walk frames can sit on a bigger canvas: line frame 0's feet up with the standing pose.
		ash_walk_offset.append(_feet_offset(frames[0]) if frames.size() > 0 else ash_feet)
	nib_rot.clear()
	for d in DIRS:
		nib_rot.append(load(dir + "nibbler/" + d + ".png"))
	nib_feet = _feet_offset(nib_rot[0])

	for c in actors.get_children():
		c.queue_free()
	ash = _actor(6.0)
	ash_sprite = ash.get_child(0)
	for n in nibblers:
		n.node = _actor(4.5)
		n.sprite = n.node.get_child(0)
		n.sprite.offset = nib_feet

	camera.zoom = Vector2.ONE * o.zoom
	camera.limit_left = 0
	camera.limit_top = 0
	camera.limit_right = W * tile
	camera.limit_bottom = H * tile
	_place()
	camera.position = ash.position
	camera.reset_smoothing()
	ground.queue_redraw()


## An actor: a soft shadow blob (code) under a sprite. Radius in 16 px units.
func _actor(shadow_r: float) -> Node2D:
	var n := Node2D.new()
	var s := Sprite2D.new()
	n.add_child(s)
	var r := shadow_r * tile / 16.0
	n.draw.connect(func(): _draw_shadow(n, r))
	actors.add_child(n)
	n.queue_redraw()
	return n


func _draw_shadow(n: Node2D, r: float) -> void:
	var pts := PackedVector2Array()
	for i in 20:
		var a := TAU * i / 20.0
		pts.append(Vector2(cos(a) * r, sin(a) * r * 0.45))
	n.draw_colored_polygon(pts, Color(0.05, 0.04, 0.1, 0.32))


## Sprite offset that puts the lowest opaque pixel (the feet) on the node's origin.
func _feet_offset(tex: Texture2D) -> Vector2:
	var used := tex.get_image().get_used_rect()
	var bottom := used.position.y + used.size.y
	return Vector2(0, tex.get_height() / 2.0 - bottom + 1)


func _upper(vx: int, vy: int) -> bool:
	## The meadow: a winding dirt path, a trampled clearing and a couple of bald patches.
	var path_y := 13.0 + 3.0 * sin(vx * 0.21) + 1.2 * sin(vx * 0.57 + 1.0)
	if absf(vy - path_y) < 0.8:
		return true
	if Vector2(vx, vy).distance_to(Vector2(10, 6)) < 2.4:
		return true
	if Vector2(vx, vy).distance_to(Vector2(21, 19)) < 1.2:
		return true
	return vx == 10 and vy > 6 and vy < path_y  # a side path into the clearing


func _draw_ground() -> void:
	for cy in H:
		for cx in W:
			var key := ""
			for c in [Vector2i(cx, cy), Vector2i(cx + 1, cy), Vector2i(cx, cy + 1), Vector2i(cx + 1, cy + 1)]:
				key += "U" if _upper(c.x, c.y) else "L"
			ground.draw_texture(tiles[key], Vector2(cx, cy) * tile)


## Where the Blank's edge sits on row y (in tiles), wobbling slowly.
func _edge_x(y: float) -> float:
	return BLANK_X + 1.1 * sin(y * 0.55 + t * 0.4) + 0.5 * sin(y * 1.7 - t * 0.9) + 0.25 * sin(y * 4.3 + t * 1.3)


func _draw_blank() -> void:
	## The Blank: paper white with a ragged ink-black rim, fading the meadow just before it.
	var px := tile / 16.0  # one art pixel of option A, so the rim is equally chunky in both options
	var step := 0.25
	var edge := PackedVector2Array()
	var y := -1.0
	while y <= H + 1.0:
		edge.append(Vector2(_edge_x(y) * tile, y * tile))
		y += step
	# Washed-out band: the world losing its colour before it disappears.
	for band in 4:
		var off := (4 - band) * 0.55 * tile
		var poly := PackedVector2Array()
		for p in edge:
			poly.append(p - Vector2(off, 0))
		poly.append(Vector2(W * tile + 64, (H + 1) * tile))
		poly.append(Vector2(W * tile + 64, -tile))
		blank.draw_colored_polygon(poly, Color(PAPER, 0.13))
	var fill := edge.duplicate()
	fill.append(Vector2(W * tile + 64, (H + 1) * tile))
	fill.append(Vector2(W * tile + 64, -tile))
	blank.draw_colored_polygon(fill, PAPER)
	blank.draw_polyline(edge, INK, 2.0 * px)
	# Ink specks and torn-paper bits along the rim.
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for i in 70:
		var sy := rng.randf() * H
		var sx := _edge_x(sy) + rng.randf_range(-0.6, 0.3)
		var s := rng.randf_range(1.0, 2.5) * px
		var col := INK if rng.randf() < 0.6 else PAPER
		blank.draw_rect(Rect2(Vector2(sx * tile, sy * tile).snapped(Vector2(px, px)), Vector2(s, s)), col)
	for f in flakes:
		var a: float = clampf(f[2], 0.0, 1.0)
		blank.draw_rect(Rect2((f[0] * tile).snapped(Vector2(px, px)), Vector2(2, 2) * px), Color(PAPER, a))


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("swap"):
		_switch()
	elif event.is_action_pressed("pause"):
		get_tree().change_scene_to_file(TITLE_SCENE)
	elif event is InputEventScreenTouch or event is InputEventMouseButton:
		var pos: Vector2 = event.position
		if event.pressed:
			var hit := _button_at(pos)
			if hit != "":
				if hit != option:
					_switch()
				touch_target = null
			else:
				touch_target = pos
		else:
			touch_target = null
	elif event is InputEventScreenDrag or (event is InputEventMouseMotion and touch_target != null):
		touch_target = event.position


func _switch() -> void:
	option = "b" if option == "a" else "a"
	_build()


func _button_rects() -> Dictionary:
	var vs := get_viewport_rect().size
	return {"a": Rect2(vs.x - 76, 8, 32, 22), "b": Rect2(vs.x - 40, 8, 32, 22)}


func _button_at(screen_pos: Vector2) -> String:
	var local := screen_pos  # the HUD layer has no transform
	var rects := _button_rects()
	for k in rects:
		if rects[k].grow(4).has_point(local):
			return k
	return ""


func _process(delta: float) -> void:
	t += delta
	var input := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if input == Vector2.ZERO and touch_target != null:
		var world: Vector2 = get_canvas_transform().affine_inverse() * (touch_target as Vector2)
		var to := world / tile - ash_pos
		if to.length() > 0.3:
			input = to.normalized()
	ash_moving = input != Vector2.ZERO
	if ash_moving:
		ash_facing = input
		var next := ash_pos + input * SPEED * delta
		next.x = clampf(next.x, 0.8, minf(W - 0.8, _edge_x(next.y) - 0.9))
		next.y = clampf(next.y, 1.0, H - 0.4)
		ash_pos = next
		anim_t += delta
	else:
		anim_t = 0.0
	for n in nibblers:
		_tick_nibbler(n, delta)
	_tick_flakes(delta)
	_place()
	camera.position = ash.position
	blank.queue_redraw()
	hud.queue_redraw()


func _tick_nibbler(n: Dictionary, delta: float) -> void:
	n.hop += delta * 9.0
	n.wait -= delta
	if n.wait <= 0.0:
		if n.vel == Vector2.ZERO:
			# Nibblers sniff towards Ash when close, otherwise wander.
			var to: Vector2 = ash_pos - n.pos
			var dir := to.normalized() if to.length() < 5.0 else Vector2.from_angle(randf() * TAU)
			n.vel = dir * randf_range(1.2, 2.2)
			n.wait = randf_range(0.6, 1.4)
		else:
			n.vel = Vector2.ZERO
			n.wait = randf_range(0.4, 1.6)
	var next: Vector2 = n.pos + n.vel * delta
	if next.distance_to(ash_pos) < 1.4 or next.x > _edge_x(next.y) - 1.0 or next.x < 1 or next.y < 1 or next.y > H - 1:
		n.vel = -n.vel
	else:
		n.pos = next


func _tick_flakes(delta: float) -> void:
	if randf() < delta * 6.0:
		var y := randf() * H
		flakes.append([Vector2(_edge_x(y) - 0.1, y), Vector2(randf_range(-0.9, -0.3), randf_range(-0.4, 0.2)), randf_range(1.5, 3.0)])
	for f in flakes:
		f[0] += f[1] * delta
		f[2] -= delta
	flakes = flakes.filter(func(f): return f[2] > 0.0)


func _place() -> void:
	var row := Hero.dir_row(ash_facing)
	ash.position = (ash_pos * tile).round()
	var frames: Array = ash_walk[row] if ash_walk.size() > row else []
	if ash_moving and frames.size() > 0:
		ash_sprite.texture = frames[int(anim_t * WALK_FPS) % frames.size()]
		ash_sprite.offset = ash_walk_offset[row]
	else:
		ash_sprite.texture = ash_rot[row]
		ash_sprite.offset = ash_feet
	for n in nibblers:
		if n.node == null:
			continue
		n.node.position = (n.pos * tile).round()
		var moving: bool = n.vel != Vector2.ZERO
		n.sprite.texture = nib_rot[Hero.dir_row(n.vel if moving else ash_pos - n.pos)]
		# Small hop while moving; one art pixel of option A is tile / 16 screen-world pixels.
		var hop := absf(sin(n.hop)) * 2.0 * tile / 16.0 if moving else 0.0
		n.sprite.offset = nib_feet - Vector2(0, roundf(hop))


func _draw_hud() -> void:
	var o: Dictionary = OPTIONS[option]
	var font := ThemeDB.fallback_font
	var vs := hud.get_viewport_rect().size
	_text(Vector2(10, 18), "The Frayed Meadow", 11, Color.WHITE)
	_text(Vector2(10, 31), "Art detail trial  ·  " + o.name, 8, Color("ffd166"))
	_text(Vector2(10, 42), o.info, 7, Color(0.9, 0.9, 0.9))
	var rects := _button_rects()
	for k in rects:
		var r: Rect2 = rects[k]
		var on: bool = k == option
		hud.draw_rect(r, Color(0.07, 0.07, 0.1, 0.85) if not on else Color("ffd166"))
		hud.draw_rect(r, Color("ffd166"), false, 1.0)
		var s := (k as String).to_upper()
		var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		hud.draw_string(font, r.position + Vector2((r.size.x - w) / 2.0, 16), s, HORIZONTAL_ALIGNMENT_LEFT, -1, 12,
			Color(0.07, 0.07, 0.1) if on else Color.WHITE)
	# Party boxes in the style of the mission HUD.
	var names := ["Ash", "Bran"]
	for i in names.size():
		var r := Rect2(8 + i * 118, vs.y - 34, 110, 26)
		hud.draw_rect(r, Color(0.06, 0.07, 0.09, 0.82))
		if i == 0:
			hud.draw_rect(r, Color("e8c66a"), false, 1.0)
		_text(r.position + Vector2(5, 10), names[i], 8, Color.WHITE)
		_text(r.position + Vector2(r.size.x - 24, 10), "100%", 8, Color.WHITE)
		hud.draw_rect(Rect2(r.position + Vector2(5, 14), Vector2(r.size.x - 10, 4)), Color("6ee39a"))
		hud.draw_rect(Rect2(r.position + Vector2(5, 20), Vector2((r.size.x - 10) * 0.6, 2)), Color(0.85, 0.85, 0.9))
	_text(Vector2(vs.x - 250, vs.y - 10), "Tab / Y / tap A B: switch   ·   Move: WASD, stick, touch   ·   Esc: back", 7, Color(0.85, 0.85, 0.85))


func _text(pos: Vector2, s: String, size: int, col: Color) -> void:
	var font := ThemeDB.fallback_font
	hud.draw_string_outline(font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 3, Color(0, 0, 0, 0.85))
	hud.draw_string(font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
