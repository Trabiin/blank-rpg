class_name Blank
extends Node2D
## The hungry Blank: a white, silent nothing eating the map from the east.

var base_x := 1100.0
var height := 960.0
var width := 1400.0
var t := 0.0


func edge_x(y: float) -> float:
	return base_x + sin(y * 0.021 + t * 0.8) * 14.0 + sin(y * 0.057 - t * 1.3) * 6.0 + sin(y * 0.13 + t * 2.1) * 2.0


const PAPER := Color("f3eee2")
const INK := Color("12141f")
const RULE := Color(0.55, 0.62, 0.72, 0.22)  # the faint ruled lines of an empty ledger page

var flakes: Array = []  # torn paper scraps drifting off the edge: [pos, vel, life, size]


## The ragged rim: the smooth edge plus a fine tear that shifts slowly.
func rim_x(y: float) -> float:
	var n := sin(y * 0.9 + floor(t * 3.0)) * 1.2 + sin(y * 2.3) * 0.8
	return edge_x(y) + n


func _process(delta: float) -> void:
	t += delta
	# Paper flakes peel off the edge and drift back over the meadow before fading.
	if flakes.size() < 36 and randf() < delta * 14.0:
		var y := randf_range(0.0, height)
		flakes.append([Vector2(rim_x(y) - 2.0, y), Vector2(randf_range(-22.0, -8.0), randf_range(-6.0, 6.0)), randf_range(1.5, 3.5), randf_range(1.0, 2.5)])
	for f in flakes:
		f[0] += f[1] * delta
		f[1].y += sin(t * 3.0 + f[0].x * 0.1) * 6.0 * delta
		f[2] -= delta
	flakes = flakes.filter(func(f): return f[2] > 0.0)
	queue_redraw()


func _draw() -> void:
	var step := 4.0
	var edge := PackedVector2Array()
	var y := -40.0
	while y <= height + 40.0:
		edge.append(Vector2(rim_x(y), y))
		y += step
	var far := width + 200.0
	# The world loses its colour just before it disappears: soft paper bands ahead of the edge.
	for band in 3:
		var off := (3 - band) * 9.0
		var poly := PackedVector2Array()
		for p in edge:
			poly.append(p - Vector2(off, 0))
		poly.append(Vector2(far, height + 40.0))
		poly.append(Vector2(far, -40.0))
		draw_colored_polygon(poly, Color(PAPER, 0.12))
	var fill := edge.duplicate()
	fill.append(Vector2(far, height + 40.0))
	fill.append(Vector2(far, -40.0))
	draw_colored_polygon(fill, PAPER)
	# Ruled lines on the empty page, starting a little inside the edge.
	var ry := 6.0
	while ry < height:
		draw_line(Vector2(rim_x(ry) + 6.0, ry), Vector2(far, ry), RULE, 1.0)
		ry += 12.0
	draw_polyline(edge, INK, 1.5)
	# Ink specks and crawling static along the rim.
	var rng := RandomNumberGenerator.new()
	rng.seed = int(t * 15.0)
	for i in 120:
		var yy := rng.randf_range(0.0, height)
		var xx := rim_x(yy) - rng.randf_range(0.0, 26.0) * rng.randf() * rng.randf() * 2.0
		var sz := rng.randf_range(1.0, 2.0)
		var col := Color(INK, 0.75) if rng.randf() < 0.5 else Color(PAPER, 0.95)
		draw_rect(Rect2(xx, yy, sz, sz), col)
	for f in flakes:
		var a := clampf(f[2], 0.0, 1.0)
		draw_rect(Rect2(f[0], Vector2(f[3], f[3])), Color(PAPER, a))
		draw_rect(Rect2(f[0] + Vector2(0, f[3]), Vector2(f[3], 0.5)), Color(INK, 0.4 * a))
