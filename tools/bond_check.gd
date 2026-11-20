extends SceneTree
## Bond check (not exported: tools/* is excluded). Plays every rank scene of the given people through
## the real scene view, checks the data, the perks and the personal missions, and saves screenshots.
##   xvfb-run -a godot --path . -s tools/bond_check.gd -- out=/tmp/bonds who=ottoline,jessamy,odile,velvette
## Prints "BOND CHECK OK" at the end, or a list of problems.

var frame := 0
var args := {}
var problems: Array = []
var queue: Array = []  # [who, rank, stage] still to shoot
var view
var bonds_view
var empire
var step := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"


func _fail(s: String) -> void:
	problems.append(s)
	printerr("PROBLEM: " + s)


func _shot(name: String) -> void:
	var out := str(args.get("out", "/tmp/bonds"))
	DirAccess.make_dir_recursive_absolute(out)
	root.get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out, name])


func _setup() -> void:
	empire = root.get_node("Empire")
	empire.reset()
	empire.buildings["guildhall"] = 1
	var who: PackedStringArray = str(args.get("who", "ottoline,jessamy,odile,velvette")).split(",")
	for id in who:
		empire.recruits[id] = {"role": "idle", "target": "", "injured": 0}
	for id in ["gristle", "ninefingers", "abeyance"]:
		empire.recruits[id] = {"role": "idle", "target": "", "injured": 0}
	var bg := ColorRect.new()
	bg.color = Color.BLACK
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	view = load("res://scripts/scene_view.gd").new()
	root.add_child(view)
	view.visible = false
	for id in who:
		_check_data(id)
		for r in range(1, 6):
			queue.append([id, r])
			if r == 3 and Relationships.can_romance(id):  # the romance question comes before rank 4 (issue #116)
				queue.append([id, Relationships.MOMENT])


func _check_data(id: String) -> void:
	var info: Dictionary = empire.bond_info(id)
	if info.is_empty():
		_fail("%s has no bond" % id)
		return
	if load("res://scripts/scene_view.gd").portrait(id) == null:
		_fail("%s has no portrait" % id)
	for k in ["3", "5"]:
		if not info.get("perks", {}).has(k):
			_fail("%s has no rank %s perk" % [id, k])
	if empire.personal_job(id) == "":
		_fail("%s has no personal mission" % id)
	var ranks := []
	for sc in info.get("scenes", []):
		ranks.append(int(sc["rank"]))
		var all: Array = sc["lines"] + sc.get("end", [])
		if sc.get("choice", []).size() < 2:
			_fail("%s rank %d has fewer than two choices" % [id, sc["rank"]])
		for ch in sc.get("choice", []):
			all += ch.get("reply", [])
			if String(ch["label"]).length() > 60:
				_fail("%s rank %d choice too long: %s" % [id, sc["rank"], ch["label"]])
		for l in all:
			var sp: String = l[0]
			if sp != "" and sp != id and not empire.recruits.has(sp) and empire.recruit(sp).is_empty():
				_fail("%s rank %d: unknown speaker %s" % [id, sc["rank"], sp])
			if l.size() > 2 and not l[2] in ["happy", "angry", "sad", "surprised", "smug"]:
				_fail("%s rank %d: unknown expression %s" % [id, sc["rank"], l[2]])
			# The text box is 86 px tall: four lines of 11 px text fit.
			var f: Font = view.font if view.font != null else ThemeDB.fallback_font
			var h := f.get_multiline_string_size(String(l[1]), HORIZONTAL_ALIGNMENT_LEFT, 640 - 48, 11).y
			if h > 4 * f.get_height(11) + 1:
				_fail("%s rank %d: line too long for the box: %s" % [id, sc["rank"], String(l[1]).left(50)])
	if ranks != [1, 2, 3, 4, 5]:
		_fail("%s scenes are ranks %s" % [id, ranks])


func _process(_delta: float) -> bool:
	frame += 1
	if frame == 2:
		_setup()
		return false
	if frame < 4:
		return false
	# One scene every 4 frames: open it, shoot a line, shoot the choice, pick, shoot the outro.
	if view.visible:
		match step:
			1:
				view._at = mini(2, view._lines.size() - 1)
				view._shown = 99999.0
			2:
				_shot("%s_r%d_line" % [view.id, view.rank])
				view._at = view._lines.size() - 1
				view._shown = 99999.0
				view._advance()
			3:
				if view._stage != "choice":
					_fail("%s rank %d never reached its choice" % [view.id, view.rank])
				_shot("%s_r%d_choice" % [view.id, view.rank])
				view._pick(0)
			4:
				while view._stage == "reply":
					view._shown = 99999.0
					view._advance()
				_shot("%s_r%d_done" % [view.id, view.rank])
				if view.rank == Relationships.MOMENT:
					if Relationships.romance_of(view.id) != "partner":
						_fail("%s: saying yes did not start a romance" % view.id)
				elif empire.bond_rank(view.id) != view.rank:
					_fail("%s did not reach rank %d" % [view.id, view.rank])
				view._close()
		step += 1
		return false
	if not queue.is_empty():
		var q: Array = queue.pop_front()
		var id: String = q[0]
		var r: int = q[1]
		empire.bonds[id] = empire.bonds.get(id, {"points": 0, "rank": r - 1, "talk_day": 0, "personal_done": false})
		if r == Relationships.MOMENT:
			empire.bonds[id]["points"] = maxi(int(empire.bonds[id]["points"]), int(Relationships.data()["romance"]["moment_points"]))
		else:
			empire.bonds[id]["points"] = empire.bond_threshold(r)
		if r == 5:
			var st: String = PersonalMissions.state(id)
			if st != "offered" and st != "blocked":
				_fail("%s's personal mission is not on the Command Table at rank 4 (%s)" % [id, st])
			empire.bonds[id]["personal_done"] = true
		if empire.bond_next_scene(id) != r:
			_fail("%s: next scene is %d, expected %d" % [id, empire.bond_next_scene(id), r])
		view.play(id, r)
		step = 1
		return false
	if step >= 0:
		_check_perks()
		bonds_view = load("res://scripts/bonds_view.gd").new()
		root.add_child(bonds_view)
		bonds_view.open()
		bonds_view.sel = 9
		step = -1
		return false
	step -= 1
	if step == -4:
		_shot("bonds_screen_bottom")
		bonds_view.sel = 0
	if step == -7:
		_shot("bonds_screen_top")
		print("BOND CHECK OK" if problems.is_empty() else "BOND CHECK FAILED: %d problem(s)" % problems.size())
		return true
	return false


func _check_perks() -> void:
	var e = empire
	if e.damage_to_party(20) != 18:
		_fail("House Rules: 20 damage became %d, expected 18" % e.damage_to_party(20))
	var home: Dictionary = e.territory().find("hollowmark")
	if not e.fray_sources(home).any(func(s): return String(s[0]).begins_with("Nobody Gets Through")):
		_fail("Nobody Gets Through is not in Hollowmark's Fray list")
	var two := ""
	for jid in e.job_data:
		if int(e.job(jid).get("days", 0)) == 2:
			two = jid
			break
	if not is_equal_approx(e.job_days(two), 1.6):
		_fail("Back Roads: a 2-day job takes %s days" % e.job_days(two))
	if not e.ledger().any(func(l): return String(l["label"]).begins_with("Fair Assessment") and int(l["gilt"]) >= 1):
		_fail("Fair Assessment is not in the ledger")
	if not e.ledger().any(func(l): return String(l["label"]).begins_with("Night Freight") and int(l["supplies"]) == 2):
		_fail("Night Freight is not in the ledger")
	var raw: Dictionary = e.building("barracks")["levels"][0]["cost"]
	var cut: Dictionary = e.next_level("barracks")["cost"]
	if raw.has("gilt") and int(cut["gilt"]) != int(floor(int(raw["gilt"]) * 0.8)):
		_fail("Clean Books: barracks costs %s (was %s)" % [cut, raw])
	var before: int = e.standing_of("guild")
	e.change_standing("guild", 3, "", true)
	if e.standing_of("guild") - before != 4:
		_fail("Pillow Talk: +3 standing became %+d" % (e.standing_of("guild") - before))
	var b: Dictionary = e.mission_boosts()
	if not is_equal_approx(float(b["power_rate"]), 1.15):
		_fail("Encore: power rate %s" % b["power_rate"])
	# Losing a home province locks rank 5 (Ojon's rule) until it is reclaimed.
	var gal: Dictionary = e.territory().find("gallows")
	var owner_was: String = gal["owner"]
	e.bonds["ottoline"]["personal_done"] = false
	gal["owner"] = "erased"
	if e.personal_lost("ottoline") == "" or PersonalMissions.state("ottoline") != "lost":
		_fail("an erased home province should lock Ottoline's personal mission")
	gal["owner"] = owner_was
	if e.personal_lost("ottoline") != "":
		_fail("Ottoline's job should come back with the province")
	e.bonds["ottoline"]["personal_done"] = true
	print("perks: ", ", ".join(e.bond_perks().map(func(p): return "%s (%s)" % [p["name"], p["id"]])))
	print("mission lines: ", b["lines"])
