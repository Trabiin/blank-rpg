class_name HelpWatch
extends Node
## Watches a host scene (the hub or the Command Table) for help to give (issue #115):
##   - a Command screen opening for the first time: its explainer plays over it;
##   - a screen the story has not opened yet: it closes again and someone says why;
##   - an unlock or a first-time tip coming due (Help.due) while nothing else is on screen.
## The host needs its screens in the properties named by Help.SCREENS (any it lacks are skipped)
## and alerts_blocked(), which says when a screen, menu or conversation is up. A host with
## _story_check() gets it called after each card, so story beats wait their turn.
##
## Usage, in the host's _ready after its screens exist:  HelpWatch.attach(self)

const CHECK_EVERY := 0.4

var host: Node
var on_command := false
var _t := 0.0


static func attach(p_host: Node) -> HelpWatch:
	var w := HelpWatch.new()
	w.host = p_host
	p_host.add_child(w)
	return w


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	on_command = host.scene_file_path == Saves.COMMAND_SCENE
	var card := HelpCard.ensure(host)
	card.closed.connect(_on_card_closed)
	for screen in Help.SCREENS:
		var prop: String = Help.SCREENS[screen]
		if prop == "" or not prop in host:
			continue
		var view = host.get(prop)
		if view is CanvasItem:
			(view as CanvasItem).visibility_changed.connect(_on_view_shown.bind(view, screen))
	Empire.notice.connect(_on_notice)
	Help.settle_old_campaign()


func _on_notice(text: String, _warning: bool) -> void:
	if text.ends_with("has been erased."):
		Help.flag("erased")


## A screen just opened: shut it if the story has not opened it yet, else explain it the first time.
func _on_view_shown(view: CanvasItem, screen: String) -> void:
	if not view.visible:
		return
	if not Help.is_open(screen):
		call_deferred("_refuse", view, screen)
		return
	var t := Help.for_screen(screen)
	if not t.is_empty() and Help.tips_on() and not Help.seen(t["id"]):
		call_deferred("_explain", t["id"], view)


func _refuse(view: CanvasItem, screen: String) -> void:
	if view.visible and view.has_method("close"):
		view.call("close")
	Help.play_locked(screen)


func _explain(id: String, view: CanvasItem) -> void:
	if view.visible and not Help.busy():
		Help.play(id, view)


func _on_card_closed() -> void:
	if host.has_method("_story_check"):
		host.call_deferred("_story_check")


func _process(delta: float) -> void:
	_t -= delta
	if _t > 0.0:
		return
	_t = CHECK_EVERY
	if Help.busy() or not host.is_inside_tree():
		return
	if host.has_method("alerts_blocked") and host.call("alerts_blocked"):
		return
	if on_command and Help.tips_on() and not Help.seen("command"):
		Help.play("command")
		return
	var t := Help.due()
	if not t.is_empty():
		Help.play(t["id"])
