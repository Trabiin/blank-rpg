class_name MissionObjectives
extends RefCounted
## The objective kinds behind the Defense, Reclaim and Rescue missions (#51). Objective hands a
## mission's "objective" dict here when its kind is one of KINDS, and forwards its hooks.
##
## They are built from a few shared pieces, so a new type is mostly a new combination:
##   - a creeping Blank: the white wall moves west at "creep" px/s (kills can push it back),
##   - spawning: Nibblers on a timer, from the Blank's edge or around a point,
##   - a thing to protect (Wardstone), break (Blot) or find (a recruit waiting to be rescued),
##   - an exit to walk back to, and a pointer at the screen edge to whatever matters next.

const KINDS := ["defense", "reclaim", "rescue"]
const EnemyScript := preload("res://scripts/enemy.gd")
const BlotScript := preload("res://scripts/blot.gd")
const WardScript := preload("res://scripts/wardstone.gd")
const HeroScript := preload("res://scripts/hero.gd")
const MAX_SPAWNED := 12
const FIND_RANGE := 24.0
const EXIT_RANGE := 26.0

var kind := ""
var obj := {}
var main  # main.gd
var phase := 0  # rescue: 0 = find them, 1 = bring them back
var time_left := 0.0
var spawn_t := 1.5
var start_blank_x := 0.0
var end_t := -1.0  # counts up once the goal is met: a beat to watch the Blank let go
var fail_why := ""
var ward: Wardstone
var blot: Blot
var captive: Hero
var exit_pos := Vector2.ZERO
var pointer: Control


static func handles(k: String) -> bool:
	return k in KINDS


func setup(p_obj: Dictionary, p_main) -> void:
	obj = p_obj
	kind = obj.get("kind", "")
	main = p_main
	start_blank_x = main.blank.base_x
	exit_pos = main.area.party_start
	match kind:
		"defense":
			time_left = float(obj.get("seconds", 75))
			ward = WardScript.new()
			ward.max_hp = int(obj.get("ward_hp", 100))
			ward.hp = ward.max_hp
			ward.position = _tile(obj["ward"])
			main.entities.add_child(ward)
		"reclaim":
			blot = BlotScript.new()
			blot.total_hp = int(obj.get("hp", 220))
			blot.position = _tile(obj["blot"])
			main.entities.add_child(blot)
			spawn_t = 3.0
		"rescue":
			var rid: String = obj.get("who", "")
			var look: Dictionary = Empire.recruit(rid).get("look", {})
			captive = HeroScript.new()
			captive.hero_name = Empire.short_name(rid)
			captive.outfit = look.get("outfit", "archer")
			var cols := {}
			for k in look.get("colors", {}):
				cols[k] = Color(look["colors"][k])
			if not cols.is_empty():
				captive.colors = cols
			captive.move_speed = 66.0
			captive.position = _tile(obj["at"])
			captive.facing = Vector2.LEFT
			main.entities.add_child(captive)
			captive.set_physics_process(false)  # stuck where they are until Ash turns up
			for i in int(obj.get("guards", 4)):
				_spawn(captive.position + Vector2.RIGHT.rotated(TAU * i / 4.0 + 0.4) * 46.0)
	pointer = Pointer.new()
	pointer.obj = self
	main.hud.get_parent().add_child(pointer)


func _tile(t: Array) -> Vector2:
	return Vector2(int(t[0]) * 16 + 8, int(t[1]) * 16 + 8)


func on_kill() -> void:
	if kind == "defense":
		_move_blank(float(obj.get("push", 7.0)))  # every Nibbler dispersed gives back a little ground


func update(delta: float) -> void:
	if fail_why != "":
		return
	if end_t >= 0.0:
		end_t += delta
		_move_blank(260.0 * delta)  # the white pulls back east
		return
	match kind:
		"defense":
			time_left -= delta
			_move_blank(-float(obj.get("creep", 3.0)) * delta)
			_spawn_timer(delta, float(obj.get("spawn_every", 3.0)), func(): return _edge_point(ward.position.y, 160.0), true)
			if ward.hp <= 0:
				fail_why = "The wardstone broke. The surge will land."
			elif main.blank.edge_x(ward.position.y) <= ward.position.x + 8.0:
				fail_why = "The Blank swallowed the wardstone."
			elif time_left <= 0.0:
				time_left = 0.0
				end_t = 0.0
				main.hud.say("The surge breaks. The white goes quiet.", 3.0)
		"reclaim":
			if blot.dead:
				end_t = 0.0
				main.hud.say("The Blot bursts. The Blank lets go of the land.", 3.0)
				return
			_spawn_timer(delta, float(obj.get("spawn_every", 4.0)), func(): return blot.position + Vector2(randf_range(-30, -14), randf_range(-26, 26)), false)
		"rescue":
			if phase == 0:
				_move_blank(-float(obj.get("creep", 2.6)) * delta)
				if main.blank.edge_x(captive.position.y) <= captive.position.x + 6.0:
					fail_why = "The white closed over %s before you got there." % captive.hero_name
				elif main.leader and main.leader.global_position.distance_to(captive.global_position) < FIND_RANGE:
					phase = 1
					captive.party = main
					captive.set_physics_process(true)  # follows the leader and fights like an ally
					main.hud.say("%s: \"Took you long enough. Which way is out?\"" % captive.hero_name, 3.5)
			elif main.leader and main.leader.global_position.distance_to(exit_pos) < EXIT_RANGE:
				end_t = 1.6  # nothing to watch here: done right away


func _move_blank(dx: float) -> void:
	var b = main.blank
	var limit: float = main.world.x + 80.0 if end_t >= 0.0 else start_blank_x
	b.base_x = clampf(b.base_x + dx, 120.0, maxf(limit, start_blank_x))
	Art.world_material().set_shader_parameter("blank_x", b.base_x)


func _edge_point(y: float, spread: float) -> Vector2:
	var yy := clampf(y + randf_range(-spread, spread), 40.0, main.world.y - 40.0)
	return Vector2(main.blank.edge_x(yy) - 14.0, yy)


func _spawn_timer(delta: float, every: float, where: Callable, to_ward: bool) -> void:
	spawn_t -= delta
	if spawn_t > 0.0:
		return
	spawn_t = every
	if main.get_tree().get_nodes_in_group("enemies").size() >= MAX_SPAWNED:
		return
	var e := _spawn(where.call())
	if to_ward:
		e.goal = ward


func _spawn(pos: Vector2) -> Enemy:
	var e: Enemy = EnemyScript.new()
	e.position = pos
	main.entities.add_child(e)
	e.died.connect(main._on_enemy_died)
	Fx.burst(main.entities, pos + Vector2(0, -6), [Color.WHITE, Color.BLACK], 8, 50.0)
	return e


func done() -> bool:
	return end_t >= 1.5


func failed() -> bool:
	return fail_why != ""


func fail_text() -> String:
	return fail_why


func text() -> String:
	match kind:
		"defense":
			return "Hold the wardstone: %d s   (stone %d/%d)" % [ceili(time_left), ward.hp, ward.max_hp]
		"reclaim":
			return "Break the Blot   (%d/%d)" % [blot.hp, blot.max_hp] if not blot.dead else "The Blot is broken"
		"rescue":
			if phase == 0:
				var gap := maxf(main.blank.edge_x(captive.position.y) - captive.position.x, 0.0)
				return "Find %s before the white does   (%d paces)" % [captive.hero_name, int(gap / 4.0)]
			return "Bring %s back to where you came in" % captive.hero_name
	return ""


## Where the edge pointer aims, or null when nothing needs pointing at.
func target_pos():
	if end_t >= 0.0 or fail_why != "":
		return null
	match kind:
		"defense":
			return ward.global_position
		"reclaim":
			return blot.global_position
		"rescue":
			return captive.global_position if phase == 0 else exit_pos
	return null


## Draws the exit ring in the world (rescue, once they are found). Called by Pointer each frame.
func exit_visible() -> bool:
	return kind == "rescue" and phase == 1 and end_t < 0.0


## A small HUD arrow at the screen edge pointing at the objective, plus the exit ring.
class Pointer extends Control:
	var obj  # MissionObjectives
	var t := 0.0

	func _ready() -> void:
		set_anchors_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(delta: float) -> void:
		t += delta
		queue_redraw()

	func _draw() -> void:
		var xf := get_viewport().get_canvas_transform()
		var vs := get_viewport_rect().size
		if obj.exit_visible():
			var ep: Vector2 = xf * obj.exit_pos
			var r := (13.0 + sin(t * 4.0) * 1.5) * xf.get_scale().x
			draw_arc(ep, r, 0, TAU, 32, Color("ffd166"), 2.0)
			_label(ep + Vector2(0, -r - 4), "EXIT")
		var tp = obj.target_pos()
		if tp == null:
			return
		var sp: Vector2 = xf * (tp as Vector2)
		var margin := 18.0
		var inner := Rect2(Vector2(margin, margin + 40), vs - Vector2(margin * 2, margin * 2 + 80))
		if inner.has_point(sp):
			var bob := sin(t * 5.0) * 2.0
			var tip := sp + Vector2(0, -34 * xf.get_scale().y / 2.0 - 12 + bob)
			draw_colored_polygon(PackedVector2Array([tip, tip + Vector2(-5, -7), tip + Vector2(5, -7)]), Color("ffd166"))
			return
		var c := vs / 2.0
		var d := (sp - c).normalized()
		var k := minf(absf((inner.size.x / 2.0) / d.x) if absf(d.x) > 0.001 else 1e9, absf((inner.size.y / 2.0) / d.y) if absf(d.y) > 0.001 else 1e9)
		var at := c + d * k
		var a := d.angle()
		var pts := PackedVector2Array([at + Vector2(14, 0).rotated(a), at + Vector2(-8, -10).rotated(a), at + Vector2(-8, 10).rotated(a)])
		draw_colored_polygon(pts, Color("ffd166", 0.8 + 0.2 * sin(t * 6.0)))
		draw_polyline(pts + PackedVector2Array([pts[0]]), Color(0, 0, 0, 0.8), 1.5)

	func _label(pos: Vector2, s: String) -> void:
		var f := ThemeDB.fallback_font
		var w := f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x
		draw_string_outline(f, pos - Vector2(w / 2.0, 0), s, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, 3, Color(0, 0, 0, 0.8))
		draw_string(f, pos - Vector2(w / 2.0, 0), s, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color("ffd166"))
