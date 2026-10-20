class_name Plots
extends RefCounted
## Land plots and the town's own buildings (docs/specs/barge/07-land-map.md; 13-addendum-1 part A).
##
## A town's land is a packed set of PLOT records, one per map tile: grid x/y, acres (default 5), use, owner,
## tenant, flags, woodland stand and a short history. Nothing is drawn that is not a plot, and the farm plots
## are DERIVED from the land the families and the town estate hold: plot acres of a crop held by a family =
## that family's f.land[crop], always. Families.move_land (the one place land changes hands: the land market,
## forced sales, seizures, a house dying out) calls land_moved here, which moves whole plots (splitting one
## only for the odd acres) and writes a history line on each.
##
## e["plots"] = P (saved with the world; JSON brings the columns back as Arrays, _fix packs them again):
##   gw, gh, g PackedInt32Array (cell -> plot id, -1 = beyond the town's land)
##   columns, one entry per plot (PackedInt32Array): x, y, ac (acres), use, sub, own, ten, fl
##     use  FIELD/ORCHARD/VINEYARD (sub = crop index into P.crops) | PASTURE | WOOD | HOME | YARD/MINE (sub = biz id)
##          | WASTE (sub 1 = hills) | ROAD (sub 1 = gate) | WATER | WALL | STATE (sub = index into P.bld) | COMMON
##          | SQUARE | LOT (an empty house plot)
##     own  family id; 0 = the town (estate / state); -1 = the market (a house for sale)
##     ten  homes: the family renting it from the town; pasture: the family whose herd grazes it; else -1
##     fl   F_SEIZED | F_FELLED | F_CLEARING | F_SALE
##   st PackedFloat32Array: woodland stand (1 = a full wood; felling takes it down, regrowth brings it back)
##   h [[day, text], ...] per plot (newest last, HIST_MAX), crops [crop key], bld [{k, n, p, h}]
##   heads {fid: head pid} (inheritance lines), wood_seen (the town's wood ledger at the last felling)
##   cl {p, done, need} the plot the public works are clearing, overcut (loads cut beyond the town's woods)
##   tot (cached totals, rebuilt when dirty)
## The daily pass (daily()) does one town in seven each day: felling from the wood the cutters really made,
## regrowth, clearing with the public works crew's real days, and the weekly match of homes, yards and grazing.

const ACRES := 5
const PLOT_CAP := 1500

const FIELD := 0
const ORCHARD := 1
const VINEYARD := 2
const PASTURE := 3
const WOOD := 4
const HOME := 5
const YARD := 6
const MINE := 7
const WASTE := 8
const ROAD := 9
const WATER := 10
const WALL := 11
const STATE := 12
const COMMON := 13
const SQUARE := 14
const LOT := 15
const USE_NAMES := ["field", "orchard", "vineyard", "pasture", "woodland", "home", "business yard", "mine or quarry",
	"wasteland", "road", "river or coast", "wall", "town building", "common land", "market square", "empty lot"]
const LAND_USES := [FIELD, ORCHARD, VINEYARD]

const TOWN := 0
const MARKET := -1

const F_SEIZED := 1
const F_FELLED := 2
const F_CLEARING := 4
const F_SALE := 8

const DENSE := 0.7               # [ours] stand at or above: dense wood
const THIN := 0.3                # [ours] at or above: thinned; below it a felled plot is still regrowing
const FELLED_AT := 0.08          # [ours] cut below this and the plot is felled
const LOADS_PER_ACRE := 300.0    # [ours] loads of cut wood in an acre of full wood
const REGROW_DAY := 0.0006       # [ours] stand regained a day: ~4 years to thin wood again, ~13 to dense
const CLEAR_DAYS_ACRE := 20.0    # [ours] worker-days to grub out the stumps of one felled acre for the plough
const CLEAR_SHARE := 0.5         # [ours] share of the public works crew's days spent clearing while a plot is open
const AUTO_CLEAR := true         # the public works clear felled plots that lie by the fields
const PASTURE_ACRES := {"cattle": 1.0, "sheep": 0.3, "goats": 0.3, "pigs": 0.15, "horses": 1.2, "donkeys": 0.6}   # [ours] grazing per head
const HIST_MAX := 6
const NO_YARD := ["collector", "estate", "works", "academy"]   # town rows housed in the hall, the shelter and the research house, or working the fields
const EDGE_YARD := ["mine", "quarry"]

const KINDS := ["keep", "hall", "barracks", "armory", "granary", "shelter", "jail", "mint"]
const KIND_WORDS := {"keep": "keep", "hall": "town hall", "barracks": "barracks", "armory": "armory", "granary": "granary",
	"shelter": "shelter", "jail": "jail", "mint": "mint"}
## Same roles for every race, its own names (addendum A).
const BUILDING_NAMES := {
	"middle": {"keep": "the keep", "hall": "the town hall", "barracks": "the barracks", "armory": "the armory", "granary": "the granary",
		"shelter": "the shelter", "jail": "the jail", "mint": "the mint"},
	"northern": {"keep": "the jarl's hall", "hall": "the thing-house", "barracks": "the hearth-house", "armory": "the weapon-house",
		"granary": "the grain store", "shelter": "the alms-house", "jail": "the lock-house", "mint": "the mint"},
	"orc": {"keep": "the warchief's hold", "hall": "the war-hall", "barracks": "the war-pen", "armory": "the iron-hall",
		"granary": "the meat pit", "shelter": "the scrap-hall", "jail": "the cage", "mint": "the tribute-forge"},
	"goblin": {"keep": "the warren den", "hall": "the whip-hall", "barracks": "the sleeping-heap", "armory": "the knife-cache",
		"granary": "the rot-store", "shelter": "the drip-hole", "jail": "the pit", "mint": "the hoard-hole"},
	"eastern": {"keep": "the bey's great tent", "hall": "the kurultai tent", "barracks": "the keshig camp", "armory": "the quiver house",
		"granary": "the grain pits", "shelter": "the guest tents", "jail": "the stocks", "mint": "the khan's mint"},
	"dwarf": {"keep": "the baron's hall", "hall": "the hall of records", "barracks": "the guard hall", "armory": "the armor vault",
		"granary": "the deep larder", "shelter": "the alms hall", "jail": "the cells", "mint": "the coin forge"},
	"moon_elf": {"keep": "the moon lodge", "hall": "the council lodge", "barracks": "the warden hall", "armory": "the blade hall",
		"granary": "the seed vault", "shelter": "the hospice", "jail": "the quiet cell", "mint": "the silver mint"}}

const COLS := ["x", "y", "ac", "use", "sub", "own", "ten", "fl"]

# ================================================================== access
## The town's plots, laid out on first use (older saves, towns made after world gen) and packed after a load.
static func of(town: Dictionary) -> Dictionary:
	if not TownEcon.has_econ(town):
		return {}
	var e: Dictionary = town["econ"]
	if not e.has("plots"):
		layout(Game.world, town)
	return _p(e)

static func _p(e: Dictionary) -> Dictionary:
	var P: Dictionary = e.get("plots", {})
	if P.is_empty():
		return P
	if not (P["x"] is PackedInt32Array):
		_fix(P)
	return P

## After a load: JSON gives the columns back as Arrays of floats; pack them again and rebuild the totals.
static func _fix(P: Dictionary) -> void:
	for k in COLS + ["g"]:
		var a := PackedInt32Array()
		for v in P.get(k, []):
			a.append(int(v))
		P[k] = a
	var s := PackedFloat32Array()
	for v in P.get("st", []):
		s.append(float(v))
	P["st"] = s
	for k in ["gw", "gh", "clear", "wood_seen", "drift", "v"]:
		P[k] = int(P.get(k, -1 if k == "clear" else 0))
	for b in P.get("bld", []):
		b["p"] = int(b["p"])
	P.erase("tot")
	P["dirty"] = true

static func count(P: Dictionary) -> int:
	return (P["x"] as PackedInt32Array).size()

## World gen: every town's plots, read from the land, homes, businesses and herds the economy made (one call at
## the end of CampaignWorld.generate).
static func init_world(game) -> void:
	var w: Dictionary = game.world
	var ids: Array = w.get("towns", {}).keys()
	ids.sort()
	for tid in ids:
		init_town(game, String(tid))

## One original initial town pass, shared by synchronous and staged generation.
static func init_town(game, tid: String) -> void:
	var w: Dictionary = game.world
	var t: Dictionary = w["towns"][tid]
	if TownEcon.has_econ(t):
		layout(w, t)
		# Plot rotation is now known. Reconcile the initial jobs against those
		# fields and the registered forces before the campaign starts.
		var initial_businesses: int = t["econ"]["biz"].size()
		Families.assign_all(t["econ"])
		if t["econ"]["biz"].size() != initial_businesses:
			_sync_yards(t["econ"], t["econ"]["plots"], 0.0)
			_dirty(t["econ"]["plots"])
		for f in t["econ"]["fams"]:
			Persons.track_jobs(t["econ"], f, 0.0)

# ================================================================== layout (world gen)
## Lays the town out in rings by its real terrain: the town's own buildings, the market square, homes and
## business yards in the middle; the wall; fields, orchards and vineyards (one wedge per holder); common land;
## pasture; woodland toward the forest, mines and rough hills toward the hills at the edge. Roads run out toward
## the towns the roads lead to; a river or the shore cuts across on the water side.
static func layout(w: Dictionary, town: Dictionary) -> Dictionary:
	var e: Dictionary = town["econ"]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([int(w.get("seed", 0)), String(town.get("id", "")), "plots"])
	var P := {"v": 1, "crops": [], "bld": [], "heads": {}, "clear": -1, "cl_done": 0.0, "overcut": 0.0,
		"wood_seen": int(e.get("led", {}).get("made", {}).get("wood", 0)), "dirty": true, "drift": 0}
	var cul := String(e.get("culture", "middle"))
	var fams: Array = e["fams"]
	# ---------------------------------------------------------------- the town's own buildings
	var kinds := ["keep", "hall", "barracks", "armory", "granary", "shelter", "jail"]
	if town.get("capital", false) or String(town.get("specialty", "")) == "mining":
		kinds.append("mint")
	if e.has("academy"):
		kinds.append("academy")   # v0.012: the state's research house, a state building of the capital
	var names: Dictionary = BUILDING_NAMES.get(cul, BUILDING_NAMES["middle"])
	var state_items := []
	for i in kinds.size():
		var bn: String = Academy.the_name(e) if kinds[i] == "academy" else String(names[kinds[i]])
		(P["bld"] as Array).append({"k": kinds[i], "n": bn, "p": -1, "h": []})
		state_items.append([STATE, i, TOWN, -1, 1, 0])
	state_items.append([SQUARE, 0, TOWN, -1, 2, 0])
	# ---------------------------------------------------------------- homes and yards, family by family
	var core := []
	# Reserve additional five-acre town lots before the grid is laid out.
	for i in maxi(2, int(ceil(float(e["homes"]) / 30))): core.append([LOT, 0, TOWN, -1, ACRES, 0])
	var biz: Array = e.get("biz", [])
	var edge_yards := []
	for f in fams:
		if f.get("gone", false) or f.get("estate", false):
			continue
		var fid := int(f["id"])
		if f.has("lodging"): continue
		var rent := mini(int(f.get("rent", 0)), int(f["homes"]))
		for i in maxi(0, int(f["homes"]) - rent):
			core.append([HOME, 0, fid, -1, 1, 0])
		for i in rent:
			core.append([HOME, 0, TOWN, fid, 1, 0])
		for bid in f.get("owns", []):
			_yard_item(biz[int(bid)], fid, core, edge_yards)
	for i in int(fams[0].get("homes", 0)):
		core.append([HOME, 0, TOWN, -1, 1, 0])
	for i in int(e.get("stock", {}).get("home", 0)):
		core.append([HOME, 0, MARKET, -1, 1, 0])
	for b in biz:
		if int(b["owner"]) < 0:
			_yard_item(b, TOWN, core, edge_yards)
	# ---------------------------------------------------------------- land: every holding in whole plots
	var land := []
	var land_total := 0
	for f in fams:
		if f.get("gone", false):
			continue
		var ks: Array = (f["land"] as Dictionary).keys()
		ks.sort()
		for c in ks:
			var a := int(f["land"][c])
			land_total += a
			var ci := _crop_index(P, String(c))
			var use := crop_use(e, String(c))
			while a > 0:
				var n := mini(ACRES, a)
				land.append([use, ci, int(f["id"]), -1, n, 0])
				a -= n
	var common := maxi(0, int(e.get("territory", land_total)) - land_total)
	var common_items := []
	while common > 0:
		var n2 := mini(ACRES, common)
		common_items.append([COMMON, 0, TOWN, -1, n2, 0])
		common -= n2
	# ---------------------------------------------------------------- pasture, woods, mines and hills
	var terr := _terrain_dirs(w, town)
	var graze := 0.0
	for a2 in e.get("herd", {}):
		graze += float(e["herd"][a2]) * float(PASTURE_ACRES.get(a2, 0.5))
	if e.has("hd"):   # herds as records: every grazing herd (a herder's business too)
		graze = Herds.graze_acres(e)
	var n_past := clampi(int(ceil(graze / ACRES)), 1 if graze > 0.0 else 0, 260)
	var tt: Dictionary = e.get("terrain", {})
	var n_wood := clampi(6 + 3 * int(tt.get("forest_cells", terr["forest"])) + (30 if String(town.get("specialty", "")) == "timber" else 0), 6, 200)
	var n_hill := clampi(int(tt.get("hill_cells", terr["hills"])), 0, 60)
	var base_n := state_items.size() + core.size() + land.size() + common_items.size() + n_past + n_wood + n_hill + edge_yards.size()
	var spare := PLOT_CAP - 120 - base_n   # room left for walls, roads and water
	if spare < 0:   # an outsize town: fewer woods and pasture tiles, never fewer land plots
		var cut := -spare
		var dw := mini(cut, n_wood - 6); n_wood -= dw; cut -= dw
		var dp := mini(cut, maxi(0, n_past - 1)); n_past -= dp; cut -= dp
		var dh := mini(cut, n_hill); n_hill -= dh
	var edge := []
	for i in n_wood:
		edge.append([WOOD, 0, TOWN, -1, ACRES, 0])
	var walled := int(town.get("size", 0)) >= 1
	# ---------------------------------------------------------------- the grid
	var items_n := state_items.size() + core.size() + land.size() + common_items.size() + n_past + edge.size() + edge_yards.size() + n_hill
	var S := int(ceil(sqrt(float(items_n) * 1.5))) + 3
	for _try in 6:
		if _place(P, e, town, rng, S, terr, walled, state_items, core, land, common_items, n_past, edge, edge_yards, n_hill):
			break
		S += 3
	# woods: full, but the nearest fifth already thinned by the cutters of earlier years
	var wl := []
	for i in count(P):
		if int(P["use"][i]) == WOOD:
			wl.append(i)
	var cx := float(P["gw"]) * 0.5; var cy := float(P["gh"]) * 0.5
	wl.sort_custom(func(a, b): return Vector2(P["x"][a] - cx, P["y"][a] - cy).length() < Vector2(P["x"][b] - cx, P["y"][b] - cy).length())
	for k in wl.size():
		P["st"][wl[k]] = rng.randf_range(0.35, 0.62) if k < wl.size() / 5 else rng.randf_range(0.82, 1.0)
	e["plots"] = P
	CropRotation.ensure(e, P, 0.0)
	_sync_grazing(e, P)
	_mark_heads(e, P, false)
	_dirty(P)
	return P

static func _yard_item(b: Dictionary, owner: int, core: Array, edge_yards: Array) -> void:
	if NO_YARD.has(String(b["type"])):
		return
	var fl := F_SALE if b.get("for_sale", false) or b.get("closed", false) else 0
	if EDGE_YARD.has(String(b["type"])):
		edge_yards.append([MINE, int(b["id"]), owner, -1, ACRES, fl])
	else:
		core.append([YARD, int(b["id"]), owner, -1, 1, fl])

static func _crop_index(P: Dictionary, crop: String) -> int:
	var cl: Array = P["crops"]
	var i := cl.find(crop)
	if i < 0:
		cl.append(crop)
		i = cl.size() - 1
	return i

## A crop's plot use: fruit grows in orchards, or vineyards where the town's fruit is the grape.
static func crop_use(e: Dictionary, crop: String) -> int:
	if crop == "fruit":
		var v := TownEcon.variety_word(e, crop)
		return VINEYARD if v.contains("grape") or v.contains("vine") else ORCHARD
	return FIELD

## Directions (unit vectors in the town's map frame) toward its forest, hills and water, and the cells of each
## around it; roads toward the towns its roads lead to.
static func _terrain_dirs(w: Dictionary, town: Dictionary) -> Dictionary:
	var out := {"fdir": Vector2.ZERO, "hdir": Vector2.ZERO, "wdir": Vector2.ZERO, "forest": 0, "hills": 0, "water": 0, "roads": []}
	var terr: String = w.get("terrain", "")
	var W := int(w.get("w", WorldGen.W)); var H := int(w.get("h", WorldGen.H))
	var cell := float(w.get("cell", WorldGen.CELL))
	var pos: Vector2 = town.get("pos", Vector2.ZERO)
	var c := Vector2i(int(pos.x / cell), int(pos.y / cell))
	if terr != "" and terr.length() >= W * H:
		for dy in range(-4, 5):
			for dx in range(-4, 5):
				var x := c.x + dx; var y := c.y + dy
				if x < 0 or y < 0 or x >= W or y >= H or (dx == 0 and dy == 0):
					continue
				var v := Vector2(dx, dy).normalized()
				match terr[y * W + x]:
					"f", "s":
						out["fdir"] += v; out["forest"] += 1
					"h", "m":
						out["hdir"] += v; out["hills"] += 1
					"w":
						out["wdir"] += v; out["water"] += 1
	for k in ["fdir", "hdir", "wdir"]:
		out[k] = (out[k] as Vector2).normalized()
	for l in town.get("road_links", []):
		var o: Dictionary = w.get("towns", {}).get(String(l.get("id", "")), {})
		if not o.is_empty():
			var d: Vector2 = (o["pos"] as Vector2) - pos
			if d.length() > 0.1:
				var ang := snappedf(d.angle(), PI / 4.0)
				if not (out["roads"] as Array).has(ang):
					out["roads"].append(ang)
	if (out["roads"] as Array).is_empty():
		out["roads"] = [0.0, PI]
	return out

## Places the items on an S x S grid. False when they do not fit (the caller grows the grid).
static func _place(P: Dictionary, e: Dictionary, town: Dictionary, rng: RandomNumberGenerator, S: int, terr: Dictionary, walled: bool,
		state_items: Array, core: Array, land: Array, common_items: Array, n_past: int, edge: Array, edge_yards: Array, n_hill: int) -> bool:
	for k in COLS:
		P[k] = PackedInt32Array()
	P["st"] = PackedFloat32Array()
	P["h"] = []
	P["gw"] = S; P["gh"] = S
	var g := PackedInt32Array()
	g.resize(S * S)
	g.fill(-1)
	P["g"] = g
	var c := Vector2(float(S - 1) * 0.5, float(S - 1) * 0.5)
	var dist := PackedFloat32Array()
	dist.resize(S * S)
	var cells := []
	for y in S:
		for x in S:
			var d := Vector2(x, y).distance_to(c) + rng.randf_range(0.0, 0.35)
			dist[y * S + x] = d
			cells.append(y * S + x)
	cells.sort_custom(func(a, b): return dist[a] < dist[b] if dist[a] != dist[b] else a < b)
	var items_n := state_items.size() + core.size() + land.size() + common_items.size() + n_past + edge.size() + edge_yards.size() + n_hill
	var R := sqrt(float(items_n) / PI) + 1.0
	# roads out of the middle and the river across the water side
	var special := {}
	for ang in terr["roads"]:
		var dv := Vector2.from_angle(float(ang))
		var r := 1.6
		while r < float(S):
			var p := (c + dv * r).round()
			if p.x < 0 or p.y < 0 or p.x >= S or p.y >= S:
				break
			special[int(p.y) * S + int(p.x)] = ROAD
			r += 0.5
	if int(terr["water"]) >= 3 and (terr["wdir"] as Vector2) != Vector2.ZERO:
		var wd: Vector2 = terr["wdir"]
		for ci in S * S:
			var v := Vector2(ci % S, ci / S) - c
			var pr := v.dot(wd)
			if pr >= R * 0.72 and pr < R * 0.72 + 1.7 and not special.has(ci):
				special[ci] = WATER
	var free := cells.filter(func(ci): return not special.has(ci))
	var at := [0]
	var take := func(n: int) -> Array:
		var out := free.slice(at[0], at[0] + n)
		at[0] += n
		return out
	if free.size() < items_n + 8 * int(R):
		return false
	var by_angle := func(list: Array) -> Array:
		var l2 := list.duplicate()
		l2.sort_custom(func(a, b):
			var aa := (Vector2(a % S, a / S) - c).angle(); var ab := (Vector2(b % S, b / S) - c).angle()
			return aa < ab if aa != ab else a < b)
		return l2
	# the town's own buildings and the square at the very middle, the keep first
	var cs: Array = take.call(state_items.size())
	for i in cs.size():
		var pid := _add(P, cs[i], state_items[i])
		if int(state_items[i][0]) == STATE:
			P["bld"][int(state_items[i][1])]["p"] = pid
	# homes and yards around them, family by family (a family's yards beside its homes)
	var hc: Array = by_angle.call(take.call(core.size()))
	var rc := 0.0
	for i in hc.size():
		_add(P, hc[i], core[i])
		rc = maxf(rc, dist[hc[i]])
	rc = maxf(rc, 1.5)
	for i in cs.size():
		rc = maxf(rc, dist[cs[i]])
	# the wall: the ring of cells just outside; where a road crosses it, a gate
	if walled:
		while at[0] < free.size() and dist[free[at[0]]] <= rc + 1.05:
			_add(P, free[at[0]], [WALL, 0, TOWN, -1, 1, 0])
			at[0] += 1
	# fields, orchards and vineyards: each holder's plots in one wedge
	var lc: Array = by_angle.call(take.call(land.size()))
	for i in lc.size():
		_add(P, lc[i], land[i])
	var cc: Array = by_angle.call(take.call(common_items.size()))
	for i in cc.size():
		_add(P, cc[i], common_items[i])
	var pc: Array = by_angle.call(take.call(n_past))
	for ci in pc:
		_add(P, ci, [PASTURE, 0, TOWN, -1, ACRES, 0])
	# the edge: woods toward the forest, then mines and hills toward the hills
	var ec: Array = take.call(edge.size() + edge_yards.size() + n_hill)
	var fd: Vector2 = terr["fdir"]; var hd: Vector2 = terr["hdir"]
	ec.sort_custom(func(a, b):
		var sa := (Vector2(a % S, a / S) - c).normalized().dot(fd); var sb := (Vector2(b % S, b / S) - c).normalized().dot(fd)
		return sa > sb if sa != sb else a < b)
	var woods: Array = ec.slice(0, edge.size())
	var rest: Array = ec.slice(edge.size())
	rest.sort_custom(func(a, b):
		var sa := (Vector2(a % S, a / S) - c).normalized().dot(hd); var sb := (Vector2(b % S, b / S) - c).normalized().dot(hd)
		return sa > sb if sa != sb else a < b)
	for i in woods.size():
		_add(P, woods[i], edge[i])
	for i in rest.size():
		if i < edge_yards.size():
			_add(P, rest[i], edge_yards[i])
		else:
			_add(P, rest[i], [WASTE, 1, TOWN, -1, ACRES, 0])
	# roads and water inside the town's reach become plots too; beyond it the grid stays empty
	var reach := 0.0
	for ci2 in free.slice(0, at[0]):
		reach = maxf(reach, dist[ci2])
	var sk: Array = special.keys()
	sk.sort()
	for ci3 in sk:
		if dist[ci3] <= reach + 0.3:
			var u := int(special[ci3])
			var sub := 1 if u == ROAD and walled and absf(dist[ci3] - (rc + 0.5)) <= 0.6 else 0
			_add(P, ci3, [u, sub, TOWN, -1, 1 if u == ROAD else ACRES, 0])
	return true

static func _add(P: Dictionary, cell: int, it: Array) -> int:
	var S := int(P["gw"])
	var pid := count(P)
	P["x"].append(cell % S); P["y"].append(cell / S)
	P["ac"].append(int(it[4])); P["use"].append(int(it[0])); P["sub"].append(int(it[1]))
	P["own"].append(int(it[2])); P["ten"].append(int(it[3])); P["fl"].append(int(it[5]))
	P["st"].append(1.0 if int(it[0]) == WOOD else 0.0)
	(P["h"] as Array).append([])
	P["g"][cell] = pid
	return pid

# ================================================================== totals (cached on change)
static func _dirty(P: Dictionary) -> void:
	P["dirty"] = true

## {own_crop {fid: {crop: acres}}, crop {crop: acres}, use_ac [acres by use], use_n [plots by use], land (all farm
## acres), wood {dense, thin, felled, regrowing}: plots}. Rebuilt only after a change.
static func totals(e: Dictionary) -> Dictionary:
	var P := _p(e)
	if P.is_empty():
		return {}
	if not P.get("dirty", true) and P.has("tot"):
		return P["tot"]
	var oc := {}; var cr := {}
	var ua := []; var un := []
	ua.resize(USE_NAMES.size()); un.resize(USE_NAMES.size())
	ua.fill(0); un.fill(0)
	var wood := {"dense": 0, "thin": 0, "felled": 0, "regrowing": 0}
	var land := 0
	var crops: Array = P["crops"]
	var use: PackedInt32Array = P["use"]; var ac: PackedInt32Array = P["ac"]; var own: PackedInt32Array = P["own"]; var sub: PackedInt32Array = P["sub"]
	for i in use.size():
		var u := use[i]
		ua[u] += ac[i]; un[u] += 1
		if u <= VINEYARD:
			var crop: String = crops[sub[i]]
			if not oc.has(own[i]):
				oc[own[i]] = {}
			oc[own[i]][crop] = int(oc[own[i]].get(crop, 0)) + ac[i]
			cr[crop] = int(cr.get(crop, 0)) + ac[i]
			land += ac[i]
		elif u == WOOD:
			wood[wood_stage(P, i)] += 1
	var t := {"own_crop": oc, "crop": cr, "use_ac": ua, "use_n": un, "land": land, "wood": wood}
	P["tot"] = t
	P["dirty"] = false
	return t

## Farm acres a family (0 = the town estate) holds, by the plots.
static func acres_of(e: Dictionary, fid: int) -> int:
	var n := 0
	var oc: Dictionary = totals(e).get("own_crop", {}).get(fid, {})
	for c in oc:
		n += int(oc[c])
	return n

static func wood_stage(P: Dictionary, i: int) -> String:
	var s := float(P["st"][i])
	if int(P["fl"][i]) & F_FELLED:
		return "felled" if s < FELLED_AT * 2.0 else "regrowing"
	return "dense" if s >= DENSE else "thin"

# ================================================================== land changes hands (hook from Families.move_land)
## n acres of crop went from family a to family b (either may be the town estate). Moves whole plots; the odd
## acres move by shifting a boundary into a part-plot of the same crop, else one plot is split. A history line
## on each plot says how it changed hands.
static func land_moved(e: Dictionary, a: Dictionary, b: Dictionary, crop: String, n: int) -> void:
	var P := _p(e)
	if P.is_empty() or n <= 0:
		return
	var fa := int(a["id"]); var fb := int(b["id"])
	var ci := _crop_index(P, crop)
	var day := float(e.get("day", 0))
	var year := Calendar.year(day)
	var n0 := count(P)
	var cache_ok: bool = bool(P.get("_crop_work_plots_valid", false)) and int(P.get("crop_year", -999)) == year and int(P.get("crop_count", -1)) == n0 and P.has("crop_work_acres") and P.has("crop_work_plots") and P.has("crop_yields") and P.has("crop_names") and P.has("variety") and P["variety"].size() == n0 and P.has("soil") and P["soil"].size() == n0 and P.has("rotation_phase") and P["rotation_phase"].size() == n0 and e.has("crop_mix")
	var touched: Array = []
	var why := _why(e, a, b)
	var mine := move_candidates(P, fa, ci)
	var rem := n
	var left := []
	for i in mine:
		if rem > 0 and int(P["ac"][i]) <= rem:
			rem -= int(P["ac"][i])
			_give(P, e, i, fb, why, day)
			touched.append(i)
		else:
			left.append(i)
	if rem > 0:
		var g := -1
		for i in left:
			if int(P["ac"][i]) > rem and (g < 0 or int(P["ac"][i]) < int(P["ac"][g])):
				g = i
		if g < 0:
			P["drift"] = int(P.get("drift", 0)) + rem   # fewer plots than acres: the weekly check mends it
			cache_ok = false
		else:
			var indexed_plots: bool = bool(P.get("_crop_work_plots_valid", false)) and int(P.get("crop_count", -1)) == n0 and P.has("crop_work_plots") and fa != fb
			var b_plots: Array = P["crop_work_plots"].get(str(fb), {}).get(crop, []) if indexed_plots else []
			var q := _purchase_part(P, b_plots if touched.is_empty() else b_plots + touched, rem, g) if indexed_plots else _part_plot(P, fb, ci, rem, g)
			touched.append(g)
			if q >= 0:
				P["ac"][g] = int(P["ac"][g]) - rem
				P["ac"][q] = int(P["ac"][q]) + rem
				_hist(P, g, day, "%d acres off its edge %s." % [rem, why[1]])
				_hist(P, q, day, "%d acres added to it from the next plot, %s, for %d coins." % [rem, why[1], rem * int(why[3])])
				touched.append(q)
				if cache_ok: CropRotation._move_mix_acres(e, P, g, q, rem)
			else:
				var extra := int(P["ac"][g]) - rem
				var q2 := _purchase_part(P, left, extra, g) if fa != fb else _part_plot(P, fa, ci, extra, g)
				if q2 >= 0:
					P["ac"][g] = rem
					P["ac"][q2] = int(P["ac"][q2]) + extra
					_give(P, e, g, fb, why, day)
					_hist(P, q2, day, "%d acres kept back from the plot next to it" % extra)
					touched.append(q2)
					if cache_ok: CropRotation._move_mix_acres(e, P, g, q2, extra)
				else:
					P["ac"][g] = extra
					var np := _split(P, g, rem)
					_give(P, e, np, fb, why, day)
					_hist(P, g, day, "%d acres split off it, %s." % [rem, why[1]])
					touched.append(np)
					if cache_ok:
						CropRotation._ensure_plot(e, P, np, year, Persons.race_of(e), String(e.get("climate", "temperate")), day)
						CropRotation._move_mix_acres(e, P, g, np, rem)
	if not (cache_ok and CropRotation.reindex_owners(e, P, [fa, fb], touched)):
		P["crop_count"] = -1
	_dirty(P)

## Native transfer order, also used for cheap rejection bounds on purchases.
static func move_candidates(P: Dictionary, fid: int, ci: int) -> Array:
	var mine: Array = []
	if bool(P.get("_crop_work_plots_valid", false)) and int(P.get("crop_count", -1)) == count(P) and P.has("crop_work_plots") and ci >= 0 and ci < P["crops"].size():
		for i in P["crop_work_plots"].get(str(fid), {}).get(String(P["crops"][ci]), []): mine.append(int(i))
	else:
		for i in count(P):
			if int(P["own"][i]) == fid and int(P["sub"][i]) == ci and LAND_USES.has(int(P["use"][i])):
				mine.append(i)
	mine.sort_custom(func(x, y): return int(P["ac"][x]) > int(P["ac"][y]) if int(P["ac"][x]) != int(P["ac"][y]) else x < y)
	return mine

## Exact physical work preview. Prepared books visit only the two holdings;
## new splits reuse native grid placement. No cash, creditors, wages or harvest
## ownership are settled, copied back, or touched while choosing a quantity.
static func purchase_work(e: Dictionary, a: Dictionary, b: Dictionary, crop: String, n: int, candidates: Array = [], ctx: Dictionary = {}) -> Dictionary:
	var P: Dictionary = e.get("plots", {})
	if P.is_empty():
		return {"acres": Families.acres(b) + n, "active": Families.acres(b) + n, "fallow": 0.0}
	if bool(P.get("_crop_work_plots_valid", false)) and int(a["id"]) != int(b["id"]) and int(P.get("crop_year", -999)) == Calendar.year(float(e.get("day", 0))) and int(P.get("crop_count", -1)) == count(P) and P.has("crop_work_plots") and P.has("crop_work_acres"):
		return _purchase_indexed(e, a, b, crop, n, candidates, ctx)
	# Unprepared books retain the original pure preview, without warming live data.
	var preview := {"plots": P.duplicate(true), "crops": e.get("crops", {}).duplicate(true),
		"day": e.get("day", 0), "culture": e["culture"], "climate": e["climate"], "head": e.get("head", {})}
	land_moved(preview, a, b, crop, n)
	var rows := CropRotation.work_acres(preview, b)
	var active := 0.0
	var fallow := 0.0
	for good in rows:
		active += float(rows[good]["active"])
		fallow += float(rows[good]["fallow"])
	return {"acres": active + fallow, "active": active, "fallow": fallow}

## Match land_moved's whole-plot order and its buyer/donor boundary precedence.
## No histories, harvest accounts or unrelated owners are copied or rebuilt.
static func _purchase_indexed(e: Dictionary, a: Dictionary, b: Dictionary, crop: String, n: int, candidates: Array, ctx: Dictionary = {}) -> Dictionary:
	var P: Dictionary = e["plots"]
	var active: float = 0.0
	var fallow: float = 0.0
	if ctx.has("b_active") and ctx.has("b_fallow"):
		active = float(ctx["b_active"])
		fallow = float(ctx["b_fallow"])
	else:
		for row in P["crop_work_acres"].get(str(int(b["id"])), {}).values():
			active += float(row["active"])
			fallow += float(row["fallow"])
	if ctx.has("rem_by_n") and (ctx.has("s_min_act") or ctx.has("min_active")):
		var rem_arr: PackedInt32Array = ctx["rem_by_n"]
		if n >= 0 and n < rem_arr.size() and rem_arr[n] == 0:
			var act0: float = (active + float((ctx["s_min_act"] as PackedFloat64Array)[n])) if ctx.has("s_min_act") else float((ctx["min_active"] as PackedFloat64Array)[n])
			var fal0: float = fallow + float(n) - (act0 - active)
			return {"acres": act0 + fal0, "active": act0, "fallow": fal0}
	var mine: Array = candidates if not candidates.is_empty() else move_candidates(P, int(a["id"]), (P["crops"] as Array).find(crop))
	var owned: Array = P["crop_work_plots"].get(str(int(b["id"])), {}).get(crop, []).duplicate()
	var left: Array = []
	var rem: int = n
	for i in mine:
		var ac: int = int(P["ac"][i])
		if rem > 0 and ac <= rem:
			rem -= ac
			owned.append(i)
			if String(P["variety"][i]) == "fallow": fallow += ac
			else: active += ac
		else:
			left.append(i)
	if rem > 0:
		var g: int = -1
		for i in left:
			if int(P["ac"][i]) > rem and (g < 0 or int(P["ac"][i]) < int(P["ac"][g])):
				g = int(i)
		if g >= 0:
			var q: int = _purchase_part(P, owned, rem, g)
			var variety: String
			if q >= 0:
				variety = String(P["variety"][q])
			elif _purchase_part(P, left, int(P["ac"][g]) - rem, g) >= 0:
				variety = String(P["variety"][g])
			elif ctx.has("split_var"):
				var sv: Dictionary = ctx["split_var"]
				if not sv.has(g):
					sv[g] = _purchase_split_variety(e, P, crop, g)
				variety = String(sv[g])
			else:
				variety = _purchase_split_variety(e, P, crop, g)
			if variety == "fallow": fallow += rem
			else: active += rem
	return {"acres": active + fallow, "active": active, "fallow": fallow}

## Same nearest-plot and ascending-id tie rule as _part_plot, over known owners.
static func _purchase_part(P: Dictionary, candidates: Array, add: int, g: int) -> int:
	var best: int = -1
	var bd: float = 1.0e9
	var gp: Vector2 = Vector2(P["x"][g], P["y"][g])
	for candidate in candidates:
		var i: int = int(candidate)
		if i == g or int(P["ac"][i]) + add > ACRES: continue
		var d: float = gp.distance_squared_to(Vector2(P["x"][i], P["y"][i]))
		if d < bd or (d == bd and best >= 0 and i < best):
			bd = d
			best = i
	return best

## Only a new cereal plot's coordinates affect its work. Use the native room/
## growth search on private geometry; all existing rotation phases stay fixed.
static func _purchase_split_variety(e: Dictionary, P: Dictionary, crop: String, g: int) -> String:
	if crop != "grain": return String(e.get("crops", {}).get(crop, crop))
	var geometry: Dictionary = {"gw": P["gw"], "gh": P["gh"], "g": P["g"].duplicate(),
		"x": P["x"].duplicate(), "y": P["y"].duplicate(), "use": P["use"]}
	var cell: int = _make_room(geometry, g)
	if cell < 0: cell = _free_cell_near(geometry, int(geometry["x"][g]), int(geometry["y"][g]))
	var x: int = cell % int(geometry["gw"])
	var y: int = cell / int(geometry["gw"])
	var soil: String = ["loam", "light", "heavy"][posmod(x + 2 * y, 3)]
	var phase: int = posmod(x + y, 4) + Calendar.year(float(e.get("day", 0)))
	return CropRotation.choose_crop(Persons.race_of(e), String(e.get("climate", "temperate")), soil, phase)

## [plot owner text, short words for a part, words for the gainer] for a land move.
static func _why(e: Dictionary, a: Dictionary, b: Dictionary) -> Array:
	var price := int(TownEcon.data()["land"]["acre_price"])
	var an := "the town" if a.get("estate", false) else "the %s" % Backstory.plural(String(a["name"]))
	var bn := "the town" if b.get("estate", false) else "the %s" % Backstory.plural(String(b["name"]))
	var head := String(e.get("head", {}).get("title", "head"))
	var debt := float(a.get("debt", 0.0)) > 0.01
	if b.get("estate", false):
		if debt:
			return ["seized", "seized by the town from %s for a missed loan to the %s" % [an, head], "seized by the town", price]
		if Families.people(a) <= 0:
			return ["inherited", "passed to the town when the %s house came to an end" % String(a["name"]), "came to the town", 0]
		return ["sold", "sold by %s to the town" % an, "bought by the town", price]
	if a.get("estate", false):
		return ["bought", "bought from the town by %s" % bn, "bought by %s" % bn, price]
	if debt:
		return ["forced", "sold by %s for their debt; bought by %s" % [an, bn], "bought by %s" % bn, price]
	return ["sold", "sold by %s to %s" % [an, bn], "bought by %s" % bn, price]

static func _give(P: Dictionary, e: Dictionary, i: int, fb: int, why: Array, day: float) -> void:
	P["own"][i] = fb
	var fl := int(P["fl"][i]) & ~F_SEIZED
	if String(why[0]) == "seized":
		fl |= F_SEIZED
	P["fl"][i] = fl
	var price := int(P["ac"][i]) * int(why[3])
	_hist(P, i, day, ("%s for %d coins." % [_cap(String(why[1])), price]) if price > 0 else "%s." % _cap(String(why[1])))

static func _cap(s: String) -> String:
	return s.substr(0, 1).to_upper() + s.substr(1) if s != "" else s

## A plot of family fid of crop ci with room for `add` more acres (<= ACRES), nearest to plot g; -1 if none.
static func _part_plot(P: Dictionary, fid: int, ci: int, add: int, g: int) -> int:
	var best := -1; var bd := 1.0e9
	var gp := Vector2(P["x"][g], P["y"][g])
	for i in count(P):
		if i != g and int(P["own"][i]) == fid and int(P["sub"][i]) == ci and LAND_USES.has(int(P["use"][i])) and int(P["ac"][i]) + add <= ACRES:
			var d := gp.distance_squared_to(Vector2(P["x"][i], P["y"][i]))
			if d < bd:
				bd = d; best = i
	return best

## A new plot of `acres` cut from plot g (same use and crop), placed beside it: the plots between it and the
## nearest open ground move out one step (the outer land shifts, nothing is lost). Returns the new plot's id.
static func _split(P: Dictionary, g: int, acres: int) -> int:
	var cell := _make_room(P, g)
	if cell < 0:
		cell = _free_cell_near(P, int(P["x"][g]), int(P["y"][g]))
	var pid := _add(P, cell, [int(P["use"][g]), int(P["sub"][g]), int(P["own"][g]), -1, acres, 0])
	return pid

## The empty cell nearest (x, y); the grid grows a ring when none is left.
static func _free_cell_near(P: Dictionary, x: int, y: int) -> int:
	for _try in 2:
		var S := int(P["gw"])
		var g: PackedInt32Array = P["g"]
		var best := -1; var bd := 1.0e9
		for ci in g.size():
			if g[ci] < 0:
				var d := Vector2(ci % S - x, ci / S - y).length_squared()
				if d < bd:
					bd = d; best = ci
		if best >= 0:
			return best
		_grow(P)
		x += 1; y += 1
	return -1

## Frees a cell next to (x, y): a breadth-first path over movable plots to the nearest empty cell, and every plot
## on the path moves one step outward. Grows the grid by a ring when there is no open ground left.
static func _make_room(P: Dictionary, near: int) -> int:
	for _try in 3:
		var S := int(P["gw"]); var Hh := int(P["gh"])
		var g: PackedInt32Array = P["g"]
		var start := int(P["y"][near]) * S + int(P["x"][near])
		var prev := {start: -1}
		var q := [start]
		var found := -1
		while not q.is_empty() and found < 0:
			var cur: int = q.pop_front()
			var cx := cur % S; var cy := cur / S
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nx: int = cx + d.x; var ny: int = cy + d.y
				if nx < 0 or ny < 0 or nx >= S or ny >= Hh:
					continue
				var ni := ny * S + nx
				if prev.has(ni):
					continue
				var pid := g[ni]
				if pid < 0:
					prev[ni] = cur
					found = ni
					break
				if _movable(int(P["use"][pid])):
					prev[ni] = cur
					q.append(ni)
		if found >= 0:
			# walk back: each plot on the path steps into the next cell outward
			var path := []
			var k := found
			while k != start:
				path.append(k)
				k = int(prev[k])
			path.reverse()   # path[0] next to start ... path[-1] the empty cell
			for j in range(path.size() - 1, 0, -1):
				var from: int = path[j - 1]; var to: int = path[j]
				var pid2 := g[from]
				g[to] = pid2
				P["x"][pid2] = to % S; P["y"][pid2] = to / S
				g[from] = -1
			return path[0]
		_grow(P)
	return -1

static func _movable(u: int) -> bool:
	return u in [FIELD, ORCHARD, VINEYARD, PASTURE, WOOD, COMMON, WASTE]

## One more ring of open ground round the grid (every plot shifts by one cell).
static func _grow(P: Dictionary) -> void:
	var S := int(P["gw"]); var Hh := int(P["gh"])
	var S2 := S + 2; var H2 := Hh + 2
	var g2 := PackedInt32Array()
	g2.resize(S2 * H2)
	g2.fill(-1)
	for i in count(P):
		P["x"][i] = int(P["x"][i]) + 1; P["y"][i] = int(P["y"][i]) + 1
		g2[int(P["y"][i]) * S2 + int(P["x"][i])] = i
	P["g"] = g2
	P["gw"] = S2; P["gh"] = H2

static func _hist(P: Dictionary, i: int, day: float, text: String) -> void:
	var h: Array = P["h"][i]
	h.append([day, text])
	while h.size() > HIST_MAX:
		h.pop_front()

static func hist_lines(P: Dictionary, i: int) -> Array:
	var out := []
	for x in P["h"][i]:
		out.append("%s: %s" % [date_text(float(x[0])), String(x[1])])
	return out

## "Spring, year 2, day 6"
static func date_text(day: float) -> String:
	return "%s, year %d, day %d" % [Calendar.season(day).capitalize(), Calendar.year(day), Calendar.day_of_season(day)]

# ================================================================== daily pass
## One town in seven each day (by its place in the town list): felling, regrowth, clearing (a week's worth) and
## the weekly match of homes, yards, grazing and heirs. Land itself is kept exact by land_moved.
static func daily(game, d: int) -> void:
	var w: Dictionary = game.world
	var ids: Array = w.get("towns", {}).keys()
	ids.sort()
	for i in ids.size():
		if (d + i) % 7 != 2:
			continue
		var t: Dictionary = w["towns"][ids[i]]
		if TownEcon.has_econ(t) and not of(t).is_empty():   # older saves and later towns are laid out here
			week(game, t, float(d), 7)

static func week(game, town: Dictionary, day: float, days: int) -> void:
	var e: Dictionary = town["econ"]
	var P := _p(e)
	if P.is_empty():
		return
	CropRotation.ensure(e, P, float(e.get("day", day)))
	fell(e, P, day)
	regrow(P, day, days)
	clear_step(e, P, day, days)
	sync(game, town, day)

## The wood the cutters really made since the last pass comes out of the woods: the nearest standing wood first.
static func fell(e: Dictionary, P: Dictionary, day: float) -> void:
	var made := int(e.get("led", {}).get("made", {}).get("wood", 0))
	var loads := float(made - int(P.get("wood_seen", made)))
	P["wood_seen"] = made
	if loads <= 0.0:
		return
	var cx := float(P["gw"]) * 0.5; var cy := float(P["gh"]) * 0.5
	var woods := []
	for i in count(P):
		if int(P["use"][i]) == WOOD and float(P["st"][i]) >= FELLED_AT and not (int(P["fl"][i]) & F_FELLED and float(P["st"][i]) < THIN):
			woods.append(i)
	woods.sort_custom(func(a, b): return Vector2(P["x"][a] - cx, P["y"][a] - cy).length_squared() < Vector2(P["x"][b] - cx, P["y"][b] - cy).length_squared())
	for i in woods:
		if loads <= 0.0:
			break
		var have := float(P["st"][i]) * float(P["ac"][i]) * LOADS_PER_ACRE
		var cut := minf(have, loads)
		loads -= cut
		var st := (have - cut) / (float(P["ac"][i]) * LOADS_PER_ACRE)
		var was := wood_stage(P, i)
		P["st"][i] = st
		if st < FELLED_AT:
			P["st"][i] = 0.0
			P["fl"][i] = int(P["fl"][i]) | F_FELLED
		var now := wood_stage(P, i)
		if now != was:
			_hist(P, i, day, "Felled for firewood and timber." if now == "felled" else "Thinned by the woodcutters.")
	if loads > 0.0:
		P["overcut"] = float(P.get("overcut", 0.0)) + loads   # the town's woods are cut out: the cutters go further afield
	_dirty(P)

## Woods grow back slowly: a felled plot regrows to thin wood in years, never at once.
static func regrow(P: Dictionary, day: float, days: int) -> void:
	var chg := false
	for i in count(P):
		if int(P["use"][i]) != WOOD or float(P["st"][i]) >= 1.0 or int(P["fl"][i]) & F_CLEARING:
			continue
		var was := wood_stage(P, i)
		P["st"][i] = minf(1.0, float(P["st"][i]) + REGROW_DAY * float(days))
		if int(P["fl"][i]) & F_FELLED and float(P["st"][i]) >= THIN:
			P["fl"][i] = int(P["fl"][i]) & ~F_FELLED
		var now := wood_stage(P, i)
		if now != was:
			chg = true
			_hist(P, i, day, {"regrowing": "Saplings coming up among the stumps.", "thin": "Grown back to thin wood.", "dense": "A full wood again."}.get(now, "Growing back."))
	if chg:
		_dirty(P)

## Clearing: the public works crew grubs out a felled plot that lies beside the fields (real worker-days from
## the town's works row); when the days are in, it is a field of the town estate (offered for sale by the
## ordinary land loop), and the territory grows by its acres.
static func clear_step(e: Dictionary, P: Dictionary, day: float, days: int) -> void:
	var wb: Dictionary = e["biz"][int(e["works_biz"])] if e.has("works_biz") and int(e["works_biz"]) < (e["biz"] as Array).size() else {}
	var crew := float(wb.get("workers", 0)) if not wb.is_empty() and not wb.get("closed", false) else 0.0
	if int(P.get("clear", -1)) < 0:
		if not AUTO_CLEAR or crew <= 0.0:
			return
		var pick := _clearable(P)
		if pick < 0:
			return
		start_clearing(e, P, pick, day)
	work_clearing(e, P, crew * CLEAR_SHARE * float(days), day)

## A felled wood plot with a field beside it (-1 if none).
static func _clearable(P: Dictionary) -> int:
	var S := int(P["gw"]); var Hh := int(P["gh"])
	for i in count(P):
		if int(P["use"][i]) != WOOD or not (int(P["fl"][i]) & F_FELLED) or float(P["st"][i]) >= THIN:
			continue
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nx: int = int(P["x"][i]) + d.x; var ny: int = int(P["y"][i]) + d.y
			if nx < 0 or ny < 0 or nx >= S or ny >= Hh:
				continue
			var j := int(P["g"][ny * S + nx])
			if j >= 0 and LAND_USES.has(int(P["use"][j])):
				return i
	return -1

static func start_clearing(e: Dictionary, P: Dictionary, i: int, day: float) -> void:
	P["clear"] = i
	P["cl_done"] = 0.0
	P["fl"][i] = int(P["fl"][i]) | F_CLEARING
	_hist(P, i, day, "The town's public works began grubbing out the stumps (%d worker-days of work)." % int(CLEAR_DAYS_ACRE * float(P["ac"][i])))

## Adds worker-days to the plot being cleared; when it has all it needs it becomes a grain field of the town.
static func work_clearing(e: Dictionary, P: Dictionary, worker_days: float, day: float) -> void:
	var i := int(P.get("clear", -1))
	if i < 0 or worker_days <= 0.0:
		return
	P["cl_done"] = float(P["cl_done"]) + worker_days
	var need := CLEAR_DAYS_ACRE * float(P["ac"][i])
	if float(P["cl_done"]) + 0.0001 < need:
		return
	var crop := "grain"
	var acres := int(P["ac"][i])
	P["use"][i] = FIELD
	P["sub"][i] = _crop_index(P, crop)
	P["own"][i] = TOWN
	P["fl"][i] = 0
	P["st"][i] = 0.0
	P["clear"] = -1
	P["cl_done"] = 0.0
	_hist(P, i, day, "Cleared for the plough by the public works (%d worker-days); a %s field of the town now." % [int(need), TownEcon.variety_word(e, crop)])
	# the economy's own books: the estate holds the new acres and the territory grows by them
	var est: Dictionary = e["fams"][0]
	Families.settle(e, est)
	est["land"][crop] = int(est["land"].get(crop, 0)) + acres
	est["cum"][crop] = float(e.get("cum", {}).get(crop, 0.0))
	e["land"][crop] = int(e["land"].get(crop, 0)) + acres
	e["wacres"][crop] = float(e["wacres"].get(crop, 0.0)) + float(acres) * float(est.get("worked", 0.0))
	e["territory"] = int(e.get("territory", 0)) + acres
	TownEcon.town_hist(e, "The public works cleared %d acres of felled wood for the plough." % acres, day)
	# This in-place land conversion leaves crop_count unchanged until its usual rebuild.
	P["_crop_work_plots_valid"] = false
	_dirty(P)

# ================================================================== weekly match: homes, yards, grazing, heirs
## Brings homes, business yards and grazing in line with the records (houses are bought, let, sold for debt,
## built and fall down by many paths; businesses change hands and close), and writes the inheritance lines.
## Also mends any farm plot that drifted from the land records (should never happen; counted in P.drift).
static func sync(game, town: Dictionary, day: float) -> void:
	var e: Dictionary = town["econ"]
	var P := _p(e)
	if P.is_empty():
		return
	_sync_land(e, P, day)
	_sync_homes(e, P, day)
	_sync_yards(e, P, day)
	_sync_grazing(e, P)
	_mark_heads(e, P, true)
	_dirty(P)

static func _sync_land(e: Dictionary, P: Dictionary, day: float) -> void:
	var t := totals(e)
	var oc: Dictionary = t["own_crop"]
	var bad := false
	for f in e["fams"]:
		var fid := int(f["id"])
		var want: Dictionary = {} if f.get("gone", false) else f["land"]
		var have: Dictionary = oc.get(fid, {})
		for c in want:
			if int(want[c]) != int(have.get(c, 0)):
				bad = true
		for c in have:
			if int(have[c]) != int(want.get(c, 0)):
				bad = true
	if not bad:
		return
	# rebuild the farm plots of the town from the records, keeping the cells (rare: a path that skipped the hook)
	P["drift"] = int(P.get("drift", 0)) + 1
	var cells := []
	for i in count(P):
		if LAND_USES.has(int(P["use"][i])):
			cells.append(i)
	var items := []
	for f in e["fams"]:
		if f.get("gone", false):
			continue
		var ks: Array = (f["land"] as Dictionary).keys()
		ks.sort()
		for c in ks:
			var a := int(f["land"][c])
			while a > 0:
				var n := mini(ACRES, a)
				items.append([crop_use(e, String(c)), _crop_index(P, String(c)), int(f["id"]), n])
				a -= n
	for k in items.size():
		var it: Array = items[k]
		var i := -1
		if k < cells.size():
			i = cells[k]
		else:
			var cell := _free_cell_near(P, int(P["gw"]) / 2, int(P["gh"]) / 2)
			i = _add(P, cell, [FIELD, 0, TOWN, -1, 1, 0])
		if int(P["own"][i]) != int(it[2]) or int(P["sub"][i]) != int(it[1]):
			_hist(P, i, day, "Entered in the land book to %s." % owner_text(e, int(it[2])))
		P["use"][i] = int(it[0]); P["sub"][i] = int(it[1]); P["own"][i] = int(it[2]); P["ac"][i] = int(it[3])
	for k in range(items.size(), cells.size()):
		var j: int = cells[k]
		P["use"][j] = COMMON; P["own"][j] = TOWN; P["sub"][j] = 0
		_hist(P, j, day, "Fell out of use; common land now.")
	P["crop_count"] = -1
	_dirty(P)

static func _sync_homes(e: Dictionary, P: Dictionary, day: float) -> void:
	# what the records say: [owner, tenant] -> count
	var want := {}
	for f in e["fams"]:
		if f.get("gone", false) or f.get("estate", false):
			continue
		var fid := int(f["id"])
		if f.has("lodging"): continue
		var rent := mini(int(f.get("rent", 0)), int(f["homes"]))
		if int(f["homes"]) - rent > 0:
			want[Vector2i(fid, -1)] = int(f["homes"]) - rent
		if rent > 0:
			want[Vector2i(TOWN, fid)] = rent
	if int(e["fams"][0].get("homes", 0)) > 0:
		want[Vector2i(TOWN, -1)] = int(e["fams"][0]["homes"])
	if int(e.get("stock", {}).get("home", 0)) > 0:
		want[Vector2i(MARKET, -1)] = int(e["stock"]["home"])
	var have := {}
	var pool := []
	for i in count(P):
		if int(P["use"][i]) != HOME or P.get("lodging_plots", []).has(i):
			continue
		var k := Vector2i(int(P["own"][i]), int(P["ten"][i]))
		have[k] = int(have.get(k, 0)) + 1
		if int(have[k]) > int(want.get(k, 0)):
			pool.append(i)
	var need := []
	for k in want:
		for j in maxi(0, int(want[k]) - int(have.get(k, 0))):
			need.append(k)
	need.sort()
	for k in need:
		var i := -1
		if not pool.is_empty():
			i = pool.pop_front()
		else:
			i = _new_core_plot(P, HOME)
			_hist(P, i, day, "A new %s built here." % String(TownEcon.culture_of(e)["home"]["type"]))
		P["own"][i] = k.x; P["ten"][i] = k.y
		_hist(P, i, day, _home_words(e, k))
	for i in pool:
		P["use"][i] = LOT; P["own"][i] = TOWN; P["ten"][i] = -1
		_hist(P, i, day, "The house is gone: pulled down or fallen to ruin. An empty lot.")

static func _home_words(e: Dictionary, k: Vector2i) -> String:
	if k.x == MARKET:
		return "For sale at the market."
	if k.x == TOWN and k.y >= 0:
		return "Let by the town to %s." % owner_text(e, k.y)
	if k.x == TOWN:
		return "Held by the town, standing empty."
	return "Now the home of %s." % owner_text(e, k.x)

## An empty lot inside the town, else the open cell nearest the middle (a house or yard outside the walls).
static func _new_core_plot(P: Dictionary, use: int) -> int:
	for i in count(P):
		if int(P["use"][i]) == LOT:
			P["use"][i] = use
			return i
	var best := _free_cell_near(P, int(P["gw"]) / 2, int(P["gh"]) / 2)
	return _add(P, best, [use, 0, TOWN, -1, 1, 0])

static func _sync_yards(e: Dictionary, P: Dictionary, day: float) -> void:
	var yard := {}
	for i in count(P):
		if int(P["use"][i]) == YARD or int(P["use"][i]) == MINE:
			yard[int(P["sub"][i])] = i
	for b in e.get("biz", []):
		if NO_YARD.has(String(b["type"])):
			continue
		var bid := int(b["id"])
		var owner := maxi(TOWN, int(b["owner"]))
		var sale: bool = b.get("for_sale", false) or b.get("closed", false)
		var i := int(yard.get(bid, -1))
		if i < 0:
			if b.get("closed", false):
				continue
			i = _new_core_plot(P, YARD) if not EDGE_YARD.has(String(b["type"])) else _new_edge_plot(P, MINE)
			P["sub"][i] = bid; P["own"][i] = owner; P["ac"][i] = 1 if int(P["use"][i]) == YARD else ACRES
			_hist(P, i, day, "%s set up here." % _cap(Businesses.title(e, b)))
		elif int(P["own"][i]) != owner:
			P["own"][i] = owner
			_hist(P, i, day, ("Taken over by the town." if owner == TOWN else "Bought by %s." % owner_text(e, owner)))
		var fl := int(P["fl"][i])
		var nf := (fl | F_SALE) if sale else (fl & ~F_SALE)
		if nf != fl:
			P["fl"][i] = nf
			if sale:
				_hist(P, i, day, "Closed; the yard stands empty, for sale." if b.get("closed", false) else "For sale.")

## Open ground at the edge (a new mine or quarry): the empty cell farthest out that touches a plot.
static func _new_edge_plot(P: Dictionary, use: int) -> int:
	var cell := _free_cell_near(P, int(P["gw"]) - 1, int(P["gh"]) / 2)
	return _add(P, cell, [use, 0, TOWN, -1, ACRES, 0])

## Pasture is the town's common grazing; each tile is grazed by one herd-holding family (tiles shared out by
## their head counts, largest remainder; families' herds as the economy holds them).
static func _sync_grazing(e: Dictionary, P: Dictionary) -> void:
	if e.has("hd"):   # herds as records (addendum 1 B): owned pasture to its owners' herds, the common shared by need
		Herds.assign_tiles(e, P)
		return
	var past := []
	for i in count(P):
		if int(P["use"][i]) == PASTURE:
			past.append(i)
	if past.is_empty():
		return
	var heads := []
	var tot := 0
	for f in e["fams"]:
		if f.get("gone", false):
			continue
		var n := Families.heads(f)
		if n > 0:
			heads.append([int(f["id"]), n])
			tot += n
	for i in past:
		P["ten"][i] = -1
	if tot <= 0:
		return
	var share := []
	var given := 0
	for hrow in heads:
		var q := float(past.size()) * float(hrow[1]) / float(tot)
		share.append([hrow[0], int(floor(q)), q - floor(q)])
		given += int(floor(q))
	var order := range(share.size())
	order.sort_custom(func(a, b): return float(share[a][2]) > float(share[b][2]) if float(share[a][2]) != float(share[b][2]) else int(share[a][0]) < int(share[b][0]))
	for k in mini(past.size() - given, order.size()):
		share[order[k]][1] = int(share[order[k]][1]) + 1
	var at := 0
	for s in share:
		for j in int(s[1]):
			if at < past.size():
				P["ten"][past[at]] = int(s[0])
				at += 1

## The head of each landholding family; a new head (the old one died or left) inherits: a line on its plots.
static func _mark_heads(e: Dictionary, P: Dictionary, write: bool) -> void:
	var heads: Dictionary = P["heads"]
	var race := Persons.race_of(e)
	var oc: Dictionary = totals(e).get("own_crop", {})
	var day := float(e.get("day", 0))
	for f in e["fams"]:
		if f.get("estate", false) or f.get("gone", false) or not oc.has(int(f["id"])):
			continue
		var h := Persons.head_of(f)
		if h.is_empty():
			continue
		var key := str(int(f["id"]))
		var pid := int(h[0])
		if write and heads.has(key) and int(heads[key]) != pid:
			var nm := Persons.name_of(f, h, race)
			for i in count(P):
				if int(P["own"][i]) == int(f["id"]) and LAND_USES.has(int(P["use"][i])):
					_hist(P, i, day, "Inherited by %s, now head of the %s family." % [nm, f["name"]])
		heads[key] = pid

# ================================================================== reading a plot
static func owner_text(e: Dictionary, fid: int) -> String:
	if fid == MARKET:
		return "the market (for sale)"
	if fid == TOWN:
		return "the town"
	var fams: Array = e["fams"]
	if fid < 0 or fid >= fams.size():
		return "nobody"
	return "the %s" % Backstory.plural(String(fams[fid]["name"]))

## Words for what is on the plot: "barley field (ripe)", "dense wood", "home of the Marshes", "the Thorne tanner's yard".
static func use_text(e: Dictionary, P: Dictionary, i: int, day: float) -> String:
	var u := int(P["use"][i])
	match u:
		FIELD, ORCHARD, VINEYARD:
			var crop: String = P["crops"][int(P["sub"][i])]
			var v := String(P.get("variety", [])[i]) if P.has("variety") and P["variety"].size() > i and String(P["variety"][i]) != "" else TownEcon.variety_word(e, crop)
			return "%s %s (%s)" % [v, USE_NAMES[u], season_word(day)] if u == FIELD else "%s %s" % [v, USE_NAMES[u]]
		WOOD:
			var s := wood_stage(P, i)
			return {"dense": "dense wood", "thin": "thinned wood", "felled": "felled wood (stumps)", "regrowing": "regrowing wood"}[s] + \
				(" (being cleared)" if int(P["fl"][i]) & F_CLEARING else "")
		YARD, MINE:
			var b: Dictionary = (e["biz"] as Array)[int(P["sub"][i])] if int(P["sub"][i]) < (e["biz"] as Array).size() else {}
			return "yard of %s" % Businesses.title(e, b) if not b.is_empty() else USE_NAMES[u]
		STATE:
			var bl: Dictionary = P["bld"][int(P["sub"][i])]
			return String(bl["n"])
		WASTE:
			return "rough hills" if int(P["sub"][i]) == 1 else "rough ground"
		ROAD:
			return "town gate" if int(P["sub"][i]) == 1 else "road"
		HOME:
			return String(TownEcon.culture_of(e)["home"]["type"])
	return USE_NAMES[u]

## Fields by the season: sown, growing, ripe, stubble (after the harvest month's first two thirds), bare.
static func season_word(day: float) -> String:
	var si := Calendar.season_index(day)
	match si:
		0: return "sown"
		1: return "growing"
		2: return "ripe" if Calendar.day_of_season(day) <= 20 else "stubble"
	return "bare"

## Gold the plot is worth by the sim's own prices: land at the land price, a house at the market's price for
## a home, a business yard at the town's asking price for a business; -1 = not priced (town ground).
static func value(e: Dictionary, P: Dictionary, i: int) -> int:
	var u := int(P["use"][i])
	if LAND_USES.has(u):
		return int(P["ac"][i]) * int(TownEcon.data()["land"]["acre_price"])
	if u == HOME:
		return int(round(float(e.get("price", {}).get("home", 0.0))))
	if u == YARD or u == MINE:
		var b: Dictionary = (e["biz"] as Array)[int(P["sub"][i])]
		return int(80.0 + float(b["cap"]) * 25.0)   # what the town asks for a business (TownEcon._sell_businesses)
	return -1

## For sale now: the town estate's land (the land loop sells it), a business up for sale or closed, a house
## at the market.
static func for_sale(P: Dictionary, i: int) -> bool:
	var u := int(P["use"][i])
	if LAND_USES.has(u):
		return int(P["own"][i]) == TOWN
	if u == YARD or u == MINE:
		return int(P["fl"][i]) & F_SALE != 0
	return u == HOME and int(P["own"][i]) == MARKET

## Worked today: farm plots by the holder's share of its land worked (f.worked), a family's plots in order;
## pasture by the grazing family; yards when the business has workers; the town's buildings always.
static func worked_mask(e: Dictionary, P: Dictionary) -> PackedByteArray:
	var m := PackedByteArray()
	m.resize(count(P))
	var per := {}
	for i in count(P):
		if LAND_USES.has(int(P["use"][i])):
			var o := int(P["own"][i])
			if not per.has(o):
				per[o] = []
			per[o].append(i)
	var fams: Array = e["fams"]
	for o in per:
		var f: Dictionary = fams[int(o)] if int(o) >= 0 and int(o) < fams.size() else {}
		var wk := float(f.get("worked", 0.0))
		var l: Array = per[o]
		var n := int(round(wk * float(l.size())))
		for k in mini(n, l.size()):
			m[l[k]] = 1
	for i in count(P):
		var u := int(P["use"][i])
		if u == PASTURE and int(P["ten"][i]) >= 0 and int(P["ten"][i]) < fams.size():
			m[i] = 1 if float(fams[int(P["ten"][i])].get("worked", 0.0)) > 0.0 else 0
		elif u == YARD or u == MINE:
			var b: Dictionary = (e["biz"] as Array)[int(P["sub"][i])]
			m[i] = 1 if (int(b.get("workers", 0)) > 0 or int(b.get("kw", 0)) > 0) and not b.get("closed", false) else 0
		elif u == STATE:
			m[i] = 1
	return m

## The people who work a farm plot: the holder family's members on its own land (Persons.work), or the hands
## hired on the town fields for the estate. [{fid, pid, name}]
static func workers(e: Dictionary, P: Dictionary, i: int) -> Array:
	var out := []
	var u := int(P["use"][i])
	var fams: Array = e["fams"]
	var race := Persons.race_of(e)
	if LAND_USES.has(u) or u == PASTURE:
		var fid := int(P["own"][i]) if u != PASTURE else int(P["ten"][i])
		if fid < 0 or fid >= fams.size():
			return out
		if fid == TOWN:
			return staff_of_biz(e, int(e.get("estate_biz", -1)))
		var f: Dictionary = fams[fid]
		var wk := Persons.work(e, f)
		for pid in wk:
			if String(wk[pid]["kind"]) == ("herd" if u == PASTURE else "land"):
				var p := Persons.by_pid(f, int(pid))
				if not p.is_empty():
					out.append({"fid": fid, "pid": int(pid), "name": Persons.name_of(f, p, race)})
	elif u == YARD or u == MINE:
		return staff_of_biz(e, int(P["sub"][i]))
	return out

## Register persons working at a business row (any family): [{fid, pid, name}].
static func staff_of_biz(e: Dictionary, bid: int) -> Array:
	var out := []
	if bid < 0:
		return out
	var race := Persons.race_of(e)
	for f in e["fams"]:
		if f.get("gone", false) or f.get("estate", false):
			continue
		var jobs: Dictionary = f.get("jobs", {})
		if int(jobs.get(bid, jobs.get(str(bid), 0))) <= 0:
			continue
		var wk := Persons.work(e, f)
		for pid in wk:
			if int(wk[pid].get("biz", -1)) == bid:
				var p := Persons.by_pid(f, int(pid))
				if not p.is_empty():
					out.append({"fid": int(f["id"]), "pid": int(pid), "name": Persons.name_of(f, p, race)})
	return out

## Register persons of the families holding a casual job (rat catchers keep the granary).
static func casual_staff(e: Dictionary, job: String) -> Array:
	var out := []
	var race := Persons.race_of(e)
	for f in e["fams"]:
		if f.get("gone", false) or (int(f.get("cj", {}).get(job, 0)) <= 0 and not f.get("child_cj", {}).values().has(job)):
			continue
		var wk := Persons.work(e, f)
		for pid in wk:
			if String(wk[pid].get("cj", "")) == job:
				var p := Persons.by_pid(f, int(pid))
				if not p.is_empty():
					out.append({"fid": int(f["id"]), "pid": int(pid), "name": Persons.name_of(f, p, race)})
	return out

## Everything the plot card shows (data only; ui/land_map.gd lays it out). Lines are plain text; `taps` are
## {text, fid} rows the card makes into buttons (a family record, a person's household).
static func card(game, town: Dictionary, i: int) -> Dictionary:
	var e: Dictionary = town["econ"]
	var P := of(town)
	var day := float(game.day)
	var u := int(P["use"][i])
	var lines := []
	var taps := []
	var title := _cap(use_text(e, P, i, day))
	var lodging := TownHousing.plot_info(e, i)
	if not lodging.is_empty():
		lodging["plot"] = i; lodging["hist"] = P["h"][i]; return lodging
	if u == STATE:
		var info := building(game, town, int(P["sub"][i]))
		return {"title": _cap(String(info["name"])), "lines": info["lines"], "taps": info["taps"], "plot": i, "hist": info["hist"]}
	lines.append("%s, %s." % [USE_NAMES[u].capitalize() if u != STATE else "Town building", TownEcon.n_of(int(P["ac"][i]), "acres")])
	var own := int(P["own"][i])
	if u == HOME:
		if int(P["ten"][i]) >= 0:
			lines.append("Held by the town, let to %s at %d coins a week." % [owner_text(e, int(P["ten"][i])), int(round(Shelter.rent_week(e)))])
			taps.append({"text": "The household: %s" % owner_text(e, int(P["ten"][i])), "fid": int(P["ten"][i])})
		elif own > 0:
			lines.append("Home of %s." % owner_text(e, own))
			taps.append({"text": "The household: %s" % owner_text(e, own), "fid": own})
		else:
			lines.append("Held by %s, standing empty." % owner_text(e, own))
	elif u == PASTURE and e.has("hd"):   # herds as records: owner, each herd, its herders, what the plot carries
		var hc := Herds.card_lines(game, town, P, i)
		lines.append_array(hc["lines"])
		taps.append_array(hc["taps"])
	elif u == PASTURE:
		lines.append("The town's common grazing.")
		if int(P["ten"][i]) > 0:
			var gf: Dictionary = e["fams"][int(P["ten"][i])]
			var hd := []
			for a in gf["herd"]:
				hd.append(TownEcon.n_of(int(gf["herd"][a]), String(a)))
			lines.append("Grazed by %s's herd (%s in all)." % [owner_text(e, int(P["ten"][i])), ", ".join(PackedStringArray(hd))])
			taps.append({"text": "Herd owners: %s" % owner_text(e, int(P["ten"][i])), "fid": int(P["ten"][i])})
	elif u == YARD or u == MINE:
		var b: Dictionary = (e["biz"] as Array)[int(P["sub"][i])]
		lines.append("%s: %s, %d of %d at work, %d coins a day%s." % [_cap(Businesses.title(e, b)), "closed" if b.get("closed", false) else Businesses.state_word(b),
			int(b["workers"]), int(b["cap"]), int(round(float(b["wage"]))), ", for sale" if for_sale(P, i) else ""])
		if own > 0:
			taps.append({"text": "Owners: %s" % owner_text(e, own), "fid": own})
		else:
			lines.append("Owned by the town.")
	else:
		lines.append("Held by %s%s." % [owner_text(e, own), " (seized)" if int(P["fl"][i]) & F_SEIZED else ""])
		if own > 0:
			taps.append({"text": "Owner: %s" % owner_text(e, own), "fid": own})
	if u == WOOD:
		lines.append("Standing wood: %d%% of a full wood (about %d loads)." % [int(round(float(P["st"][i]) * 100.0)), int(float(P["st"][i]) * float(P["ac"][i]) * LOADS_PER_ACRE)])
		if int(P.get("clear", -1)) == i:
			lines.append("Being cleared: %d of %d worker-days done." % [int(P["cl_done"]), int(CLEAR_DAYS_ACRE * float(P["ac"][i]))])
	if u == HOME and e.has("hd"):   # herds: the household's pens (hens, rats, hives)
		var pc := Herds.card_lines(game, town, P, i)
		lines.append_array(pc["lines"])
	var ws := workers(e, P, i) if not (u == PASTURE and e.has("hd")) else []
	if not ws.is_empty():
		var nm := []
		for wp in ws.slice(0, 6):
			nm.append(String(wp["name"]))
		lines.append("Worked by %s%s." % [", ".join(PackedStringArray(nm)), (" and %d more" % (ws.size() - 6)) if ws.size() > 6 else ""])
		var seen := {}
		for wp in ws.slice(0, 4):
			if not seen.has(int(wp["fid"])):
				seen[int(wp["fid"])] = true
				taps.append({"text": "Worker: %s" % wp["name"], "fid": int(wp["fid"])})
	elif LAND_USES.has(u):
		lines.append("Nobody works it today.")
	var v := value(e, P, i)
	if v >= 0:
		lines.append("Value %d coins%s." % [v, (" (the land price, %d an acre)" % int(TownEcon.data()["land"]["acre_price"])) if LAND_USES.has(u) else ""])
	if for_sale(P, i) and v >= 0:
		lines.append("For sale: %d coins." % v)
	if own > 0 and LAND_USES.has(u):
		var of2: Dictionary = e["fams"][own]
		if float(of2.get("debt", 0.0)) > 0.01:
			lines.append("Loan: the %s owe %d coins to the %s; this land is their pledge." % [Backstory.plural(String(of2["name"])), int(round(float(of2["debt"]))),
				String(e["head"]["title"])])
	var h := hist_lines(P, i)
	if h.is_empty() and LAND_USES.has(u):
		h = ["Held by %s since before the land book was begun." % owner_text(e, own)]
	return {"title": title, "lines": lines, "taps": taps, "plot": i, "hist": h}

# ================================================================== the town's own buildings (addendum A)
## Live record of one of the town's buildings: who runs it, staff and residents (register persons), capacity,
## stock, upkeep a day (what the treasury really pays for it now) and what it is doing. Reads the economy's own
## data (militia, shelter, armory, granary, collectors); nothing is copied.
## {kind, name, plot, runner {fid, pid, name} | {}, staff [...], residents [...], cap, used, stock, upkeep, now, lines, taps, hist}
static func building(game, town: Dictionary, bi: int) -> Dictionary:
	var e: Dictionary = town["econ"]
	var P := of(town)
	var bl: Dictionary = P["bld"][bi]
	var k := String(bl["k"])
	var race := Persons.race_of(e)
	var head: Dictionary = e.get("head", {})
	var hf: Dictionary = e["fams"][int(head.get("fam", 0))]
	var hp := Persons.head_of(hf)
	var head_ref := {} if hp.is_empty() else {"fid": int(hf["id"]), "pid": int(hp[0]), "name": Persons.name_of(hf, hp, race),
		"role": String(head.get("title", "head"))}
	var out := {"kind": k, "name": String(bl["n"]), "plot": int(bl["p"]), "runner": {}, "staff": [], "residents": [], "cap": 0, "used": 0,
		"stock": "", "upkeep": 0.0, "now": "", "cond": 1.0}
	match k:
		"keep":
			out["runner"] = head_ref
			out["residents"] = _household(e, hf)
			out["cap"] = maxi(1, int(hf.get("homes", 1))) * int(TownEcon.culture_of(e)["home"]["room"])
			out["used"] = (out["residents"] as Array).size()
			out["now"] = "Seat of the %s; the household of %d lives here." % [String(head.get("title", "head")), int(out["used"])]
		"hall":
			out["runner"] = head_ref
			var col := -1
			for b in e["biz"]:
				if String(b["type"]) == "collector":
					col = int(b["id"])
			out["staff"] = staff_of_biz(e, col)
			if col >= 0:
				var cb: Dictionary = e["biz"][col]
				out["cap"] = int(cb["cap"])
				out["used"] = int(cb["workers"])
				out["upkeep"] = float(cb["workers"]) * float(cb["wage"])
			var lent := 0
			var debt := 0.0
			for f in e["fams"]:
				if float(f.get("debt", 0.0)) > 0.01 and not f.get("gone", false):
					lent += 1; debt += float(f["debt"])
			out["stock"] = "chest %d coins" % int(float(e.get("treasury", 0.0)))
			out["now"] = "The chest holds %d coins; %d loans out (%d coins); the land book has %d plots." % [int(float(e.get("treasury", 0.0))), lent, int(debt), count(P)]
		"barracks":
			var mil := _militia(game, town)
			out["residents"] = mil["people"]
			out["runner"] = mil["captain"]
			out["cap"] = int(e.get("barracks_beds", Militia.target_size(town)))
			out["used"] = (mil["people"] as Array).size()
			out["upkeep"] = mil["pay"]
			out["now"] = "Beds %d / %d." % [int(out["used"]), int(out["cap"])]
		"armory":
			out["runner"] = head_ref
			var have := (town.get("armory_items", []) as Array).size()
			var tgt := 0
			for c in e.get("arms_tgt", {}):
				tgt += int(e["arms_tgt"][c])
			out["cap"] = tgt
			out["used"] = have
			out["stock"] = "%d pieces of arms" % have
			out["now"] = "Arms %d against a target of %d." % [have, tgt]
		"granary":
			out["runner"] = head_ref
			out["staff"] = casual_staff(e, "rat_catcher")
			var cjw := float(TownEcon.data().get("casual_jobs", {}).get("rat_catcher", {}).get("wage", 0.0))
			out["upkeep"] = cjw * float((out["staff"] as Array).size())
			var gr := int(e.get("granary", 0))
			var per_day := maxf(1.0, float(e.get("pop", 1)) * float(TownEcon.data()["needs"]["food"]))
			out["used"] = gr
			out["stock"] = "%d grain" % gr
			out["now"] = "%d grain stored: %d days of bread for the town." % [gr, int(float(gr) / per_day)]
		"shelter":
			var wb := int(e.get("works_biz", -1))
			out["staff"] = staff_of_biz(e, wb)
			var keeper: Array = out["staff"]
			out["runner"] = keeper[0] if not keeper.is_empty() else head_ref
			var res := []
			for f in e["fams"]:
				if f.get("shel", false) and not f.get("gone", false):
					res.append_array(_household(e, f))
			out["residents"] = res
			out["cap"] = Shelter.cap(town)
			out["used"] = res.size()
			var S: Dictionary = TownEcon.data()["shelter"]
			out["upkeep"] = float(e.get("stats", {}).get("shelter_cost", 0.0))
			var bed := float(S.get("bed_price", 0.0))
			var meal := float(S.get("meal_price", 0.0))
			var gruel := bool(e.get("gruel", e.get("gruel_open", false)))
			var terms := []
			terms.append("a bed %s" % ("%d coins a night" % int(bed) if bed > 0.0 else "free (the treasury pays)"))
			terms.append(("meals %d coins" % int(meal)) if meal > 0.0 else "broth from the granary")
			terms.append("free gruel today" if gruel else "the gruel kitchen closed")
			out["now"] = "Beds %d / %d; %d on broth; %s." % [res.size(), int(out["cap"]), int(e.get("broth_n", 0)), ", ".join(PackedStringArray(terms))]
		"jail":
			var mil2 := _militia(game, town)
			out["runner"] = mil2["captain"] if not (mil2["captain"] as Dictionary).is_empty() else head_ref
			out["cap"] = 2 + int(town.get("size", 0))
			out["now"] = "Empty: nobody is held."
		"academy":   # v0.012: the research house (campaign/academy.gd)
			var ab := Academy.biz_of(e)
			if not ab.is_empty():
				var L: Array = ab.get("lead", [])
				var ln := Academy.lead_name(e, ab)
				if ln != "":
					out["runner"] = {"fid": int(L[0]), "pid": int(L[1]), "name": ln, "role": Academy.lead_title(e)}
				out["staff"] = staff_of_biz(e, int(ab["id"]))
				out["cap"] = int(ab["cap"])
				out["used"] = int(ab["workers"])
				out["upkeep"] = float(ab["workers"]) * float(ab["wage"])
				var S := Academy.state(game.world, String(e.get("faction", town.get("faction", ""))))
				var parts := []
				for kk in S["kh"]:
					parts.append("%s know-how %.1f%%" % [kk, float(S["kh"][kk])])
				out["now"] = "%s: %s; %s." % [Academy.house_name(e), Businesses.state_word(ab), ", ".join(PackedStringArray(parts))]
		"mint":
			out["now"] = "Cold: no coin is cast here yet."
			out["stock"] = "%d bronze bars in the town" % int(e.get("stock", {}).get("bronze_bars", 0))
	var lines := []
	lines.append(String(out["now"]))
	var r: Dictionary = out["runner"]
	lines.append("Run by %s." % (("%s (%s)" % [r["name"], r.get("role", "")]) if not r.is_empty() and String(r.get("role", "")) != "" else (String(r["name"]) if not r.is_empty() else "nobody")))
	if not (out["staff"] as Array).is_empty():
		lines.append("Staff: %s." % _names(out["staff"]))
	if not (out["residents"] as Array).is_empty():
		lines.append("Residents: %s." % _names(out["residents"]))
	if float(out["upkeep"]) > 0.0:
		lines.append("Upkeep: %d coins a day from the treasury." % int(round(float(out["upkeep"]))))
	var taps := []
	if not r.is_empty():
		taps.append({"text": "Runs it: %s" % r["name"], "fid": int(r["fid"])})
	var seen := {}
	for p in (out["staff"] as Array) + (out["residents"] as Array):
		if seen.size() >= 4:
			break
		if not seen.has(int(p["fid"])):
			seen[int(p["fid"])] = true
			taps.append({"text": "%s's household" % p["name"], "fid": int(p["fid"])})
	out["lines"] = lines
	out["taps"] = taps
	out["hist"] = hist_lines(P, int(bl["p"])) if int(bl["p"]) >= 0 else []
	return out

static func buildings(game, town: Dictionary) -> Array:
	var out := []
	var P := of(town)
	if P.is_empty():
		return out
	for bi in (P["bld"] as Array).size():
		out.append(building(game, town, bi))
	return out

static func _names(l: Array) -> String:
	var nm := []
	for p in l.slice(0, 8):
		nm.append(String(p["name"]))
	return ", ".join(PackedStringArray(nm)) + ((" and %d more" % (l.size() - 8)) if l.size() > 8 else "")

## A household's people at home (grown-ups and children): [{fid, pid, name}].
static func _household(e: Dictionary, f: Dictionary) -> Array:
	var out := []
	var race := Persons.race_of(e)
	for p in (f.get("pp", []) as Array) + (f.get("kp", []) as Array):
		if String(p[4]) in ["", "hire"]:
			out.append({"fid": int(f["id"]), "pid": int(p[0]), "name": Persons.name_of(f, p, race)})
	return out

## The town militia (a city's guard) as register persons, its captain (the highest rank) and its pay a day.
static func _militia(game, town: Dictionary) -> Dictionary:
	var e: Dictionary = town["econ"]
	var race := Persons.race_of(e)
	var people := []
	var cap := {}
	var best := -1
	var pay := 0.0
	for u in TownDefence.garrison(game, String(town["id"])):
		var fid: int = u.family
		if u.home_town != String(town["id"]) or fid < 0 or fid >= (e["fams"] as Array).size():
			continue
		var f: Dictionary = e["fams"][fid]
		var p := Persons.by_uid(f, u.uid)
		if p.is_empty():
			continue
		var ref := {"fid": fid, "pid": int(p[0]), "name": Persons.name_of(f, p, race), "role": Army.rank_title(u)}
		people.append(ref)
		pay += u.last_pay
		if u.rank > best:
			best = u.rank
			cap = ref
	return {"people": people, "captain": cap, "pay": pay}
