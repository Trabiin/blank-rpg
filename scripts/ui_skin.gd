class_name UiSkin
extends RefCounted
## The art pass UI look (docs/ART_STYLE.md "UI"): framed panels instead of plain rectangles, drawn as
## 9-slices from small palette-locked textures in assets/ui (PixelLab, picked in Phase 6), and the title
## font for headings. Body text uses the project font (Jersey 10, set as the theme's custom font).
##   ledger - dark ink-blue panel with a brass-cornered frame: HUD plates, menus, the dialogue box
##   paper  - torn parchment: signs, notes, tooltips
##   button - leather button with a brass rim: ability slots, choices

const TEX := {
	"ledger": preload("res://assets/ui/panel_ledger.png"),
	"paper": preload("res://assets/ui/panel_paper.png"),
	"button": preload("res://assets/ui/button.png"),
}
const MARGIN := {"ledger": 14, "paper": 9, "button": 6}
## Clean frames stretch; the torn paper edge repeats so it stays ragged.
const TILED := ["paper"]
const TITLE_FONT := preload("res://assets/fonts/Jacquard12-Regular.ttf")
const PAPER_INK := Color("2a2019")  # text colour on paper

static var _boxes := {}


static func box(kind: String) -> StyleBoxTexture:
	if not _boxes.has(kind):
		var sb := StyleBoxTexture.new()
		sb.texture = TEX[kind]
		var m: int = MARGIN[kind]
		sb.texture_margin_left = m
		sb.texture_margin_right = m
		sb.texture_margin_top = m
		sb.texture_margin_bottom = m
		if kind in TILED:
			sb.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT
			sb.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT
		_boxes[kind] = sb
	return _boxes[kind]


## Draws a framed panel. The frame needs a little room, so tiny rects grow to the frame's minimum.
static func panel(ci: CanvasItem, r: Rect2, kind := "ledger", tint := Color.WHITE) -> void:
	var m: float = MARGIN[kind] * 2.0
	r.size = Vector2(maxf(r.size.x, m), maxf(r.size.y, m))
	var sb := box(kind)
	sb.modulate_color = tint
	ci.draw_style_box(sb, r.grow(2.0))


## A gold highlight around a panel (the controlled hero, the chosen row).
static func highlight(ci: CanvasItem, r: Rect2, col := Color("e8c65a")) -> void:
	ci.draw_rect(r.grow(1.0), col, false, 1.0)


## Icons (assets/icons/<id>.png, 32px, picked in Phase 6). Ids follow the data: item, gear, ability, research,
## building and faction ids as they are; tech_<hero>, role_<role>, trait_<trait>, status_<kind>; gilt, supplies,
## ink, renown, insight. A missing icon is null, and callers just leave the space out.
static var _icons := {}


static func icon(id: String) -> Texture2D:
	if not _icons.has(id):
		var p := "res://assets/icons/%s.png" % id
		_icons[id] = load(p) if ResourceLoader.exists(p) else null
	return _icons[id]


## Draws the icon into r (square). Returns whether there was one, so text can make room only when needed.
static func draw_icon(ci: CanvasItem, id: String, r: Rect2, tint := Color.WHITE) -> bool:
	var t := icon(id)
	if t == null:
		return false
	ci.draw_texture_rect(t, r, false, tint)
	return true
