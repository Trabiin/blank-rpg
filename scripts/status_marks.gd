class_name StatusMarks
extends Node2D
## Little status icons over an enemy: circling stars while stunned (Last Orders, Chucking Out,
## Through the Door) and a gold tally seal while Audited (Odile). Drawn above the enemy's own overlay.

var enemy: Enemy


func _ready() -> void:
	z_index = 3


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if enemy == null or enemy.dead or enemy.dying_t >= 0.0:
		return
	var top := -24.0 if enemy.boss else -20.0
	if enemy.stun_left() > 0.0:
		var t := Time.get_ticks_msec() / 1000.0
		for k in 3:
			var a := t * 6.0 + k * TAU / 3.0
			var p := Vector2(cos(a) * 6.0, top + sin(a) * 2.0)
			draw_rect(Rect2(p - Vector2(1, 1), Vector2(2, 2)), Color("ffe58a"))
			draw_rect(Rect2(p - Vector2(0.5, 0.5), Vector2(1, 1)), Color.WHITE)
	if enemy.marked():
		# A ledger tick in a gold ring: "this one owes".
		var c := Vector2(7, top + 4)
		draw_circle(c, 3.2, Color(0.08, 0.06, 0.1, 0.8))
		draw_arc(c, 3.2, 0, TAU, 12, Color("e8c45a"), 1.0)
		draw_line(c + Vector2(-1.5, 0), c + Vector2(-0.3, 1.3), Color("e8c45a"), 1.0)
		draw_line(c + Vector2(-0.3, 1.3), c + Vector2(1.8, -1.6), Color("e8c45a"), 1.0)
