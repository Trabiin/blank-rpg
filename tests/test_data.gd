extends "res://tests/test_case.gd"
## Data checks (issue #110): every file in data/ parses, and every id it points at exists.
## A failure names the file and the entry, e.g. "missions.json gutterwoods_patrol: map ... missing".

const EXPRESSIONS := ["", "happy", "angry", "sad", "surprised", "smug"]
const OBJECTIVE_KINDS := ["kills", "boss", "defense", "reclaim", "rescue"]
const OWNERS := ["you", "free", "erased"]

var D := {}  # file name -> parsed JSON


func before_each() -> void:
	D = {}
	for f in DirAccess.get_files_at("res://data/"):
		if f.ends_with(".json"):
			D[f] = JSON.parse_string(FileAccess.get_file_as_string("res://data/" + f))


func _ids(arr: Array) -> Dictionary:
	var out := {}
	for e in arr:
		out[str(e["id"])] = e
	return out


func _unique(file: String, arr: Array) -> void:
	var seen := {}
	for e in arr:
		var id := str(e.get("id", ""))
		check(id != "", "%s: an entry has no id" % file)
		check(not seen.has(id), "%s: id %s used twice" % [file, id])
		seen[id] = true


func _recruits() -> Dictionary:
	return _ids(D["recruits.json"]["recruits"])


func _provinces() -> Dictionary:
	return _ids(D["provinces.json"]["provinces"])


func _talks() -> Dictionary:
	var t: Dictionary = D["dialogue.json"]["talks"].duplicate()
	t.merge(D["story.json"]["talks"])
	return t


func _speakers() -> Dictionary:
	var s := {"": true}
	for id in _recruits():
		s[id] = true
	for id in D["dialogue.json"]["speakers"]:
		s[id] = true
	for id in D["story.json"]["speakers"]:
		s[id] = true
	return s


func _res_keys(where: String, d: Dictionary) -> void:
	for k in d:
		check(Empire.RES_NAMES.has(k), "%s: unknown resource '%s'" % [where, k])


func _lines(where: String, lines: Array) -> void:
	var speakers := _speakers()
	for l in lines:
		var a: Array = Dialogue.line(l)
		check(speakers.has(a[0]), "%s: unknown speaker '%s'" % [where, a[0]])
		check(a[2] in EXPRESSIONS, "%s: unknown expression '%s'" % [where, a[2]])
		check(str(a[1]).strip_edges() != "", "%s: empty line for '%s'" % [where, a[0]])


func _res(path: String) -> bool:
	return ResourceLoader.exists(path) or FileAccess.file_exists(path)


# ------------------------------------------------------------------ files

func test_every_data_file_parses() -> void:
	check(D.size() >= 18, "expected the data files, found %d" % D.size())
	for f in D:
		check(typeof(D[f]) == TYPE_DICTIONARY, "%s does not parse to a JSON object" % f)


# ------------------------------------------------------------------ people

func test_recruits() -> void:
	var rs: Array = D["recruits.json"]["recruits"]
	_unique("recruits.json", rs)
	var traits: Dictionary = D["recruits.json"]["traits"]
	var jobs := _ids(D["expeditions.json"]["jobs"])
	var factions := _ids(D["factions.json"]["factions"])
	var buildings := _ids(D["buildings.json"]["buildings"])
	var nodes := _ids(D["research.json"]["nodes"])
	var tiers := _ids(D["factions.json"]["tiers"])
	for r in rs:
		var id: String = r["id"]
		var w: String = "recruits.json " + id
		for t in r.get("traits", []):
			check(traits.has(t), "%s: unknown trait %s" % [w, t])
		for s in r.get("stats", {}):
			check(Empire.STAT_NAMES.has(s), "%s: unknown stat %s" % [w, s])
		check(_res("res://assets/portraits/%s.png" % id), "%s: no portrait assets/portraits/%s.png" % [w, id])
		check(D["sprites.json"]["sprites"].has(id), "%s: no sprite set in sprites.json" % w)
		var outfit := str(r.get("look", {}).get("outfit", ""))
		if outfit != "":
			check(_res("res://assets/characters/outfit_%s.png" % outfit), "%s: outfit %s has no image" % [w, outfit])
		var j: Dictionary = r.get("join", {})
		match str(j.get("type", "")):
			"":
				check(r.get("start", false) or jobs.values().any(func(x): return x.get("recruit", "") == id),
					"%s: not a starting recruit and has no way to join" % w)
			"rescue":
				check(jobs.has(j.get("job", "")), "%s: rescue job %s missing" % [w, j.get("job")])
			"claim":
				check(_provinces().has(j.get("province", "")), "%s: claim province %s missing" % [w, j.get("province")])
			"building":
				check(buildings.has(j.get("building", "")), "%s: building %s missing" % [w, j.get("building")])
			"standing":
				check(factions.has(j.get("faction", "")), "%s: faction %s missing" % [w, j.get("faction")])
				check(tiers.has(j.get("tier", "")), "%s: tier %s missing" % [w, j.get("tier")])
			"research":
				check(nodes.has(j.get("node", "")), "%s: research node %s missing" % [w, j.get("node")])
			"renown":
				check(int(j.get("amount", 0)) > 0, "%s: renown amount" % w)
			"bond":
				check(D["bonds.json"]["cast"].has(j.get("who", "")), "%s: bond with %s, who has no bond" % [w, j.get("who")])
			var other:
				check(false, "%s: unknown join type %s" % [w, other])
		_res_keys(w + " hire", r.get("hire", {}))


func test_field_heroes() -> void:
	var heroes: Dictionary = D["heroes.json"]["heroes"]
	var recruits := _recruits()
	var abilities: Dictionary = D["abilities.json"]["abilities"]
	var techs: Dictionary = D["techs.json"]["techs"]
	var gear: Dictionary = D["gear.json"]
	for id in heroes:
		var h: Dictionary = heroes[id]
		var w: String = "heroes.json " + id
		check(recruits.has(id), "%s: not a recruit" % w)
		check(str(recruits.get(id, {}).get("tier", "")) == "field", "%s: recruit tier is not field" % w)
		for a in h.get("abilities", []):
			check(abilities.has(a), "%s: unknown ability %s" % [w, a])
		check(AllyAI.PRESETS.has(AllyAI.preset_id(str(h.get("ai", "")))) and (AllyAI.PRESETS.has(h.get("ai", "")) or AllyAI.LEGACY.has(h.get("ai", ""))),
			"%s: unknown ai style %s" % [w, h.get("ai")])
		check(techs.has(id), "%s: no charged tech in techs.json" % w)
		check(gear["growth"].has(id), "%s: no level growth in gear.json" % w)
		var start := str(gear["start"]["gear"].get(id, ""))
		check(start != "", "%s: no starting weapon in gear.json" % w)
		if start != "":
			check(gear["items"].has(start), "%s: starting gear %s missing" % [w, start])
	for id in techs:
		check(heroes.has(id), "techs.json: %s is not a field hero" % id)
	for id in gear["growth"]:
		check(id == "_default" or heroes.has(id), "gear.json growth: %s is not a field hero" % id)
	for id in gear["start"]["gear"]:
		check(heroes.has(id), "gear.json start: %s is not a field hero" % id)


func test_gear_and_items() -> void:
	var gear: Dictionary = D["gear.json"]
	var heroes: Dictionary = D["heroes.json"]["heroes"]
	for id in gear["items"]:
		var it: Dictionary = gear["items"][id]
		var w: String = "gear.json item " + id
		if it.has("hero"):
			check(heroes.has(it["hero"]), "%s: hero %s is not a field hero" % [w, it["hero"]])
		check(str(it.get("name", "")) != "", "%s: no name" % w)
		check(str(it.get("blurb", "")) != "", "%s: no blurb" % w)
	for id in gear["drops"]["table"]:
		check(gear["items"].has(id), "gear.json drops: %s missing" % id)
	for id in gear["start"]["gear"]:
		var item: Dictionary = gear["items"].get(gear["start"]["gear"][id], {})
		check(str(item.get("hero", id)) == id, "gear.json start: %s gets %s, made for %s" % [id, gear["start"]["gear"][id], item.get("hero")])
	for id in D["items.json"]["items"]:
		check(str(D["items.json"]["items"][id].get("desc", "")) != "", "items.json %s: no description" % id)


func test_bonds() -> void:
	var b: Dictionary = D["bonds.json"]
	var recruits := _recruits()
	var buildings := _ids(D["buildings.json"]["buildings"])
	for id in b["cast"]:
		var c: Dictionary = b["cast"][id]
		var w: String = "bonds.json " + id
		check(recruits.has(id), "%s: not a recruit" % w)
		for role in c.get("likes", []) + c.get("dislikes", []):
			var parts := str(role).split(":")
			check(Empire.ROLE_NAMES.has(parts[0]), "%s: unknown role %s" % [w, role])
			if parts.size() > 1 and parts[0] == "staff":
				check(buildings.has(parts[1]), "%s: unknown building in %s" % [w, role])
		var ranks := {}
		for s in c.get("scenes", []):
			ranks[int(s["rank"])] = true
			_lines("%s rank %d scene" % [w, int(s["rank"])], s.get("lines", []))
			for ch in s.get("choice", []):
				_lines("%s rank %d choice" % [w, int(s["rank"])], ch.get("reply", []))
		for r in range(1, 6):
			check(ranks.has(r), "%s: no rank %d scene" % [w, r])
		for r in c.get("perks", {}):
			check(str(c["perks"][r].get("name", "")) != "", "%s: perk at rank %s has no name" % [w, r])


# ------------------------------------------------------------------ world

func test_provinces_and_factions() -> void:
	var ps: Array = D["provinces.json"]["provinces"]
	_unique("provinces.json", ps)
	var factions := _ids(D["factions.json"]["factions"])
	_unique("factions.json", D["factions.json"]["factions"])
	for p in ps:
		var w: String = "provinces.json " + str(p["id"])
		check(str(p["owner"]) in OWNERS or factions.has(p["owner"]), "%s: unknown owner %s" % [w, p["owner"]])
		check(Empire.STAT_NAMES.has(p.get("favors", "")), "%s: favours unknown stat %s" % [w, p.get("favors")])
		_res_keys(w + " output", p.get("output", {}))
	for fid in factions:
		var f: Dictionary = factions[fid]
		var w: String = "factions.json " + fid
		check(_provinces().has(f.get("province", "")), "%s: province %s missing" % [w, f.get("province")])
		check(Empire.STAT_NAMES.has(f.get("respects", "")), "%s: respects unknown stat %s" % [w, f.get("respects")])
		for deal in f.get("deals", {}):
			check(deal in Empire.DEAL_ORDER, "%s: unknown deal %s" % [w, deal])
			_res_keys("%s deal %s cost" % [w, deal], f["deals"][deal].get("cost", {}))


func test_buildings_and_research() -> void:
	_unique("buildings.json", D["buildings.json"]["buildings"])
	for b in D["buildings.json"]["buildings"]:
		check(Empire.STAT_NAMES.has(b.get("stat", "")), "buildings.json %s: unknown stat %s" % [b["id"], b.get("stat")])
		for lv in b.get("levels", []):
			_res_keys("buildings.json %s cost" % b["id"], lv.get("cost", {}))
	var branches := _ids(D["research.json"]["branches"])
	_unique("research.json", D["research.json"]["nodes"])
	for n in D["research.json"]["nodes"]:
		check(branches.has(n.get("branch", "")), "research.json %s: unknown branch %s" % [n["id"], n.get("branch")])
		_res_keys("research.json %s cost" % n["id"], n.get("cost", {}))


func test_expeditions() -> void:
	var e: Dictionary = D["expeditions.json"]
	_unique("expeditions.json", e["jobs"])
	var recruits := _recruits()
	for j in e["jobs"]:
		var w: String = "expeditions.json " + str(j["id"])
		check(_provinces().has(j.get("province", "")), "%s: province %s missing" % [w, j.get("province")])
		for s in j.get("stats", {}):
			check(Empire.STAT_NAMES.has(s), "%s: unknown stat %s" % [w, s])
		_res_keys(w + " reward", j.get("reward", {}))
		if j.has("recruit") and str(j["recruit"]) != "":
			check(recruits.has(j["recruit"]), "%s: recruit %s missing" % [w, j["recruit"]])
		if j.has("who"):
			check(recruits.has(j["who"]), "%s: recruit %s missing" % [w, j["who"]])
	for p in e["pairs"]:
		for id in p["ids"]:
			check(recruits.has(id), "expeditions.json pair: %s missing" % id)


func test_missions_and_enemies() -> void:
	var ms: Array = D["missions.json"]["missions"]
	_unique("missions.json", ms)
	var kinds: Dictionary = D["enemies.json"]["kinds"]
	var talks := _talks()
	for m in ms:
		var w: String = "missions.json " + str(m["id"])
		check(_provinces().has(m.get("province", "")), "%s: province %s missing" % [w, m.get("province")])
		check(FileAccess.file_exists(m.get("map", "")), "%s: map %s missing" % [w, m.get("map")])
		check(str(m.get("objective", {}).get("kind", "kills")) in OBJECTIVE_KINDS, "%s: unknown objective kind" % w)
		for k in m.get("enemies", {}):
			check(kinds.has(k), "%s: unknown enemy %s" % [w, k])
		_res_keys(w + " rewards", m.get("rewards", {}))
		_res_keys(w + " loot", m.get("loot", {}))
		if m.has("intro"):
			check(talks.has(m["intro"]), "%s: intro talk %s missing" % [w, m["intro"]])
		if m.has("scene"):
			check(ResourceLoader.exists(m["scene"]), "%s: scene %s missing" % [w, m["scene"]])
	for k in kinds:
		var info: Dictionary = kinds[k]
		check(EnemyKinds.SCRIPTS.has(info.get("script", k)), "enemies.json %s: no behaviour script" % k)
		check(D["sprites.json"]["sprites"].has(info.get("sprite", k)), "enemies.json %s: no sprite set %s" % [k, info.get("sprite", k)])
		check(str(info.get("tip", "")) != "", "enemies.json %s: no tip" % k)
	for r in D["enemies.json"]["rosters"]:
		check(r == "default" or _provinces().has(r), "enemies.json roster %s: not a province" % r)
		for k in D["enemies.json"]["rosters"][r]:
			check(kinds.has(k), "enemies.json roster %s: unknown enemy %s" % [r, k])
	for pl in D["blank.json"]["plans"]:
		check(_provinces().has(pl.get("target", "")), "blank.json %s: target %s missing" % [pl["id"], pl.get("target")])
		check(pl.get("counter", "") in ["governor", "lamp"], "blank.json %s: unknown counter %s" % [pl["id"], pl.get("counter")])


# ------------------------------------------------------------------ words and pictures

func test_dialogue_and_story() -> void:
	var dl: Dictionary = D["dialogue.json"]
	var recruits := _recruits()
	var talks := _talks()
	for id in talks:
		var t = talks[id]
		_lines("talk " + id, t.get("lines", []) if typeof(t) == TYPE_DICTIONARY else t)
	for id in dl["first_talk"]:
		check(recruits.has(id), "dialogue.json first_talk: %s is not a recruit" % id)
		check(talks.has(dl["first_talk"][id]), "dialogue.json first_talk %s: talk %s missing" % [id, dl["first_talk"][id]])
	for id in dl["events"]:
		_lines("event " + id, dl["events"][id].get("lines", []))
	for map in dl["banter"]:
		check(FileAccess.file_exists("res://maps/%s.txt" % map), "dialogue.json banter: no map maps/%s.txt" % map)
		for z in dl["banter"][map]:
			_lines("banter %s %s" % [map, z.get("id", "?")], z.get("lines", []))
			for n in z.get("needs", []):
				check(recruits.has(n), "banter %s %s: needs unknown %s" % [map, z.get("id"), n])
	var missions := _ids(D["missions.json"]["missions"])
	for b in D["story.json"]["beats"]:
		check(talks.has(b.get("talk", "")), "story.json beat: talk %s missing" % b.get("talk"))
		var then := str(b.get("then", ""))
		if then.begins_with("launch:"):
			check(missions.has(then.trim_prefix("launch:")), "story.json beat %s: mission %s missing" % [b.get("talk"), then])
		_conditions("story.json beat " + str(b.get("talk")), b.get("when", {}), missions, talks, recruits)
	for g in D["story.json"]["goals"]:
		_conditions("story.json goal " + str(g.get("text")), g.get("done", {}), missions, talks, recruits)
		_conditions("story.json goal " + str(g.get("text")), g.get("show", {}), missions, talks, recruits)


func _conditions(w: String, c: Dictionary, missions: Dictionary, talks: Dictionary, recruits: Dictionary) -> void:
	for mid in c.get("cleared", []) + c.get("not_cleared", []):
		check(missions.has(mid), "%s: mission %s missing" % [w, mid])
	for tid in c.get("seen", []):
		check(talks.has(tid), "%s: talk %s missing" % [w, tid])
	for rid in c.get("joined", []):
		check(recruits.has(rid), "%s: recruit %s missing" % [w, rid])


func test_sprite_sets_have_their_frames() -> void:
	var sprites: Dictionary = D["sprites.json"]["sprites"]
	for id in sprites:
		var s: Dictionary = sprites[id]
		for anim in s.get("anims", {}):
			for dir in s["anims"][anim].get("dirs", []):
				var p := "res://assets/sprites/%s/%s_%s.png" % [id, anim, dir]
				check(ResourceLoader.exists(p), "sprites.json %s: %s missing" % [id, p])


func test_maps_load() -> void:
	for f in DirAccess.get_files_at("res://maps/"):
		if f.ends_with(".txt"):
			var text := FileAccess.get_file_as_string("res://maps/" + f)
			check(text.strip_edges() != "", "maps/%s is empty" % f)
