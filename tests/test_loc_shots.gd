extends "res://tests/test_case.gd"
## Screenshots of every main screen with pseudo-localisation on (accented, bracketed, 30% longer
## text), to look for clipped or overflowing text before a longer language ships (issue #143).
## Does nothing in the normal test run. To take them, under a display (not --headless):
##   LOC_SHOTS=/tmp/loc xvfb-run -a godot --audio-driver Dummy --path . -s tests/run.gd -- loc_shots --pseudo-loc
## (--pseudo-loc turns pseudo-localisation on before any data loads.) Leave out --pseudo-loc for
## English shots to compare with.

const HUB := "res://scenes/hub.tscn"
const COMMAND := "res://scenes/command.tscn"
const MAIN := "res://scenes/main.tscn"
const TITLE := "res://scenes/title.tscn"

var shots := ""


func before_each() -> void:
	shots = OS.get_environment("LOC_SHOTS")
	if shots != "" and DisplayServer.get_name() == "headless":
		shots = ""
	if shots != "":
		DirAccess.make_dir_recursive_absolute(shots)


func _shot(name: String) -> void:
	await frames(4)
	var img := tree.root.get_viewport().get_texture().get_image()
	if img != null:
		img.save_png("%s/%s.png" % [shots, name])


func test_screens() -> void:
	if shots == "":
		return
	var Empire := autoload("Empire")
	autoload("Saves").pending = {}
	Empire.reset()
	for id in ["gristle", "ninefingers", "abeyance"]:
		Empire.recruits[id] = {"role": "idle", "target": "", "injured": 0}
	Dialogue.mark_seen("talk:meadow_intro")
	for k in Dialogue.data().get("talks", {}):
		Dialogue.mark_seen("talk:" + str(k))
	Settings.tips = false
	var title := await goto(TITLE, 20)
	await _shot("00_title")
	var hub := await goto(HUB, 20)
	await _shot("01_hub")
	hub.open_menu()
	await _shot("02_hub_menu")
	var cmd := await goto(COMMAND, 20)
	await _shot("03_command")
	var views := {"roster": cmd.roster_view, "buildings": cmd.buildings_view, "expeditions": cmd.expedition_view,
		"research": cmd.research_view, "diplomacy": cmd.diplomacy_view, "bonds": cmd.bonds_view,
		"newcomers": cmd.newcomers_view}
	var i := 10
	for name in views:
		views[name].open()
		await _shot("%02d_%s" % [i, name])
		views[name].close()
		i += 1
	cmd.gear_view.open("town")
	await _shot("20_gear")
	cmd.gear_view.close()
	cmd.governor_view.open("hollowmark")
	await _shot("21_governor")
	cmd.governor_view.close()
	if cmd.armory_view:
		cmd.armory_view.open()
		await _shot("22_armory")
		cmd.armory_view.close()
	if cmd.journal_view:
		cmd.journal_view.open()
		await _shot("23_journal")
		cmd.journal_view.close()
	cmd._open_brief(Missions.find("meadow_patrol"))
	await _shot("24_briefing")
	cmd._on_brief("go")
	await _shot("25_party_picker")
	cmd.party_picker.close()
	var opts := OptionsView.popup(cmd)
	await _shot("26_options")
	opts.queue_free()
	var help := HelpView.popup(cmd)
	await _shot("27_help")
	help.queue_free()
	Missions.launch(Missions.find("meadow_patrol"))
	var main := await wait_scene(MAIN)
	await frames(30)
	await _shot("30_mission")
	main.open_quick_menu()
	await _shot("31_quick_menu")
	main.quick_menu.close()
	await frames(5)
	main._show_results("success")
	await _shot("32_results")
	check(true, "shots taken")
