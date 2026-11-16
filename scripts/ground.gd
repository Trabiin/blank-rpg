extends Node2D
## Code-drawn meadow ground. Placeholder until the CC0 tileset lands.

var size := Vector2(1280, 960)
var blank_x := 1100.0

const WORDS := ["and then", "was", "the", "almost", "she said", "once", "here lived", "...", "until", "nobody"]


func _draw() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	draw_rect(Rect2(Vector2.ZERO, size), Color("3f5e48"))
	# soft patches
	for i in 70:
		var p := Vector2(rng.randf_range(0, size.x), rng.randf_range(0, size.y))
		var col := Color("4a6b4f") if i % 2 == 0 else Color("36523f")
		draw_set_transform(p, 0.0, Vector2(1.0, 0.55))
		draw_circle(Vector2.ZERO, rng.randf_range(20, 60), col)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# dirt path winding east, toward the Blank
	var path := PackedVector2Array()
	var x := -20.0
	while x < size.x + 20.0:
		path.append(Vector2(x, 480.0 + sin(x * 0.006) * 90.0 + sin(x * 0.017) * 20.0))
		x += 20.0
	draw_polyline(path, Color("6b5a43"), 26.0, true)
	draw_polyline(path, Color("7d6a4f"), 18.0, true)
	# grass tufts and flowers, draining of color near the Blank
	for i in 900:
		var p := Vector2(rng.randf_range(0, size.x), rng.randf_range(0, size.y))
		var fade := clampf((p.x - (blank_x - 360.0)) / 360.0, 0.0, 1.0)
		var g := Color("5f8a5c").lerp(Color("b9b8b0"), fade)
		draw_line(p, p + Vector2(-1, -3), g, 1.0)
		draw_line(p + Vector2(2, 0), p + Vector2(3, -4), g, 1.0)
		if rng.randf() < 0.08:
			var fl := [Color("e07a8f"), Color("f2d06b"), Color("9fb7ff")][rng.randi() % 3] as Color
			draw_rect(Rect2(p + Vector2(0, -5), Vector2(2, 2)), fl.lerp(Color("cfcfcf"), fade))
	# Near the Blank the grass grows in half-sentences.
	var font := ThemeDB.fallback_font
	for i in 40:
		var p := Vector2(rng.randf_range(blank_x - 300.0, blank_x + 20.0), rng.randf_range(20, size.y - 20))
		var fade := clampf((p.x - (blank_x - 300.0)) / 300.0, 0.0, 1.0)
		draw_string(font, p, WORDS[rng.randi() % WORDS.size()], HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(0.85, 0.85, 0.8, 0.15 + 0.45 * fade))
