extends "res://tests/diag_producer_recovery.gd"
## Captured state is from before the day's closing prices. Probe one copied
## producer at those closing prices without advancing the world or paying wages.
func context(town: Dictionary, b: Dictionary) -> Dictionary:
	var e: Dictionary = town["econ"]
	var D := TownEcon.data()
	var T: Dictionary = D["businesses"][b["type"]]
	var recipes := []
	for r in T["recipes"]:
		var ins := Businesses._recipe_inputs(e, D, r)
		var inputs := {}
		for g in ins: inputs[g] = {"batch_units": ins[g], "stock": e["stock"].get(g, 0), "price": e["price"].get(g, 0)}
		var outputs := {}
		for g in r["out"]:
			outputs[g] = {"batch_units": r["out"][g], "stock": e["stock"].get(g, 0), "need": e["need"].get(g, 0), "demand": e["dem"].get(g, 0), "aim": e.get("_aimu", {}).get(g, null), "aim_rest": e.get("_aimrest", {}).has(g), "price": e["price"].get(g, 0)}
		recipes.append({"inputs": inputs, "outputs": outputs, "batch_cost": Businesses._batch_cost(e, ins), "batch_receipt": Businesses._batch_quote(e, r, float(D["market"]["buy_share"])), "rate": r.get("rate", 1)})
	var f: Dictionary = e["fams"][int(b["owner"])] if int(b["owner"]) >= 0 else {}
	return {"type": b["type"], "recipes": recipes, "owner_purse": f.get("purse", null), "owner_last_turn": f.get("last", null), "workers": b["workers"], "keeper": b.get("kw", 0), "owed": b.get("owed", 0), "wage_cost_day": b.get("wage_cost_day", 0), "daily_upkeep": float(Barge.B()["business"]["upkeep"][0]) + float(Barge.B()["business"]["upkeep"][1]) * float(b["workers"]), "operating_cash_quote": Businesses.operating_cash(e, b, float(b.get("owed", 0))), "hiring": Businesses.hiring(e, b), "shop_size": town.get("shop", []).size(), "shop_cap": Businesses.arms_cap(town), "tips_wanted": BowsEcon.tips_wanted(e), "weapon_orders": ArmsTrade.has_orders(e, "weapon"), "mine_full_now": String(b["type"]) == "mine" and float(e["stock"].get(b.get("ore", "copper_ore"), 0)) >= Businesses.stock_cap(e, b.get("ore", "copper_ore")) * 2.0}

func run(_tree: SceneTree) -> int:
	var source := OS.get_environment("PRODUCER_CHECKPOINT")
	var output := OS.get_environment("PRODUCER_OUTPUT")
	if source == "" or output == "": return 1
	DirAccess.make_dir_recursive_absolute(output)
	Game._write_save(Game.SAVE_PATH, JSON.parse_string(FileAccess.get_file_as_string(source)))
	if not Game.load_game(): return 1
	var before := JSON.stringify(Game._save_tree())
	var rows := []
	var report := EconomyAudit.world_report(Game)
	for tr in report["towns"]:
		for issue in tr["issues"]:
			if issue["rule"] != "full_market_broke_producer": continue
			var town: Dictionary = Game.world["towns"][tr["town"]]
			var b: Dictionary = town["econ"]["biz"][int(issue["business"])]
			var copied: Dictionary = town.duplicate(true)
			var e: Dictionary = copied["econ"]
			var cb: Dictionary = e["biz"][int(b["id"])]
			e["prod"] = [int(b["id"])]
			var row := {"town": town["id"], "business": b["id"], "context": context(town, b), "before": b.duplicate(true)}
			var cash := TownEcon.town_gold(e)
			var rng := RandomNumberGenerator.new(); rng.seed = 1337
			Businesses.daily(Game, copied, e, TownEcon.data(), Calendar.season_index(Game.day), rng)
			row["copied_one_production_call"] = cb.duplicate(true)
			row["copied_town_cash_difference"] = TownEcon.town_gold(e) - cash
			rows.append(row)
	var unchanged := JSON.stringify(Game._save_tree()) == before
	write_json(output.path_join("context.json"), {"checkpoint": source, "loaded_not_exact_vm_replay": true, "world_unchanged": unchanged, "rows": rows})
	print("FULL PRODUCER CONTEXT rows=", rows.size(), " world_unchanged=", unchanged)
	return 0 if unchanged else 1
