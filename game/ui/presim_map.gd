extends Control
## The small world map on the world-start screen (ui/presim.gd). v0.014, Douglas: "when doing a world start we
## need to add something to entertain the player"; 20:59: "any chance we can watch the map build too?".
##
## Two parts:
## 1. The making of the world. World gen (CampaignWorld.generate) completes before map setup; the map REVEALS its real output in the generator's own order, layer by layer: land and sea, then
##    mountains and hills, then forests, then climate and the realms' borders, then the towns one by one in the
##    order they were founded (the dwarf holds last, with their mountain land), then the roads one by one. Each
##    ground layer sweeps down the map row by row, as gen_terrain fills it. Nothing is generated here: every
##    colour, town and road is read from Game.world. (World gen has no rivers: its water is sea and lakes.)
## 2. The years before. The same map, redrawn only when the screen asks (a few times a second): each town's
##    banner in its current owner's colours, its people as dots (more people, more dots; green when the town has
##    grown since the start, red when it has shrunk), the moving forces as small marks (caravans brass squares,
##    armies on the march bigger with a red rim), and a flash where a chronicle event happened.
## No class_name (the screen preloads this file).

const GROUND := ["Land and sea", "Mountains and hills", "Forests", "Climate and realms"]
const STAGE_NAMES := ["Land and sea", "Mountains and hills", "Forests", "Climate and realms", "Towns and holds", "Roads"]
const STAGE_SEC := [1.0, 0.7, 0.7, 0.8, 1.8, 1.0]   # how long each stage of the making takes to show (seconds)
## Ground colours (the campaign map's own, campaign/map_terrain.gd), copied so this file stands alone.
const BLANK := Color(0.07, 0.06, 0.09, 1.0)
const SEA := Color("#2a74c0")
const BARE := Color("#a9a56e")
const PEAK := Color("#8d8680")
const HILL := Color("#aea45c")
const WOOD := Color("#3f8c3a")
const SILVER := Color("#a2c8bc")
const DRY := Color("#d48a4a")
const GRASS := ["#7cc84a", "#69ad62", "#b0bd4a", "#b9b456", "#76c886", "#c9bd6a", "#8fa860"]
const FOREST_FLOOR := ["#3f8c3a", "#2c6e4a", "#5f822e", "#4f7f30", "#4a9a6a", "#6a7a34", "#3f6a40"]
const HOLDS_REGION := 6
const FLASH_MSEC := 2600

var w: Dictionary
var gw := 1   # grid cells across / down
var gh := 1
var cell := 24.0
var terr: String
var reg: String
var img: Image
var tex: ImageTexture
var row_level := PackedInt32Array()   # ground layer drawn on each row (-1 none yet)
var holds_land := false   # the holds' land carved (the end of the towns stage)
var order: Array = []     # town ids in founding order
var n_plain := 0          # towns before the holds
var pop0 := {}            # tid -> people at the start
var build_t := 0.0        # seconds into the making
var built := false
var flashes: Array = []   # [pos, msec, colour]
var reg_col: Array = []   # region index -> border colour
var font: Font

func setup(world: Dictionary) -> void:
	w = world
	mouse_filter = MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	font = ThemeDB.fallback_font
	gw = int(w.get("w", WorldGen.W))
	gh = int(w.get("h", WorldGen.H))
	cell = float(w.get("cell", WorldGen.CELL))
	terr = w["terrain"]
	reg = w["region"]
	for i in WorldGen.REGIONS.size():
		var fid := WorldGen.region_faction(WorldGen.REGIONS[i])
		reg_col.append(CampaignWorld.faction_color(fid).lightened(0.2))
	img = Image.create(gw, gh, false, Image.FORMAT_RGBA8)
	img.fill(BLANK)
	tex = ImageTexture.create_from_image(img)
	row_level.resize(gh)
	row_level.fill(-1)
	order = (w["towns"] as Dictionary).keys()
	order.sort_custom(func(a, b): return String(a).substr(1).to_int() < String(b).substr(1).to_int())
	for tid in order:
		var t: Dictionary = w["towns"][tid]
		if String(t.get("region", "")) != "holds":
			n_plain += 1
		if TownEcon.has_econ(t):
			pop0[tid] = int(t["econ"].get("pop", 0))
	resized.connect(queue_redraw)

func build_total() -> float:
	var s := 0.0
	for x in STAGE_SEC:
		s += float(x)
	return s

## The stage being shown now (0 .. 5), and how far through it (0 .. 1).
func _stage() -> Vector2:
	var t := build_t
	for i in STAGE_SEC.size():
		if t < float(STAGE_SEC[i]):
			return Vector2(i, t / float(STAGE_SEC[i]))
		t -= float(STAGE_SEC[i])
	return Vector2(STAGE_SEC.size(), 0.0)

func stage_name() -> String:
	var s := int(_stage().x)
	return STAGE_NAMES[mini(s, STAGE_NAMES.size() - 1)]

## Moves the making on (dt seconds); returns true once it has all been shown.
func advance_build(dt: float) -> bool:
	build_t += dt
	_paint_ground()
	queue_redraw()
	return build_t >= build_total()

func skip_build() -> void:
	build_t = build_total()
	_paint_ground()
	queue_redraw()

func finish_build() -> void:
	built = true
	build_t = build_total()
	_paint_ground()
	queue_redraw()

## Repaints only the rows whose ground layer changed since the last call.
func _paint_ground() -> void:
	var st := _stage()
	var s := int(st.x)
	var f := st.y
	var want_holds := s > 4 or (s == 4 and f >= float(n_plain) / maxf(1.0, float(order.size())))
	var redo_all := want_holds != holds_land
	holds_land = want_holds
	var changed := false
	for y in gh:
		var lv: int
		if s >= GROUND.size():
			lv = GROUND.size() - 1
		else:
			lv = s if float(y) < f * gh else s - 1
		if lv == row_level[y] and not redo_all:
			continue
		row_level[y] = lv
		changed = true
		for x in gw:
			img.set_pixel(x, y, _cell_col(x, y, lv))
	if changed:
		tex.update(img)

func _cell_col(x: int, y: int, lv: int) -> Color:
	if lv < 0:
		return BLANK
	var i := y * gw + x
	var t := terr[i]
	if t == "w":
		return SEA
	var r := int(reg[i])
	var holds := r == HOLDS_REGION
	if holds and not holds_land:
		r = -1   # before the holds are carved their land shows as plain country
	if lv == 0:
		return BARE
	if t == "m":
		return PEAK
	if t == "h":
		return HILL
	if lv == 1:
		return BARE
	if lv == 2:
		if t == "f":
			return WOOD
		if t == "s":
			return SILVER
		return BARE
	# climate and realms: the region's grass and forest floor, dry badlands, and the realm borders
	var c: Color
	if t == "f":
		c = Color(FOREST_FLOOR[r]) if r >= 0 else WOOD
	elif t == "s":
		c = SILVER
	elif t == "b":
		c = DRY
	else:
		c = Color(GRASS[r]) if r >= 0 else Color("#7cc24a")
	if r >= 0:
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nx: int = x + d.x; var ny: int = y + d.y
			if nx < 0 or ny < 0 or nx >= gw or ny >= gh:
				continue
			var j := ny * gw + nx
			if terr[j] == "w":
				continue
			var rj := int(reg[j])
			if rj == HOLDS_REGION and not holds_land:
				continue
			if rj != r:
				return c.lerp(reg_col[r], 0.65)
	return c

## A flash at a map position (world px) where a chronicle event happened.
func flash(pos: Vector2, col: Color) -> void:
	flashes.append([pos, Time.get_ticks_msec(), col])
	if flashes.size() > 8:
		flashes.pop_front()

func _draw() -> void:
	if w.is_empty():
		return
	var wpx := Vector2(gw, gh) * cell
	var sc := minf(size.x / wpx.x, size.y / wpx.y)
	var off := (size - wpx * sc) * 0.5
	var rect := Rect2(off, wpx * sc)
	draw_rect(rect.grow(3), Color(0.05, 0.03, 0.02, 0.9))
	draw_texture_rect(tex, rect, false)
	var st := _stage()
	var s := int(st.x)
	var f := st.y
	# roads (the roads stage reveals them one by one, in the order they were built)
	var roads: Array = w.get("roads", [])
	var n_roads := roads.size() if s > 5 else (int(f * roads.size()) if s == 5 else 0)
	for k in n_roads:
		var pts := PackedVector2Array()
		for p in roads[k]["pts"]:
			pts.append(off + (p as Vector2) * sc)
		if pts.size() >= 2:
			draw_polyline(pts, Color("#e2c486", 0.85), maxf(1.0, 1.4 * sc / 0.2))
	# towns (the towns stage founds them one by one; the holds come last)
	var n_towns := order.size() if s > 4 else (int(f * order.size()) if s == 4 else 0)
	var per := float(STAGE_SEC[4]) / maxf(1.0, float(order.size()))
	for k in n_towns:
		var tid: String = order[k]
		var t: Dictionary = w["towns"].get(tid, {})
		if t.is_empty():
			continue
		var grow := 1.0
		if s == 4:
			var age := (f * order.size() - k) * per
			grow = clampf(age / 0.25, 0.0, 1.0)
		_draw_town(tid, t, off + (t["pos"] as Vector2) * sc, grow)
	if built:
		_draw_forces(off, sc)
	# flashes where events happened
	var now := Time.get_ticks_msec()
	for fl in flashes:
		var a := float(now - int(fl[1])) / FLASH_MSEC
		if a < 0.0 or a >= 1.0:
			continue
		var p: Vector2 = off + (fl[0] as Vector2) * sc
		var c: Color = fl[2]
		draw_arc(p, 5.0 + a * 22.0, 0, TAU, 28, Color(c, 1.0 - a), 3.0)
		draw_circle(p, 4.0 * (1.0 - a), Color(c, 1.0 - a))

func _draw_town(tid: String, t: Dictionary, p: Vector2, grow: float) -> void:
	if grow <= 0.0:
		return
	var fid := String(t["faction"])
	var prim := CampaignWorld.faction_color(fid)
	var sec := Color(DB.factions.get(fid, {}).get("colors", {}).get("secondary", "#f0e0c0"))
	var sz := int(t.get("size", 1))
	var r := (2.5 + sz * 1.1) * grow
	if String(t.get("region", "")) == "holds":
		draw_colored_polygon(PackedVector2Array([p + Vector2(-r - 1, r * 0.7), p + Vector2(r + 1, r * 0.7), p + Vector2(0, -r - 1)]), Color("#b4aea4"))
	else:
		draw_circle(p, r + 1.0, Color(0.1, 0.07, 0.05, 0.9))
		draw_circle(p, r, Color("#efe2c4"))
	if t.get("capital", false):
		draw_arc(p, r + 2.5, 0, TAU, 20, UiTheme.BRASS, 1.5)
	# banner in the owner's colours (it changes when the town changes hands)
	var bp := p + Vector2(r * 0.6, -r * 0.5)
	var h := 10.0 * grow
	draw_line(bp, bp + Vector2(0, -h), Color("#2a1a10"), 1.5)
	draw_colored_polygon(PackedVector2Array([bp + Vector2(0.5, -h), bp + Vector2(8 * grow, -h + 2.5 * grow), bp + Vector2(0.5, -h + 5 * grow)]), prim)
	draw_line(bp + Vector2(1, -h + 2.5 * grow), bp + Vector2(5 * grow, -h + 2.5 * grow), sec, 1.0)
	# its people as dots
	if grow >= 1.0 and TownEcon.has_econ(t):
		var pop := int(t["econ"].get("pop", 0))
		var p0 := int(pop0.get(tid, pop))
		var n := clampi(int(sqrt(float(pop)) / 5.0), 1, 10)
		var col := Color("#fff4dc")
		if pop >= p0 * 1.1 + 2:
			col = Color("#8be07a")
		elif pop <= p0 * 0.9 - 2:
			col = Color("#ff7a62")
		for k in n:
			var dp := p + Vector2((k - (n - 1) * 0.5) * 3.2, r + 4.0)
			draw_circle(dp, 1.3, col)
	if t.get("capital", false) and grow >= 1.0:
		var nm := String(t.get("name", ""))
		var lp := p + Vector2(-60, -r - 6)
		draw_string_outline(font, lp, nm, HORIZONTAL_ALIGNMENT_CENTER, 120, 12, 3, Color(0.05, 0.03, 0.02, 0.9))
		draw_string(font, lp, nm, HORIZONTAL_ALIGNMENT_CENTER, 120, 12, Color("#fff4dc"))

## The moving forces as small marks: caravans brass squares, armies on the march bigger with a red rim, the rest
## (patrols, outlaws, beasts) small dots in their colours.
func _draw_forces(off: Vector2, sc: float) -> void:
	var wbs: Dictionary = w.get("warbands", {})
	for wid in wbs:
		var wb: Dictionary = wbs[wid]
		var p: Vector2 = off + (wb["pos"] as Vector2) * sc
		var kind := String(wb.get("kind", ""))
		if kind == "caravan":
			draw_rect(Rect2(p - Vector2(1.6, 1.6), Vector2(3.2, 3.2)), UiTheme.BRASS)
		elif kind == "assault" or kind == "war" or String(wb.get("target_town", "")) != "":
			draw_circle(p, 3.2, Color("#b02a1e"))
			draw_circle(p, 2.2, CampaignWorld.faction_color(String(wb.get("faction", ""))))
		else:
			draw_circle(p, 1.6, CampaignWorld.faction_color(String(wb.get("faction", ""))))
