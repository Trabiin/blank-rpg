class_name Territory
extends RefCounted
## The Inklands as regions and provinces: data from data/provinces.json, plus the shape of each
## province (issue #53: about 24 provinces in five regions, opened in story order).
##
## Shapes are a noisy Voronoi diagram of the province seed points, clipped to the coast of the
## Inklands. The same function decides what is drawn and which provinces border each other, so
## adjacency (used by the Blank's spread, claims and roads) always matches the picture.
##
## Which regions are open is campaign state and lives in Empire (Empire.region_open()).

const DATA := "res://data/provinces.json"
## Land and sea, traced from the painted map (assets/ui/map_painted.jpg, tools/trace_land.py):
## white = land (lakes count as land, so the provinces round them can hold them), black = open sea.
const LAND_MASK := "res://assets/map/land_mask.png"
const SEA := -1
const BLANK_EDGE := 0.93  # map x (0-1) where the Blank's wall begins (it wobbles round this, see wall_x)
const EDGE_REACH := 3  # provinces with land this many cells from the wall "touch the Blank's edge"

var provinces: Array = []  # Dictionaries from the JSON, plus "index", "center", "cells"
var regions: Array = []  # Dictionaries from the JSON, plus "index", "provinces" (indices), "bounds" and "frame" (cells)
var biomes := {}  # id -> {"name", "maps"}
var neighbors: Array = []  # neighbors[i] = Array of province indices bordering i
var grid := PackedInt32Array()  # province index per cell, SEA outside the coast
var grid_size := Vector2i.ZERO

var _warp := FastNoiseLite.new()
var _coast := FastNoiseLite.new()
var _seeds := PackedVector2Array()
var _weights := PackedFloat32Array()
var _mask: Image


func _init() -> void:
	_warp.seed = 7
	_warp.frequency = 0.035
	_warp.fractal_octaves = 3
	_coast.seed = 19
	_coast.frequency = 0.02
	_coast.fractal_octaves = 4
	var tex = load(LAND_MASK) if ResourceLoader.exists(LAND_MASK) else null
	if tex is Texture2D:
		_mask = (tex as Texture2D).get_image()
		if _mask.is_compressed():
			_mask.decompress()
	var d := _read()
	provinces = d.get("provinces", [])
	regions = d.get("regions", [])
	biomes = d.get("biomes", {})
	for i in regions.size():
		regions[i]["index"] = i
		regions[i]["provinces"] = []
	for i in provinces.size():
		var p: Dictionary = provinces[i]
		p["index"] = i
		var r := region(p.get("region", ""))
		if r.is_empty() and not regions.is_empty():
			r = regions[0]  # a province without a known region belongs to the first one
			p["region"] = r["id"]
		if not r.is_empty():
			r["provinces"].append(i)
			p["_region_i"] = r["index"]
		_seeds.append(Vector2(p["pos"][0], p["pos"][1]))
		_weights.append(float(p.get("weight", 1.0)))


func _read() -> Dictionary:
	var f := FileAccess.open(DATA, FileAccess.READ)
	assert(f != null, "Missing " + DATA)
	return JSON.parse_string(f.get_as_text())


## Puts the changeable fields (owner, Fray) back to their starting values. Shapes stay.
func reload_data() -> void:
	var fresh: Array = _read()["provinces"]
	for i in mini(fresh.size(), provinces.size()):
		for k in ["owner", "fray"]:
			provinces[i][k] = fresh[i][k]
		provinces[i]["scar"] = 0


func find(id: String) -> Dictionary:
	for p in provinces:
		if p["id"] == id:
			return p
	return {}


func region(id: String) -> Dictionary:
	for r in regions:
		if r["id"] == id:
			return r
	return {}


func region_of(p: Dictionary) -> Dictionary:
	return region(p.get("region", ""))


## The mission maps a province can use (res:// paths): its biome's pool, best first.
func map_pool(pid: String) -> Array:
	var p := find(pid)
	var out := []
	for m in biomes.get(p.get("biome", ""), {}).get("maps", []):
		out.append("res://maps/%s.txt" % m)
	return out


## Is map point uv (0-1 on both axes) land? The traced mask when there is one; otherwise a wide continent with a ragged, noisy coast, cut by
## three long bays that set the regions apart: the Candle Sound in the north (between the capital and
## the Abbey), the Gulf of Quills in the west (between the capital and the Causeway) and the Saltgrave
## Reach in the south (between the Causeway and the Unfinished Coast).
const BAYS := [
	[Vector2(0.47, -0.02), Vector2(0.475, 0.16), 0.055],
	[Vector2(-0.02, 0.47), Vector2(0.23, 0.49), 0.06],
	[Vector2(0.51, 1.02), Vector2(0.495, 0.85), 0.05],
]


func is_land(uv: Vector2) -> bool:
	if _mask != null:
		var px := Vector2i((uv * Vector2(_mask.get_size())).floor()).clamp(Vector2i.ZERO, _mask.get_size() - Vector2i.ONE)
		return _mask.get_pixelv(px).r > 0.5
	var n := _coast.get_noise_2d(uv.x * 520.0, uv.y * 520.0)
	var d := ((uv - Vector2(0.5, 0.5)) * Vector2(2.08, 2.16)).length()
	# Squarer than a circle: the land fills the corners of the map more than a blob would.
	var q := (uv - Vector2(0.5, 0.5)).abs() * 2.0
	d = lerpf(d, maxf(q.x * 1.03, q.y * 1.07), 0.3) + n * 0.3
	if d >= 0.97:
		return false
	for b in BAYS:
		var a: Vector2 = b[0]
		var e: Vector2 = b[1]
		var k := clampf((uv - a).dot(e - a) / (e - a).length_squared(), 0.0, 1.0)
		var w: float = b[2] * (1.0 - 0.55 * k) + n * 0.02  # narrows towards its head
		if uv.distance_to(a.lerp(e, k)) < w:
			return false
	return true


## Which province owns map point uv (0-1 on both axes), or SEA.
func region_at(uv: Vector2) -> int:
	if not is_land(uv):
		return SEA
	# Domain-warped nearest seed gives organic borders instead of straight Voronoi edges.
	var w := Vector2(_warp.get_noise_2d(uv.x * 420.0, uv.y * 420.0), _warp.get_noise_2d(uv.x * 420.0 + 99.0, uv.y * 420.0)) * 0.045
	var q := uv + w
	var best := SEA
	var best_d := 1e9
	for i in _seeds.size():
		var dd := q.distance_to(_seeds[i]) / _weights[i]
		if dd < best_d:
			best_d = dd
			best = i
	return best


## Rasterises the map into `grid` at the given size and works out adjacency, centres and
## each region's bounding box.
func build_grid(size: Vector2i) -> void:
	grid_size = size
	grid.resize(size.x * size.y)
	var counts := []
	neighbors = []
	for i in provinces.size():
		provinces[i]["at_edge"] = false
		counts.append(0)
		neighbors.append([])
	var edge_x := PackedInt32Array()  # per row: the first column the Blank's wall reaches (see wall_x)
	for y in size.y:
		edge_x.append(int(wall_x(y, size.y) * size.x) - EDGE_REACH)
	for y in size.y:
		for x in size.x:
			var r := region_at(Vector2((x + 0.5) / size.x, (y + 0.5) / size.y))
			grid[y * size.x + x] = r
	_tidy(size)
	for i in provinces.size():
		counts[i] = 0
	for r in regions:
		r["bounds"] = Rect2()
	for y in size.y:
		for x in size.x:
			var r := grid[y * size.x + x]
			if r != SEA:
				counts[r] += 1
				var rg: Dictionary = regions[provinces[r]["_region_i"]] if provinces[r].has("_region_i") else {}
				if not rg.is_empty():
					rg["bounds"] = Rect2(x, y, 1, 1) if rg["bounds"].size == Vector2.ZERO else (rg["bounds"] as Rect2).merge(Rect2(x, y, 1, 1))
				if x >= edge_x[y]:
					provinces[r]["at_edge"] = true  # its land runs up to the Blank's wall
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
		provinces[i]["center"] = _seeds[i]
		provinces[i]["cells"] = counts[i]
	for r in regions:
		# "bounds": every cell of the region; "frame": what the camera fits when it shows the region
		# (its province centres with a margin, so the names fit without empty coast round them).
		var box := Rect2()
		for i in r["provinces"]:
			var c: Vector2 = _seeds[i] * Vector2(size)
			box = Rect2(c, Vector2.ZERO) if box.size == Vector2.ZERO and box.position == Vector2.ZERO else box.expand(c)
		r["frame"] = box.grow(24.0)


## Every province is one connected piece: stray pockets that the noisy borders cut off are given
## to the province round them (each province keeps its biggest piece), and specks of land cut off
## by the sea sink.
func _tidy(size: Vector2i) -> void:
	var seen := PackedByteArray()
	seen.resize(size.x * size.y)
	var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	var pieces := []  # [province, cells, {neighbour province: shared edges}]
	var biggest := {}  # province -> index into pieces
	for start in grid.size():
		var r := grid[start]
		if r == SEA or seen[start] == 1:
			continue
		var piece := [start]
		seen[start] = 1
		var around := {}
		var head := 0
		while head < piece.size():
			var c: int = piece[head]
			head += 1
			var cx := c % size.x
			var cy := c / size.x
			for o in dirs:
				var nx: int = cx + o.x
				var ny: int = cy + o.y
				if nx < 0 or ny < 0 or nx >= size.x or ny >= size.y:
					continue
				var ni := ny * size.x + nx
				var nr := grid[ni]
				if nr == r:
					if seen[ni] == 0:
						seen[ni] = 1
						piece.append(ni)
				elif nr != SEA:
					around[nr] = int(around.get(nr, 0)) + 1
		pieces.append([r, piece, around])
		if not biggest.has(r) or piece.size() > (pieces[biggest[r]][1] as Array).size():
			biggest[r] = pieces.size() - 1
	for i in pieces.size():
		var pc: Array = pieces[i]
		if biggest[pc[0]] == i:
			continue
		var to := SEA
		var most := 0
		for k in pc[2]:
			if int(pc[2][k]) > most:
				most = int(pc[2][k])
				to = k
		for c in pc[1]:
			grid[c] = to


## Where the Blank's wall starts on row y of h (0-1 across the map). The Command Table draws the
## wall from this, so "touches the Blank's edge" always matches the picture.
static func wall_x(y: int, h: int) -> float:
	var k := float(y) * 300.0 / h  # the wobble is tuned for a 300-row map
	return BLANK_EDGE + sin(k * 0.05) * 0.006 + sin(k * 0.015 + 1.0) * 0.01


func cell(x: int, y: int) -> int:
	if x < 0 or y < 0 or x >= grid_size.x or y >= grid_size.y:
		return SEA
	return grid[y * grid_size.x + x]
