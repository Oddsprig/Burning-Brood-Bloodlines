extends Node2D
## Draws the battle ground from sim.tile_at(cell) ("open" | "rough" | "blocked"): terrain-coloured tiles with
## per-tile variation and small decorations, rough ground as darker scrub/stones, blocked tiles as trees, rocks
## or water depending on terrain, plus a darker margin beyond the map edge. Purely visual.

const PALETTES := {
	"plains": {"base": Color("#5f7d38"), "alt": Color("#6b7f3c"), "deco": Color("#3f5a26"), "stone": Color("#8f8a7a"), "edge": Color("#2f4220"), "block": "rock"},
	"forest": {"base": Color("#4f8f35"), "alt": Color("#47832f"), "deco": Color("#2f6a24"), "stone": Color("#7d7a6c"), "edge": Color("#24401a"), "block": "tree"},
	"silverwood": {"base": Color("#5f9c6a"), "alt": Color("#56915f"), "deco": Color("#3d7a52"), "stone": Color("#a8b4b0"), "edge": Color("#2c4a38"), "block": "silvertree"},
	"hills": {"base": Color("#8aa84a"), "alt": Color("#7f9c43"), "deco": Color("#647f32"), "stone": Color("#9d958a"), "edge": Color("#4f5e2c"), "block": "rock"},
	"mountains": {"base": Color("#9a9a84"), "alt": Color("#8f8f7a"), "deco": Color("#707060"), "stone": Color("#b0aca2"), "edge": Color("#55554a"), "block": "rock"},
	"badlands": {"base": Color("#c79a5e"), "alt": Color("#bd9055"), "deco": Color("#9a7040"), "stone": Color("#a07a58"), "edge": Color("#6e4e2c"), "block": "rock"},
	"snow": {"base": Color("#e6eef4"), "alt": Color("#d9e4ec"), "deco": Color("#b9c8d4"), "stone": Color("#8a96a0"), "edge": Color("#7f93a3"), "block": "rock"},
	"marsh": {"base": Color("#5d7f4a"), "alt": Color("#557444"), "deco": Color("#3f5e4a"), "stone": Color("#6d6f5c"), "edge": Color("#2e3f2a"), "block": "water"},
	"road": {"base": Color("#66803c"), "alt": Color("#72823f"), "deco": Color("#4a6229"), "stone": Color("#a08f70"), "edge": Color("#34471f"), "block": "rock"},
}
const ALIASES := {"grassland": "plains", "mud": "marsh", "swamp": "marsh", "desert": "badlands"}

var sim
var grid_w := 32
var grid_h := 18
var tile := 40.0
var terrain := "plains"
var seed_value := 1
var margin := 120.0
var settlement := ""   # "siege": town walls beyond the defenders' edge; "raid": houses and fields

func configure(battle_sim, tile_px: float, terrain_id: String, s: int) -> void:
	sim = battle_sim
	grid_w = sim.grid_w; grid_h = sim.grid_h; tile = tile_px
	terrain = ALIASES.get(terrain_id, terrain_id)
	seed_value = s
	_bake_ground()

func _tile(x: int, y: int) -> String:
	return sim.tile_at(Vector2i(x, y)) if sim != null else "open"

## The ground is painted ONCE into a texture (SubViewport, UPDATE_ONCE) and drawn as a single quad: a large
## battlefield is thousands of shapes, which otherwise cost thousands of canvas commands every frame.
const BAKE_SCALE := 0.75
var _bake: SubViewport
var _painter: Node2D

class Painter:
	extends Node2D
	var host
	func _draw() -> void:
		host._paint(self)

func _bake_ground() -> void:
	var size := Vector2(grid_w * tile, grid_h * tile) + Vector2(margin, margin) * 2.0
	if _bake == null:
		_bake = SubViewport.new()
		_bake.transparent_bg = false
		_bake.disable_3d = true
		_bake.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_LINEAR
		add_child(_bake)
		_painter = Painter.new()
		_painter.host = self
		_bake.add_child(_painter)
	_bake.size = Vector2i(ceili(size.x * BAKE_SCALE), ceili(size.y * BAKE_SCALE))
	_painter.position = Vector2(margin, margin) * BAKE_SCALE
	_painter.scale = Vector2.ONE * BAKE_SCALE
	_painter.queue_redraw()
	_bake.render_target_update_mode = SubViewport.UPDATE_ONCE
	queue_redraw()

func _draw() -> void:
	if _bake == null: return
	var size := Vector2(grid_w * tile, grid_h * tile)
	draw_texture_rect(_bake.get_texture(), Rect2(-Vector2(margin, margin), size + Vector2(margin, margin) * 2.0), false)
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.35), false, 3.0)

func _paint(ci: CanvasItem) -> void:
	var pal: Dictionary = PALETTES.get(terrain, PALETTES["plains"])
	var size := Vector2(grid_w * tile, grid_h * tile)
	ci.draw_rect(Rect2(-Vector2(margin, margin), size + Vector2(margin, margin) * 2.0), pal["edge"])
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var blocked := []
	for y in grid_h:
		for x in grid_w:
			var c: Color = (pal["base"] as Color).lerp(pal["alt"], 0.5 + 0.5 * sin(x * 0.37 + y * 0.21) * cos(y * 0.29 - x * 0.13))
			c = c.lightened(rng.randf_range(-0.025, 0.03))
			var kind := _tile(x, y)
			var r := Rect2(x * tile, y * tile, tile, tile)
			if kind == "rough":
				c = c.darkened(0.16).lerp(pal["stone"], 0.12)
			ci.draw_rect(r, c)
			if kind == "rough":
				for i in 4:
					var p := r.position + Vector2(rng.randf_range(5, tile - 5), rng.randf_range(8, tile - 3))
					if rng.randf() < 0.5:
						ci.draw_circle(p, rng.randf_range(2.0, 3.5), pal["stone"].darkened(0.1))
					else:
						for j in 3:
							ci.draw_line(p + Vector2((j - 1) * 3.0, 0), p + Vector2((j - 1) * 4.5, -6 - rng.randf() * 3), pal["deco"].darkened(0.15), 1.5)
			elif kind == "blocked":
				blocked.append(Vector2i(x, y))
	# soft light/dark patches break up the tile pattern (baked once, so they cost nothing per frame)
	for i in grid_w * grid_h / 6:
		var pc := Vector2(rng.randf() * size.x, rng.randf() * size.y)
		var tone: Color = (pal["deco"] as Color) if rng.randf() < 0.55 else (pal["base"] as Color).lightened(0.12)
		tone.a = 0.055
		ci.draw_circle(pc, tile * rng.randf_range(0.8, 2.4), tone)
	var gl: Color = pal["deco"]; gl.a = 0.07
	for x in grid_w + 1:
		ci.draw_line(Vector2(x * tile, 0), Vector2(x * tile, size.y), gl, 1.0)
	for y in grid_h + 1:
		ci.draw_line(Vector2(0, y * tile), Vector2(size.x, y * tile), gl, 1.0)
	var n := grid_w * grid_h / 3
	for i in n:
		var p := Vector2(rng.randf() * size.x, rng.randf() * size.y)
		var k := rng.randf()
		var cell := Vector2i(int(p.x / tile), int(p.y / tile))
		if _tile(cell.x, cell.y) != "open":
			continue
		if k < 0.6:
			for j in 3:
				var dx := (j - 1) * 3.0
				ci.draw_line(p + Vector2(dx, 0), p + Vector2(dx * 1.6, -5 - rng.randf() * 3), pal["deco"], 1.5)
		elif k < 0.85:
			ci.draw_circle(p, 2.0 + rng.randf() * 2.5, pal["stone"])
		else:
			ci.draw_circle(p, 2.0, Color("#f3e36b") if rng.randf() < 0.5 else Color("#f08ab0"))
	if settlement != "": _paint_settlement(ci, size, rng)
	# blocked tiles last so tree crowns overlap the row above
	for b in blocked:
		_draw_blocked(ci, Rect2(b.x * tile, b.y * tile, tile, tile), pal, rng)

func _draw_blocked(ci: CanvasItem, r: Rect2, pal: Dictionary, rng: RandomNumberGenerator) -> void:
	var ctr := r.get_center()
	match str(pal["block"]):
		"tree", "silvertree":
			var crown: Color = Color("#2e6b2a") if pal["block"] == "tree" else Color("#9fd0c0")
			var trunk: Color = Color("#5a3a1e") if pal["block"] == "tree" else Color("#d8dcd6")
			ci.draw_set_transform(ctr + Vector2(0, tile * 0.38), 0.0, Vector2(1.0, 0.35))
			ci.draw_circle(Vector2.ZERO, tile * 0.42, Color(0, 0, 0, 0.3))
			ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			ci.draw_rect(Rect2(ctr + Vector2(-3, 0), Vector2(6, tile * 0.42)), trunk)
			ci.draw_circle(ctr + Vector2(0, -tile * 0.12), tile * 0.42, crown.darkened(0.2))
			ci.draw_circle(ctr + Vector2(-tile * 0.1, -tile * 0.2), tile * 0.3, crown)
			ci.draw_circle(ctr + Vector2(tile * 0.12, -tile * 0.3), tile * 0.16, crown.lightened(0.18))
		"water":
			ci.draw_rect(r.grow(-1), Color("#3f6f8a"))
			ci.draw_line(ctr + Vector2(-10, -4), ctr + Vector2(6, -4), Color("#8fc0d8"), 2.0)
			ci.draw_line(ctr + Vector2(-4, 6), ctr + Vector2(10, 6), Color("#8fc0d8"), 2.0)
		_:
			var sc := rng.randf_range(0.85, 1.05)
			var pts := PackedVector2Array()
			for i in 7:
				var a := TAU * i / 7.0
				pts.append(ctr + Vector2(cos(a), sin(a) * 0.75) * tile * 0.45 * sc * rng.randf_range(0.8, 1.1) + Vector2(0, 3))
			ci.draw_colored_polygon(pts, Color(pal["stone"]).darkened(0.2))
			ci.draw_circle(ctr + Vector2(-tile * 0.08, -tile * 0.08), tile * 0.16, Color(pal["stone"]).lightened(0.15))

## Purely visual backdrop beyond the right (defenders') map edge.
func _paint_settlement(ci: CanvasItem, size: Vector2, rng: RandomNumberGenerator) -> void:
	var x0 := size.x + 6.0
	if settlement == "siege":
		var stone := Color("#8d877a"); var dark := Color("#5f5a50"); var light := Color("#aaa395")
		ci.draw_rect(Rect2(x0, -margin, margin - 6.0, size.y + margin * 2.0), stone)
		ci.draw_rect(Rect2(x0, -margin, 10.0, size.y + margin * 2.0), dark)
		var y := -margin
		while y < size.y + margin:
			ci.draw_rect(Rect2(x0 - 10.0, y, 16.0, 14.0), light)
			y += 26.0
		var ty := 0.0
		while ty < size.y:
			ci.draw_rect(Rect2(x0 - 18.0, ty + 40.0, 70.0, 70.0), dark)
			ci.draw_rect(Rect2(x0 - 12.0, ty + 46.0, 58.0, 58.0), light)
			ci.draw_rect(Rect2(x0 + 8.0, ty + 64.0, 18.0, 26.0), Color("#2a2620"))
			ty += 320.0
		for i in 12:
			var by := rng.randf() * size.y
			ci.draw_rect(Rect2(x0 + 14.0 + rng.randf() * 60.0, by, 14.0, 9.0), dark.lerp(stone, 0.5))
	else:
		for i in int(size.y / 120.0) + 1:
			var hy := float(i) * 120.0 + rng.randf_range(-20.0, 20.0)
			var hx := x0 + rng.randf_range(10.0, 40.0)
			ci.draw_rect(Rect2(hx, hy, 64.0, 44.0), Color("#8a6a48"))
			ci.draw_colored_polygon(PackedVector2Array([Vector2(hx - 8, hy), Vector2(hx + 32, hy - 30), Vector2(hx + 72, hy)]), Color("#c9a35a"))
			ci.draw_rect(Rect2(hx + 24, hy + 18, 14, 26), Color("#3b2a1c"))
