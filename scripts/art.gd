class_name Art
## Shared art helpers: CC0 sheet regions, materials, and paper-doll palettes.

const OVERWORLD := preload("res://assets/tiles/overworld.png")
const BODY := preload("res://assets/characters/body.png")
const SLIME := preload("res://assets/characters/slime.png")
const OUTFITS := {
	"archer": preload("res://assets/characters/outfit_archer.png"),
	"warrior": preload("res://assets/characters/outfit_warrior.png"),
	"soldier": preload("res://assets/characters/outfit_soldier.png"),
	"mage": preload("res://assets/characters/outfit_mage.png"),
}
const PALETTE_SWAP := preload("res://shaders/palette_swap.gdshader")
const WORLD_TINT := preload("res://shaders/world_tint.gdshader")

## Source color groups in each Puny Characters layer, light to dark.
## A hero picks one target color per group; the shading is carried over.
const GROUPS := {
	"body": {"skin": ["f7d099", "f6a954", "d97f40", "aa5a33", "84482a"]},
	"archer": {
		"cloth": ["8b9e0f", "627105", "455000", "303600"],
		"leather": ["866114", "433416"],
		"boots": ["5d4717", "3f3013"],
		"trim": ["d4cfc4", "c8c1b3", "bfb7a6", "a8a59d", "6e6c68", "686662"],
	},
	"warrior": {
		"metal": ["bebbb5", "a29e96", "7d7b76", "4d4c4b", "363636", "1e1e1e"],
		"accent": ["00b49d", "007966", "004b3f", "002e27"],
		"boots": ["5d4717", "3f3013"],
	},
	"soldier": {
		"metal": ["bebbb5", "a29e96", "7d7b76", "4d4c4b", "363636", "1e1e1e"],
		"cloth": ["007d89", "005355", "00332f"],
		"boots": ["5d4717", "3f3013"],
	},
	"mage": {
		"cloth": ["00b49d", "007966", "004f43", "002e27"],
		"leather": ["866114", "433416"],
		"boots": ["5d4717", "3f3013"],
		"trim": ["bfb7a6", "c8c1b3", "6e6c68"],
	},
	"slime": {
		"body": ["c0e869", "a9e74e", "6bd926", "40ad29", "087129", "005928"],
		"core": ["002f15"],
		"shine": ["e0e8b1", "ededed"],
	},
}

static var _world_material: ShaderMaterial


static func world_material() -> ShaderMaterial:
	if _world_material == null:
		_world_material = ShaderMaterial.new()
		_world_material.shader = WORLD_TINT
	return _world_material


static func tile_region(cx: int, cy: int, w := 1, h := 1) -> AtlasTexture:
	var t := AtlasTexture.new()
	t.atlas = OVERWORLD
	t.region = Rect2(cx * 16, cy * 16, w * 16, h * 16)
	return t


static func _lum(c: Color) -> float:
	return 0.299 * c.r + 0.587 * c.g + 0.114 * c.b


## Builds a palette-swap material for one layer. `targets` maps group -> Color.
## Each source shade keeps its brightness relative to the group's average shade.
static func recolor_material(layer: String, targets: Dictionary) -> ShaderMaterial:
	var src := PackedColorArray()
	var dst := PackedColorArray()
	var groups: Dictionary = GROUPS[layer]
	for g in groups:
		if not targets.has(g):
			continue
		var target: Color = targets[g]
		var shades: Array = groups[g]
		var ref := 0.0
		for hex in shades:
			ref += _lum(Color(hex))
		ref /= shades.size()
		for hex in shades:
			var s := Color(hex)
			# Keep each shade's brightness relative to the group average, slightly flattened
			# so light targets do not blow out to white.
			var k := 1.0 + (_lum(s) / maxf(ref, 0.01) - 1.0) * 0.8
			src.append(s)
			dst.append(Color(clampf(target.r * k, 0, 1), clampf(target.g * k, 0, 1), clampf(target.b * k, 0, 1)))
	while src.size() < 24:
		src.append(Color(0, 0, 0, 0))
		dst.append(Color(0, 0, 0, 0))
	var m := ShaderMaterial.new()
	m.shader = PALETTE_SWAP
	m.set_shader_parameter("count", _count(groups, targets))
	m.set_shader_parameter("src", src)
	m.set_shader_parameter("dst", dst)
	return m


static func _count(groups: Dictionary, targets: Dictionary) -> int:
	var n := 0
	for g in groups:
		if targets.has(g):
			n += (groups[g] as Array).size()
	return mini(n, 24)
