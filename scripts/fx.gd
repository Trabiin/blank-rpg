class_name Fx
extends Node2D
## Code-drawn effects: floating damage numbers and pixel bursts.

enum Kind { NUMBER, BURST }

var kind: int = Kind.NUMBER
var text := ""
var color := Color.WHITE
var life := 0.0
var max_life := 0.7
var particles: Array = []  # each: [pos: Vector2, vel: Vector2, size: float, color: Color]


static func damage_number(parent: Node, pos: Vector2, value: String, col: Color) -> void:
	var f := Fx.new()
	f.kind = Kind.NUMBER
	f.text = value
	f.color = col
	f.position = pos + Vector2(randf_range(-4, 4), 0)
	f.z_index = 50
	parent.add_child(f)


static func burst(parent: Node, pos: Vector2, cols: Array, count := 14, speed := 90.0) -> void:
	var f := Fx.new()
	f.kind = Kind.BURST
	f.position = pos
	f.max_life = 0.55
	f.z_index = 40
	for i in count:
		var dir := Vector2.RIGHT.rotated(randf() * TAU)
		f.particles.append([Vector2.ZERO, dir * randf_range(speed * 0.3, speed), randf_range(1.0, 3.0), cols[i % cols.size()]])
	parent.add_child(f)


func _process(delta: float) -> void:
	life += delta
	if life >= max_life:
		queue_free()
		return
	if kind == Kind.NUMBER:
		position.y -= 28.0 * delta
	else:
		for p in particles:
			p[0] += p[1] * delta
			p[1] *= 0.9
	queue_redraw()


func _draw() -> void:
	var a := 1.0 - life / max_life
	if kind == Kind.NUMBER:
		var font := ThemeDB.fallback_font
		var size := 11
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		for o in [Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1)]:
			draw_string(font, Vector2(-w / 2.0, 0) + o, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(0, 0, 0, a))
		draw_string(font, Vector2(-w / 2.0, 0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(color, a))
	else:
		for p in particles:
			var s: float = p[2]
			draw_rect(Rect2(p[0] - Vector2(s, s) / 2.0, Vector2(s, s)), Color(p[3], a))
