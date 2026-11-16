extends StaticBody2D
## Scenery from the CC0 overworld sheet. Origin = the prop's footprint on the ground.

## kind -> [tile x, tile y, width, height (tiles), collision radius]
const KINDS := {
	"bush": [5, 16, 2, 2, 11.0],
	"shrub": [2, 14, 1, 1, 6.0],
	"rock_big": [4, 1, 2, 2, 11.0],
	"rock": [7, 5, 1, 1, 6.0],
	"stump": [31, 3, 2, 2, 11.0],
	"skull": [28, 2, 1, 1, 0.0],
	"bones": [29, 2, 1, 1, 0.0],
	"sign": [34, 2, 1, 1, 5.0],
}

var kind := "bush"
var text := ""
var seed_v := 0


func _ready() -> void:
	collision_layer = 1
	var k: Array = KINDS[kind]
	var spr := Sprite2D.new()
	spr.texture = Art.tile_region(k[0], k[1], k[2], k[3])
	spr.centered = true
	# Bottom of the sprite sits a few pixels below the origin, so Y-sorting feels right.
	spr.offset = Vector2(0, -k[3] * 8.0 + 3.0)
	spr.flip_h = seed_v % 2 == 1 and kind in ["bush", "shrub", "rock", "rock_big"]
	spr.material = Art.world_material()
	add_child(spr)
	if k[4] > 0.0:
		var shape := CircleShape2D.new()
		shape.radius = k[4]
		var col := CollisionShape2D.new()
		col.shape = shape
		col.position = Vector2(0, -2)
		add_child(col)
