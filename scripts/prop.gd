extends StaticBody2D
## Scenery from the CC0 overworld sheet. Origin = the bottom-centre of the prop's footprint.
##
## Town buildings are placeholders until the PixelLab art pass (#3): each kind is one line
## here, so swapping a sprite never touches the maps or the code that places them.

## kind -> [tile x, tile y, width, height (tiles), collision radius, optional collision box,
## optional source rect in pixels (when the art is not on the 16px grid)]
const KINDS := {
	"bush": [5, 16, 2, 2, 11.0],
	"shrub": [2, 14, 1, 1, 6.0],
	"rock_big": [4, 1, 2, 2, 11.0],
	"rock": [7, 5, 1, 1, 6.0],
	"stump": [31, 3, 2, 2, 11.0],
	"skull": [28, 2, 1, 1, 0.0],
	"bones": [29, 2, 1, 1, 0.0],
	"sign": [34, 2, 1, 1, 5.0],
	"pond": [2, 9, 2, 2, 13.0],
	# Hollowmark
	"house": [6, 0, 5, 5, 0.0, Vector2(72, 40)],
	"barn": [11, 0, 5, 5, 0.0, Vector2(72, 40)],
	"stall": [18, 22, 4, 5, 0.0, Vector2(58, 14)],
	"fountain": [22, 9, 3, 3, 0.0, Vector2(42, 26)],
	"crates": [30, 0, 2, 2, 0.0, Vector2(28, 14)],
	"barrels": [33, 0, 2, 1, 0.0, Vector2(26, 8)],
	"produce": [24, 20, 5, 2, 0.0, Vector2(76, 10)],
	"bench": [28, 4, 3, 1, 0.0, Vector2(40, 6)],
	"banner": [5, 27, 1, 2, 3.0],
	"grave": [0, 0, 1, 2, 0.0, Vector2(16, 6), Rect2(566, 82, 22, 26)],
}
## Flat things lie on the ground: always drawn under characters.
const FLAT := ["pond", "bones", "skull"]

var kind := "bush"
var text := ""  # sign text, or a building's name plate
var seed_v := 0


static func footprint(k: String) -> Vector2i:
	return Vector2i(KINDS[k][2], KINDS[k][3])


func _ready() -> void:
	collision_layer = 1
	if kind in FLAT:
		z_index = -1
	var k: Array = KINDS[kind]
	var spr := Sprite2D.new()
	spr.texture = Art.region(k[6]) if k.size() > 6 else Art.tile_region(k[0], k[1], k[2], k[3])
	spr.centered = true
	# Bottom of the sprite sits a few pixels below the origin, so Y-sorting feels right.
	spr.offset = Vector2(0, -spr.texture.get_height() / 2.0 + 3.0)
	spr.flip_h = seed_v % 2 == 1 and kind in ["bush", "shrub", "rock", "rock_big", "grave"]
	spr.material = Art.world_material()
	add_child(spr)
	if k.size() > 5:
		var box: Vector2 = k[5]
		var rect := RectangleShape2D.new()
		rect.size = box
		var colb := CollisionShape2D.new()
		colb.shape = rect
		colb.position = Vector2(0, -box.y / 2.0)
		add_child(colb)
	elif k[4] > 0.0:
		var shape := CircleShape2D.new()
		shape.radius = k[4]
		var col := CollisionShape2D.new()
		col.shape = shape
		col.position = Vector2(0, -2)
		add_child(col)
	if text != "" and kind != "sign":
		var plate := Node2D.new()
		add_child(plate)
		plate.draw.connect(_draw_plate.bind(plate))


## A code-drawn name board over a building's door.
func _draw_plate(c: Node2D) -> void:
	var font := ThemeDB.fallback_font
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 6).x + 8.0
	var y := -float(KINDS[kind][3]) * 16.0 * 0.42
	var r := Rect2(-w / 2.0, y - 7.0, w, 9.0)
	c.draw_rect(r, Color("3a2a1c"))
	c.draw_rect(r, Color("c9a46a"), false, 1.0)
	c.draw_string(font, Vector2(r.position.x + 4.0, y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 6, Color("f3e3c3"))
