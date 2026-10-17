extends RefCounted
## Delivered v0.031 campaign through the actual loader; every town is checked.

var checks := 0
var fails := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: fails += 1; printerr("FAIL: ", message)

func quantities(values: Dictionary) -> Dictionary:
	# The raw JSON checkpoint has floats; the actual loader restores integer
	# counts. Compare the same quantities without treating that type repair as
	# a physical change, and without rounding any value away.
	var out := {}
	for key in values: out[String(key)] = float(values[key])
	return out

func physical(e: Dictionary) -> Dictionary:
	var owners := []
	for f in e["fams"]:
		owners.append([quantities(f["land"]), quantities(f["herd"]), int(f.get("ox", -1)), Families.people(f)])
	var plots: Dictionary = e.get("plots", {})
	var columns := {}
	for key in ["ac", "use", "sub", "own"]:
		var values := []
		for v in plots.get(key, []): values.append(int(v))
		columns[key] = values
	return {"owners": owners, "plots": columns, "barn": quantities(e["barn"]), "land": quantities(e["land"]), "territory": int(e["territory"])}

func run(_tree: SceneTree) -> int:
	var path := OS.get_environment("LABOUR_LEGACY_SAVE")
	check(path != "" and FileAccess.file_exists(path), "actual delivered v0.031 checkpoint supplied")
	if path == "" or not FileAccess.file_exists(path): return fails
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	check(saved.has("world") and saved.has("day"), "fixture is a complete real campaign")
	if not saved.has("world"): return fails
	Game.world = Game._deserialize(saved["world"].duplicate(true)); Game.gold = int(saved["gold"])
	var coins := Barge.holdings(Game)
	var before := {}
	for tid in Game.world["towns"]:
		if TownEcon.has_econ(Game.world["towns"][tid]): before[tid] = physical(Game.world["towns"][tid]["econ"])
	var jobs: Array = Game.world.get("work", []).duplicate(true)
	Game._write_save(Game.SAVE_PATH, saved)
	check(Game.load_game(), "delivered v0.031 loads with the actual campaign loader")
	check(absf(Barge.holdings(Game) - coins) < 0.0001, "loading new work rules preserves all existing coins")
	check(Game.world.get("work", []) == jobs, "load preserves pending work without executing it")
	var cultures := {}
	for tid in before:
		var e: Dictionary = Game.world["towns"][tid]["econ"]
		cultures[String(e["culture"])] = true
		check(physical(e) == before[tid], "load preserves every family's acres, livestock, population and physical food")
		for f in e["fams"]:
			if f.get("gone", false) or f.get("estate", false): continue
			var day: float = f["last"]
			var need := Families.need_hands(f, e)
			check(need >= 0.0 and is_finite(need), "old physical fields and herds have finite real work requirements")
			check(Families.farm_capacity_stale(e, f), "old assignment has no fabricated new-rule marker before ordinary matching")
			Families.reassign(e, f)
			check(not Families.assignments_stale(f), "existing matcher assigns only actual available civilians")
			check(not Families.farm_capacity_stale(e, f), "existing matcher repairs old capacity and records current work need")
			check(float(f["last"]) == day, "work correction does not advance household spending or paydays")
		check(physical(e) == before[tid], "matching creates no land, people, livestock or stored crops")
	check(cultures.size() == TownEcon.data()["cultures"].size(), "actual checkpoint covers every registered economy culture")
	check(absf(Barge.holdings(Game) - coins) < 0.0001, "real owner funding and earned-wage settlement conserve existing world coins")
	Game.save_game(); check(Game.load_game(), "corrected assignments survive a real second load")
	check(absf(Barge.holdings(Game) - coins) < 0.0001, "second load preserves all real cash")
	for tid in before:
		var e: Dictionary = Game.world["towns"][tid]["econ"]
		check(physical(e) == before[tid], "repeated loading cannot resize an existing town or change its goods")
		for f in e["fams"]:
			if f.get("gone", false) or f.get("estate", false): continue
			check(is_equal_approx(float(f["assigned_need"]), Families.need_hands(f, e)), "saved work markers refer to the same real acres and herds")
	print("FARM WORK SAVE towns=", before.size(), " checks=", checks, " failures=", fails)
	return fails
