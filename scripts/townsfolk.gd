class_name Townsfolk
extends Node2D
## Hollowmark townsfolk (art pass, docs/ART_ROADMAP.md 3.2): ambient people who stroll between open
## plaza tiles, stop, and look about. No collision and no talk: they only make the town feel lived in.

const BODIES := ["folk_man", "folk_woman", "folk_elder", "folk_child"]

var body_id := "folk_man"
var free := {}  # Vector2i tile -> true: plaza tiles clear of props and posts (built once by the hub)
var art: SpriteSet
var spr: Sprite2D
var target := Vector2.ZERO
var wait := 0.0
var facing := Vector2.DOWN
var t := 0.0
var speed := 22.0


func _ready() -> void:
	art = SpriteSet.of(body_id)
	spr = Sprite2D.new()
	add_child(spr)
	speed = {"folk_elder": 13.0, "folk_child": 30.0}.get(body_id, 22.0)
	wait = randf_range(0.0, 3.0)
	target = position
	facing = [Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT, Vector2.UP][randi() % 4]


func _process(delta: float) -> void:
	if art == null:
		return
	t += delta
	var moving := false
	if wait > 0.0:
		wait -= delta
	else:
		var to := target - position
		if to.length() < 1.0:
			wait = randf_range(1.5, 6.0)
			_pick()
		else:
			facing = to.normalized()
			position += facing * minf(speed * delta, to.length())
			moving = true
	art.apply(spr, "walk" if moving and art.has("walk") else "idle", Hero.dir_row(facing), t)


## Next stop: an open tile not too far away, reachable in a straight line over open tiles.
func _pick() -> void:
	var keys := free.keys()
	if keys.is_empty():
		return
	for i in 16:
		var c: Vector2i = keys[randi() % keys.size()]
		var p := Vector2(c * 16) + Vector2(8, 8) + Vector2(randf_range(-4, 4), randf_range(-4, 4))
		var d := p.distance_to(position)
		if d < 24.0 or d > 150.0:
			continue
		if _clear(position, p):
			target = p
			return


func _clear(a: Vector2, b: Vector2) -> bool:
	var steps := int(a.distance_to(b) / 6.0) + 1
	for i in steps + 1:
		var q := a.lerp(b, float(i) / float(steps))
		if not free.has(Vector2i(floori(q.x / 16.0), floori(q.y / 16.0))):
			return false
	return true
