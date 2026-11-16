extends RefCounted

var fails := 0
var checks := 0
func check(ok: bool, msg: String) -> void:
	checks += 1
	if not ok: fails += 1; printerr("FAIL: ", msg)

func fixture() -> Array:
	for t in Game.world["towns"].values():
		if not TownEcon.has_econ(t): continue
		var e: Dictionary = t["econ"]
		for f in e["fams"]:
			if f.get("gone", false) or f.get("estate", false) or Families.serving(f) > 0 or int(f["farm"]) < 0: continue
			var b: Dictionary = e["biz"][int(f["farm"])]
			if f["land"].is_empty() or b.get("closed", false): continue
			for worker in e["fams"]:
				if worker == f or worker.get("gone", false) or worker.get("estate", false) or Families.adults(worker) <= 0 or Families.serving(worker) > 0: continue
				for key in worker["jobs"].keys(): Families.set_job(e, worker, int(key), 0)
				b["cap"] = maxi(2, int(b["workers"]) + 1)
				Families.set_job(e, worker, int(b["id"]), 1)
				# Real transfer into the till supplies the final existing worker wage.
				var transfer := minf(1000.0, float(e["treasury"]))
				e["treasury"] -= transfer; b["till"] += transfer
				b["owed"] = 321.5
				# This fixture intentionally models a pre-ledger aggregate balance.
				# Remove attribution fields to exercise actual legacy migration.
				b.erase("wage_claims"); b.erase("owed_unattributed")
				return [t, e, f, b, worker]
	return []

func lifecycle(kind: String, rows: Array) -> void:
	var t: Dictionary = rows[0]; var e: Dictionary = rows[1]; var f: Dictionary = rows[2]; var b: Dictionary = rows[3]; var worker: Dictionary = rows[4]
	var land: Dictionary = f["land"].duplicate()
	var est: Dictionary = e["fams"][0]
	var estate_land: Dictionary = est["land"].duplicate()
	var cash := Barge.holdings(Game)
	var till := float(b["till"]); var owed := float(b["owed"]); var tools := int(b["tools"])
	var staff := int(b["workers"])
	var ordinary := Businesses._row(e, "carpenter", int(f["id"]), 1, TownEcon.data())
	# _row generation budget is removed from the fixture, rather than counted as new money.
	ordinary["till"] = 0.0
	ordinary["kw"] = 1
	if kind == "extinct": Families.extinct(e, f, 7.0)
	elif kind == "leave": Families.leave_town(e, f, 7.0)
	else:
		var dest := {}
		for other in Game.world["towns"].values():
			if other != t and TownEcon.has_econ(other) and Persons.race_of(other["econ"]) == Persons.race_of(e): dest = other; break
		check(not dest.is_empty(), "same-race destination exists for ordinary household migration")
		if dest.is_empty(): return
		Barge.move_family(Game, t, f, dest, "work", 7.0)
	check(b.get("closed", false) and int(b["cap"]) == 0 and not b.get("for_sale", true), kind + ": former farm no longer advertises jobs or a second sale of estate land")
	check(int(b["owner"]) == -1 and int(b.get("kw", 0)) == 0, kind + ": departed keeper no longer works the farm")
	check(float(b["till"]) == till and float(b["owed"]) == owed and int(b["tools"]) == tools, kind + ": prior money, wages owed and tools remain in the closing books")
	check(int(b["workers"]) == staff and int(worker["jobs"].get(str(int(b["id"])), 0)) == 1, kind + ": existing workers retain their ordinary final payday assignment")
	check(Businesses.takeable(b) == 0, kind + ": no new worker can sign on to an obsolete farm")
	for crop in land:
		check(int(est["land"].get(crop, 0)) == int(estate_land.get(crop, 0)) + int(land[crop]), kind + ": actual acreage joins the existing estate once")
	check(absf(Barge.holdings(Game) - cash) < 0.001, kind + ": household transfer conserves coins")
	check(int(ordinary["owner"]) == -1 and ordinary.get("for_sale", false) and not ordinary.get("closed", false) and int(ordinary["kw"]) == 0, kind + ": an ordinary shop remains for sale without its departed keeper")
	Families.reassign(e, worker)
	check(not worker["jobs"].has(str(int(b["id"]))), kind + ": existing closed-job matching releases the worker")

# Use the shipped schema-1 checkpoint, not a current save with a forged version.
# The three existing case labels select three distinct real staffed farm rows.
func legacy_fixture(seed_value: int) -> Array:
	var path: String = "res://tests/fixtures/legacy_v099_save.json"
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
	check(parsed is Dictionary, "shipped older-schema farm checkpoint exists and parses")
	if not (parsed is Dictionary): return []
	var checkpoint: Dictionary = parsed as Dictionary
	var valid: bool = int(checkpoint.get("version", -1)) == 1 and checkpoint.has("world") and checkpoint.has("gold") and int(checkpoint.get("militia_cap", 0)) == 1
	check(valid, "native schema-1 checkpoint retains its actual version and militia policy")
	if not valid: return []
	Game.restore_exact(checkpoint)
	Game.wait_save()
	Game.world = Game._deserialize(checkpoint["world"])
	Game.gold = int(checkpoint["gold"])
	var wanted: int = [713, 2026, 8801].find(seed_value)
	var index: int = 0
	for t: Dictionary in Game.world["towns"].values():
		if not TownEcon.has_econ(t): continue
		var e: Dictionary = t["econ"]
		for b: Dictionary in e["biz"]:
			var owner_id: int = int(b["owner"])
			if b["type"] != "farm" or b.get("closed", false) or owner_id < 0 or owner_id >= e["fams"].size(): continue
			if int(b["workers"]) <= 0 or float(b["owed"]) <= 0.0 or int(b["tools"]) <= 0: continue
			var f: Dictionary = e["fams"][owner_id]
			if f.get("gone", false) or f.get("estate", false) or Families.serving(f) > 0 or f["land"].is_empty(): continue
			for worker: Dictionary in e["fams"]:
				if worker == f or worker.get("gone", false) or worker.get("estate", false) or Families.serving(worker) > 0: continue
				if int(worker["jobs"].get(str(int(b["id"])), 0)) != 1: continue
				if index == wanted: return [t, e, f, b, worker, checkpoint]
				index += 1
	return []

func legacy(rows: Array) -> void:
	var t: Dictionary = rows[0]; var e: Dictionary = rows[1]; var b: Dictionary = rows[3]; var worker: Dictionary = rows[4]
	var tid: String = t["id"]; var bid := int(b["id"]); var fid := int(worker["id"])
	b["owner"] = -1; b["for_sale"] = true; b["closed"] = false
	var cash := Barge.holdings(Game)
	# The native codec preserves the actual historical till and liability exactly.
	var saved: Array = [b["till"], b["owed"], b["workers"], b["tools"]]
	var keep := [float(saved[0]), float(saved[1]), int(saved[2]), int(saved[3])]
	# Stage only the existing orphan-row flags on the authentic older snapshot.
	# Keep its schema, people, coin, wage books, tools and incumbent job unchanged.
	var checkpoint: Dictionary = rows[5]
	checkpoint["world"] = Game._serialize(Game.world)
	var receipt: Dictionary = Game._write_save(Game.SAVE_PATH, checkpoint)
	check(bool(receipt.get("ok", false)), "older-schema orphan scenario writes through the native codec")
	if not bool(receipt.get("ok", false)): return
	check(Game.load_game(), "prior ownerless farm save loads")
	e = Game.world["towns"][tid]["econ"]; b = e["biz"][bid]
	check(b.get("closed", false) and int(b["cap"]) == 0 and Businesses.takeable(b) == 0, "load retires existing orphan farm vacancies")
	check(int(b["owner"]) == -1 and int(b.get("kw", 0)) == 0 and not b.get("for_sale", true), "legacy retirement removes keeper and duplicate land-sale offers")
	check([float(b["till"]), float(b["owed"]), int(b["workers"]), int(b["tools"])] == keep, "load preserves final wage books and physical tools")
	check(int(e["fams"][fid]["jobs"].get(str(bid), 0)) == 1, "load leaves incumbent assignment for normal settlement")
	check(absf(Barge.holdings(Game) - cash) < 0.001, "load invents no compensation and loses no cash")
	Game.save_game(); check(Game.load_game(), "repaired campaign loads again")
	b = Game.world["towns"][tid]["econ"]["biz"][bid]
	check([float(b["till"]), float(b["owed"]), int(b["workers"]), int(b["tools"])] == keep and b.get("closed", false), "repeat migration is idempotent")

func run(_tree: SceneTree) -> int:
	var selected_seed: String = "all"
	var selected_kind: String = "all"
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--inheritance-seed="): selected_seed = arg.trim_prefix("--inheritance-seed=")
		if arg.begins_with("--inheritance-kind="): selected_kind = arg.trim_prefix("--inheritance-kind=")
	var valid_selection: bool = selected_seed in ["all", "713", "2026", "8801"] and selected_kind in ["all", "extinct", "leave", "move", "legacy"]
	check(valid_selection, "inheritance selector names an existing seed and case")
	if not valid_selection: return fails
	WorldGen.gen_size = "normal"
	for seed_v in [713, 2026, 8801]:
		if selected_seed != "all" and str(seed_v) != selected_seed: continue
		for kind in ["extinct", "leave", "move", "legacy"]:
			if selected_kind != "all" and String(kind) != selected_kind: continue
			if kind == "legacy":
				var historical: Array = legacy_fixture(seed_v)
				check(historical.size() == 6, "real older farm with earned debt, tools and an incumbent exists")
				if historical.size() == 6: legacy(historical)
				continue
			Game.new_game(seed_v)
			var rows := fixture(); check(rows.size() == 5, "generated farm and actual worker fixture exists")
			if rows.size() == 5:
				lifecycle(kind, rows)
	print("FARM INHERITANCE seed=", selected_seed, " kind=", selected_kind, " checks=", checks, " failures=", fails)
	return fails
