extends Node
## Save slots (autoload "Saves"). One autosave slot plus three manual slots, stored as JSON
## in user://. On the web build user:// lives in the browser's IndexedDB, so saves survive
## closing the tab.
##
## The game scene hands over a snapshot Dictionary; this script only stores and finds them.
## To load, put the data in `pending` and change to the game scene, which applies it on start.

const VERSION := 1
const SLOTS := ["auto", "1", "2", "3"]
const GAME_SCENE := "res://scenes/main.tscn"

## Snapshot for the game scene to apply on its next _ready(), then clear.
var pending: Dictionary = {}


func _path(slot: String) -> String:
	return "user://save_%s.json" % slot


func slot_label(slot: String) -> String:
	return "Autosave" if slot == "auto" else "Slot " + slot


func save(slot: String, data: Dictionary) -> bool:
	data["version"] = VERSION
	data["saved_at"] = int(Time.get_unix_time_from_system())
	var f := FileAccess.open(_path(slot), FileAccess.WRITE)
	if f == null:
		push_warning("Could not write save %s: %s" % [slot, error_string(FileAccess.get_open_error())])
		return false
	f.store_string(JSON.stringify(data))
	f.close()  # closing the file is what flushes it to IndexedDB on the web
	return true


func read(slot: String) -> Dictionary:
	if not FileAccess.file_exists(_path(slot)):
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(_path(slot)))
	if typeof(parsed) != TYPE_DICTIONARY or int(parsed.get("version", 0)) != VERSION:
		return {}
	return parsed


func exists(slot: String) -> bool:
	return not read(slot).is_empty()


## The most recently written slot, or "" when there are no saves.
func latest_slot() -> String:
	var best := ""
	var best_t := -1
	for s in SLOTS:
		var d := read(s)
		if not d.is_empty() and int(d["saved_at"]) > best_t:
			best_t = int(d["saved_at"])
			best = s
	return best


## One-line description for menus, e.g. "Frayed Meadow  12m played  (5 min ago)".
func describe(slot: String) -> String:
	var d := read(slot)
	if d.is_empty():
		return "(empty)"
	var mins := int(float(d.get("playtime", 0.0)) / 60.0)
	return "%s   %dm played   (%s)" % [d.get("area_name", "?"), mins, _ago(int(d["saved_at"]))]


func _ago(t: int) -> String:
	var s := int(Time.get_unix_time_from_system()) - t
	if s < 60:
		return "just now"
	if s < 3600:
		return "%d min ago" % (s / 60)
	if s < 86400:
		return "%d h ago" % (s / 3600)
	return "%d days ago" % (s / 86400)


## Loads a slot into `pending` and starts the game scene. Returns false if the slot is empty.
func load_and_play(slot: String) -> bool:
	var d := read(slot)
	if d.is_empty():
		return false
	pending = d
	get_tree().paused = false
	get_tree().change_scene_to_file(GAME_SCENE)
	return true


## Menu items for picking a slot. `for_saving` lists manual slots only, all selectable.
func slot_items(for_saving: bool) -> Array:
	var out := []
	for s in SLOTS:
		if for_saving and s == "auto":
			continue
		var has := exists(s)
		out.append({"id": s, "label": slot_label(s), "detail": describe(s), "enabled": for_saving or has})
	out.append({"id": "back", "label": "Back"})
	return out
