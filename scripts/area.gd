class_name Area
extends Node2D
## Loads a hand-written text map (maps/*.txt) into Godot TileMapLayers plus props.
##
## Layers, bottom to top: grass variants and flowers (TileMapLayers), then dirt paths drawn by
## the terrain_blend shader from a one-texel-per-tile mask, which gives smooth organic edges
## for any path shape without needing hand-made transition tiles.

const PropScript := preload("res://scripts/prop.gd")
const DIRT := preload("res://assets/tiles/dirt.png")
const TERRAIN_BLEND := preload("res://shaders/terrain_blend.gdshader")

const GRASS := [Vector2i(0, 0), Vector2i(0, 0), Vector2i(0, 0), Vector2i(0, 9), Vector2i(1, 9), Vector2i(0, 10), Vector2i(1, 10), Vector2i(5, 9)]
const FLOWERS := [Vector2i(0, 8), Vector2i(1, 8), Vector2i(3, 11), Vector2i(2, 12), Vector2i(3, 12)]
const PROP_CHARS := {"T": "bush", "t": "shrub", "r": "rock", "R": "rock_big", "S": "stump", "o": "pond", "b": "bones", "k": "skull"}
const WORDS := ["and then", "was", "the", "almost", "she said", "once", "here lived", "...", "until", "nobody"]

var area_name := ""
var size_tiles := Vector2i.ZERO
var blank_x := 1e9
var party_start := Vector2.ZERO
var spawns: Array[Vector2] = []
var props: Array = []
var markers := {}  # id -> Array of tile-centre positions (@mark lines: posts, the Command Table)
var _rows: PackedStringArray = []
var _signs := {}
var _custom := {}  # char -> [kind, plate text] from @prop lines
var _marks := {}  # char -> marker id
var _dirt_chars := ":@"


func world_size() -> Vector2:
	return Vector2(size_tiles * 16)


## Reads the map file and builds everything. Props are added to `entities` (the Y-sorted layer).
func build(path: String, entities: Node2D) -> void:
	_parse(path)
	_build_tiles()
	_build_objects(entities)
	var words := Node2D.new()
	add_child(words)
	if blank_x < 1e8:
		words.draw.connect(_draw_words.bind(words))


func _parse(path: String) -> void:
	var f := FileAccess.open(path, FileAccess.READ)
	assert(f != null, "Missing map " + path)
	var in_rows := false
	while not f.eof_reached():
		var line := f.get_line()
		if in_rows:
			if line.strip_edges() != "":
				_rows.append(line)
		elif line == "---":
			in_rows = true
		elif line.begins_with("@"):
			var sp := line.find(" ")
			var key := line.substr(1, sp - 1)
			var val := line.substr(sp + 1)
			if key == "name":
				area_name = val
			elif key == "blank":
				blank_x = float(val) * 16.0
			elif key.begins_with("sign"):
				_signs[key.substr(4)] = val.replace("|", "\n")
			elif key.begins_with("prop"):
				# @propH house|TOWN HALL  ->  H places a house with that name board
				_custom[key.substr(4)] = [val.get_slice("|", 0), val.get_slice("|", 1) if val.contains("|") else ""]
			elif key.begins_with("mark"):
				_marks[key.substr(4)] = val
			elif key == "dirt":
				_dirt_chars += val  # these characters sit on the dirt layer too
	size_tiles = Vector2i(_rows[0].length(), _rows.size())


func _cell(x: int, y: int) -> String:
	if y < 0 or y >= _rows.size() or x < 0 or x >= _rows[y].length():
		return "."
	return _rows[y][x]


func _is_dirt(x: int, y: int) -> int:
	var ch := _cell(x, y)
	return 1 if _dirt_chars.contains(ch) else 0


func _layer(tex: Texture2D, coords: Array) -> TileMapLayer:
	var ts := TileSet.new()
	ts.tile_size = Vector2i(16, 16)
	var src := TileSetAtlasSource.new()
	src.texture = tex
	src.texture_region_size = Vector2i(16, 16)
	for c in coords:
		if not src.has_tile(c):
			src.create_tile(c)
	ts.add_source(src, 0)
	var layer := TileMapLayer.new()
	layer.tile_set = ts
	layer.material = Art.world_material()
	add_child(layer)
	return layer


func _build_tiles() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(area_name)
	var grass := _layer(Art.OVERWORLD, GRASS)
	var flowers := _layer(Art.OVERWORLD, FLOWERS)
	for y in size_tiles.y:
		for x in size_tiles.x:
			grass.set_cell(Vector2i(x, y), 0, GRASS[rng.randi() % GRASS.size()])
			if _cell(x, y) == "f":
				flowers.set_cell(Vector2i(x, y), 0, FLOWERS[rng.randi() % FLOWERS.size()])
	# Dirt paths: mask texture (white = path) blown up to map size, shaded into dirt.
	var mask := Image.create(size_tiles.x, size_tiles.y, false, Image.FORMAT_L8)
	for y in size_tiles.y:
		for x in size_tiles.x:
			mask.set_pixel(x, y, Color.WHITE if _is_dirt(x, y) else Color.BLACK)
	var dirt := Sprite2D.new()
	dirt.texture = ImageTexture.create_from_image(mask)
	dirt.centered = false
	dirt.scale = Vector2(16, 16)
	dirt.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	var mat := ShaderMaterial.new()
	mat.shader = TERRAIN_BLEND
	mat.set_shader_parameter("dirt_tex", DIRT)
	mat.set_shader_parameter("tiles", Vector2(size_tiles))
	mat.set_shader_parameter("blank_x", blank_x)
	dirt.material = mat
	add_child(dirt)


func _build_objects(entities: Node2D) -> void:
	for y in size_tiles.y:
		for x in size_tiles.x:
			var ch := _cell(x, y)
			var center := Vector2(x * 16 + 8, y * 16 + 8)
			if ch == "@":
				party_start = center
			elif ch == "e":
				spawns.append(center)
			elif _marks.has(ch):
				if not markers.has(_marks[ch]):
					markers[_marks[ch]] = []
				markers[_marks[ch]].append(center)
			elif PROP_CHARS.has(ch) or _signs.has(ch) or _custom.has(ch):
				var kind: String = PROP_CHARS.get(ch, "sign")
				var prop = PropScript.new()
				if _custom.has(ch):
					kind = _custom[ch][0]
					prop.text = _custom[ch][1]
				elif kind == "sign":
					prop.text = _signs[ch]
				prop.kind = kind
				prop.seed_v = x * 31 + y
				# Origin = bottom-centre of the footprint. Big props anchor at their top-left tile.
				var fp: Vector2i = PropScript.footprint(kind)
				prop.position = Vector2(x * 16 + fp.x * 8, y * 16 + fp.y * 16 - 3)
				entities.add_child(prop)
				props.append(prop)


func _draw_words(canvas: Node2D) -> void:
	# Near the Blank the grass grows in half-sentences.
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var font := ThemeDB.fallback_font
	var h := world_size().y
	for i in 40:
		var p := Vector2(rng.randf_range(blank_x - 300.0, blank_x + 20.0), rng.randf_range(20, h - 20))
		var fade := clampf((p.x - (blank_x - 300.0)) / 300.0, 0.0, 1.0)
		canvas.draw_string(font, p, WORDS[rng.randi() % WORDS.size()], HORIZONTAL_ALIGNMENT_LEFT, -1, 6, Color(0.2, 0.2, 0.22, 0.12 + 0.4 * fade))
