extends StaticBody2D
## Trees, rocks and signposts, code-drawn. kind: "tree", "rock", "sign".

var kind := "tree"
var text := ""
var erased := 0.0  # 0..1, how much the Blank has already eaten
var seed_v := 0


func _ready() -> void:
	collision_layer = 1
	var shape := CircleShape2D.new()
	shape.radius = {"tree": 7.0, "rock": 9.0, "sign": 4.0}[kind]
	var col := CollisionShape2D.new()
	col.shape = shape
	add_child(col)


func _draw() -> void:
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.4))
	draw_circle(Vector2.ZERO, 12.0 if kind == "tree" else 9.0, Color(0, 0, 0, 0.28))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var white := Color("f3f1ea")
	match kind:
		"tree":
			draw_rect(Rect2(-3, -14, 6, 14), Color("4a3628").lerp(white, erased))
			var leaf := Color("2f5a46").lerp(white, erased)
			var hi := Color("3f7458").lerp(white, erased)
			draw_circle(Vector2(0, -28), 15.0, leaf)
			draw_circle(Vector2(-8, -22), 10.0, leaf)
			draw_circle(Vector2(8, -22), 10.0, leaf)
			draw_circle(Vector2(-3, -32), 8.0, hi)
			if erased > 0.0:
				var rng := RandomNumberGenerator.new()
				rng.seed = seed_v
				for i in int(30 * erased):
					draw_rect(Rect2(Vector2(rng.randf_range(-16, 16), rng.randf_range(-44, -10)), Vector2(3, 3)), white)
		"rock":
			draw_circle(Vector2(0, -5), 9.0, Color("6f6a73").lerp(white, erased))
			draw_circle(Vector2(-2, -8), 5.0, Color("8a8590").lerp(white, erased))
		"sign":
			draw_rect(Rect2(-1, -16, 2, 16), Color("5a4430"))
			draw_rect(Rect2(-10, -24, 20, 10), Color("8a6a48"))
			draw_rect(Rect2(-8, -21, 16, 1), Color("3a2a1c"))
			draw_rect(Rect2(-8, -18, 12, 1), Color("3a2a1c"))
