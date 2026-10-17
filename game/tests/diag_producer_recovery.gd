extends RefCounted
## Read-only evidence capture: original audit selection and unchanged normal campaign days.
var selected := {}
var recent := []

func advance_normal_day() -> bool:
	var previous := Game.day
	# presim_step stops at the configured history length. Continue the same
	# campaign on_time path explicitly instead of accepting repeated snapshots.
	Game.day += 1.0
	CampaignWorld.on_time(Game, 1.0, true)
	Game.world["encounter"] = ""
	if Game.day != previous + 1.0:
		printerr("FAIL: normal-day continuation did not advance"); return false
	for town in Game.world["towns"].values():
		if TownEcon.has_econ(town) and int(town["econ"]["day"]) != int(Game.day):
			printerr("FAIL: queued town day did not close at ", town["id"]); return false
	return true

func write_json(path: String, data: Variant) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(data, "\t", true, true)); file.close()

func business_snapshot(town: Dictionary, b: Dictionary) -> Dictionary:
	var e: Dictionary = town["econ"]
	var families := []
	for f in e["fams"]:
		if int(f["id"]) == int(b["owner"]) or f["jobs"].has(str(int(b["id"]))) or b.get("wage_claims", {}).has(str(int(f["id"]))):
			var row := {}
			for key in ["id", "gone", "extinct", "moved", "wage_destination", "jobs", "purse", "hands", "idle", "last", "unpaid", "income_parts", "wage_receipts", "store", "homes", "land", "herd"]:
				if f.has(key): row[key] = f[key]
			families.append(row.duplicate(true))
	var outputs := {}
	var inputs := {}
	var recipes: Array = TownEcon.data()["businesses"][b["type"]].get("recipes", [])
	for recipe in recipes:
		for good in recipe["out"]: outputs[good] = true
		for good in recipe["in"]: inputs[good] = true
	if b["type"] == "mine": outputs[b.get("ore", "copper_ore")] = true
	var goods := {}
	for good in outputs.keys() + inputs.keys():
		var row := {"stock_cap": Businesses.stock_cap(e, good), "output": outputs.has(good), "input": inputs.has(good)}
		for key in ["stock", "barn", "price", "need", "dem", "sup", "req", "bdem", "_aimu", "_aimrest"]: row[key] = e.get(key, {}).get(good, null)
		for key in ["made", "used", "spoiled", "in", "out"]: row["ledger_" + key] = e.get("led", {}).get(key, {}).get(good, null)
		goods[good] = row
	return {"town": town["id"], "day": Game.day, "business": b.duplicate(true), "funded": Businesses.takeable(b), "hiring": Businesses.hiring(e, b),
		"families": families, "goods": goods, "market": e["biz"][int(e["mkt"])] .duplicate(true), "treasury": e["treasury"], "tax": e["tax"].duplicate(true), "stats": e["stats"].duplicate(true)}

func observations(all_producers: bool = false) -> Array:
	var rows := []
	for tid in Game.world["towns"]:
		var town: Dictionary = Game.world["towns"][tid]
		if not TownEcon.has_econ(town): continue
		var e: Dictionary = town["econ"]
		for bid in (e.get("prod", []) if all_producers else selected.get(tid, [])):
			rows.append(business_snapshot(town, e["biz"][int(bid)]))
	return rows

func run(_tree: SceneTree) -> int:
	var output := OS.get_environment("PRODUCER_OUTPUT")
	if output == "": printerr("PRODUCER_OUTPUT required"); return 1
	DirAccess.make_dir_recursive_absolute(output)
	WorldGen.gen_size = "large"; CampaignWorld.presim_years = 5
	Game.new_game(2026)
	for d in 600:
		CampaignWorld.presim_step(Game, 1)
		if d >= 572: recent.append(observations(true))
		if (d + 1) % 120 == 0: print("PRODUCER simulated day ", d + 1)
	var report := EconomyAudit.world_report(Game)
	write_json(output.path_join("audit.json"), report)
	Game._write_save(output.path_join("checkpoint_day600.json"), Game._save_tree())
	for town in report["towns"]:
		for issue in town["issues"]:
			if issue["rule"] != "full_market_broke_producer": continue
			if not selected.has(town["town"]): selected[town["town"]] = []
			selected[town["town"]].append(int(issue["business"]))
	var before := []
	for day_rows in recent:
		before.append(day_rows.filter(func(row): return selected.get(row["town"], []).has(int(row["business"]["id"]))))
	recent.clear()
	write_json(output.path_join("prior28.json"), {"selected": selected, "trace": before})
	print("PRODUCER selected=", selected)
	var after := [observations()]
	for d in 90:
		if not advance_normal_day(): return 1
		after.append(observations())
		if (d + 1) % 15 == 0:
			write_json(output.path_join("follow90.json"), {"selected": selected, "trace": after})
			print("PRODUCER continuation day ", d + 1)
	Game._write_save(output.path_join("checkpoint_day690.json"), Game._save_tree())
	write_json(output.path_join("final_audit.json"), EconomyAudit.world_report(Game))
	return 0
