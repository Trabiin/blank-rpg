class_name SpriteSet
extends RefCounted
## Art pass sprites (docs/ART_ROADMAP.md section 4): one folder per character under
## res://assets/sprites/<id>/ holding horizontal strips named <anim>_<dir>.png, described in
## data/sprites.json (frame size, feet line, fps and which directions exist per animation).
##
## Directions follow Hero.dir_row(): 0 south, 1 south-east, 2 east, 3 north-east, 4 north,
## 5 north-west, 6 west, 7 south-west. Only the right-hand side is usually generated; the
## left-hand side is the mirror image (flip_h), as SNES games did.
##
## Anything without an entry falls back to the old paper doll, so art lands one character at a time.

const DATA_FILE := "res://data/sprites.json"
const DIRS := ["south", "south-east", "east", "north-east", "north", "north-west", "west", "south-west"]
## Which drawn direction stands in for a missing one, and whether it is mirrored.
const MIRROR := {"south-west": "south-east", "west": "east", "north-west": "north-east",
	"south-east": "south-west", "east": "west", "north-east": "north-west"}
## Fallback order when an animation has fewer directions (hurt has 3, KO has 1).
const NEAREST := {
	"south-east": ["south", "east"], "north-east": ["north", "east"], "east": ["south-east", "north-east", "south"],
	"north": ["north-east", "east", "south"], "south": ["south-east", "east"],
}

static var _data := {}
static var _cache := {}  # id -> SpriteSet (or null when there is no art)

var id := ""
var frame_size := Vector2i(32, 32)
var feet := Vector2(16, 28)  # pixel in the frame that stands on the node origin
var anims := {}  # name -> {fps, loop, frames, dirs: {dir: Texture2D}}
var face_rect := Rect2i()  # head window on the south rotation, for HUD and menu icons
var _face: AtlasTexture


static func _load_data() -> Dictionary:
	if _data.is_empty():
		var f := FileAccess.open(DATA_FILE, FileAccess.READ)
		if f:
			var d = JSON.parse_string(f.get_as_text())
			if d is Dictionary:
				_data = d.get("sprites", {})
	return _data


static func has_art(id: String) -> bool:
	return _load_data().has(id)


## The sprite set for a character id, or null if it has no art yet.
static func of(id: String) -> SpriteSet:
	if _cache.has(id):
		return _cache[id]
	var entry: Dictionary = _load_data().get(id, {})
	var s: SpriteSet = null
	if not entry.is_empty():
		s = SpriteSet.new()
		s._build(id, entry)
	_cache[id] = s
	return s


func _build(set_id: String, entry: Dictionary) -> void:
	id = set_id
	var folder: String = "res://assets/sprites/%s/" % entry.get("folder", set_id)
	var sz: Array = entry.get("size", [32, 32])
	frame_size = Vector2i(int(sz[0]), int(sz[1]))
	var ft: Array = entry.get("feet", [frame_size.x / 2, frame_size.y - 4])
	feet = Vector2(float(ft[0]), float(ft[1]))
	var fr: Array = entry.get("face", [])
	if fr.size() == 4:
		face_rect = Rect2i(int(fr[0]), int(fr[1]), int(fr[2]), int(fr[3]))
	for anim_name in entry.get("anims", {}):
		var a: Dictionary = entry["anims"][anim_name]
		var dirs := {}
		for d in a.get("dirs", []):
			var path: String = folder + "%s_%s.png" % [anim_name, d]
			if ResourceLoader.exists(path):
				dirs[d] = load(path)
		if dirs.is_empty():
			continue
		anims[anim_name] = {"fps": float(a.get("fps", 8)), "loop": bool(a.get("loop", true)),
			"frames": int(a.get("frames", 1)), "dirs": dirs}


## A small head icon cut from the south-facing rotation (HUD party plates, menus). Null if none.
func face() -> Texture2D:
	if _face == null and face_rect.size != Vector2i.ZERO and anims.has("rot"):
		var dirs: Dictionary = anims["rot"]["dirs"]
		if dirs.has("south"):
			_face = AtlasTexture.new()
			_face.atlas = dirs["south"]
			_face.region = Rect2(face_rect)
	return _face


func has(anim: String) -> bool:
	return anims.has(anim)


func frames_of(anim: String) -> int:
	return int(anims[anim]["frames"]) if anims.has(anim) else 0


func duration(anim: String) -> float:
	if not anims.has(anim):
		return 0.0
	return float(anims[anim]["frames"]) / maxf(float(anims[anim]["fps"]), 0.1)


## Resolves a direction index to [drawn direction, flip_h] for one animation.
func _dir_for(anim: String, row: int) -> Array:
	var dirs: Dictionary = anims[anim]["dirs"]
	var want: String = DIRS[posmod(row, 8)]
	if dirs.has(want):
		return [want, false]
	if MIRROR.has(want) and dirs.has(MIRROR[want]):
		return [MIRROR[want], true]
	# Fewer directions drawn (hurt, KO): take the nearest one, mirrored for the left side.
	var flip := want in ["south-west", "west", "north-west"]
	var right: String = MIRROR.get(want, want) if flip else want
	for d in NEAREST.get(right, []):
		if dirs.has(d):
			return [d, flip]
	return [dirs.keys()[0], false]


## Applies one frame to a Sprite2D: texture strip, frame index, mirroring and feet offset.
## `t` is seconds since the animation started; looping animations wrap, others hold the last frame.
func apply(sprite: Sprite2D, anim: String, row: int, t: float) -> void:
	if not anims.has(anim):
		anim = "idle" if anims.has("idle") else anims.keys()[0]
	var a: Dictionary = anims[anim]
	var df := _dir_for(anim, row)
	var n: int = a["frames"]
	var i := int(t * float(a["fps"]))
	i = posmod(i, n) if a["loop"] else mini(i, n - 1)
	apply_frame(sprite, anim, row, i, df)


## Same as apply() but with an explicit frame index (attacks follow the swing timer).
func apply_frame(sprite: Sprite2D, anim: String, row: int, i: int, df: Array = []) -> void:
	if not anims.has(anim):
		anim = "idle" if anims.has("idle") else anims.keys()[0]
	var a: Dictionary = anims[anim]
	if df.is_empty():
		df = _dir_for(anim, row)
	var tex: Texture2D = a["dirs"][df[0]]
	if sprite.texture != tex:
		sprite.texture = tex
		sprite.hframes = int(a["frames"])
		sprite.vframes = 1
	sprite.frame = clampi(i, 0, int(a["frames"]) - 1)
	sprite.flip_h = df[1]
	# Sprite2D is centred: shift so the feet pixel lands on the origin (mirrored feet flip too).
	var fx := feet.x if not df[1] else float(frame_size.x) - feet.x
	sprite.offset = Vector2(float(frame_size.x) / 2.0 - fx, float(frame_size.y) / 2.0 - feet.y)
