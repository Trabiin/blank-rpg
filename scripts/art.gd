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
static var _art_world_material: ShaderMaterial


static func world_material() -> ShaderMaterial:
	if _world_material == null:
		_world_material = ShaderMaterial.new()
		_world_material.shader = WORLD_TINT
	return _world_material


## The same Blank fade for art pass tiles and props, with no mood grade: they are locked to the style palette
## (docs/ART_STYLE.md), so their colours are shown as drawn and only the day/night light changes them.
static func art_world_material() -> ShaderMaterial:
	if _art_world_material == null:
		_art_world_material = ShaderMaterial.new()
		_art_world_material.shader = WORLD_TINT
		_art_world_material.set_shader_parameter("desat", 0.0)
		_art_world_material.set_shader_parameter("tint", Vector3(1.0, 1.0, 1.0))
		_art_world_material.set_shader_parameter("gain", 1.0)
		_art_world_material.set_shader_parameter("blank_x", world_material().get_shader_parameter("blank_x"))
	return _art_world_material


## Where the Blank starts eating colour, for both world materials.
static func set_blank_x(x: float) -> void:
	world_material().set_shader_parameter("blank_x", x)
	art_world_material().set_shader_parameter("blank_x", x)


static func tile_region(cx: int, cy: int, w := 1, h := 1) -> AtlasTexture:
	var t := AtlasTexture.new()
	t.atlas = OVERWORLD
	t.region = Rect2(cx * 16, cy * 16, w * 16, h * 16)
	return t


## Any pixel rect of the overworld sheet, for art that is not on the 16px grid.
static func region(r: Rect2) -> AtlasTexture:
	var t := AtlasTexture.new()
	t.atlas = OVERWORLD
	t.region = r
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


## A small heart drawn in code (bonds). s = half its width in pixels.
static func draw_heart(ci: CanvasItem, c: Vector2, s: float, col: Color) -> void:
	var r := s * 0.52
	ci.draw_circle(c + Vector2(-s * 0.48, -s * 0.35), r, col)
	ci.draw_circle(c + Vector2(s * 0.48, -s * 0.35), r, col)
	ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-s * 0.98, -s * 0.18), c + Vector2(s * 0.98, -s * 0.18),
		c + Vector2(0, s * 0.95)]), col)


## Cast shadow under an art pass building or prop (docs/ART_STYLE.md: light from the top left), drawn on `c`
## with the object's bottom-centre at `base`: a soft contact ellipse, and for tall things a band thrown to the
## bottom right.
static func draw_cast_shadow(c: CanvasItem, base: Vector2, w: float, tall: float) -> void:
	var col := Color(0.03, 0.04, 0.09, 0.32)
	c.draw_set_transform(base + Vector2(w * 0.06, 0.5), 0.0, Vector2(1.0, 0.3))
	c.draw_circle(Vector2.ZERO, w * 0.52, col)
	c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if tall > 28.0:
		var d := minf(tall * 0.18, 12.0)
		var pts := PackedVector2Array([base + Vector2(-w * 0.42, -1), base + Vector2(w * 0.5, -1),
				base + Vector2(w * 0.5 + d, d * 0.55), base + Vector2(-w * 0.42 + d, d * 0.55)])
		c.draw_colored_polygon(pts, Color(col.r, col.g, col.b, 0.22))

