extends RefCounted
## Load one supplied real-daily-tick checkpoint, without advancing or saving it.
## PROBE_DIR=user://econ_years_base_1669935 PROBE_YEAR=2 (one load per run).
func run(_tree: SceneTree) -> int:
	var directory: String = OS.get_environment("PROBE_DIR")
	if directory == "": directory = "user://econ_years"
	var year: int = maxi(1, OS.get_environment("PROBE_YEAR").to_int())
	var previous: String = Game.SAVE_PATH
	Game.SAVE_PATH = directory + "/year_%d.save" % year
	var loaded: bool = Game.load_game()
	Game.SAVE_PATH = previous
	if not loaded: return 1
	var totals: Dictionary = {}
	var dt: int = 0
	for town: Dictionary in Game.world.get("towns", {}).values():
		if not TownEcon.has_econ(town): continue
		var e: Dictionary = town["econ"]
		var food: Dictionary = {}
		for good in ["grain", "fruit"]:
			var physical: int = int(e.get("barn", {}).get(good, 0))
			var free: int = HarvestClaims.available(e, good)
			food[good] = {"barn": physical, "saleable": free, "held": physical - free,
				"market": e.get("stock", {}).get(good, 0), "demand": e.get("dem", {}).get(good, 0.0)}
		print("FLOW town=%s day=%d land=%s worked=%s food=%s market_till=%.2f" % [
			town["id"], int(e["day"]), JSON.stringify(e["land"]), JSON.stringify(e["wacres"]),
			JSON.stringify(food), float(e["biz"][int(e["mkt"])]["till"])])
		for b: Dictionary in e.get("biz", []):
			if not String(b["type"]) in ["farm", "estate", "mint"]: continue
			var f: Dictionary = e["fams"][int(b.get("public_property", maxi(0, int(b["owner"]))))] if b["type"] != "mint" else {}
			print("FLOW town=%s type=%s id=%d closed=%s workers=%d cap=%d wage=%.2f till=%.2f owed=%.2f purse=%.2f worked=%.4f state=%s why=%s" % [
				town["id"], b["type"], int(b["id"]), str(b["closed"]), int(b["workers"]), int(b["cap"]),
				float(b["wage"]), float(b["till"]), float(b.get("owed", 0.0)), float(f.get("purse", 0.0)),
				float(f.get("worked", 0.0)), b.get("state", ""), b.get("why", "")])
			if not f.is_empty():
				print("FIELD town=%s id=%d own=%d helpers=%.2f hired_effective=%.2f base_need=%.2f seasonal_need=%.2f annual_wage_limit=%.2f hungry=%d ox=%d" % [town["id"], int(b["id"]), int(f["hands"]), Barge.helper_hands(e, f, float(e["day"])), Families.field_hands(e, b), Families.need_hands(f, e), Families.seasonal_need_hands(f, float(e["day"]), e), EconomyRules.farm_hand_value(e, f), int(f["hungry"]), int(f.get("ox", -1))])
			if b["type"] == "mint":
				print("MINT_STAFF town=%s keeper=%d sick=%d funded_places=%d till=%.2f treasury=%.2f" % [town["id"], int(b.get("kw", 0)), int(b.get("sick", 0)), Businesses.takeable(b), float(b["till"]), float(e["treasury"])])
				print("MINT town=%s bday=%d room=%.2f stock=%s recipes=%s costs=%s req=%s" % [
					town["id"], int(e.get("bday", -1)), Barge.mint_room(Game.world),
					JSON.stringify(e["stock"]), JSON.stringify(Barge._mint_recipes(e)),
					JSON.stringify(Barge._mint_recipes(e).map(func(r: Dictionary) -> float: return Barge._recipe_cost(e, r))), JSON.stringify(e["req"])])
		var book: Dictionary = e.get("census", {})
		dt += int(book.get("dt", 0))
		# Seasonal counters retain bulk cohort deaths, unlike the capped
		# individual death list. Print coverage against dt rather than
		# claiming retained rows are necessarily the entire history.
		var rows: Array = book.get("rows", []).duplicate()
		rows.append(book.get("cur", {}))
		for row: Dictionary in rows:
			for cause in row.get("deaths", {}):
				totals[cause] = int(totals.get(cause, 0)) + int(row["deaths"][cause])
		for f: Dictionary in e.get("fams", []):
			if not Population.is_cohort(f) or f.get("gone", false) or float(f.get("fshort", 0.0)) <= 0.0: continue
			print("CAUSE town=%s family=%d people=%d jobs=%d idle=%d purse=%.2f income_week=%.2f short=%.3f condition=%s stock=%s barn=%s" % [
				town["id"], int(f["id"]), Families.people(f), Families.job_total(f), int(f.get("idle", 0)),
				float(f["purse"]), float(f.get("inc", 0.0)), float(f["fshort"]),
				JSON.stringify(f.get("pool_condition", {})), JSON.stringify(e.get("stock", {})), JSON.stringify(e.get("barn", {}))])
	var covered: int = 0
	for value in totals.values(): covered += int(value)
	print("CAUSE year=%d day=%d dt=%d retained_counted=%d causes=%s" % [year, int(Game.day), dt, covered, JSON.stringify(totals)])
	return 0
