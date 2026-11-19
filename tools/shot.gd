extends SceneTree
## Screenshot helper for art review (not exported: tools/* is excluded).
##   xvfb-run -a godot --path . -s tools/shot.gd -- out=/tmp/x.png scene=mission party=ash,bran,gristle,ninefingers frames=90
## scene: mission (Frayed Meadow patrol), town (Hollowmark), picker (Command Table party picker).
## Autoloads exist only after the first frame, so setup happens in _process.

var frame := 0
var args := {}
var shots: Array = []


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"


func _process(_delta: float) -> bool:
	frame += 1
	if frame == 2:
		var empire = root.get_node("Empire")
		empire.reset()
		var dlg = load("res://scripts/dialogue.gd")  # loaded late: class scripts need the autoloads
		for k in dlg.data().get("talks", {}):
			dlg.mark_seen("talk:" + str(k))  # no opening conversation in the way
		if args.has("fx"):  # fx=mist:80,vignette:0 sets Options > Visual effects sliders for this run
			var st = load("res://scripts/settings.gd")
			for pair in str(args["fx"]).split(","):
				var kv := pair.split(":")
				st.fx[kv[0]] = int(kv[1])
		if args.has("day"):
			empire.day_t = float(args["day"])  # 0.5 noon, 0.75 dusk, 0.9 night
		var party: PackedStringArray = str(args.get("party", "ash,bran,gristle")).split(",")
		for id in empire.recruits:
			if empire.recruits[id]["role"] == "party":
				empire.recruits[id]["role"] = "idle"
		for id in party:
			empire.recruits[id] = {"role": "party", "target": "", "injured": 0}
		if args.has("levels"):  # every Hollowmark building at this level, and the Wardlamp lit
			for id in empire.building_ids():
				if id != "wardlamp":
					empire.buildings[id] = int(args["levels"])
			empire.lamps["hollowmark"] = clampi(int(args["levels"]) - 1, 1, 2)
		var scene := str(args.get("scene", "mission"))
		if scene == "mission":
			var m: Dictionary = load("res://scripts/missions.gd").find(str(args.get("mission", "meadow_patrol")))
			empire.active_mission = m
			change_scene_to_file("res://scenes/main.tscn")
		elif scene == "town":
			change_scene_to_file("res://scenes/hub.tscn")
	var total := int(args.get("frames", "90"))
	if args.has("at") and frame == 20:
		var cur := current_scene
		if cur != null and "heroes" in cur:
			var xy: PackedStringArray = str(args["at"]).split(",")
			var pos := Vector2(float(xy[0]), float(xy[1])) * 16.0
			for h in cur.heroes:
				h.global_position = pos
			cur.camera.global_position = pos
			cur.camera.reset_smoothing()
			if args.has("enemies"):
				for i in int(args["enemies"]):
					cur._spawn_enemy(pos + Vector2(60 + 24 * i, -30 + 30 * (i % 3)))
	if args.has("zoom") and frame == 22 and current_scene != null and "camera" in current_scene:
		current_scene.camera.zoom = Vector2.ONE * float(args["zoom"])  # wider overview shots
		current_scene.camera.reset_smoothing()
	if args.has("spread") and frame >= total - 40 and frame <= total - 10:
		_spread()
	if frame == total - int(args.get("lead", "30")) and args.has("act"):
		_act(str(args["act"]))
	if frame == total:
		var img := root.get_texture().get_image()
		img.save_png(str(args.get("out", "/tmp/shot.png")))
		print("saved ", args.get("out", "/tmp/shot.png"))
		quit()
	return false


## Small staged moments for screenshots: "swing" makes every hero swing, "spread" fans them out.
func _act(what: String) -> void:
	var cur := current_scene
	if cur == null or not ("heroes" in cur):
		return
	var i := 0
	for h in cur.heroes:
		if what == "swing":
			h.facing = [Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT][i % 3]
			h.try_attack()
		elif what == "hurt":
			h.flash_t = 0.5
			h.invuln_t = 0.7
		i += 1


## Holds the party in a loose row so each hero is visible (the AI otherwise bunches them up).
func _spread() -> void:
	var cur := current_scene
	if cur == null or not ("heroes" in cur) or cur.heroes.is_empty():
		return
	var base: Vector2 = cur.heroes[0].global_position if not has_meta("base") else get_meta("base")
	set_meta("base", base)
	var offs := [Vector2.ZERO, Vector2(-34, -6), Vector2(34, -6)]
	for i in cur.heroes.size():
		cur.heroes[i].global_position = base + offs[i % 3]
		cur.heroes[i].velocity = Vector2.ZERO
