extends Node2D
## TEMPORARY art test: press V in Hollowmark to swap Ash between the current paper doll
## and the PixelLab test sprite (full size, then half size, then back).
##
## Self-contained so it is easy to remove: delete this file, assets/pixellab/, and the
## one line in hub.gd that adds it. Nothing else depends on it.
##
## PixelLab export: 8 static rotations (48x48) and a walk cycle facing south only (64x64,
## same character centred in a bigger canvas). Directions without a walk show the rotation.

const DIR := "res://assets/pixellab/ash/"
## Same order as Hero.dir_row(): clockwise starting from facing down.
const DIRS := ["south", "south-east", "east", "north-east", "north", "north-west", "west", "south-west"]
const WALK_FRAMES := 6
const WALK_FPS := 10.0
## The feet sit 2px above the bottom of the 48px frame (and of the 48px area inside the 64px walk frames).
const FEET_OFFSET := Vector2(0, -22)
const MODE_NAMES := ["Paper doll Ash (current CC0 art)", "PixelLab Ash, full size (48px)", "PixelLab Ash, half size"]

static var mode := 0  # 0 paper doll, 1 PixelLab full size, 2 PixelLab half size; kept between hub visits

var hero: Hero
var hud  # hub_hud.gd, for the little toast when switching
var sprite: Sprite2D
var rotations: Array[Texture2D] = []
var walk: Array[Texture2D] = []


func _ready() -> void:
	for d in DIRS:
		rotations.append(load(DIR + d + ".png"))
	for i in WALK_FRAMES:
		walk.append(load(DIR + "walk_south_%d.png" % i))
	sprite = Sprite2D.new()
	sprite.offset = FEET_OFFSET
	hero.add_child(sprite)  # added last, so it also covers the leader arrow (which would sit on Ash's chest)
	_apply()


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key and key.pressed and not key.echo and key.physical_keycode == KEY_V:
		mode = (mode + 1) % 3
		_apply()
		if hud:
			hud.say(MODE_NAMES[mode] + "   (V to switch)", 2.0)
		get_viewport().set_input_as_handled()


func _apply() -> void:
	var on := mode != 0
	sprite.visible = on
	sprite.scale = Vector2.ONE * (0.5 if mode == 2 else 1.0)
	hero.body_sprite.visible = not on
	hero.outfit_sprite.visible = not on


func _process(_delta: float) -> void:
	if mode == 0:
		return
	var row := Hero.dir_row(hero.facing)
	if hero.moving and DIRS[row] == "south":
		sprite.texture = walk[int(hero.anim_t * WALK_FPS) % WALK_FRAMES]
	else:
		sprite.texture = rotations[row]
