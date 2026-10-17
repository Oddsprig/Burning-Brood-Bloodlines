class_name Lairs
extends RefCounted
## Monsters wave 1: lairs on the campaign map (wolf den, bear den, boar wallow, bandit camp).
##
## world.lairs[id] = {id, kind, name, pos: Vector2, faction ("beasts" | "outlaws"), creature (cid or ""),
##   resident: warband id living there ("" = empty), cleared_until: day (a cleared lair stays empty this long),
##   known: bool (seen by the company or named by a contract), created: day,
##   camps only: stock: Array[Item] (raided gear the camp re-arms from), gold}
## Lairs sit in the wilds (forest, silverwood, hills, badlands; caves = hills next to mountains), away from towns.
## Density is a share of wild map area (data/creatures.json "spawning": lair_density, camp_density): sparse by design.

static var _wild_key := ""
static var _wild: Dictionary = {}      # terrain char -> Array[int] of wild cell indices
static var _wild_n := 0

static func info(kind: String) -> Dictionary:
	return DB.creature_data.get("lairs", {}).get(kind, {})

static func kinds() -> Array:
	var out := []
	for k in DB.creature_data.get("lairs", {}):
		if not String(k).begins_with("_"):
			out.append(k)
	out.sort()
	return out

## Wild cells by terrain char: main landmass, wild terrain, at least min_town_cells from any town. Cached per map.
static func wild_cells(w: Dictionary) -> Dictionary:
	var key := "%s|%d|%d" % [str(w.get("seed", 0)), (w["terrain"] as String).hash(), (w.get("towns", {}) as Dictionary).size()]
	if key == _wild_key:
		return _wild
	_wild_key = key
	_wild = {}
	_wild_n = 0
	var terr: String = w["terrain"]
	var land := WorldGen.main_landmass(w)
	var md := int(Creatures.tun("min_town_cells", 7))
	# cells within md of a town (the same square test as before), stamped once per town: O(cells + towns), not
	# O(cells x towns) (world size)
	var near := PackedByteArray(); near.resize(WorldGen.W * WorldGen.H)
	for tid in w.get("towns", {}):
		var tc := WorldGen.cell_of(w["towns"][tid]["pos"])
		for y in range(maxi(0, tc.y - md + 1), mini(WorldGen.H, tc.y + md)):
			for x in range(maxi(0, tc.x - md + 1), mini(WorldGen.W, tc.x + md)):
				near[WorldGen.idx(x, y)] = 1
	for y in WorldGen.H:
		for x in WorldGen.W:
			var i := WorldGen.idx(x, y)
			var ch := terr[i]
			if not ch in ["f", "s", "h", "b"] or land[i] == 0 or near[i] == 1:
				continue
			if not _wild.has(ch):
				_wild[ch] = []
			(_wild[ch] as Array).append(i)
			_wild_n += 1
	return _wild

static func wild_count(w: Dictionary) -> int:
	wild_cells(w)
	return _wild_n

## Target numbers are shares of the wild area (min 1, capped).
static func target_lairs(wild_n: int) -> int:
	if wild_n <= 0:
		return 0
	return clampi(int(round(wild_n * float(Creatures.tun("lair_density", 0.0045)))), 1, roundi(float(Creatures.tun("max_lairs", 18)) * WorldGen.TF))   # world size: the cap per area of the normal map

static func target_camps(wild_n: int) -> int:
	if wild_n <= 0:
		return 0
	return clampi(int(round(wild_n * float(Creatures.tun("camp_density", 0.0012)))), 1, roundi(float(Creatures.tun("max_camps", 4)) * WorldGen.TF))   # world size

static func count(w: Dictionary, camps: bool) -> int:
	var n := 0
	for lid in w.get("lairs", {}):
		if (w["lairs"][lid]["kind"] == "bandit_camp") == camps:
			n += 1
	return n

## Place a new lair of `kind` on a random fitting wild cell (not next to another lair). Returns its id or "".
static func place(game, kind: String, rng: RandomNumberGenerator) -> String:
	if not Monsters.campaign_creatures_enabled() and kind != "bandit_camp": return ""
	var w: Dictionary = game.world
	var inf := info(kind)
	if inf.is_empty():
		return ""
	var wild := wild_cells(w)
	var cands := []
	for ch in inf.get("terrain", ["f"]):
		cands.append_array(wild.get(ch, []))
	if cands.is_empty():
		return ""
	var terr: String = w["terrain"]
	var others := []
	for lid in w.get("lairs", {}):
		others.append(WorldGen.cell_of(w["lairs"][lid]["pos"]))
	for _try in 40:
		var i: int = cands[rng.randi() % cands.size()]
		var c := Vector2i(i % WorldGen.W, i / WorldGen.W)
		var ok := true
		for o in others:
			if absi(o.x - c.x) < 5 and absi(o.y - c.y) < 5:
				ok = false
				break
		if not ok:
			continue
		if inf.get("cave", false) and _try < 30:
			# caves: hills with a mountain next door
			var m := false
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					var x := c.x + dx
					var y := c.y + dy
					if x >= 0 and y >= 0 and x < WorldGen.W and y < WorldGen.H and terr[WorldGen.idx(x, y)] == "m":
						m = true
			if not m:
				continue
		var id := CampaignWorld.new_id(w, "lair")
		var l := {"id": id, "kind": kind, "name": String(inf.get("name", kind)), "pos": WorldGen.cell_center(c),
			"faction": String(inf.get("faction", "beasts")), "creature": String(inf.get("creature", "")), "resident": "",
			"cleared_until": 0.0, "known": false, "created": float(game.day)}
		if kind == "bandit_camp":
			l["stock"] = []
			l["gold"] = 0
		if not w.has("lairs"):
			w["lairs"] = {}
		w["lairs"][id] = l
		return id
	return ""

static func near_text(w: Dictionary, l: Dictionary) -> String:
	return "%s near %s" % [l["name"], CampaignWorld.nearest_town_name(w, l["pos"])]

## Battle map for a fight at a lair: choke points from impassable (#) and rough (,) tiles around the enemy side.
## den / cave: a rock enclosure on the right with one narrow mouth; thicket: a dense rough ring with gaps;
## camp: a palisade with two gates. Deploy columns stay open (the sim deploys side 1 on the right edge).
static func battle_tiles(kind: String, grid: Vector2i, seed: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed * 31 + 7
	var W := grid.x
	var H := grid.y
	var cells := []
	for y in H:
		var row := []
		row.resize(W)
		row.fill(".")
		cells.append(row)
	var style := String(info(kind).get("style", "den"))
	var x0 := W - 9
	var y_top := 2
	var y_bot := H - 3
	var cy := H / 2
	match style:
		"den", "cave":
			var gap := 1 if style == "cave" else 2
			for y in range(y_top, y_bot + 1):
				for x in [x0, x0 + 1]:
					if absi(y - cy) >= gap or (gap == 1 and y != cy):
						cells[y][x] = "#"
			for x in range(x0, W):
				cells[y_top][x] = "#"
				cells[y_bot][x] = "#"
			cells[cy][x0] = "."
			cells[cy][x0 + 1] = "."
			if gap > 1:
				cells[cy - 1][x0] = "."
				cells[cy - 1][x0 + 1] = "."
			# rubble before the mouth
			for k in 6:
				var c := Vector2i(rng.randi_range(x0 - 6, x0 - 2), rng.randi_range(y_top, y_bot))
				cells[c.y][c.x] = ","
		"thicket":
			for y in range(y_top, y_bot + 1):
				for x in range(x0 - 1, x0 + 2):
					if absi(y - cy) > 1 and rng.randf() < 0.85:
						cells[y][x] = "," if rng.randf() < 0.6 else "#"
			for x in range(x0, W):
				if rng.randf() < 0.7:
					cells[y_top][x] = ","
					cells[y_bot][x] = ","
		"camp":
			for y in range(y_top, y_bot + 1):
				if absi(y - H / 3) > 0 and absi(y - (2 * H) / 3) > 0:
					cells[y][x0] = "#"
			for x in range(x0, W):
				cells[y_top][x] = "#"
				cells[y_bot][x] = "#"
			# tents inside
			for k in 2:
				var tx := rng.randi_range(x0 + 2, W - 4)
				var ty := rng.randi_range(y_top + 2, y_bot - 2)
				cells[ty][tx] = "#"
	# light clutter in the open ground (kept out of the player's deploy columns)
	for k in int(W * H * 0.02):
		var c2 := Vector2i(rng.randi_range(9, x0 - 3), rng.randi_range(1, H - 2))
		if cells[c2.y][c2.x] == ".":
			cells[c2.y][c2.x] = ","
	# side 1 deploys on the last column: keep it open inside the enclosure
	for y in range(y_top + 1, y_bot):
		cells[y][W - 1] = "."
		cells[y][W - 2] = "."
	var rows := []
	for row in cells:
		rows.append("".join(row))
	return rows
