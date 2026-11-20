extends RefCounted
## Base for test files (tests/run.gd). Each test_* method gets a fresh instance.

var tree: SceneTree
var runner  # tests/run.gd, for clear_scratch()
var failures: Array = []


func before_each() -> void:
	pass


func after_each() -> void:
	pass


func check(cond: bool, msg: String) -> bool:
	if not cond:
		failures.append(msg)
	return cond


func check_eq(got, want, msg: String) -> bool:
	return check(got == want, "%s: got %s, want %s" % [msg, str(got), str(want)])


## The log scanner (tools/run_tests.sh) fails the run on any ERROR or WARNING line. A test that
## means to trigger one (a corrupt save being set aside) announces it first with a regex.
func allow_log(pattern: String) -> void:
	print("##allow " + pattern)


func autoload(name: String) -> Node:
	return tree.root.get_node(name)


## Waits n frames.
func frames(n: int) -> void:
	for i in n:
		await tree.process_frame


## Changes scene and waits until it is running. Returns the new scene (null on failure).
func goto(path: String, settle := 10) -> Node:
	tree.paused = false
	tree.change_scene_to_file(path)
	await frames(settle)
	return tree.current_scene


## Waits until the current scene is `path` (after a game call changed it), up to `limit` frames.
func wait_scene(path: String, limit := 60) -> Node:
	for i in limit:
		await tree.process_frame
		if tree.current_scene and tree.current_scene.scene_file_path == path:
			await frames(5)
			return tree.current_scene
	failures.append("scene never became %s (now %s)" % [path, tree.current_scene.scene_file_path if tree.current_scene else "none"])
	return null
