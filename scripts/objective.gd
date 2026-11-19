class_name Objective
extends RefCounted
## What a mission asks of the party, and how far along it is (issue #5).
## main.gd calls the hooks; the mission dict's "objective" says which kind this is.
##
## Kinds so far:
##   kills: disperse `count` Nibblers.
##   defense, reclaim, rescue (issue #51): handed to MissionObjectives (mission_objectives.gd),
##   which needs the world, so it is set up on the first update() once the map exists.
##   boss (issue #17): handed to BossFight (boss_fight.gd), a MissionObjectives subclass.
## `main` is the mission scene (main.gd), for kinds that need the world: main.entities,
## main.blank, main.area, main.hud, main._spawn_enemy().

var data := {}
var kind := ""
var main  # main.gd
var progress := 0
var target := 1
var elapsed := 0.0
var inner: MissionObjectives  # the #51 kinds
var _inner_ready := false


func setup(objective: Dictionary, mission_main) -> void:
	data = objective
	kind = objective.get("kind", "kills")
	main = mission_main
	match kind:
		"kills":
			target = maxi(int(objective.get("count", 10)), 1)
		_:
			target = maxi(int(objective.get("count", 1)), 1)
	if MissionObjectives.handles(kind):
		inner = MissionObjectives.new()
	elif kind == "boss":
		inner = BossFight.new()


func on_kill() -> void:
	match kind:
		"kills":
			progress = mini(progress + 1, target)
		_:
			if _inner_ready:
				inner.on_kill()


func update(delta: float) -> void:
	elapsed += delta
	if inner != null:
		if not _inner_ready:
			_inner_ready = true
			inner.setup(data, main)
		inner.update(delta)


func done() -> bool:
	if inner != null:
		return _inner_ready and inner.done()
	match kind:
		_:
			return progress >= target


## True when the objective can no longer be met (a Defense line broken, say). The party is
## sent home with the "wiped" outcome.
func failed() -> bool:
	if inner != null:
		return _inner_ready and inner.failed()
	match kind:
		_:
			return false


## The HUD line, e.g. "Disperse Nibblers  7/12".
func text() -> String:
	if inner != null:
		return inner.text() if _inner_ready else ""
	match kind:
		_:
			return "%s  %d/%d" % [data.get("label", "Objective"), progress, target]


## For the briefing on the map.
static func describe(objective: Dictionary) -> String:
	match objective.get("kind", "kills"):
		"kills":
			return "%s (%d)" % [objective.get("label", "Disperse Nibblers"), int(objective.get("count", 10))]
		"defense":
			return "Hold the wardstone for %d seconds" % int(objective.get("seconds", 75))
		"reclaim":
			return "Break the Blot"
		"rescue":
			return "Find %s and bring them back" % Empire.short_name(objective.get("who", ""))
		"boss":
			return objective.get("label", "Defeat the boss")
		_:
			return objective.get("label", "Objective")


## Why it failed, for the results screen ("" when it did not).
func fail_text() -> String:
	return inner.fail_text() if inner != null and _inner_ready else ""


func to_save() -> Dictionary:
	return {"progress": progress, "elapsed": elapsed}


func from_save(d: Dictionary) -> void:
	progress = clampi(int(d.get("progress", 0)), 0, target)
	elapsed = float(d.get("elapsed", 0.0))
