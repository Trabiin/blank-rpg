class_name Territory
extends RefCounted
## The Inklands as provinces: data from data/provinces.json, plus the shape of each province.
##
## Shapes are a noisy Voronoi diagram of the province seed points, clipped to an island
## outline. The same function decides what is drawn and which provinces border each other,
## so adjacency (used by the Blank's spread and by roads) always matches the picture.

const DATA := "res://data/provinces.json"
const SEA := -1
const BLANK_EDGE := 0.94  # map x (0-1) where the Blank's wall begins

var provinces: Array = []  # Dictionaries from the JSON, plus "index" and "center"
var neighbors: Array = []  # neighbors[i] = Array of province indices bordering i
var grid := PackedInt32Array()  # province index per cell, SEA outside the island
var grid_size := Vector2i.ZERO

var _warp := FastNoiseLite.new()
var _coast := FastNoiseLite.new()


func _init() -> void:
	_warp.seed = 7
	_warp.frequency = 0.035
	_warp.fractal_octaves = 3
	_coast.seed = 19
	_coast.frequency = 0.02
	_coast.fractal_octaves = 3
	provinces = _read()
	for i in provinces.size():
		provinces[i]["index"] = i


func _read() -> Array:
	var f := FileAccess.open(DATA, FileAccess.READ)
	assert(f != null, "Missing " + DATA)
	return JSON.parse_string(f.get_as_text())["provinces"]


## Puts the changeable fields (owner, Fray) back to their starting values. Shapes stay.
func reload_data() -> void:
	var fresh := _read()
	for i in mini(fresh.size(), provinces.size()):
		for k in ["owner", "fray"]:
			provinces[i][k] = fresh[i][k]
		provinces[i]["scar"] = 0


func find(id: String) -> Dictionary:
	for p in provinces:
		if p["id"] == id:
			return p
	return {}


## Which province owns map point uv (0-1 on both axes), or SEA. `cell` scales the noise.
func region_at(uv: Vector2, cell := 1.0) -> int:
	# Island outline: a squashed blob with a ragged noisy coast.
	var d := ((uv - Vector2(0.5, 0.5)) * Vector2(2.1, 2.35)).length()
	if d + _coast.get_noise_2d(uv.x * 400.0, uv.y * 400.0) * 0.35 > 1.02:
		return SEA
	# Domain-warped nearest seed gives organic borders instead of straight Voronoi edges.
	var w := Vector2(_warp.get_noise_2d(uv.x * 300.0, uv.y * 300.0), _warp.get_noise_2d(uv.x * 300.0 + 99.0, uv.y * 300.0)) * 0.07
	var q := uv + w
	var best := SEA
	var best_d := 1e9
	for p in provinces:
		var s := Vector2(p["pos"][0], p["pos"][1])
		var dd := q.distance_to(s) / float(p.get("weight", 1.0))
		if dd < best_d:
			best_d = dd
			best = p["index"]
	return best


## Rasterises the map into `grid` at the given size and works out adjacency and centers.
func build_grid(size: Vector2i) -> void:
	grid_size = size
	grid.resize(size.x * size.y)
	var counts := []
	neighbors = []
	for i in provinces.size():
		provinces[i]["at_edge"] = false
		counts.append(0)
		neighbors.append([])
	for y in size.y:
		for x in size.x:
			var r := region_at(Vector2((x + 0.5) / size.x, (y + 0.5) / size.y))
			grid[y * size.x + x] = r
			if r != SEA:
				counts[r] += 1
				if float(x) / size.x > BLANK_EDGE - 0.03:
					provinces[r]["at_edge"] = true  # touches the wall of Blank down the east side
	for y in size.y:
		for x in size.x:
			var a := grid[y * size.x + x]
			if a == SEA:
				continue
			for o in [Vector2i(1, 0), Vector2i(0, 1)]:
				var nx: int = x + o.x
				var ny: int = y + o.y
				if nx >= size.x or ny >= size.y:
					continue
				var b := grid[ny * size.x + nx]
				if b != SEA and b != a and not neighbors[a].has(b):
					neighbors[a].append(b)
					neighbors[b].append(a)
	for i in provinces.size():
		# Label point: the seed, which always sits inside its own province.
		provinces[i]["center"] = Vector2(provinces[i]["pos"][0], provinces[i]["pos"][1])
		provinces[i]["cells"] = counts[i]


func cell(x: int, y: int) -> int:
	if x < 0 or y < 0 or x >= grid_size.x or y >= grid_size.y:
		return SEA
	return grid[y * grid_size.x + x]
