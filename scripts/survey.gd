class_name Survey
extends RefCounted
## The playtest survey (issues #148, #168): which builds show it, the questions (data/survey.json),
## the playtest settings (data/playtest.json), what the tester has already seen or sent, and the
## report the answers go out as. SurveyView is the form; docs/PLAYTEST.md is how a round is run and
## tools/playtest_report.py turns the answers into the round summary.
##
## The survey asks about art, characters and writing in neutral words first and only names AI on its
## last real page ("ai": true in survey.json). Opening that page locks the earlier answers, so an
## AI remark on an earlier page is always unprompted. Answers travel as a Feedback report of kind
## "survey" (the same private inbox as bug reports, docs/FEEDBACK.md), with the answers in
## survey.json and a readable copy in the report text.

const QUESTIONS := "res://data/survey.json"
const SETTINGS := "res://data/playtest.json"
const AI_USE := "res://data/ai_use.json"  # the AI use statement (issue #164), when it exists
const TYPES := ["scale", "choice", "multi", "text", "line", "character"]
const MAX_ANSWER := 1500  # characters per typed answer
const OTHER := "_other"  # character answer: someone not in the list
const REOFFER_MIN := 45.0  # more minutes of play before the title asks again
const MAX_OFFERS := 3

## Tests point these elsewhere.
static var state_path := "user://playtest.cfg"
static var override := {}  # merged over data/playtest.json
static var as_release := false  # tests: behave like a release export (no editor / test_shortcuts feature)


static func _json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	return d if typeof(d) == TYPE_DICTIONARY else {}


static func settings() -> Dictionary:
	var s := {"round": "", "offer_after_min": 30, "welcome_title": "", "welcome": "", "ai_short": "", "ai_url": ""}
	s.merge(_json(SETTINGS), true)
	s.merge(override, true)
	return s


static func questions() -> Dictionary:
	return _json(QUESTIONS)


static func pages() -> Array:
	return questions().get("pages", [])


static func version() -> int:
	return int(questions().get("version", 0))


## The round this build is for: data/playtest.json "round", or "dev" in builds with the test
## shortcuts (the editor and the web link Ojon tests on), or "" (release: no survey anywhere).
static func round_id() -> String:
	var r := str(settings()["round"]).strip_edges()
	if r != "":
		return r
	if as_release:
		return ""
	return "dev" if OS.has_feature("editor") or OS.has_feature("test_shortcuts") else ""


static func enabled() -> bool:
	return round_id() != ""


## The short AI statement: data/ai_use.json "short" (issue #164) when it exists, else our own copy.
static func ai_short() -> String:
	var s := str(_json(AI_USE).get("short", "")).strip_edges()
	return s if s != "" else str(settings()["ai_short"])


static func ai_url() -> String:
	return str(settings()["ai_url"])


## The menu entry for the title and pause menus: nothing in release builds.
static func menu_items() -> Array:
	if not enabled():
		return []
	var done := submitted()
	return [{"id": "survey", "label": TranslationServer.translate("Playtest survey"),
		"detail": TranslationServer.translate("sent, thank you") if done else TranslationServer.translate("5 minutes, helps a lot")}]


# ---------------------------------------------------------------- what the tester has seen

static func _state() -> ConfigFile:
	var cfg := ConfigFile.new()
	cfg.load(state_path)
	return cfg


static func _read(key: String, default):
	return _state().get_value(round_id(), key, default)


static func _write(key: String, value) -> void:
	var cfg := _state()
	cfg.set_value(round_id(), key, value)
	cfg.save(state_path)


static func submitted() -> bool:
	return _read("submitted", "") != ""


static func mark_submitted(report_id: String) -> void:
	_write("submitted", report_id)


static func welcomed() -> bool:
	return bool(_read("welcomed", false))


static func mark_welcomed() -> void:
	_write("welcomed", true)


static func mute_offers() -> void:
	_write("muted", true)


## Minutes played in the most advanced campaign: the open game, else the newest save.
static func minutes_played() -> float:
	var secs := 0.0
	var tree := Engine.get_main_loop() as SceneTree
	var empire = tree.root.get_node_or_null("Empire") if tree else null
	if empire:
		secs = float(empire.playtime)
	var saves = tree.root.get_node_or_null("Saves") if tree else null
	if saves:
		var slot: String = saves.latest_slot()
		if slot != "":
			secs = maxf(secs, float(saves.read(slot).get("playtime", 0.0)))
	return secs / 60.0


## Whether the title should ask for the survey now: a playtest round, not sent yet, not told to stop,
## enough play since the last time it asked, and at most MAX_OFFERS times.
static func should_offer() -> bool:
	if not enabled() or submitted() or bool(_read("muted", false)):
		return false
	var offers := int(_read("offers", 0))
	if offers >= MAX_OFFERS:
		return false
	var mins := minutes_played()
	var due := float(settings()["offer_after_min"]) if offers == 0 else float(_read("offered_at_min", 0.0)) + REOFFER_MIN
	return mins >= due


static func mark_offered() -> void:
	_write("offers", int(_read("offers", 0)) + 1)
	_write("offered_at_min", minutes_played())


# ---------------------------------------------------------------- answers

## The characters the "character" questions offer: the tester's roster (open game, else newest save),
## as [{id, name}], sorted by name.
static func characters() -> Array:
	var tree := Engine.get_main_loop() as SceneTree
	var empire = tree.root.get_node_or_null("Empire") if tree else null
	if empire == null:
		return []
	var ids: Array = empire.roster_ids()
	if ids.is_empty():
		var saves = tree.root.get_node_or_null("Saves")
		var slot: String = saves.latest_slot() if saves else ""
		if slot != "":
			var saved = saves.read(slot).get("empire", {}).get("recruits", {})
			if typeof(saved) == TYPE_DICTIONARY:
				ids = saved.keys().filter(func(id): return empire.recruit_data.has(id))
	var out := []
	for id in ids:
		out.append({"id": str(id), "name": empire.short_name(id)})
	out.sort_custom(func(a, b): return a["name"] < b["name"])
	return out


static func find_question(qid: String) -> Dictionary:
	for p in pages():
		for q in p.get("questions", []):
			if q["id"] == qid:
				return q
	return {}


## Whether an answer counts as given (blank answers are allowed everywhere).
static func answered(value) -> bool:
	match typeof(value):
		TYPE_NIL:
			return false
		TYPE_STRING:
			return value.strip_edges() != ""
		TYPE_INT, TYPE_FLOAT:
			return int(value) > 0
		TYPE_ARRAY:
			return not value.is_empty()
		TYPE_DICTIONARY:
			return str(value.get("id", "")) != "" or str(value.get("other", "")).strip_edges() != ""
	return false


## An answer as English text for the report (the stored answers stay in English too, whatever the
## game's language, so rounds and languages can be compared).
static func answer_text(q: Dictionary, value) -> String:
	match str(q.get("type", "")):
		"scale":
			var labels: Array = q.get("labels", [])
			var i := int(value)
			return "%d/%d %s" % [i, labels.size(), labels[i - 1]] if i >= 1 and i <= labels.size() else ""
		"multi":
			return ", ".join(value) if value is Array else ""
		"character":
			if value is Dictionary:
				return str(value.get("name", "")) if str(value.get("id", "")) not in ["", OTHER] \
					else "Someone else: " + str(value.get("other", "")).strip_edges()  # no-tr: report text stays English
			return ""
	return str(value).strip_edges() if value != null else ""


## Drops unknown questions and empty answers, clamps typed text and out-of-range picks.
static func clean(answers: Dictionary) -> Dictionary:
	var out := {}
	for qid in answers:
		var q := find_question(str(qid))
		var v = answers[qid]
		if q.is_empty() or not answered(v):
			continue
		match str(q["type"]):
			"scale":
				var i := int(v)
				if i >= 1 and i <= q.get("labels", []).size():
					out[qid] = i
			"choice":
				if str(v) in q.get("options", []):
					out[qid] = str(v)
			"multi":
				var picked := []
				for o in v:
					if str(o) in q.get("options", []) and str(o) not in picked:
						picked.append(str(o))
				if not picked.is_empty():
					out[qid] = picked
			"character":
				out[qid] = {"id": str(v.get("id", "")), "name": str(v.get("name", "")).left(60),
					"other": str(v.get("other", "")).strip_edges().left(120)}
			_:
				out[qid] = str(v).strip_edges().left(MAX_ANSWER)
	return out


## The readable copy that becomes the report text (and the report issue's body): one block per
## answered question, in survey order, cut to fit the report's text limit.
static func summary(answers: Dictionary) -> String:
	var lines := ["Playtest survey, round %s (survey v%d)" % [round_id(), version()]]  # no-tr: report text
	for p in pages():
		var block := []
		for q in p.get("questions", []):
			if q["id"] == "contact" or not answers.has(q["id"]):
				continue  # the contact line stays in the report's own contact field
			block.append("%s\n  %s" % [q["prompt"], answer_text(q, answers[q["id"]]).replace("\n", "\n  ")])
		if not block.is_empty():
			lines.append("")
			lines.append("== %s ==" % p["title"])
			lines.append_array(block)
	var text := "\n".join(lines)
	return text if text.length() <= Feedback.MAX_TEXT else text.left(Feedback.MAX_TEXT - 40) + "\n(cut: full answers in survey.json)"  # no-tr


## The report the survey sends: a Feedback report of kind "survey" with the answers attached.
## meta: {"ai_page_seen": bool, "minutes": time spent in the form, "characters": the names offered}.
static func build_report(answers: Dictionary, meta := {}, id := "") -> Dictionary:
	var a := clean(answers)
	var contact := str(a.get("contact", ""))
	a.erase("contact")
	var report := Feedback.build({"id": id if id != "" else Feedback.new_id(), "kind": "feedback",
		"text": summary(a), "contact": contact, "logs": false, "save": false})
	report["kind"] = "survey"
	var payload := {
		"survey_version": version(),
		"round": round_id(),
		"answers": a,
		"ai_page_seen": bool(meta.get("ai_page_seen", false)),
		"minutes": float(meta.get("minutes", 0.0)),
		"characters": meta.get("characters", []),
	}
	report["attachments"]["survey.json"] = {"type": "application/json", "data": JSON.stringify(payload, "\t")}
	return report
