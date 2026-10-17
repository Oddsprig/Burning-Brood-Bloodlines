class_name MapTokens
extends RefCounted
## Campaign-map tokens (docs/specs/map-tokens.md, Direction A): one object per moving force. Shape = type,
## colour = faction, pips = size band and stance toward the company. Painted in code into a 64x64 box with a small
## anti-aliased scanline rasteriser (polygons only: circles, lines and arcs are turned into polygons), then cached
## as one texture per (type, variant, pips, stance). Nothing is painted per frame.
##   MapTokens.texture(type, variant, pips, stance) -> Texture2D   (cached; same key -> same object)
##   MapTokens.sync(parent, tokens, game, visible_ids, zoom, refresh, player_token)   per map frame, cheap
##   MapTokens.pick(tokens, warbands, world_point, zoom) -> wid under a tap (hit circle r=30 screen px)
##   MapTokens.night_comp(canvas_tint) -> modulate that caps the night darkening of tokens at 30%
## Types: player, army, militia, caravan, bandit, deserter, monster. Variant: faction id (army, militia: the
## home town's faction, caravan, deserter) or creature id (monster: wolf, bear, boar, hydra, dragon).

const R := 2.0              # texture pixels per box unit (64 box -> 128 px; on screen 52 px at 100%, up to ~135)
const PAD := 4.0            # box units of margin around the 64 box (pennants and outlines poke out)
const BOX := 64.0
const SIZE := 144           # (BOX + 2 * PAD) * R
const ANCHOR := Vector2(32, 55)   # box point on the force's map position
const SS := 4               # sub-scanlines per pixel row (vertical anti-aliasing; horizontal is analytic)
const SCREEN_PX := 52.0     # on-screen height of the 64 box at 100% zoom
const MIN_PX := 40.0        # never smaller than this on screen
const HIT_R := 30.0         # tap / hover hit circle, screen px
const NIGHT_CAP := 0.3      # tokens never darken more than this

const INK := Color("#2b1d14")
const BONE := Color("#f3ead2")
const WOOD := Color("#8a5a32")
const WOOD_D := Color("#5e3a1e")
const GOLD := Color("#ffd34a")
const OL := 2.2
const STANCE_COL := {"hostile": Color("#e0392b"), "neutral": Color("#efe6cc"), "allied": Color("#52c35a")}
const TIER_RIM := {"common": Color("#7a2d1c"), "epic": Color("#7b3fbf"), "legendary": Color("#e0a020")}
const TYPES := ["player", "army", "militia", "caravan", "bandit", "deserter", "monster"]
const MONSTERS := ["wolf", "bear", "boar", "hydra", "dragon"]

static var _tex := {}      # full key -> ImageTexture
static var _base := {}     # "type|variant" -> Image (no pips)
static var paint_count := 0   # bases painted (tests: cache)

# ================================================================== public
static func key(type: String, variant: String, pips: int, stance: String) -> String:
	return "%s|%s|%d|%s" % [type, variant, pips, stance]

static func texture(type: String, variant: String = "", pips: int = 0, stance: String = "hostile") -> Texture2D:
	if type == "player":
		pips = 0
	var k := key(type, variant, pips, stance)
	var t: Texture2D = _tex.get(k)
	if t != null:
		return t
	var img := image(type, variant, pips, stance)
	img.generate_mipmaps()
	t = ImageTexture.create_from_image(img)
	_tex[k] = t
	return t

## The token image (SIZE x SIZE, straight alpha, no mipmaps). Uncached copy of the cached base plus pips.
static func image(type: String, variant: String = "", pips: int = 0, stance: String = "hostile") -> Image:
	var bk := type + "|" + variant
	var base: Image = _base.get(bk)
	if base == null:
		base = paint_base(type, variant)
		_base[bk] = base
	var img: Image = base.duplicate()
	if pips > 0 and type != "player":
		var strip := _paint_pips(_pip_x(type), pips, STANCE_COL.get(stance, STANCE_COL["neutral"]))
		img.blend_rect(strip, Rect2i(0, 0, strip.get_width(), strip.get_height()), Vector2i(0, int((PIP_Y0 + PAD) * R)))
	return img

static func clear_cache() -> void:
	_tex.clear()
	_base.clear()

## Compact headcount, kept separate from the cached texture so casualties do not create new textures.
static func count_text(n: int) -> String:
	return str(n) if n < 1000 else "%.1fk" % (float(n) / 1000.0)

## Size band of a headcount (beasts count as men): 1 = 1-5, 2 = 6-15, 3 = 16-30, 4 = 31-60, 5 = 61+.
static func pips_for(n: int) -> int:
	if n <= 5: return 1
	if n <= 15: return 2
	if n <= 30: return 3
	if n <= 60: return 4
	return 5

## [type, variant] of a warband dictionary.
static func kind_of(game, wb: Dictionary) -> Array:
	var k := String(wb.get("kind", ""))
	var fid := String(wb.get("faction", ""))
	if k in ["beasts", "den"] or fid == "beasts":
		var cid := String(wb.get("creature", ""))
		if cid == "" and not (wb["units"] as Array).is_empty():
			cid = String(wb["units"][0].race)
		return ["monster", cid]
	if k in ["camp", "bandit"] or fid == "outlaws":
		return ["bandit", ""]
	if k == "deserter" or bool(wb.get("deserter", false)):
		return ["deserter", fid]
	if k == "militia":
		var t: Dictionary = game.world["towns"].get(String(wb.get("home", "")), {})
		return ["militia", String(t.get("faction", fid))]
	if k == "caravan":
		return ["caravan", fid]
	return ["army", fid]

## hostile | neutral | allied toward the company (diplomacy thresholds; monsters, bandits, deserters always hostile).
static func stance_of(game, wb: Dictionary, type: String) -> String:
	if type in ["monster", "bandit", "deserter"] or Monsters.band_hostile(game, wb):
		return "hostile"
	if Diplomacy.friendly(game, String(wb["faction"])):
		return "allied"
	return "neutral"

static func alive_count(wb: Dictionary) -> int:
	var n := 0
	for u in wb["units"]:
		if not u.dead:
			n += 1
	return n

static func token_key_for(game, wb: Dictionary) -> Array:
	var tv := kind_of(game, wb)
	var n := alive_count(wb)
	return [tv[0], tv[1], pips_for(n), stance_of(game, wb, tv[0]), n]

## World units per box unit at camera zoom z: 52 px on screen at 100%, scaling with zoom, never under 40 px.
static func box_unit(zoom: float) -> float:
	return maxf(SCREEN_PX * zoom, MIN_PX) / zoom / BOX

## Visual centre of a token standing at map point pos.
static func center(pos: Vector2, zoom: float) -> Vector2:
	return pos + Vector2(0, (32.0 - ANCHOR.y) * box_unit(zoom))

## Nearest token whose hit circle (r = 30 screen px around its centre) holds world point p; "" if none.
static func pick(tokens: Dictionary, warbands: Dictionary, p: Vector2, zoom: float) -> String:
	var best := ""
	var bd := HIT_R / zoom
	for wid in tokens:
		if not warbands.has(wid) or not (tokens[wid] as Node2D).visible:
			continue
		var d := center(warbands[wid]["pos"], zoom).distance_to(p)
		if d < bd:
			bd = d
			best = wid
	return best

## Modulate for the token layer under the map's CanvasModulate tint: the product never darkens more than 30%.
static func night_comp(tint: Color) -> Color:
	var m := minf(tint.r, minf(tint.g, tint.b))
	if m >= 1.0 - NIGHT_CAP:
		return Color.WHITE
	var k := NIGHT_CAP / (1.0 - m)
	var t := Color(lerpf(1.0, tint.r, k), lerpf(1.0, tint.g, k), lerpf(1.0, tint.b, k))
	return Color(t.r / maxf(tint.r, 0.01), t.g / maxf(tint.g, 0.01), t.b / maxf(tint.b, 0.01))

static var _frame := 0

## Per map frame: one MapToken per visible force (created / removed as forces come and go), position every frame,
## texture key (type, faction, pips, stance) re-checked only when `refresh`. Scale follows the camera zoom.
static func sync(parent: Node, tokens: Dictionary, game, vis: Array, zoom: float, refresh: bool, player: MapToken = null) -> void:
	_frame += 1
	var wbs: Dictionary = game.world["warbands"]
	var u := box_unit(zoom)
	var rescale := player != null and player.scale.x != u
	if player != null and (refresh or player.badge_text == ""):
		var tid := String(game.world.get("player_house", {}).get("town_id", ""))
		var fid := String(game.world.get("towns", {}).get(tid, {}).get("faction", "player"))
		player.set_badge(alive_count({"units": game.company}), fcol(fid))
	for wid in vis:
		var wb: Dictionary = wbs[wid]
		var tk: MapToken = tokens.get(wid)
		if tk == null:
			tk = MapToken.new()
			tk.scale = Vector2(u, u)
			parent.add_child(tk)
			tokens[wid] = tk
			tk.refresh(game, wb)
		elif refresh:
			tk.refresh(game, wb)
		tk.seen = _frame
		tk.position = wb["pos"]
	if tokens.size() > vis.size():
		for wid in tokens.keys():
			if tokens[wid].seen != _frame:
				tokens[wid].queue_free()
				tokens.erase(wid)
	if rescale:
		player.scale = Vector2(u, u)
		for wid in tokens:
			tokens[wid].scale = Vector2(u, u)

# ================================================================== painting
static var _rs: Raster

static func paint_base(type: String, variant: String) -> Image:
	paint_count += 1
	_rs = Raster.new(SIZE, SIZE, Vector2(-PAD, -PAD), R)
	match type:
		"player": _player()
		"army": _army(variant, false)
		"deserter": _army(variant, true)
		"militia": _militia(variant)
		"caravan": _caravan(variant)
		"bandit": _bandit()
		_: _monster(variant)
	var img := _rs.to_image()
	_rs = null
	return img

static func fcol(fid: String) -> Color:
	if fid == "player":
		return Color(CampaignWorld.PLAYER_COLOR)
	return Color(DB.factions.get(fid, {}).get("colors", {}).get("primary", "#888888"))

static func dark(c: Color) -> Color:
	return Color(c.r * 0.65, c.g * 0.65, c.b * 0.65, c.a)

# ---------------------------------------------------------------- geometry helpers (box units)
static func circ(c: Vector2, r: float, n: int = 0) -> PackedVector2Array:
	return ell(c, r, r, n)

static func ell(c: Vector2, rx: float, ry: float, n: int = 0) -> PackedVector2Array:
	if n <= 0:
		n = clampi(int(maxf(rx, ry) * R * 1.6), 12, 72)
	var out := PackedVector2Array()
	out.resize(n)
	for i in n:
		var a := TAU * i / n
		out[i] = c + Vector2(cos(a) * rx, sin(a) * ry)
	return out

static func quad(a: Vector2, b: Vector2, w: float) -> PackedVector2Array:
	var d := b - a
	if d.length() < 0.0001:
		d = Vector2(0.0001, 0)
	var n := d.orthogonal().normalized() * (w * 0.5)
	return PackedVector2Array([a + n, b + n, b - n, a - n])

static func rect(x0: float, y0: float, x1: float, y1: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(x0, y0), Vector2(x1, y0), Vector2(x1, y1), Vector2(x0, y1)])

## Stroke of a polyline as union pieces: a quad per segment, a round cap/join per vertex.
static func stroke_pieces(pts: PackedVector2Array, w: float, closed: bool) -> Array:
	var out := []
	var n := pts.size()
	var segs := n if closed else n - 1
	for i in segs:
		out.append([quad(pts[i], pts[(i + 1) % n], w)])
	for p in pts:
		out.append([circ(p, w * 0.5, 10)])
	return out

static func xf(pts: PackedVector2Array, at: Vector2, s: float, from: Vector2 = Vector2.ZERO) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.resize(pts.size())
	for i in pts.size():
		out[i] = at + (pts[i] - from) * s
	return out

static func mirror_x(pts: PackedVector2Array, cx: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in range(pts.size() - 1, -1, -1):
		out.append(Vector2(2.0 * cx - pts[i].x, pts[i].y))
	return out

static func qbez(a: Vector2, c: Vector2, b: Vector2, n: int, skip_first: bool = true) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in range(1 if skip_first else 0, n + 1):
		var t := float(i) / n
		out.append(a.lerp(c, t).lerp(c.lerp(b, t), t))
	return out

## Inset a convex polygon by d (edges moved inward and re-intersected).
static func inset(pts: PackedVector2Array, d: float) -> PackedVector2Array:
	var n := pts.size()
	var area := 0.0
	for i in n:
		area += pts[i].cross(pts[(i + 1) % n])
	var sgn := 1.0 if area > 0.0 else -1.0
	var lines := []
	for i in n:
		var a := pts[i]
		var b := pts[(i + 1) % n]
		var nn := (b - a).orthogonal().normalized() * sgn   # inward for this winding (y down)
		lines.append([a + nn * d, b - a])
	var out := PackedVector2Array()
	for i in n:
		var l0: Array = lines[(i - 1 + n) % n]
		var l1: Array = lines[i]
		var p: Vector2 = l0[0]; var r: Vector2 = l0[1]
		var q: Vector2 = l1[0]; var s: Vector2 = l1[1]
		var den := r.cross(s)
		if absf(den) < 1e-6:
			out.append(q)
		else:
			out.append(p + r * ((q - p).cross(s) / den))
	return out

# ---------------------------------------------------------------- drawing ops
static func fill(shape, c: Color, clip = null, cut = null) -> void:
	_rs.fill(_as_shape(shape), c, _as_shape(clip) if clip != null else [], _as_shape(cut) if cut != null else [])

static func _as_shape(s) -> Array:
	if s is PackedVector2Array:
		return [s]
	return s

static func union(pieces: Array, c: Color) -> void:
	_rs.fill_union(pieces, c)

## Filled shape with an INK outline of width olw centred on its edge (round joins).
static func shape(pts: PackedVector2Array, c: Color, olw: float = OL, olc: Color = INK) -> void:
	fill(pts, c)
	if olw > 0.0:
		union(stroke_pieces(pts, olw, true), olc)

static func outline(pts: PackedVector2Array, olw: float = OL, olc: Color = INK) -> void:
	union(stroke_pieces(pts, olw, true), olc)

## A stroked line with an INK outline (ink w + olw underneath, colour on top).
static func oline(pts: PackedVector2Array, w: float, c: Color, olw: float = 1.6) -> void:
	if olw > 0.0:
		union(stroke_pieces(pts, w + olw, false), INK)
	union(stroke_pieces(pts, w, false), c)

static func disc(c: Vector2, r: float, col: Color, olw: float = OL) -> void:
	shape(circ(c, r), col, olw)

static func ring(c: Vector2, rx: float, ry: float, w: float, col: Color) -> void:
	fill([ell(c, rx + w * 0.5, ry + w * 0.5), ell(c, rx - w * 0.5, ry - w * 0.5)], col)

static func shadow(cx: float, rx: float) -> void:
	fill(ell(Vector2(cx, 55), rx, 4.5), Color(0, 0, 0, 0.28))

# ================================================================== 1. player company
static func _player() -> void:
	var pc := fcol("player")
	shadow(32, 18)
	ring(Vector2(32, 55), 20, 6, 2.6 + 1.6, INK)
	ring(Vector2(32, 55), 20, 6, 2.6, GOLD)
	oline(PackedVector2Array([Vector2(16, 55), Vector2(16, 1)]), 3.6, WOOD_D)
	var ban := PackedVector2Array([Vector2(17, 5), Vector2(54, 5), Vector2(54, 40), Vector2(45, 34), Vector2(36, 40),
		Vector2(27, 34), Vector2(17, 40)])
	fill(ban, pc)
	fill(rect(17, 5, 54, 11), dark(pc), ban)
	outline(ban, 2.4)
	disc(Vector2(16, 1.5), 3.0, GOLD, 1.6)
	# crest: copper coin
	var cc := Vector2(35.5, 22)
	var s := 1.15
	disc(cc, 7.0 * s, Color("#c87533"), 1.8)
	ring(cc, 4.0 * s, 4.0 * s, 1.6, BONE)
	fill(quad(cc + Vector2(-6.2 * s, 0), cc + Vector2(6.2 * s, 0), 1.4), INK)

# ================================================================== 2. faction warband / army (and deserters)
static func kite_shield() -> PackedVector2Array:
	var pts := PackedVector2Array([Vector2(12, 16), Vector2(46, 16), Vector2(46, 32)])
	pts.append_array(qbez(Vector2(46, 32), Vector2(46, 47), Vector2(29, 56), 8))
	pts.append_array(qbez(Vector2(29, 56), Vector2(12, 47), Vector2(12, 32), 8))
	return pts

const RAGGED := [Vector2(26, 6), Vector2(56, 8), Vector2(50, 13), Vector2(57, 17), Vector2(49, 21), Vector2(55, 26),
	Vector2(44, 27), Vector2(40, 31), Vector2(36, 26), Vector2(27, 28)]

static func _army(fid: String, deserter: bool) -> void:
	var fc := fcol(fid)
	shadow(30, 17)
	oline(PackedVector2Array([Vector2(46, 54), Vector2(46, 4)]), 3.0, WOOD_D)
	if deserter:
		# the bandits' ragged black flag instead of the pennant
		var flag := xf(PackedVector2Array(RAGGED), Vector2(47, 3), 0.6, Vector2(26, 6))
		shape(flag, Color("#26201d"), 1.6)
	else:
		shape(PackedVector2Array([Vector2(47, 6), Vector2(62, 6), Vector2(58, 12), Vector2(62, 18), Vector2(47, 18)]), fc, 1.6)
	disc(Vector2(46, 4), 2.2, GOLD, 1.4)
	var outer := kite_shield()
	fill(outer, BONE)
	var inner := inset(outer, 3.5)
	fill(inner, fc)
	fill(rect(10, 19.5, 48, 24), dark(fc), inner)
	outline(inner, 1.0, dark(dark(fc)))
	outline(outer, 2.4)
	emblem(fid, Vector2(29, 35))

## Faction emblem, BONE with a thin INK edge, ~16 px, centred at c.
static func emblem(fid: String, c: Vector2) -> void:
	var e := 1.3
	match fid:
		"middle_kingdom":   # upright sword
			var blade := PackedVector2Array([Vector2(-1.5, -5.5), Vector2(0, -8.5), Vector2(1.5, -5.5), Vector2(1.5, 3.5), Vector2(-1.5, 3.5)])
			shape(xf(blade, c, 1.0), BONE, e)
			shape(xf(rect(-5.5, 3.2, 5.5, 5.4), c, 1.0), BONE, e)
			shape(xf(rect(-0.9, 5.4, 0.9, 8.4), c, 1.0), BONE, e)
			disc(c + Vector2(0, 9.3), 1.6, BONE, e)
		"northern_clans":   # double-bladed axe on a haft
			oline(PackedVector2Array([c + Vector2(0, 9), c + Vector2(0, -8.5)]), 1.8, BONE, e)
			var bl := PackedVector2Array([Vector2(-1, -4.5), Vector2(-5, -7.5), Vector2(-7.6, -3.5), Vector2(-8, 0),
				Vector2(-7.6, 3.5), Vector2(-5, 7.5), Vector2(-1, 4.5)])
			shape(xf(bl, c, 1.0), BONE, e)
			shape(xf(mirror_x(bl, 0.0), c, 1.0), BONE, e)
		"orc_horde":   # two tusks under a bar
			shape(xf(rect(-8, -8, 8, -4.5), c, 1.0), BONE, e)
			var tusk := PackedVector2Array([Vector2(-6.8, -4.5), Vector2(-7.0, 0), Vector2(-5.6, 4.5), Vector2(-1.6, 8.5),
				Vector2(-2.6, 4.0), Vector2(-3.0, 0), Vector2(-2.4, -4.5)])
			shape(xf(tusk, c, 1.0), BONE, e)
			shape(xf(mirror_x(tusk, 0.0), c, 1.0), BONE, e)
		"goblin_warren":   # jagged three-point crown / ears, two INK dot eyes
			var cr := PackedVector2Array([Vector2(-8.5, 7), Vector2(-8.5, -6), Vector2(-4.5, -1.5), Vector2(0, -9),
				Vector2(4.5, -1.5), Vector2(8.5, -6), Vector2(8.5, 7)])
			shape(xf(cr, c, 1.0), BONE, e)
			fill(circ(c + Vector2(-3.4, 2.8), 1.7), INK)
			fill(circ(c + Vector2(3.4, 2.8), 1.7), INK)
		"moon_court":   # crescent moon and a small star dot
			var mc := c + Vector2(-1.5, 0.5)
			var cut_c := mc + Vector2(3.6, -2.2)
			fill(circ(mc, 8.3), INK, null, circ(cut_c, 5.5))
			fill(circ(mc, 7.6), BONE, null, circ(cut_c, 6.2))
			var st := c + Vector2(5.0, -4.2)
			var star := PackedVector2Array()
			for i in 8:
				var a := -PI / 2 + i * PI / 4
				star.append(st + Vector2(cos(a), sin(a)) * (2.9 if i % 2 == 0 else 1.1))
			shape(star, BONE, 1.0)
		"dwarf_holds":   # v0.012: an anvil
			var anv := PackedVector2Array([Vector2(-8, -5), Vector2(6, -5), Vector2(8.5, -2.5), Vector2(3, -1.5), Vector2(2, 2.5),
				Vector2(5, 6.5), Vector2(-5, 6.5), Vector2(-2, 2.5), Vector2(-3, -1.5), Vector2(-8, -2.5)])
			shape(xf(anv, c, 1.0), BONE, e)
		"eastern_khanate":   # v0.012: a strung recurve bow and an arrow
			var bow := PackedVector2Array([Vector2(-2, -8.5), Vector2(1.5, -6), Vector2(2.5, -2), Vector2(2.5, 2), Vector2(1.5, 6),
				Vector2(-2, 8.5), Vector2(0, 5), Vector2(0.8, 0), Vector2(0, -5)])
			shape(xf(bow, c, 1.0), BONE, e)
			oline(PackedVector2Array([c + Vector2(-2, -8.5), c + Vector2(-2, 8.5)]), 1.0, BONE, 0.8)
			oline(PackedVector2Array([c + Vector2(-7.5, 0), c + Vector2(6.5, 0)]), 1.4, BONE, e)
		_:   # unknown faction: a plain diamond
			shape(xf(PackedVector2Array([Vector2(0, -8), Vector2(6, 0), Vector2(0, 8), Vector2(-6, 0)]), c, 1.0), BONE, e)

# ================================================================== 3. town militia
static func _militia(fid: String) -> void:
	shadow(30, 15)
	var grey := Color("#9aa3a8")
	oline(PackedVector2Array([Vector2(14, 54), Vector2(48, 6)]), 3.0, WOOD_D)
	oline(PackedVector2Array([Vector2(40, 11), Vector2(46, 15)]), 2.4, grey)
	for t in [[Vector2(43, 13), Vector2(50, 3)], [Vector2(46, 15), Vector2(54, 6)], [Vector2(40, 11), Vector2(46, 1)]]:
		oline(PackedVector2Array(t), 2.4, grey)
	var c := Vector2(30, 36)
	var disc_pts := circ(c, 17)
	fill(disc_pts, WOOD)
	fill(rect(10, 30, 50, 42), fcol(fid), disc_pts)
	# dashed rim ring
	var dashes := 16
	for i in dashes:
		var a0 := TAU * i / dashes
		var a1 := a0 + TAU / dashes * 0.55
		var seg := PackedVector2Array()
		for j in 5:
			var a := lerpf(a0, a1, j / 4.0)
			seg.append(c + Vector2(cos(a), sin(a)) * 14.6)
		union(stroke_pieces(seg, 1.6, false), Color("#c9b07a"))
	outline(disc_pts, 2.4)
	_tower(c, 0.9)

static func _tower(c: Vector2, s: float) -> void:
	var t := PackedVector2Array([Vector2(-6.5, -4.5), Vector2(-6.5, -10), Vector2(-4, -10), Vector2(-4, -7.5), Vector2(-1.3, -7.5),
		Vector2(-1.3, -10), Vector2(1.3, -10), Vector2(1.3, -7.5), Vector2(4, -7.5), Vector2(4, -10), Vector2(6.5, -10),
		Vector2(6.5, -4.5), Vector2(5, -4.5), Vector2(5, 9), Vector2(-5, 9), Vector2(-5, -4.5)])
	var o := c + Vector2(0, 0.5 * s)
	shape(xf(t, o, s), BONE, 1.3)
	fill(xf(rect(-2, 3.5, 2, 9), o, s), INK)
	fill(circ(o + Vector2(0, 3.5) * s, 2.0 * s), INK)

# ================================================================== 4. merchant caravan
static func _caravan(fid: String) -> void:
	var fc := fcol(fid)
	shadow(34, 26)
	# canvas hood: arc over the top at y=12, centre x=40
	var hood := PackedVector2Array([Vector2(22, 34), Vector2(22, 26)])
	for i in range(1, 24):
		var a := PI + PI * i / 24.0
		hood.append(Vector2(40 + cos(a) * 18, 26 + sin(a) * 14))
	hood.append_array([Vector2(58, 26), Vector2(58, 34)])
	fill(hood, BONE)
	for x in [30.0, 40.0, 50.0]:
		fill(rect(x - 1.6, 8, x + 1.6, 34), fc, hood)
	outline(hood, 2.0)
	# pennant
	oline(PackedVector2Array([Vector2(57, 22), Vector2(57, 4)]), 2.0, WOOD_D, 1.4)
	shape(PackedVector2Array([Vector2(58, 4), Vector2(66, 7), Vector2(58, 10)]), fc, 1.3)
	# bed and wheels
	shape(rect(20, 34, 60, 45), WOOD, 2.0)
	union(stroke_pieces(PackedVector2Array([Vector2(22, 39.5), Vector2(58, 39.5)]), 1.0, false), WOOD_D)
	for x in [28.0, 52.0]:
		disc(Vector2(x, 47), 6.5, WOOD_D, 1.8)
		disc(Vector2(x, 47), 1.8, BONE, 1.0)
	# ox and yoke
	oline(PackedVector2Array([Vector2(15, 38), Vector2(22, 40)]), 2.0, WOOD_D, 1.4)
	var ox := PackedVector2Array([Vector2(2, 38), Vector2(4, 32), Vector2(14, 31), Vector2(16, 36), Vector2(16, 46), Vector2(13, 46),
		Vector2(13, 41), Vector2(7, 41), Vector2(7, 46), Vector2(4, 46), Vector2(4, 41)])
	shape(ox, Color("#9a6b42"), 1.6)
	oline(PackedVector2Array([Vector2(4.2, 32.6), Vector2(2.6, 30.2), Vector2(3.4, 28.2)]), 1.3, BONE, 1.2)
	oline(PackedVector2Array([Vector2(6.6, 32.0), Vector2(7.6, 29.6), Vector2(9.8, 28.8)]), 1.3, BONE, 1.2)
	fill(circ(Vector2(4.6, 35.2), 0.9), INK)

# ================================================================== 5. bandits
static func _bandit() -> void:
	shadow(30, 15)
	oline(PackedVector2Array([Vector2(26, 56), Vector2(28, 30), Vector2(25, 4)]), 3.4, WOOD_D)
	shape(PackedVector2Array(RAGGED), Color("#26201d"), 1.8)
	# red skull
	var c := Vector2(40, 17)
	var s := 0.85
	var red := Color("#e64a2e")
	fill(xf(rect(-3.6, 2.0, 3.6, 7.0), c, s), red)
	fill(circ(c + Vector2(0, -1) * s, 6.0 * s), red)
	fill(circ(c + Vector2(-2.3, -0.5) * s, 1.7 * s), INK)
	fill(circ(c + Vector2(2.3, -0.5) * s, 1.7 * s), INK)
	fill(xf(PackedVector2Array([Vector2(0, 2), Vector2(0.9, 3.4), Vector2(-0.9, 3.4)]), c, s), INK)
	for x in [-1.3, 1.3]:
		fill(quad(c + Vector2(x, 4.6) * s, c + Vector2(x, 7.0) * s, 0.8), INK)
	# crossed daggers
	var steel := Color("#b8c0c4")
	for d in [[Vector2(10, 52), Vector2(24, 38)], [Vector2(24, 52), Vector2(10, 38)]]:
		var a: Vector2 = d[0]
		var b: Vector2 = d[1]
		var tip := b + (b - a).normalized() * 1.5
		oline(PackedVector2Array([a, tip]), 3.0, steel, 1.6)
		var g := a.lerp(b, 0.3)
		oline(PackedVector2Array([a, g]), 3.4, WOOD_D, 1.4)
		var n := (b - a).orthogonal().normalized() * 3.0
		oline(PackedVector2Array([g - n, g + n]), 1.6, steel, 1.2)

# ================================================================== 6. monsters
static func _monster(cid: String) -> void:
	shadow(32, 16)
	var tier := "common"
	if cid == "hydra":
		tier = "epic"
	elif cid == "dragon":
		tier = "legendary"
	elif DB.creature_data.get("creatures", {}).has(cid):
		var r := Creatures.rarity(cid)
		if r in ["epic", "legendary"]:
			tier = r
	var star := PackedVector2Array()
	var c := Vector2(32, 32)
	for i in 56:
		var a := -PI / 2 + PI * i / 28.0
		star.append(c + Vector2(cos(a), sin(a)) * (21.0 if i % 2 == 0 else 17.0))
	shape(star, TIER_RIM[tier], 2.0)
	disc(c, 14.5, Color("#e9d9ae"), 1.6)
	match cid:
		"wolf": _wolf()
		"bear": _bear()
		"boar": _boar()
		"hydra": _hydra()
		"dragon": _dragon()
		_: _claws()

static func _wolf() -> void:
	var g := Color("#6f6a66")
	var lt := Color("#a9a29a")
	for sx in [-1.0, 1.0]:
		var ear := PackedVector2Array([Vector2(32 + sx * 10.5, 19.5), Vector2(32 + sx * 9.5, 29), Vector2(32 + sx * 3.5, 25)])
		shape(ear, g, 1.4)
		fill(PackedVector2Array([Vector2(32 + sx * 9.6, 22.5), Vector2(32 + sx * 8.8, 27.5), Vector2(32 + sx * 5.6, 25.5)]), INK)
	var head := PackedVector2Array([Vector2(23, 28), Vector2(27, 24), Vector2(37, 24), Vector2(41, 28), Vector2(41.5, 32),
		Vector2(37.5, 36), Vector2(35.5, 42.5), Vector2(32, 45), Vector2(28.5, 42.5), Vector2(26.5, 36), Vector2(22.5, 32)])
	fill(head, g)
	fill(PackedVector2Array([Vector2(28.5, 34), Vector2(35.5, 34), Vector2(34.5, 42.5), Vector2(32, 44.5), Vector2(29.5, 42.5)]), lt, head)
	outline(head, 1.5)
	for sx in [-1.0, 1.0]:
		var e := Vector2(32 + sx * 4.3, 30.5)
		fill(PackedVector2Array([e + Vector2(-2.4 * sx, 0.6), e + Vector2(0.4 * sx, -1.6), e + Vector2(2.4 * sx, 0.6)]), GOLD)
		fill(circ(e + Vector2(0, -0.1), 0.7), INK)
	fill(ell(Vector2(32, 42.2), 2.3, 1.7), INK)

static func _bear() -> void:
	var b := Color("#6b4226")
	for sx in [-1.0, 1.0]:
		disc(Vector2(32 + sx * 8.2, 22.5), 3.7, b, 1.4)
		fill(circ(Vector2(32 + sx * 8.2, 22.8), 1.7), Color("#3d2414"))
	shape(ell(Vector2(32, 31.5), 10.5, 9.5), b, 1.5)
	shape(ell(Vector2(32, 36.5), 5.3, 4.2), Color("#b08860"), 1.0)
	fill(ell(Vector2(32, 34.6), 2.2, 1.5), INK)
	fill(quad(Vector2(32, 35.6), Vector2(32, 38.4), 0.8), INK)
	fill(circ(Vector2(27.6, 29), 1.4), INK)
	fill(circ(Vector2(36.4, 29), 1.4), INK)

static func _boar() -> void:
	var d := Color("#4a3528")
	for sx in [-1.0, 1.0]:
		shape(PackedVector2Array([Vector2(32 + sx * 6.5, 23), Vector2(32 + sx * 11.5, 18.5), Vector2(32 + sx * 11, 25.5)]), d, 1.3)
	var head := PackedVector2Array([Vector2(21, 27), Vector2(25, 22.5), Vector2(39, 22.5), Vector2(43, 27), Vector2(42.5, 33),
		Vector2(38.5, 38.5), Vector2(25.5, 38.5), Vector2(21.5, 33)])
	shape(head, d, 1.5)
	# bristle ridge
	union(stroke_pieces(PackedVector2Array([Vector2(32, 22.5), Vector2(32, 27)]), 1.0, false), Color("#2e2018"))
	shape(ell(Vector2(32, 37.5), 5.6, 3.8), Color("#a07060"), 1.2)
	fill(ell(Vector2(30.2, 37.6), 0.9, 1.3), INK)
	fill(ell(Vector2(33.8, 37.6), 0.9, 1.3), INK)
	for sx in [-1.0, 1.0]:
		var tusk := PackedVector2Array([Vector2(32 + sx * 5.2, 39.5), Vector2(32 + sx * 8.6, 38), Vector2(32 + sx * 10.2, 34.5),
			Vector2(32 + sx * 9.6, 30.5), Vector2(32 + sx * 8.8, 34.2), Vector2(32 + sx * 6.8, 36.6), Vector2(32 + sx * 4.6, 37.4)])
		shape(tusk, BONE, 1.1)
		fill(circ(Vector2(32 + sx * 4.6, 29.5), 1.5), Color("#e0502a"))
		fill(circ(Vector2(32 + sx * 4.6, 29.5), 0.6), INK)

static func _hydra() -> void:
	var gr := Color("#3f8a5a")
	var s := 0.78
	var c := Vector2(32, 32)
	var ends := [Vector2(-9, -6), Vector2(0, -10), Vector2(9, -6)]
	var roots := [Vector2(-4, 9), Vector2(0, 8), Vector2(4, 9)]
	for i in 3:
		var a: Vector2 = c + (roots[i] as Vector2) * s
		var e: Vector2 = c + (ends[i] as Vector2) * s
		var mid := a.lerp(e, 0.5) + Vector2((ends[i] as Vector2).x * 0.12, 0) * s
		oline(qbez(a, mid, e, 6, false), 4.6 * s, gr, 1.4)
	shape(ell(c + Vector2(0, 11) * s, 9.5 * s, 5.5 * s), Color("#d8d4a0"), 1.4)
	for i in 3:
		var e: Vector2 = c + (ends[i] as Vector2) * s
		var dir := 1.0 if i != 0 else -1.0
		if i == 1:
			dir = 0.0
		# wedge head pointing up-and-out, red forked tongue
		var hw := PackedVector2Array([Vector2(-3.6, 1.8), Vector2(-3.0, -2.6), Vector2(0, -6.6), Vector2(3.0, -2.6), Vector2(3.6, 1.8)])
		var rot := dir * 0.45
		var hp := PackedVector2Array()
		for p in hw:
			hp.append(e + p.rotated(rot) * s)
		var tip := e + Vector2(0, -6.6).rotated(rot) * s
		var tdir := Vector2(0, -1).rotated(rot)
		oline(PackedVector2Array([tip, tip + tdir * 2.4]), 0.8, Color("#d02a20"), 0.0)
		oline(PackedVector2Array([tip + tdir * 2.4, tip + tdir * 3.6 + tdir.orthogonal() * 1.2]), 0.7, Color("#d02a20"), 0.0)
		oline(PackedVector2Array([tip + tdir * 2.4, tip + tdir * 3.6 - tdir.orthogonal() * 1.2]), 0.7, Color("#d02a20"), 0.0)
		shape(hp, gr, 1.2)
		for ex in [-1.5, 1.5]:
			fill(circ(e + Vector2(ex, -2.0).rotated(rot) * s, 0.9), GOLD)

static func _dragon() -> void:
	var red := Color("#b8321f")
	for sx in [-1.0, 1.0]:
		var horn := PackedVector2Array([Vector2(32 + sx * 4.5, 25), Vector2(32 + sx * 9.5, 21), Vector2(32 + sx * 12.5, 15.8),
			Vector2(32 + sx * 11.2, 21.6), Vector2(32 + sx * 8.5, 26.5)])
		shape(horn, BONE, 1.2)
	var head := PackedVector2Array([Vector2(24, 25), Vector2(29, 22.5), Vector2(35, 22.5), Vector2(40, 25), Vector2(42, 30.5),
		Vector2(38.5, 37), Vector2(35.5, 42.5), Vector2(28.5, 42.5), Vector2(25.5, 37), Vector2(22, 30.5)])
	fill(head, red)
	fill(PackedVector2Array([Vector2(26, 37), Vector2(38, 37), Vector2(35.5, 42.5), Vector2(28.5, 42.5)]), Color("#5a1a10"), head)
	outline(head, 1.5)
	# brow ridges, nostrils
	oline(PackedVector2Array([Vector2(25.5, 27.2), Vector2(30, 28.4)]), 1.0, Color("#7a1e12"), 0.0)
	oline(PackedVector2Array([Vector2(38.5, 27.2), Vector2(34, 28.4)]), 1.0, Color("#7a1e12"), 0.0)
	fill(circ(Vector2(30.4, 35.2), 0.7), INK)
	fill(circ(Vector2(33.6, 35.2), 0.7), INK)
	for sx in [-1.0, 1.0]:
		fill(ell(Vector2(32 + sx * 4.3, 30.6), 2.0, 1.3), GOLD)
		fill(ell(Vector2(32 + sx * 4.3, 30.6), 0.45, 1.2), INK)
	var flame := PackedVector2Array([Vector2(29.8, 42.2), Vector2(34.2, 42.2), Vector2(34.6, 44.2), Vector2(33.2, 46.2),
		Vector2(32.6, 45.0), Vector2(32, 47.6), Vector2(31.4, 45.0), Vector2(30.8, 46.2), Vector2(29.4, 44.2)])
	shape(flame, Color("#ff9a2a"), 1.0)
	fill(PackedVector2Array([Vector2(31.2, 42.6), Vector2(32.8, 42.6), Vector2(32, 45.2)]), GOLD)

## Wave-2 creature with no head drawn yet: three claw marks (never another creature's head).
static func _claws() -> void:
	for dx in [-5.0, 0.0, 5.0]:
		oline(PackedVector2Array([Vector2(28 + dx, 23), Vector2(34 + dx, 41)]), 2.2, Color("#7a2d1c"), 1.2)

# ================================================================== pips
const PIP_Y0 := 54.0
const PIP_Y1 := 66.0

static func _pip_x(type: String) -> float:
	match type:
		"army", "deserter": return 29.0
		"militia": return 30.0
		"caravan": return 40.0
		"bandit", "monster": return 32.0
	return 32.0

static func _paint_pips(cx: float, n: int, c: Color) -> Image:
	_rs = Raster.new(SIZE, int((PIP_Y1 - PIP_Y0) * R), Vector2(-PAD, PIP_Y0), R)
	var wdt := n * 6.0 + 4.0
	var x0 := cx - wdt * 0.5
	var cap := PackedVector2Array()
	for i in 9:
		var a := PI * 0.5 + PI * i / 8.0
		cap.append(Vector2(x0 + 4, 60) + Vector2(cos(a), sin(a)) * 4.0)
	for i in 9:
		var a := -PI * 0.5 + PI * i / 8.0
		cap.append(Vector2(x0 + wdt - 4, 60) + Vector2(cos(a), sin(a)) * 4.0)
	fill(cap, INK)
	for i in n:
		fill(circ(Vector2(x0 + 5 + 6 * i, 60), 2.2, 16), c)
	var img := _rs.to_image()
	_rs = null
	return img

# ================================================================== rasteriser
## Anti-aliased scanline rasteriser: even-odd polygon sets, SS sub-scanlines per row, exact horizontal span
## coverage. Colours are kept premultiplied in floats and turned into an RGBA8 image at the end.
class Raster:
	var w: int
	var h: int
	var org: Vector2
	var r: float
	var col := PackedFloat32Array()
	var cov := PackedFloat32Array()
	var aux := PackedFloat32Array()
	var row := PackedFloat32Array()
	var bx0 := 0
	var by0 := 0
	var bx1 := -1
	var by1 := -1

	func _init(pw: int, ph: int, origin: Vector2, res: float) -> void:
		w = pw
		h = ph
		org = origin
		r = res
		col.resize(w * h * 4)
		cov.resize(w * h)
		aux.resize(w * h)
		row.resize(w + 1)

	func _reset_bb() -> void:
		bx0 = w; by0 = h; bx1 = -1; by1 = -1

	## Max-accumulate the even-odd coverage of one contour set into cov.
	func accum(contours: Array) -> void:
		var cs := []
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		for c in contours:
			var pc := PackedVector2Array()
			pc.resize(c.size())
			for i in c.size():
				var p: Vector2 = (c[i] - org) * r
				pc[i] = p
				lo = lo.min(p)
				hi = hi.max(p)
			cs.append(pc)
		var iy0 := maxi(0, floori(lo.y))
		var iy1 := mini(h - 1, floori(hi.y))
		var ix0 := maxi(0, floori(lo.x))
		var ix1 := mini(w - 1, floori(hi.x))
		if iy0 > iy1 or ix0 > ix1:
			return
		bx0 = mini(bx0, ix0); by0 = mini(by0, iy0); bx1 = maxi(bx1, ix1); by1 = maxi(by1, iy1)
		var inv := 1.0 / SS
		var fw := float(w)
		var xs := PackedFloat32Array()
		for py in range(iy0, iy1 + 1):
			var any := false
			for s in SS:
				var sy := py + (s + 0.5) * inv
				xs.clear()
				for pc in cs:
					var n: int = pc.size()
					var a: Vector2 = pc[n - 1]
					for i in n:
						var b: Vector2 = pc[i]
						if (a.y <= sy) != (b.y <= sy):
							xs.append(a.x + (sy - a.y) / (b.y - a.y) * (b.x - a.x))
						a = b
				if xs.size() < 2:
					continue
				xs.sort()
				var k := 0
				while k + 1 < xs.size():
					var xa := clampf(xs[k], 0.0, fw)
					var xb := clampf(xs[k + 1], 0.0, fw)
					k += 2
					if xb <= xa:
						continue
					any = true
					var ia := floori(xa)
					var ib := floori(xb)
					if ia == ib:
						row[ia] += (xb - xa) * inv
					else:
						row[ia] += (ia + 1 - xa) * inv
						for i in range(ia + 1, ib):
							row[i] += inv
						row[ib] += (xb - ib) * inv
			if not any:
				continue
			var base := py * w
			for x in range(ix0, ix1 + 1):
				var v: float = row[x]
				if v > 0.0:
					row[x] = 0.0
					if v > 1.0:
						v = 1.0
					if v > cov[base + x]:
						cov[base + x] = v
			row[w] = 0.0

	func fill(shape: Array, c: Color, clip: Array, cut: Array) -> void:
		fill_union([shape], c, clip, cut)

	## Union (max coverage) of several even-odd shapes, painted in one colour; optional clip / cut shapes.
	func fill_union(pieces: Array, c: Color, clip: Array = [], cut: Array = []) -> void:
		var mode := 0
		if not clip.is_empty() or not cut.is_empty():
			_reset_bb()
			accum(clip if not clip.is_empty() else cut)
			var t := aux
			aux = cov
			cov = t
			mode = 1 if not clip.is_empty() else 2
		_reset_bb()
		for p in pieces:
			accum(p)
		if bx1 < bx0:
			return
		for y in range(by0, by1 + 1):
			for x in range(bx0, bx1 + 1):
				var i := y * w + x
				var a: float = cov[i]
				if a <= 0.0:
					continue
				if mode == 1:
					a *= aux[i]
				elif mode == 2:
					a *= 1.0 - aux[i]
				a *= c.a
				if a <= 0.0:
					continue
				var j := i * 4
				var ia := 1.0 - a
				col[j] = col[j] * ia + c.r * a
				col[j + 1] = col[j + 1] * ia + c.g * a
				col[j + 2] = col[j + 2] * ia + c.b * a
				col[j + 3] = col[j + 3] * ia + a
		cov.fill(0.0)
		if mode != 0:
			aux.fill(0.0)

	func to_image() -> Image:
		var bytes := PackedByteArray()
		bytes.resize(w * h * 4)
		for i in w * h:
			var j := i * 4
			var a: float = col[j + 3]
			if a <= 0.002:
				continue
			bytes[j] = clampi(int(col[j] / a * 255.0 + 0.5), 0, 255)
			bytes[j + 1] = clampi(int(col[j + 1] / a * 255.0 + 0.5), 0, 255)
			bytes[j + 2] = clampi(int(col[j + 2] / a * 255.0 + 0.5), 0, 255)
			bytes[j + 3] = clampi(int(a * 255.0 + 0.5), 0, 255)
		return Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, bytes)
