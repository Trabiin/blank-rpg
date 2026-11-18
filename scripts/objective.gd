class_name Objective
extends RefCounted
## What a mission asks of the party, and how far along it is (issue #5).
## main.gd calls the hooks; the mission dict's "objective" says which kind this is.
##
## Kinds so far:
##   kills: disperse `count` Nibblers.
## New kinds (Reclaim, Defense, Rescue: issue #51) add a case to each match below.
## `main` is the mission scene (main.gd), for kinds that need the world: main.entities,
## main.blank, main.area, main.hud, main._spawn_enemy().

var data := {}
var kind := ""
var main  # main.gd
var progress := 0
var target := 1
var elapsed := 0.0


func setup(objective: Dictionary, mission_main) -> void:
	data = objective
	kind = objective.get("kind", "kills")
	main = mission_main
	match kind:
		"kills":
			target = maxi(int(objective.get("count", 10)), 1)
		_:
			target = maxi(int(objective.get("count", 1)), 1)


func on_kill() -> void:
	match kind:
		"kills":
			progress = mini(progress + 1, target)
		_:
			pass


func update(delta: float) -> void:
	elapsed += delta
	match kind:
		_:
			pass


func done() -> bool:
	match kind:
		_:
			return progress >= target


## True when the objective can no longer be met (a Defense line broken, say). The party is
## sent home with the "wiped" outcome.
func failed() -> bool:
	match kind:
		_:
			return false


## The HUD line, e.g. "Disperse Nibblers  7/12".
func text() -> String:
	match kind:
		_:
			return "%s  %d/%d" % [data.get("label", "Objective"), progress, target]


## For the briefing on the map.
static func describe(objective: Dictionary) -> String:
	match objective.get("kind", "kills"):
		"kills":
			return "%s (%d)" % [objective.get("label", "Disperse Nibblers"), int(objective.get("count", 10))]
		_:
			return objective.get("label", "Objective")


func to_save() -> Dictionary:
	return {"progress": progress, "elapsed": elapsed}


func from_save(d: Dictionary) -> void:
	progress = clampi(int(d.get("progress", 0)), 0, target)
	elapsed = float(d.get("elapsed", 0.0))
