class_name Ambience
extends Node2D
## Art pass mood for the field (docs/ART_ROADMAP.md 3.7): light that follows the empire clock, a lantern
## glow on the leader after dark, and drifting motes (pollen by day, fireflies at dusk and night).
## The clock is frozen during missions, so the hour a mission was launched is the hour it is played at.
## All code, no textures beyond one generated radial gradient.

## Light colour through the day (day_t 0..1, midnight at 0).
const KEYS := [
	[0.00, Color(0.42, 0.47, 0.68)],
	[0.20, Color(0.48, 0.52, 0.72)],
	[0.27, Color(0.92, 0.76, 0.72)],  # dawn
	[0.36, Color(1.00, 0.96, 0.90)],
	[0.62, Color(1.00, 0.98, 0.94)],
	[0.74, Color(1.00, 0.80, 0.66)],  # dusk
	[0.82, Color(0.60, 0.56, 0.74)],
	[1.00, Color(0.42, 0.47, 0.68)],
]

var party  # main.gd: leader, camera
var day_t := 0.5
var modulate_node: CanvasModulate
var lantern: PointLight2D
var motes: Array = []  # [pos, vel, phase]
var t := 0.0


static func light_at(dt: float) -> Color:
	dt = fposmod(dt, 1.0)
	for i in KEYS.size() - 1:
		var a: Array = KEYS[i]
		var b: Array = KEYS[i + 1]
		if dt <= b[0]:
			var k := smoothstep(0.0, 1.0, (dt - a[0]) / maxf(b[0] - a[0], 0.001))
			return (a[1] as Color).lerp(b[1], k)
	return KEYS[0][1]


## 0 in full daylight, 1 at deep night.
static func darkness(dt: float) -> float:
	var c := light_at(dt)
	return clampf((1.0 - (c.r + c.g + c.b) / 3.0) / 0.45, 0.0, 1.0)


func _ready() -> void:
	z_index = 5  # motes float above the actors
	day_t = Empire.day_t
	modulate_node = CanvasModulate.new()
	modulate_node.color = light_at(day_t)
	get_parent().add_child.call_deferred(modulate_node)
	lantern = PointLight2D.new()
	var g := GradientTexture2D.new()
	g.width = 128
	g.height = 128
	g.fill = GradientTexture2D.FILL_RADIAL
	g.fill_from = Vector2(0.5, 0.5)
	g.fill_to = Vector2(1.0, 0.5)
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 1))
	grad.set_color(1, Color(1, 1, 1, 0))
	g.gradient = grad
	lantern.texture = g
	lantern.color = Color(1.0, 0.82, 0.55)
	lantern.texture_scale = 1.6
	lantern.energy = 0.9 * darkness(day_t)
	lantern.enabled = lantern.energy > 0.05
	add_child(lantern)
	var n := 26
	for i in n:
		motes.append([Vector2(randf_range(-340, 340), randf_range(-200, 200)), Vector2(randf_range(-6, 6), randf_range(-4, 2)), randf() * TAU])


func _process(delta: float) -> void:
	t += delta
	if party != null and party.leader != null and is_instance_valid(party.leader):
		lantern.global_position = party.leader.global_position + Vector2(0, -8)
	for m in motes:
		m[0] += m[1] * delta + Vector2(sin(t * 0.7 + m[2]) * 3.0, cos(t * 0.9 + m[2]) * 2.0) * delta
	queue_redraw()


func _draw() -> void:
	if party == null or party.camera == null:
		return
	var cam: Vector2 = party.camera.get_screen_center_position()
	var dark := darkness(day_t)
	var lit := light_at(day_t)
	var undo := Color(1.0 / lit.r, 1.0 / lit.g, 1.0 / lit.b)  # motes give off their own light: cancel the dusk tint
	for m in motes:
		# Motes live in a box around the camera and wrap, so the screen always has a few.
		var p: Vector2 = m[0]
		var local := Vector2(fposmod(p.x - cam.x + 340.0, 680.0) - 340.0, fposmod(p.y - cam.y + 200.0, 400.0) - 200.0)
		var wp := cam + local
		if dark > 0.35:  # fireflies
			var a := 0.35 + 0.65 * maxf(sin(t * 2.2 + m[2] * 3.0), 0.0)
			draw_circle(wp, 1.8, Color(1.0, 0.9, 0.45, 0.18 * a) * undo)
			draw_rect(Rect2(wp, Vector2(1, 1)), Color(1.0, 0.95, 0.6, a) * undo)
		else:  # pollen and seed fluff in the light
			draw_rect(Rect2(wp, Vector2(1, 1)), Color(1.0, 0.97, 0.85, 0.45 + 0.25 * sin(t + m[2])))
