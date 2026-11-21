class_name Feedback
extends RefCounted
## Bug reports and feedback (issue #146): builds the report the player sees and sends from
## FeedbackView, writes it as a zip, and posts it to the endpoint in data/feedback.json.
##
## A report holds only what the player typed and ticked, plus the game build, system info and where
## they were in the game (Diag.system_info / game_context). It is sent only when the player presses
## Send. docs/PRIVACY.md says what is kept and for how long; docs/FEEDBACK.md says where reports go
## and how they become GitHub issues.

const CONFIG := "res://data/feedback.json"
const REPORT_DIR := "user://reports/"
const KINDS := ["bug", "feedback", "idea"]
const MAX_TEXT := 4000  # characters the player can type
const MAX_CONTACT := 120
const MAX_LOG := 256 * 1024  # bytes kept from the end of each log
const MAX_BODY := 4 * 1024 * 1024  # the endpoint refuses anything bigger

## Tests point reports at a local server with this (merged over data/feedback.json).
static var override := {}


## {"endpoint": url or "", "game_key": text, "privacy_url": url, "timeout": secs}.
static func config() -> Dictionary:
	var cfg := {"endpoint": "", "game_key": "", "privacy_url": "", "timeout": 25.0}
	if FileAccess.file_exists(CONFIG):
		var d = JSON.parse_string(FileAccess.get_file_as_string(CONFIG))
		if typeof(d) == TYPE_DICTIONARY:
			cfg.merge(d, true)
	cfg.merge(override, true)
	return cfg


## Whether this build can send reports online (otherwise the form saves them to a file).
static func can_send() -> bool:
	return str(config()["endpoint"]).begins_with("https://") or str(config()["endpoint"]).begins_with("http://127.0.0.1")


static func new_id() -> String:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	return "LI-%08X" % (rng.randi() & 0x7fffffff)


## The save the report would attach: the slot this game was loaded from or last saved to, else the newest.
static func save_slot() -> String:
	var saves = Engine.get_main_loop().root.get_node_or_null("Saves")
	if saves == null:
		return ""
	var slot: String = saves.current_slot if saves.current_slot != "" else saves.latest_slot()
	return slot if slot != "" and FileAccess.file_exists(saves.dir.path_join("save_%s.json" % slot)) else ""


## Builds a report. opts: kind, text, contact, logs (bool), save (bool), screenshot (Image or null),
## previous (the last session's Diag.previous, for a report offered after a crash).
static func build(opts: Dictionary) -> Dictionary:
	var diag = Engine.get_main_loop().root.get_node_or_null("Diag")
	var kind := str(opts.get("kind", "bug"))
	var report := {
		"id": str(opts.get("id", new_id())),
		"game": "last-ink",
		"created": Time.get_datetime_string_from_system(true) + "Z",
		"kind": kind if kind in KINDS else "bug",
		"text": str(opts.get("text", "")).strip_edges().left(MAX_TEXT),
		"contact": str(opts.get("contact", "")).strip_edges().left(MAX_CONTACT),
		"system": diag.system_info() if diag else {},
		"context": diag.game_context() if diag else {},
		"previous_session": opts.get("previous", {}),
		"attachments": {},
	}
	var att: Dictionary = report["attachments"]
	if opts.get("logs", false) and diag:
		for path in diag.log_files():
			att[path.get_file()] = {"type": "text/plain", "data": tail(FileAccess.get_file_as_string(path), MAX_LOG)}
	if opts.get("save", false):
		var slot := save_slot()
		if slot != "":
			var saves = Engine.get_main_loop().root.get_node("Saves")
			att["save_%s.json" % slot] = {"type": "application/json",
				"data": FileAccess.get_file_as_string(saves.dir.path_join("save_%s.json" % slot))}
	var shot = opts.get("screenshot")
	if shot is Image and not shot.is_empty():
		att["screenshot.png"] = {"type": "image/png", "base64": Marshalls.raw_to_base64(shot_png(shot))}
	return report


## The screenshot as PNG, halved when the window is big so a report stays small.
static func shot_png(img: Image) -> PackedByteArray:
	var copy := img.duplicate() as Image
	while copy.get_width() > 1280:
		copy.resize(copy.get_width() / 2, copy.get_height() / 2, Image.INTERPOLATE_NEAREST)
	return copy.save_png_to_buffer()


static func tail(text: String, max_bytes: int) -> String:
	if text.length() <= max_bytes:
		return text
	return "(earlier lines cut)\n" + text.right(max_bytes)


## The report as the JSON body the endpoint takes.
static func to_json(report: Dictionary) -> String:
	var body := report.duplicate()
	body["game_key"] = str(config()["game_key"])
	return JSON.stringify(body)


## A plain-text summary: the top of report.txt in the zip and the first thing a triager reads.
static func summary(report: Dictionary) -> String:
	var lines := ["Last Ink %s report %s" % [report["kind"], report["id"]], "Created: " + str(report["created"]), ""]
	lines.append(str(report["text"]) if str(report["text"]) != "" else "(no description)")
	lines.append("")
	if str(report["contact"]) != "":
		lines.append("Contact: " + str(report["contact"]))
	for section in ["context", "system"]:
		lines.append("[%s]" % section)
		var d: Dictionary = report[section]
		for k in d:
			lines.append("%s: %s" % [k, d[k]])
		lines.append("")
	var prev: Dictionary = report.get("previous_session", {})
	if not prev.is_empty():
		lines.append("[previous session]")
		lines.append("crashed: %s, errors: %d, warnings: %d" % [prev.get("crashed", false), int(prev.get("errors", 0)), int(prev.get("warnings", 0))])
		for s in prev.get("samples", []):
			lines.append("  " + str(s))
		lines.append("")
	lines.append("Attached: " + (", ".join(report["attachments"].keys()) if not report["attachments"].is_empty() else "nothing"))
	return "\n".join(lines)


## The report as a zip: report.txt, report.json (without the attachments) and each attachment.
static func zip_report(report: Dictionary) -> PackedByteArray:
	var files := {"report.txt": summary(report).to_utf8_buffer()}
	var meta := report.duplicate()
	meta.erase("attachments")
	files["report.json"] = JSON.stringify(meta, "\t").to_utf8_buffer()
	for name in report["attachments"]:
		var a: Dictionary = report["attachments"][name]
		files[name] = Marshalls.base64_to_raw(a["base64"]) if a.has("base64") else str(a["data"]).to_utf8_buffer()
	return zip_bytes(files)


## Zips files from disk (the log folder download on the web build).
static func zip_files(paths: Array) -> PackedByteArray:
	var files := {}
	for p in paths:
		files[str(p).get_file()] = FileAccess.get_file_as_bytes(p)
	return zip_bytes(files) if not files.is_empty() else PackedByteArray()


## {name: bytes} -> zip bytes (written through a scratch file: ZIPPacker only writes to disk).
static func zip_bytes(files: Dictionary) -> PackedByteArray:
	DirAccess.make_dir_recursive_absolute(REPORT_DIR)
	var tmp := REPORT_DIR.path_join(".zipping.zip")
	var zip := ZIPPacker.new()
	if zip.open(tmp) != OK:
		return PackedByteArray()
	for name in files:
		zip.start_file(name)
		zip.write_file(files[name])
		zip.close_file()
	zip.close()
	var bytes := FileAccess.get_file_as_bytes(tmp)
	DirAccess.remove_absolute(tmp)
	return bytes


## Saves the report as a zip the player can attach anywhere. Desktop: user://reports/<id>.zip, and
## returns that path. Web: the browser downloads it, and the file name is returned.
static func save_zip(report: Dictionary) -> String:
	var bytes := zip_report(report)
	if bytes.is_empty():
		return ""
	var name := "last-ink-report-%s.zip" % report["id"]
	if OS.has_feature("web"):
		JavaScriptBridge.download_buffer(bytes, name, "application/zip")
		return name
	DirAccess.make_dir_recursive_absolute(REPORT_DIR)
	var path := REPORT_DIR.path_join(name)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return ""
	f.store_buffer(bytes)
	f.close()
	return path


## Posts the report. Needs a node in the tree for the HTTPRequest (it runs while the game is paused).
## Returns {"ok": bool, "id": report id, "error": why not}.
static func send(host: Node, report: Dictionary) -> Dictionary:
	var cfg := config()
	if not can_send():
		return {"ok": false, "error": "no endpoint"}
	var body := to_json(report)
	if body.to_utf8_buffer().size() > MAX_BODY:
		return {"ok": false, "error": "too big"}
	var http := HTTPRequest.new()
	http.process_mode = Node.PROCESS_MODE_ALWAYS
	http.timeout = float(cfg["timeout"])
	host.add_child(http)
	var err := http.request(str(cfg["endpoint"]), ["Content-Type: application/json"], HTTPClient.METHOD_POST, body)
	if err != OK:
		http.queue_free()
		return {"ok": false, "error": error_string(err)}
	var res: Array = await http.request_completed
	http.queue_free()
	var code: int = res[1]
	if res[0] != HTTPRequest.RESULT_SUCCESS:
		return {"ok": false, "error": "network (%d)" % res[0]}
	var reply = JSON.parse_string((res[3] as PackedByteArray).get_string_from_utf8())
	if code < 200 or code >= 300 or typeof(reply) != TYPE_DICTIONARY or not reply.get("ok", false):
		var why: String = str(reply.get("error", "")) if typeof(reply) == TYPE_DICTIONARY else ""
		return {"ok": false, "error": "server said %d %s" % [code, why]}
	return {"ok": true, "id": str(reply.get("id", report["id"]))}
