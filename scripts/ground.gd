extends Sprite2D
## The meadow floor, stamped from the CC0 overworld tiles into one texture at startup.
## Mood grading and the Blank's color drain come from the world_tint shader.

var size := Vector2(1280, 960)
var blank_x := 1100.0

const GRASS := [Vector2i(0, 0), Vector2i(0, 0), Vector2i(0, 0), Vector2i(0, 9), Vector2i(1, 9), Vector2i(0, 10), Vector2i(1, 10), Vector2i(5, 9)]
const DIRT := Vector2i(1, 30)
const FLOWERS := [Vector2i(0, 8), Vector2i(1, 8), Vector2i(3, 11), Vector2i(2, 12), Vector2i(3, 12)]
const WORDS := ["and then", "was", "the", "almost", "she said", "once", "here lived", "...", "until", "nobody"]


static func path_y(x: float) -> float:
	return 480.0 + sin(x * 0.005) * 56.0 + sin(x * 0.013) * 10.0


func build() -> void:
	var src: Image = Art.OVERWORLD.get_image()
	src.convert(Image.FORMAT_RGBA8)
	var cols := int(size.x / 16)
	var rows := int(size.y / 16)
	var img := Image.create(cols * 16, rows * 16, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7

	# Which cells are path: a band two tiles wide that winds toward the Blank.
	var path := {}
	for cx in cols:
		var cy := int(path_y(cx * 16.0 + 8.0) / 16.0 - 0.5)
		path[Vector2i(cx, cy)] = true
		path[Vector2i(cx, cy + 1)] = true

	for cy in rows:
		for cx in cols:
			var cell := Vector2i(cx, cy)
			var t: Vector2i = DIRT if path.has(cell) else GRASS[rng.randi() % GRASS.size()]
			img.blit_rect(src, Rect2i(t * 16, Vector2i(16, 16)), cell * 16)
	# Soft dark fringe where grass meets the path, so edges read as a worn trail.
	var fringe := Color(0.13, 0.33, 0.16)
	for cell in path:
		var p: Vector2i = cell * 16
		if not path.has(cell + Vector2i(0, -1)):
			img.fill_rect(Rect2i(p.x, p.y, 16, 2), fringe)
		if not path.has(cell + Vector2i(0, 1)):
			img.fill_rect(Rect2i(p.x, p.y + 15, 16, 1), fringe.lightened(0.15))
	# Flowers scattered on grass (never on the path).
	for i in 260:
		var cell := Vector2i(rng.randi() % cols, rng.randi() % rows)
		if path.has(cell):
			continue
		var f: Vector2i = FLOWERS[rng.randi() % FLOWERS.size()]
		img.blend_rect(src, Rect2i(f * 16, Vector2i(16, 16)), cell * 16)

	texture = ImageTexture.create_from_image(img)
	centered = false
	material = Art.world_material()

	# Near the Blank the grass grows in half-sentences (unshaded child so text stays dark).
	var words := Node2D.new()
	add_child(words)
	words.draw.connect(_draw_words.bind(words))
	words.queue_redraw()


func _draw_words(canvas: Node2D) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var font := ThemeDB.fallback_font
	for i in 40:
		var p := Vector2(rng.randf_range(blank_x - 300.0, blank_x + 20.0), rng.randf_range(20, size.y - 20))
		var fade := clampf((p.x - (blank_x - 300.0)) / 300.0, 0.0, 1.0)
		canvas.draw_string(font, p, WORDS[rng.randi() % WORDS.size()], HORIZONTAL_ALIGNMENT_LEFT, -1, 6, Color(0.2, 0.2, 0.22, 0.12 + 0.4 * fade))
