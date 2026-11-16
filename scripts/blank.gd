class_name Blank
extends Node2D
## The hungry Blank: a white, silent nothing eating the map from the east.

var base_x := 1100.0
var height := 960.0
var width := 1400.0
var t := 0.0


func edge_x(y: float) -> float:
	return base_x + sin(y * 0.021 + t * 0.8) * 14.0 + sin(y * 0.057 - t * 1.3) * 6.0 + sin(y * 0.13 + t * 2.1) * 2.0


func _process(delta: float) -> void:
	t += delta
	queue_redraw()


func _draw() -> void:
	var pts := PackedVector2Array()
	var step := 16.0
	var y := -40.0
	while y <= height + 40.0:
		pts.append(Vector2(edge_x(y), y))
		y += step
	pts.append(Vector2(width + 200.0, height + 40.0))
	pts.append(Vector2(width + 200.0, -40.0))
	draw_colored_polygon(pts, Color("f3f1ea"))
	# A grey fringe and crawling static along the edge.
	var fringe := PackedVector2Array()
	for p in pts.slice(0, pts.size() - 2):
		fringe.append(p + Vector2(-3, 0))
	draw_polyline(fringe, Color(0.75, 0.74, 0.72, 0.8), 3.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(t * 15.0)
	for i in 120:
		var yy := rng.randf_range(0.0, height)
		var xx := edge_x(yy) - rng.randf_range(0.0, 26.0) * rng.randf() * rng.randf() * 2.0
		var s := rng.randf_range(1.0, 3.0)
		var col := Color(0.05, 0.04, 0.06, 0.7) if rng.randf() < 0.5 else Color(0.97, 0.96, 0.93, 0.9)
		draw_rect(Rect2(xx, yy, s, s), col)
