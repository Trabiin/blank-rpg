class_name SaveMigrations
extends RefCounted
## Upgrades old saves step by step (issue #110, docs/SAVES.md).
##
## Each step is one file in scripts/migrations/, named <yyyymmdd>_<what>.gd. The file name is the
## step's id, and steps run in file-name order. A step file looks like:
##
##     extends RefCounted
##     ## What changed in the save, and what old saves get instead.
##     static func migrate(save: Dictionary) -> Dictionary:
##         ...change and return `save`, or return {} if it cannot be upgraded...
##
## `save` is the whole save file (the scene snapshot, with the campaign under "empire").
## A save remembers which steps it already has ("migrations"); a save from before steps existed
## (format version 1) has none. New saves list every step this build knows, so they skip them all.
##
## Steps live in separate files so parallel pull requests each add their own and merge in any order.

const DIR := "res://scripts/migrations/"

static var _ids: Array = []


## Every step id this build knows, in the order they run.
static func ids() -> Array:
	if _ids.is_empty():
		var found := {}
		for f in DirAccess.get_files_at(DIR):
			# Exported builds list compiled scripts as "<name>.gd.remap" / "<name>.gdc".
			var name := f.trim_suffix(".remap")
			if name.ends_with(".gd"):
				found[name.trim_suffix(".gd")] = true
		_ids = found.keys()
		_ids.sort()
	return _ids.duplicate()


## Step ids a save lists that this build does not know: it was written by a newer build.
static func unknown(save: Dictionary) -> Array:
	var known := ids()
	var out := []
	for id in _done(save):
		if not id in known:
			out.append(id)
	return out


## Runs every step the save does not have yet. Returns {"ok": true, "data": upgraded save,
## "applied": [step ids run]} or {"ok": false, "error": text}. The input is not modified.
static func apply(save: Dictionary) -> Dictionary:
	var d := save.duplicate(true)
	var done := _done(d)
	var applied := []
	for id in ids():
		if id in done:
			continue
		var step: Script = load(DIR + id + ".gd")
		if step == null:
			return {"ok": false, "error": Loc.t("upgrade step %s is missing") % id}
		var out = step.call("migrate", d)
		if typeof(out) != TYPE_DICTIONARY or (out as Dictionary).is_empty():
			return {"ok": false, "error": Loc.t("upgrade step %s could not convert it") % id}
		d = out
		done.append(id)
		applied.append(id)
	d["migrations"] = done
	return {"ok": true, "data": d, "applied": applied}


static func _done(save: Dictionary) -> Array:
	var m = save.get("migrations", [])
	if typeof(m) != TYPE_ARRAY:
		return []
	return (m as Array).map(func(x): return str(x))
