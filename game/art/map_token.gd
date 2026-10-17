class_name MapToken
extends Node2D
## One campaign-map token (docs/specs/map-tokens.md): draws a cached MapTokens texture with the box point
## (32,55) on the node's position. The node's scale is world units per box unit (MapTokens.box_unit(zoom)).
## Static: no _process; redraws only when the cached texture or headcount badge changes.
##   var t := MapToken.new(); t.set_texture(MapTokens.key(...), MapTokens.texture(...))
##   t.refresh(game, warband)   # recompute type / faction / pips / stance from the warband

var key := ""
var tex: Texture2D
var seen := 0        # MapTokens.sync frame stamp
var count := 0       # headcount behind the current texture
var badge_text := ""
var badge_color := Color.WHITE

const _BADGE := Rect2(-23, -8, 46, 16)

const _RECT := Rect2(-MapTokens.PAD - MapTokens.ANCHOR.x, -MapTokens.PAD - MapTokens.ANCHOR.y,
	MapTokens.BOX + 2.0 * MapTokens.PAD, MapTokens.BOX + 2.0 * MapTokens.PAD)

func _init() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS

func set_texture(k: String, t: Texture2D) -> void:
	if k == key:
		return
	key = k
	tex = t
	queue_redraw()

func set_badge(n: int, color: Color) -> void:
	count = n
	var label := MapTokens.count_text(n)
	if label == badge_text and color == badge_color:
		return
	badge_text = label
	badge_color = color
	queue_redraw()

func refresh(game, wb: Dictionary) -> void:
	var tk := MapTokens.token_key_for(game, wb)
	set_badge(int(tk[4]), MapTokens.fcol(String(wb["faction"])))
	visible = count > 0 or wb.get("kind", "") != "militia"   # a wiped-out militia leaves no token
	var k := MapTokens.key(tk[0], tk[1], tk[2], tk[3])
	if k != key:
		set_texture(k, MapTokens.texture(tk[0], tk[1], tk[2], tk[3]))

func _draw() -> void:
	if tex != null:
		draw_texture_rect(tex, _RECT, false)
	if badge_text != "":
		draw_rect(_BADGE, badge_color)
		draw_rect(_BADGE, MapTokens.INK, false, 1.5)
		var font := ThemeDB.fallback_font
		var width := font.get_string_size(badge_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
		var at := Vector2(-width * 0.5, 4)
		draw_string_outline(font, at, badge_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, 3, MapTokens.INK)
		draw_string(font, at, badge_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, MapTokens.BONE)
