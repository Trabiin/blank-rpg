extends "res://tests/test_case.gd"
## Every script in the game compiles, including ones no scene test happens to reach.


func _scripts(dir: String) -> Array:
	var out := []
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))
	for d in DirAccess.get_directories_at(dir):
		out.append_array(_scripts(dir.path_join(d)))
	return out


func test_every_script_compiles() -> void:
	var all := _scripts("res://scripts")
	check(all.size() > 50, "found the game scripts (%d)" % all.size())
	for path in all:
		var s: Script = load(path)
		check(s != null and s.can_instantiate(), "%s does not compile" % path)
