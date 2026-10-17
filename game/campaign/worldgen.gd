class_name WorldGen
extends RefCounted
## Procedural campaign map: terrain grid, five faction regions, towns and roads.
## Everything is derived from one seed and stored in the world dict as plain values
## (strings for grids, Vector2 for positions) so Game.save_game can serialize it.
##
## Grid strings are row-major, one char per cell: index = y * W + x.
##   terrain: g grass, f forest, h hills, m mountains, w water, b badlands, s silverwood
##   region:  0 middle, 1 north, 2 south, 3 east, 4 west, 5 southeast, 6 holds (v0.012)
##   road:    "1" road cell, "0" none

## Map size (war pick 5, Douglas: "Map stretched 1.5x"). The geography is laid out on the old 100 x 64 grid
## (BASE_W x BASE_H: region centres, noise, town spacing are in those units) and drawn STRETCH times larger in
## each direction at the same CELL size: 150 x 96 cells = 3600 x 2304 px. Same seed = the same lands, towns and
## roads, every distance 1.5x (march days between towns grow ~1.5x), the terrain no coarser.
## W, H and K are per world: set_size(STRETCH) at generation, use_world(w) on load (a save from before the
## stretch keeps its 100 x 64 map, K = 1).
const BASE_W := 100
const BASE_H := 64
const STRETCH := 1.5
const CELL := 24   # world px per cell
static var W := 150   # cells across (this world)
static var H := 96
static var K := 1.5   # cells per old (BASE) cell: W / BASE_W
static var gen_stretch := STRETCH   # what the next new world uses (tests and diagnostics compare with 1.0)

## World size (Douglas 12:27: "we do need the map to work with considerable more space ... think a large
## battlebrothers map, minimum"). One setting: how far the base geography is stretched. The towns, roads, patrols,
## caravans and lair caps follow the land AREA (TF = (stretch / STRETCH)^2), so the country looks as settled as the
## normal map, there is just more of it: the same town spacing, road reach and lair density in real cells (KD).
## Every town runs the full economy at every size (Douglas: no light model).
## WORLD_SIZE is the default for new campaigns; the New Campaign screen (ui/newgame.gd) sets gen_size (Douglas
## 12:55: "have both be toggleable for world size/simulation span"); tests and diagnostics set it too.
## ms_day: measured wall ms per simulated day of the years before (laptop, 120-day years; DEV_NOTES "World size"):
## the New Campaign screen's startup estimate. Normal and large over five years, huge over year 1 only.
const WORLD_SIZE := "large"   # Douglas 2026-10-06: Large is the default (normal and huge still in SIZES)
const SIZES := {
	"normal": {"stretch": 1.5, "label": "Normal", "towns": "15 towns", "ms_day": 89.0},   # 150 x 96 cells, 3,600 x 2,304 px
	"large": {"stretch": 2.6, "label": "Large", "towns": "about 45 towns", "ms_day": 249.0},   # 260 x 166 cells, 6,240 x 3,984 px (a large Battle Brothers map)
	"huge": {"stretch": 3.7, "label": "Huge", "towns": "about 90 towns", "ms_day": 465.0},     # 370 x 237 cells, 8,880 x 5,688 px
}
const SIZE_ORDER := ["normal", "large", "huge"]

## Wall seconds the years before should take at this size on the measured laptop (ms_day x days).
static func presim_est_sec(size: String, years: int) -> float:
	var ms := float(SIZES.get(size, SIZES[WORLD_SIZE]).get("ms_day", 250.0))
	return ms * float(years * 4 * Calendar.DAYS_PER_SEASON) / 1000.0
static var gen_size := WORLD_SIZE   # what the next new world uses
## Steppe peoples (the Dust-Wind Khanate) in the next new world; off: the Warrens settle the south-east instead.
static var steppe_enabled := false
static var TF := 1.0   # this world's land area / the normal map's (towns, patrols, caravans, lair caps scale by it)
static var KD := 1.5   # cells per BASE cell for spacing and reach (town spacing, road links): min(K, STRETCH)

## Stretch of the next new world: the chosen size's, or gen_stretch at the normal size (tests compare with 1.0).
static func gen_stretch_now() -> float:
	if gen_size != "normal" and SIZES.has(gen_size):
		return float(SIZES[gen_size]["stretch"])
	return gen_stretch

## Area factor of a world (old saves and the normal map: 1).
static func tf_of(w: Dictionary) -> float:
	return float(w.get("tf", 1.0))

## Regions (the region grid's chars are their indices). v0.012: the old east was split: the orcs keep the north-east
## ("east", centre moved up from y 32 to 26), the Eastern humans take the dry south-east ("southeast"); "holds" (the
## dwarves) has no centre: its land is carved around the holds in the mountains once the other towns stand
## (place_holds). Every older region keeps land; the north-east and south-east halves share what the east had.
const REGIONS := ["middle", "north", "south", "east", "west", "southeast", "holds"]
const VORONOI := ["middle", "north", "south", "east", "west", "southeast"]   # the regions laid out by distance to a centre
## In BASE cells (x K for this world's cells).
const REGION_CENTERS := {"middle": Vector2(50, 32), "north": Vector2(50, 9), "south": Vector2(50, 56),
	"east": Vector2(86, 26), "west": Vector2(14, 32), "southeast": Vector2(86, 52)}
## Douglas 12:45: "more villages for gobbies": the goblins (south, wealth 1) hold 5 small warrens (2 before); their
## non-capital warrens roll hamlet or village by the realm's wealth as before. No town is ever founded in play.
const TOWNS_PER_REGION := {"middle": 4, "north": 3, "south": 5, "east": 3, "west": 3, "southeast": 3}
## Dwarf holds per unit of land area (TF): 2 on the normal map, 5 on Large (as the spec asks: near the goblins'
## warrens' count there), 10 on Huge [ours]. Few: a small people in the mountains.
const HOLDS_PER_TF := 5.0 / 3.0
## A hold needs at least this many mountain cells (in BASE cells) within 4 BASE cells: it sits in the mountains [ours].
const HOLD_MIN_PEAKS := 6.0

const TERRAIN_NAMES := {"g": "grassland", "f": "forest", "h": "hills", "m": "mountains", "w": "water",
	"b": "badlands", "s": "silverwood"}
## Travel speed multiplier per terrain (0 = impassable).
const TERRAIN_SPEED := {"g": 1.0, "f": 0.6, "h": 0.6, "m": 0.0, "w": 0.0, "b": 0.8, "s": 0.65}
const ROAD_SPEED := 1.5

const NAME_PARTS := {
	"middle": [["Ash", "Bram", "Ced", "Dun", "Elm", "Fen", "Hollow", "Kings", "Marl", "Oak", "Red", "Stone", "Wex", "Thorn", "Mill", "Brook", "Wheat", "Gold"],
		["ford", "bury", "wick", "stead", "ham", "ton", "field", "mere", "gate", "bridge", "cross", "well"]],
	"northern": [["Hrafn", "Kol", "Ulf", "Sigur", "Ice", "Grim", "Frost", "Thor", "Vik", "Dal", "Skarp", "Ormr"],
		["heim", "stad", "fell", "by", "holm", "garth", "vik", "haug"]],
	"orc": [["Gor", "Krag", "Uz", "Mor", "Skul", "Thrag", "Bruk", "Gash", "Grol", "Durz"],
		["-Tusk", "grat", "mok", "ruk", "-Gor", "bash", "zag"]],
	"goblin": [["Skrag", "Nib", "Rat", "Mud", "Grub", "Snik", "Mire", "Muck", "Sniv"],
		["warren", "hole", "den", "burrow", "nook", "pit", "sump"]],
	"moon_elf": [["Sil", "Ith", "Lun", "Vael", "Ael", "Ysil", "Myr", "Cael", "Nim", "Eluv"],
		["ithe", "ara", "undel", "esse", "mir", "valen", "orrin", "aleth"]],
	"eastern": [["Kara", "Ak", "Altyn", "Kok", "Sary", "Ulug", "Temir", "Bay", "Ordu", "Kum", "Tash", "Yesil"],
		["balik", "kent", "kurgan", "tepe", "su", "kala", "bulak", "orda"]],
	"dwarf": [["Iron", "Stone", "Deep", "Anvil", "Copper", "Grey", "Ember", "Hammer", "Gold", "Coal", "Granite", "Under"],
		["hold", "delve", "deep", "forge", "hall", "mount", "vault", "gate"]],
}

## The dry eastern band (v0.012, spec 1 C): 0..1 at a BASE cell, rising east of x 64-76 and south of y 30-40 (the
## south-east: steppe and dry hills). Terrain dries there (less forest, more badlands and open grass) and a town
## with dryness >= economy dry_min has the "dry" climate whatever its latitude (EconGen.generate) [ours].
static func dryness(u: float, v: float) -> float:
	return smoothstep(64.0, 76.0, u) * smoothstep(30.0, 40.0, v)

## Dryness at a world position (this world's cells).
static func dryness_at(pos: Vector2) -> float:
	return dryness(pos.x / CELL / K, pos.y / CELL / K)

static func noise(seed_v: int, salt: int, freq: float, octaves: int = 4) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = (seed_v % 1000003) + salt
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = freq
	n.fractal_type = FastNoiseLite.FRACTAL_FBM
	n.fractal_octaves = octaves
	return n

## A new world: stretch x the base grid (generation calls this before anything else).
static func set_size(stretch: float) -> void:
	W = roundi(BASE_W * stretch)
	H = roundi(BASE_H * stretch)
	K = float(W) / BASE_W
	KD = minf(K, STRETCH)
	TF = maxf(1.0, pow(stretch / STRETCH, 2.0))

## The grid of a world built or loaded (w["w"], w["h"]; saves from before the stretch: 100 x 64).
static func use_world(w: Dictionary) -> void:
	W = int(w.get("w", BASE_W))
	H = int(w.get("h", BASE_H))
	K = float(W) / BASE_W
	KD = minf(K, STRETCH)
	TF = tf_of(w)

## World px size of this world's map.
static func map_px() -> Vector2:
	return Vector2(W, H) * CELL

static func region_faction(region: String) -> String:
	for fid in DB.factions:
		if DB.factions[fid].get("region", "") == region:
			if fid == "eastern_khanate" and not steppe_enabled:
				return "goblin_warren"
			return fid
	return "middle_kingdom"

static func idx(x: int, y: int) -> int:
	return y * W + x

static func cell_of(pos: Vector2) -> Vector2i:
	return Vector2i(clampi(int(pos.x / CELL), 0, W - 1), clampi(int(pos.y / CELL), 0, H - 1))

static func cell_center(c: Vector2i) -> Vector2:
	return Vector2((c.x + 0.5) * CELL, (c.y + 0.5) * CELL)

static func passable_char(t: String) -> bool:
	return TERRAIN_SPEED.get(t, 0.0) > 0.0

# ------------------------------------------------------------------ terrain
static func gen_terrain(world: Dictionary, seed_v: int, rng: RandomNumberGenerator) -> void:
	var elev := noise(seed_v, 11, 0.05, 5)
	var moist := noise(seed_v, 23, 0.07, 3)
	var warp_x := noise(seed_v, 37, 0.06, 2)
	var warp_y := noise(seed_v, 41, 0.06, 2)
	var centers := {}
	for r in VORONOI:
		var c: Vector2 = REGION_CENTERS[r]
		centers[r] = c + Vector2(rng.randf_range(-4, 4), rng.randf_range(-3, 3)) if r != "middle" else c
	var terr := PackedStringArray(); terr.resize(W * H)
	var reg := PackedStringArray(); reg.resize(W * H)
	for y in H:
		for x in W:
			var u := x / K; var v := y / K   # in BASE cells: the same lands at every map size
			var wp := Vector2(u + warp_x.get_noise_2d(u, v) * 9.0, v + warp_y.get_noise_2d(u, v) * 7.0)
			var best := "middle"
			var bd := INF
			for r in VORONOI:
				var d: float = wp.distance_to(centers[r]) * (0.85 if r == "middle" else 1.0)
				if d < bd:
					bd = d; best = r
			var ri := REGIONS.find(best)
			var e := (elev.get_noise_2d(u, v) + 1.0) * 0.5
			var m := (moist.get_noise_2d(u, v) + 1.0) * 0.5
			m -= 0.25 * dryness(u, v)   # v0.012: the dry eastern band
			# coast: fall off to sea near the map edges
			var edge := minf(minf(x, W - 1 - x) / K / 7.0, minf(y, H - 1 - y) / K / 5.0)
			edge = clampf(edge, 0.0, 1.0)
			e = lerpf(0.05, e, smoothstep(0.0, 1.0, edge))
			match best:
				"north": e += 0.07
				"east", "southeast": e += 0.02
				"middle": e -= 0.03
				"south": e -= 0.01
			var t := "g"
			if e < 0.28:
				t = "w"
			elif e > 0.72:
				t = "m"
			elif e > (0.6 if best == "north" else 0.64):
				t = "h"
			else:
				match best:
					"north": t = "f" if m > 0.48 else "g"
					"south":
						if m < 0.52: t = "b"
						elif m > 0.66: t = "f"
					"west": t = "s" if m > 0.56 else ("f" if m > 0.5 else "g")
					"east":
						if m > 0.68: t = "f"
						elif m < 0.36: t = "b"
					"southeast":   # steppe: open grass, dry badlands, a little wood where it is wettest
						if m > 0.55: t = "f"
						elif m < 0.18: t = "b"
					_: t = "f" if m > 0.6 else "g"
			terr[idx(x, y)] = t
			reg[idx(x, y)] = str(ri)
	world["terrain"] = "".join(terr)
	world["region"] = "".join(reg)
	world["road"] = "0".repeat(W * H)

## Cells reachable from the middle of the map (the main continent). Returns PackedByteArray mask.
static func main_landmass(world: Dictionary) -> PackedByteArray:
	var terr: String = world["terrain"]
	var mask := PackedByteArray(); mask.resize(W * H)
	var start := Vector2i(W / 2, H / 2)
	# nearest passable cell to the centre
	var best := -1; var bd := 1 << 30
	for y in H:
		for x in W:
			if passable_char(terr[idx(x, y)]):
				var d: int = absi(x - start.x) + absi(y - start.y)
				if d < bd:
					bd = d; best = idx(x, y)
	if best < 0:
		return mask
	var stack := [best]
	mask[best] = 1
	while not stack.is_empty():
		var i: int = stack.pop_back()
		var cx := i % W; var cy := i / W
		for dxy in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nx: int = cx + dxy.x; var ny: int = cy + dxy.y
			if nx < 0 or ny < 0 or nx >= W or ny >= H:
				continue
			var j := idx(nx, ny)
			if mask[j] == 0 and passable_char(terr[j]):
				mask[j] = 1
				stack.append(j)
	return mask

# ------------------------------------------------------------------ towns
static func town_name(rng: RandomNumberGenerator, culture: String, used: Dictionary) -> String:
	var parts: Array = NAME_PARTS.get(culture, NAME_PARTS["middle"])
	for _i in 30:
		var n: String = parts[0][rng.randi() % parts[0].size()] + parts[1][rng.randi() % parts[1].size()]
		if not used.has(n):
			used[n] = true
			return n
	return "Town %d" % used.size()

static func place_towns(world: Dictionary, rng: RandomNumberGenerator) -> void:
	var terr: String = world["terrain"]
	var reg: String = world["region"]
	var land := main_landmass(world)
	var towns := {}
	var cells := []   # Vector2i of placed towns
	var used_names := {}
	var n := 0
	for r in VORONOI:
		var fid := region_faction(r)
		var fac: Dictionary = DB.factions[fid]
		var fw := int(fac.get("wealth", 2))
		var want: int = roundi(TOWNS_PER_REGION[r] * TF)   # world size: as many towns to the acre at every size
		var placed := 0
		var c0: Vector2 = REGION_CENTERS[r] * K
		var rim := roundi(2 * K)
		var gap := 9.0 * KD   # town spacing in real cells (13.5 cells on the normal map)
		var near := {}   # spatial hash of placed towns (cells of `gap`): the spacing check looks at 3 x 3 buckets
		for o in cells:
			var b0 := Vector2i(floori(o.x / gap), floori(o.y / gap))
			if not near.has(b0):
				near[b0] = []
			(near[b0] as Array).append(o)
		for attempt in roundi(600 * TF):
			if placed >= want:
				break
			var spread := (6.0 + attempt * 0.03 / TF) * K
			var c := Vector2i(roundi(c0.x + rng.randfn(0, spread)), roundi(c0.y + rng.randfn(0, spread * 0.7)))
			if c.x < rim or c.y < rim or c.x >= W - rim or c.y >= H - rim:
				continue
			var i := idx(c.x, c.y)
			if land[i] == 0 or reg[i] != str(REGIONS.find(r)):
				continue
			var ok := true
			var bc := Vector2i(floori(c.x / gap), floori(c.y / gap))
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					for o in near.get(bc + Vector2i(dx, dy), []):
						if Vector2(o).distance_to(Vector2(c)) < gap:
							ok = false; break
			if not ok:
				continue
			cells.append(c)
			if not near.has(bc):
				near[bc] = []
			(near[bc] as Array).append(c)
			var capital := placed == 0
			var size: int
			if capital:
				size = clampi(1 + fw, 2, 4)
			else:
				size = clampi(rng.randi_range(0, clampi(fw, 1, 3)), 0, 3)
			var wealth := clampi(fw + (1 if capital else rng.randi_range(-1, 0)), 1, 5)
			var id := "t%d" % n
			n += 1
			towns[id] = {"id": id, "name": town_name(rng, fac.get("culture", "middle"), used_names),
				"pos": cell_center(c), "faction": fid, "region": r, "culture": fac.get("culture", "middle"),
				"size": size, "wealth": wealth, "capital": capital,
				"specialty": pick_specialty(terr, c, capital, fw, size, r, rng),
				"crafters": {}, "healer": {}, "shop": [], "prices": {}, "material_prices": {},
				"recruits": [], "contracts": [], "next_refresh": 0.0, "neighbours": []}
			placed += 1
	place_holds(world, rng, land, towns, cells, used_names, n)
	world["towns"] = towns

## v0.012 (spec 1 B): the dwarves' holds, in the mountains on good ore, placed after every other realm's towns: the
## passable cells of the main land with the most mountain (and hill) around them (4 BASE cells, as the ore deposits
## and the mining specialty read it), at least HOLD_MIN_PEAKS mountain cells, best first (a little jitter), the
## normal town spacing from every town. HOLDS_PER_TF x TF of them (2 / 5 / 10). Their land ("holds" in the region
## grid) is the mountains and hills around each hold. Fewer holds when the mountains run out (never forced).
static func place_holds(world: Dictionary, rng: RandomNumberGenerator, land: PackedByteArray, towns: Dictionary, cells: Array,
		used_names: Dictionary, n0: int) -> void:
	var fid := region_faction("holds")
	if not DB.factions.has(fid) or String(DB.factions[fid].get("region", "")) != "holds":
		return
	var fac: Dictionary = DB.factions[fid]
	var fw := int(fac.get("wealth", 3))
	var want := maxi(1, roundi(HOLDS_PER_TF * TF))
	var terr: String = world["terrain"]
	# summed-area tables of mountain and hill cells (a window count is four reads)
	var Wp := W + 1
	var sm := PackedInt32Array(); sm.resize(Wp * (H + 1))
	var sh := PackedInt32Array(); sh.resize(Wp * (H + 1))
	for y in H:
		var rm := 0; var rh := 0
		for x in W:
			var t := terr[idx(x, y)]
			if t == "m": rm += 1
			elif t == "h": rh += 1
			sm[(y + 1) * Wp + x + 1] = sm[y * Wp + x + 1] + rm
			sh[(y + 1) * Wp + x + 1] = sh[y * Wp + x + 1] + rh
	var rr := roundi(4 * K)
	var kk := K * K
	var rim := roundi(2 * K)
	var cands := []
	for y in range(rim, H - rim):
		for x in range(rim, W - rim):
			var i := idx(x, y)
			if land[i] == 0 or not (terr[i] in ["h", "g", "f", "b"]):
				continue
			var x0 := maxi(0, x - rr); var y0 := maxi(0, y - rr); var x1 := mini(W, x + rr + 1); var y1 := mini(H, y + rr + 1)
			var mc := float(sm[y1 * Wp + x1] - sm[y0 * Wp + x1] - sm[y1 * Wp + x0] + sm[y0 * Wp + x0]) / kk
			if mc < HOLD_MIN_PEAKS:
				continue
			var hc := float(sh[y1 * Wp + x1] - sh[y0 * Wp + x1] - sh[y1 * Wp + x0] + sh[y0 * Wp + x0]) / kk
			cands.append([(2.0 * mc + 1.2 * hc) * rng.randf_range(0.85, 1.15), x, y])
	cands.sort_custom(func(a, b): return float(a[0]) > float(b[0]))
	var gap := 9.0 * KD
	var near := {}
	for o in cells:
		var b0 := Vector2i(floori(o.x / gap), floori(o.y / gap))
		if not near.has(b0):
			near[b0] = []
		(near[b0] as Array).append(o)
	var holds := []
	var n := n0
	for cd in cands:
		if holds.size() >= want:
			break
		var c := Vector2i(int(cd[1]), int(cd[2]))
		var bc := Vector2i(floori(c.x / gap), floori(c.y / gap))
		var ok := true
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				for o in near.get(bc + Vector2i(dx, dy), []):
					if Vector2(o).distance_to(Vector2(c)) < gap:
						ok = false; break
		if not ok:
			continue
		cells.append(c)
		if not near.has(bc):
			near[bc] = []
		(near[bc] as Array).append(c)
		var capital := holds.is_empty()   # the richest mountains: the king's hold
		var size: int = clampi(1 + fw, 2, 4) if capital else clampi(rng.randi_range(0, clampi(fw, 1, 3)), 0, 3)
		var id := "t%d" % n
		n += 1
		towns[id] = {"id": id, "name": town_name(rng, fac.get("culture", "dwarf"), used_names),
			"pos": cell_center(c), "faction": fid, "region": "holds", "culture": fac.get("culture", "dwarf"),
			"size": size, "wealth": clampi(fw + (1 if capital else rng.randi_range(-1, 0)), 1, 5), "capital": capital,
			"specialty": "mining",   # every hold is a mine (the ore deposits follow: EconGen gives a mining town 2-3)
			"crafters": {}, "healer": {}, "shop": [], "prices": {}, "material_prices": {},
			"recruits": [], "contracts": [], "next_refresh": 0.0, "neighbours": []}
		holds.append(c)
	# the holds' land: the mountains and hills around each (never past half the town spacing: other realms' towns
	# keep their own cells), and the hold's own cell
	if holds.is_empty():
		return
	var reg := (world["region"] as String).to_ascii_buffer()
	var hc_ch := str(REGIONS.find("holds")).unicode_at(0)
	var cr := minf(4.0 * K, gap * 0.5)
	var cri := ceili(cr)
	for hc in holds:
		var c: Vector2i = hc
		for dy in range(-cri, cri + 1):
			for dx in range(-cri, cri + 1):
				var x: int = c.x + dx; var y: int = c.y + dy
				if x < 0 or y < 0 or x >= W or y >= H or Vector2(dx, dy).length() > cr:
					continue
				var t := terr[idx(x, y)]
				if t == "m" or t == "h" or Vector2(dx, dy).length() <= 1.5 * K:
					if t != "w":
						reg[idx(x, y)] = hc_ch
	world["region"] = reg.get_string_from_ascii()

static func pick_specialty(terr: String, c: Vector2i, capital: bool, fw: int, size: int, region: String, rng: RandomNumberGenerator) -> String:
	if capital:
		return "military" if fw <= 2 else "trade"
	var s := {"mining": 0.0, "timber": 0.0, "farming": 0.0, "trade": 0.0, "herding": 0.0}
	var rr := roundi(4 * K)   # 4 BASE cells around the town
	for dy in range(-rr, rr + 1):
		for dx in range(-rr, rr + 1):
			var x := c.x + dx; var y := c.y + dy
			if x < 0 or y < 0 or x >= W or y >= H:
				continue
			match terr[idx(x, y)]:
				"h": s["mining"] += 1.2
				"m": s["mining"] += 2.0
				"b": s["mining"] += 0.6
				"f", "s": s["timber"] += 1.0
				"g":
					s["farming"] += 0.8
					if region in ["north", "east", "southeast"]:
						s["herding"] += 0.6
				"w":
					if size >= 1:
						s["trade"] += 0.8
	var best := "farming"; var bv := -1.0
	for k in s:
		var v: float = s[k] * rng.randf_range(0.8, 1.2)
		if v > bv:
			bv = v; best = k
	return best

# ------------------------------------------------------------------ roads
static func make_astar(world: Dictionary, for_roads: bool) -> AStarGrid2D:
	var a := AStarGrid2D.new()
	a.region = Rect2i(0, 0, W, H)
	a.cell_size = Vector2(CELL, CELL)
	a.offset = Vector2(CELL * 0.5, CELL * 0.5)
	a.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	a.default_compute_heuristic = AStarGrid2D.HEURISTIC_EUCLIDEAN
	a.update()
	var terr: String = world["terrain"]
	var road: String = world.get("road", "")
	for y in H:
		for x in W:
			var i := idx(x, y)
			var t := terr[i]
			var sp: float = TERRAIN_SPEED.get(t, 0.0)
			if sp <= 0.0:
				a.set_point_solid(Vector2i(x, y), true)
				continue
			if for_roads:
				# roads prefer open ground and reuse existing roads
				var w := 1.0 / sp
				if road != "" and road[i] == "1":
					w = 0.35
				a.set_point_weight_scale(Vector2i(x, y), w * w)
			else:
				if road != "" and road[i] == "1":
					sp *= ROAD_SPEED
				a.set_point_weight_scale(Vector2i(x, y), 1.0 / sp)
	return a

static func build_roads(world: Dictionary, rng: RandomNumberGenerator) -> void:
	var towns: Dictionary = world["towns"]
	var ids := towns.keys()
	ids.sort_custom(func(a, b): return int(a.substr(1)) < int(b.substr(1)))
	# Minimum spanning tree (Prim) + a few short extra links.
	# Prim with each outside town's nearest tree town kept (O(n^2), was O(n^3): world size). Ties go to the town that
	# joined the tree first, as the plain triple loop picked.
	var edges := []
	var in_tree := {ids[0]: true}
	var key := {}   # town outside the tree -> [distance to the tree, tree town, join order of that town]
	var order := 0
	for b in ids:
		if b != ids[0]:
			key[b] = [towns[ids[0]]["pos"].distance_to(towns[b]["pos"]), ids[0], 0]
	while in_tree.size() < ids.size():
		var nb := ""; var bd := INF; var bo := 1 << 30
		for b in ids:
			if in_tree.has(b):
				continue
			var k: Array = key[b]
			if float(k[0]) < bd or (float(k[0]) == bd and int(k[2]) < bo):
				bd = float(k[0]); bo = int(k[2]); nb = b
		if nb == "":
			break
		in_tree[nb] = true
		order += 1
		edges.append([key[nb][1], nb])
		for b in ids:
			if in_tree.has(b):
				continue
			var d: float = towns[nb]["pos"].distance_to(towns[b]["pos"])
			if d < float(key[b][0]):
				key[b] = [d, nb, order]
	var have := {}
	for e in edges:
		have[[e[0], e[1]]] = true
		have[[e[1], e[0]]] = true
	for a in ids:
		for b in ids:
			if int(a.substr(1)) >= int(b.substr(1)):
				continue
			var d: float = towns[a]["pos"].distance_to(towns[b]["pos"])
			if d < CELL * 15 * KD and rng.randf() < 0.45:
				if not have.has([a, b]):
					edges.append([a, b])
					have[[a, b]] = true
					have[[b, a]] = true
	var roads := []
	var road_chars := (world["road"] as String).to_ascii_buffer()
	var astar := make_astar(world, true)
	for e in edges:
		var pa := cell_of(towns[e[0]]["pos"]); var pb := cell_of(towns[e[1]]["pos"])
		var cells: Array[Vector2i] = astar.get_id_path(pa, pb)
		if cells.size() < 2:
			continue
		var pts := []
		for c in cells:
			road_chars[idx(c.x, c.y)] = "1".unicode_at(0)
			astar.set_point_weight_scale(c, 0.35 * 0.35)   # later roads reuse this one
			pts.append(cell_center(c))
		roads.append({"a": e[0], "b": e[1], "pts": smooth(pts)})
	world["road"] = road_chars.get_string_from_ascii()
	world["roads"] = roads

static func smooth(pts: Array) -> Array:
	if pts.size() < 3:
		return pts
	var out := [pts[0]]
	for i in pts.size() - 1:
		var a: Vector2 = pts[i]; var b: Vector2 = pts[i + 1]
		out.append(a.lerp(b, 0.25)); out.append(a.lerp(b, 0.75))
	out.append(pts[-1])
	return out
