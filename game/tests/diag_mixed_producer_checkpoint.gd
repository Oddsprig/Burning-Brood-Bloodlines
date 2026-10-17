extends "res://tests/diag_full_producer_context.gd"
## Bounded causal component comparison. Actual loaded property/coins and ordinary
## owner, production and books functions; no simulated household or price days.
func run(_tree: SceneTree) -> int:
	var source := OS.get_environment("PRODUCER_CHECKPOINT")
	var output := OS.get_environment("PRODUCER_OUTPUT")
	var baseline := OS.get_environment("PRODUCER_BASELINE_SOURCE")
	if source == "" or output == "" or baseline == "": return 1
	DirAccess.make_dir_recursive_absolute(output)
	Game._write_save(Game.SAVE_PATH, JSON.parse_string(FileAccess.get_file_as_string(source)))
	if not Game.load_game(): return 1
	var before := JSON.stringify(Game._save_tree())
	var old := GDScript.new()
	old.source_code = FileAccess.get_file_as_string(baseline).replace("class_name Businesses", "")
	if old.reload() != OK: return 1
	var reports := []
	for town in Game.world["towns"].values():
		if not TownEcon.has_econ(town): continue
		for b in town["econ"]["biz"]:
			if b.get("closed", false) or String(b["type"]) != "weaponsmith" or int(b["workers"]) != 0 or int(b.get("kw", 0)) != 1: continue
			if b.get("state", "") != "full" or float(b["till"]) >= float(b["wage"]): continue
			var comparison := {"town": town["id"], "business": b["id"], "context": context(town, b), "runs": []}
			for mode in ["baseline", "candidate"]:
				var copied: Dictionary = town.duplicate(true)
				var e: Dictionary = copied["econ"]; var cb: Dictionary = e["biz"][int(b["id"])]
				e["prod"] = [int(b["id"])]
				var owner: Dictionary = e["fams"][int(b["owner"])]
				var cash := TownEcon.town_gold(e)
				var made: Dictionary = e["led"]["made"].duplicate()
				var used: Dictionary = e["led"]["used"].duplicate()
				var trace := []
				var rng := RandomNumberGenerator.new(); rng.seed = 1337
				for day in 16:
					if day % 7 == 0: Businesses.owner_turn(e, owner, cb)
					if mode == "baseline": old.daily(Game, copied, e, TownEcon.data(), Calendar.season_index(Game.day), rng)
					else: Businesses.daily(Game, copied, e, TownEcon.data(), Calendar.season_index(Game.day), rng)
					Businesses.books_day(e)
					trace.append({"call": day + 1, "till": cb["till"], "owner_purse": owner["purse"], "state": cb["state"], "recipe_carry": cb["carry"], "arms_carry": cb.get("arms_carry", null)})
				var delta_made := {}; var delta_used := {}
				for g in e["led"]["made"]: delta_made[g] = int(e["led"]["made"][g]) - int(made.get(g, 0))
				for g in e["led"]["used"]: delta_used[g] = int(e["led"]["used"][g]) - int(used.get(g, 0))
				comparison["runs"].append({"mode": mode, "made": delta_made, "used": delta_used, "cash_difference": TownEcon.town_gold(e) - cash, "owed": cb["owed"], "trace": trace})
			reports.append(comparison)
	var unchanged := JSON.stringify(Game._save_tree()) == before
	write_json(output.path_join("mixed-checkpoint.json"), {"checkpoint": source, "baseline_sha256": FileAccess.get_file_as_string(baseline).sha256_text(), "loaded_not_exact_vm_replay": true, "component_calls_not_campaign_days": 16, "world_unchanged": unchanged, "rows": reports})
	print("MIXED CHECKPOINT rows=", reports.size(), " world_unchanged=", unchanged)
	return 0 if unchanged else 1
