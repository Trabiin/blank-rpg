extends SceneTree
## Soak test for allies' charged techs (scripts/ally_techs.gd), headless:
##   godot --headless --fixed-fps 60 --path . -s tools/ai_tech_sim.gd -- secs=15
## Runs every hero with a tech as an AI ally under every preset (plus "On my call" and an order)
## against waves of the area's enemies, and prints how often each fired and what each blast hit.
## With shot=/path/prefix (run under xvfb-run, not --headless) it also saves a screenshot of the first
## charge (prefix_<hero>.png) and of the quick menu's Party tab with the tech orders open (prefix_menu.png).

var args := {}
var configs: Array = []
var ci := -1
var frame := 0
var phase := "boot"
var stats := {}
var prev_hp := {}
var prev_flash := {}
var results: Array = []


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var only := str(args.get("heroes", "bran,gristle,ninefingers,ottoline,jessamy,odile,velvette,ash"))
	var presets := str(args.get("presets", "aggressive,balanced,distance,support")).split(",")
	for id in only.split(","):
		for p in presets:
			configs.append({"ally": id, "preset": p, "mode": "auto"})
		configs.append({"ally": id, "preset": "balanced", "mode": "call"})
		configs.append({"ally": id, "preset": "balanced", "mode": "order"})


func _process(_delta: float) -> bool:
	frame += 1
	if phase == "boot":
		if frame >= 2:
			_next()
		return false
	var cur := current_scene
	if phase == "load":
		if cur != null and "heroes" in cur and cur.heroes.size() >= 2 and frame > 10:
			_setup(cur)
			phase = "run"
			frame = 0
		return false
	if phase == "run":
		_tick(cur)
		if frame >= int(float(args.get("secs", "15")) * 60.0):
			_finish()
			_next()
	return false


func _next() -> void:
	ci += 1
	if ci >= configs.size():
		print("done ", results.size())
		quit()
		return
	var c: Dictionary = configs[ci]
	var empire = root.get_node("Empire")
	empire.reset()
	var dlg = load("res://scripts/dialogue.gd")
	for k in dlg.data().get("talks", {}):
		dlg.mark_seen("talk:" + str(k))
	for id in empire.recruits:
		if empire.recruits[id]["role"] == "party":
			empire.recruits[id]["role"] = "idle"
	var other: String = c["ally"] if c["ally"] != "ash" else "bran"
	for id in ["ash", other]:
		empire.recruits[id] = {"role": "party", "target": "", "injured": 0}
	var hero_id: String = c["ally"]
	empire.ai_presets[hero_id] = c["preset"]
	empire.ai_techs[hero_id] = "call" if c["mode"] != "auto" else "auto"
	empire.active_mission = load("res://scripts/missions.gd").find("meadow_patrol").duplicate()
	change_scene_to_file("res://scenes/main.tscn")
	phase = "load"
	frame = 0
	stats = {"fires": 0, "hits": [], "kills": 0, "ally_hp_lost": 0, "cancels": 0}
	prev_hp = {}
	prev_flash = {}


func _ally(cur):
	for h in cur.heroes:
		if h.hero_id == configs[ci]["ally"]:
			return h
	return null


func _setup(cur) -> void:
	var c: Dictionary = configs[ci]
	if c["ally"] == "ash":
		for h in cur.heroes:
			if h.hero_id == "bran":
				cur.take_control(h)
	var a = _ally(cur)
	a.ai_style = c["preset"]
	set_meta("start_kills", int(cur.kills))
	set_meta("hp0", a.hp)


func _tick(cur) -> void:
	if cur.get_tree().paused:  # an opening talk: skip it
		cur.dialogue_box.visible = false
		cur.get_tree().paused = false
	var a = _ally(cur)
	var lead = cur.leader
	lead.invuln_t = 1.0  # the leader stands still and can't die; the ally does the work
	lead.hp = lead.max_hp
	a.hp = maxi(a.hp, 1)
	var alive := 0
	for e in cur.get_tree().get_nodes_in_group("enemies"):
		if "dead" in e and not e.dead and e.global_position.distance_to(lead.global_position) < 140.0:
			alive += 1
	if alive < 3 and frame % 30 == 0:
		var rng := RandomNumberGenerator.new()
		rng.seed = frame * 7 + ci
		for i in 3:
			cur._spawn_enemy(lead.global_position + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(50, 90))
	if configs[ci]["mode"] == "order" and frame % 240 == 120:
		load("res://scripts/ally_techs.gd").order(a)
	# A tech went off this frame: what did it hit?
	var fl: float = prev_flash.get(a, 0.0)
	if a.tech_flash_t > fl + 0.1:
		stats["fires"] += 1
		var hit := 0
		for e in prev_hp:
			if not is_instance_valid(e) or e.hp < prev_hp[e]:
				hit += 1
		stats["hits"].append(hit)
	elif get_meta("was_charging", false) and not a.charging:
		stats["cancels"] += 1
		var why := "other"
		if a.ai_tech_cd > 1.0:
			why = "timeout"
		elif a.ai_tech_cd > 0.7:
			why = "dodge"
		elif a.ai_tech_cd > 0.4:
			why = "broken"
		stats[why] = stats.get(why, 0) + 1
	set_meta("was_charging", a.charging)
	prev_flash[a] = a.tech_flash_t
	if args.has("shot"):
		_shots(cur, a)
	if args.has("debug") and frame % 60 == 0:
		print(frame, " ts=", Engine.time_scale, " paused=", cur.get_tree().paused, " alive=", alive, " power=", a.power, " charging=", a.charging, " pos=", a.global_position, " lead=", lead.global_position, " kills=", cur.kills)
	prev_hp.clear()
	for e in cur.get_tree().get_nodes_in_group("enemies"):
		if "hp" in e and not e.dead:
			prev_hp[e] = e.hp


func _finish() -> void:
	var cur := current_scene
	var c: Dictionary = configs[ci]
	var h: Array = stats["hits"]
	var zero := h.filter(func(x): return x == 0).size()
	var total := 0
	for x in h:
		total += x
	results.append("%-12s %-10s %-6s fires=%2d avg_hit=%.2f whiffs=%d cancels=%d kills=%d" % [c["ally"], c["preset"], c["mode"],
		stats["fires"], float(total) / maxf(h.size(), 1), zero, stats["cancels"], int(cur.kills) - int(get_meta("start_kills"))])
	results[-1] += "  [t%d d%d b%d o%d]" % [stats.get("timeout", 0), stats.get("dodge", 0), stats.get("broken", 0), stats.get("other", 0)]
	print(results[-1])


func _shots(cur, a) -> void:
	var c: Dictionary = configs[ci]
	if not has_meta("shot_" + str(ci)) and a.ai_charging and a.charge_t > 0.75:
		set_meta("shot_" + str(ci), true)
		cur.camera.global_position = (a.global_position + cur.leader.global_position) / 2.0
		cur.camera.zoom = Vector2(3, 3)
		cur.camera.reset_smoothing()
		set_meta("snap_at", frame + 1)
		set_meta("snap_name", "%s_%s.png" % [args["shot"], c["ally"]])
	if has_meta("snap_at") and frame == int(get_meta("snap_at")):
		root.get_texture().get_image().save_png(str(get_meta("snap_name")))
		remove_meta("snap_at")
		if c["ally"] == "odile" and not has_meta("menu_done"):
			set_meta("menu_done", true)
			cur.quick_menu.open()
			cur.quick_menu._set_tab(2)
			cur.quick_menu._pick_row(1)
			set_meta("menu_at", frame + 8)
	if has_meta("menu_at") and frame == int(get_meta("menu_at")):
		root.get_texture().get_image().save_png(str(args["shot"]) + "_menu.png")
		remove_meta("menu_at")
		cur.quick_menu.close()
