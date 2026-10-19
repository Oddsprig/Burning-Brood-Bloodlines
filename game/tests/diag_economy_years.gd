extends RefCounted
## One checkpoint per invocation; --year is the checkpoint number, not a time skip.
## Repeat with the next number after a budget stop. Calendar years come from Game.day.
## No grants, forced projects, cleanup, or changes to production scripts.
const ROOT: String = "user://econ_years"
const META: String = "_diag_economy_years"
const YEAR: int = 120
const STOP_MS: int = 140000
const DRAIN_MS: int = 150000

var _started: int = 0


func _path(n: int) -> String:
	return "%s/year_%d.save" % [ROOT, n]


func _rulers() -> Dictionary:
	var out: Dictionary = {}
	var towns: Dictionary = Game.world.get("towns", {})
	var ids: Array = towns.keys()
	ids.sort()
	for key in ids:
		var tid: String = str(key)
		var f: Dictionary = Feudal.tax_recipient(Game, tid)
		var uid: String = str(f.get("household_uid", ""))
		if uid == "":
			continue
		if not out.has(uid):
			out[uid] = {"uid": uid, "family": f, "towns": [], "treasury": 0.0}
		out[uid]["towns"].append(tid)
		out[uid]["treasury"] = float(out[uid]["treasury"]) + float(towns[tid].get("econ", {}).get("treasury", 0.0))
	var player: Dictionary = Feudal._payer(Game)
	var puid: String = str(player.get("household_uid", ""))
	if puid != "" and not out.has(puid):
		out[puid] = {"uid": puid, "family": player, "towns": [], "treasury": 0.0}
	return out


func _wealth(uid: String, f: Dictionary) -> float:
	var value: float = float(f.get("purse", 0.0))
	for item: Dictionary in CourtEvents.hoard_view(Game, uid):
		value += float(item.get("value", 0.0))
	return value


func _balances() -> Dictionary:
	var out: Dictionary = {}
	var rulers: Dictionary = _rulers()
	for uid in rulers:
		out[uid] = _wealth(str(uid), rulers[uid]["family"])
	return out


func _snapshot() -> Dictionary:
	var out: Dictionary = {"houses": {}, "taxes": {}}
	var rulers: Dictionary = _rulers()
	for uid in rulers:
		var f: Dictionary = rulers[uid]["family"]
		var up: Dictionary = f.get("upkeep", {})
		var builds: Dictionary = {}
		for key in f.get("improvements", {}):
			var imp: Dictionary = f["improvements"][key]
			builds[key] = "%d:%d" % [int(imp.get("built_day", -1)), int(imp.get("level", 0))]
		out["houses"][uid] = {
			"last": float(f.get("last", Game.day)),
			"staff": float(up.get("total_wages_paid", 0.0)),
			"improvements": float(up.get("total_imp_upkeep_paid", 0.0)),
			"builds": builds,
		}
	for tid in Game.world.get("towns", {}):
		var town: Dictionary = Game.world["towns"][tid]
		out["taxes"][tid] = {
			"uid": str(Feudal.tax_recipient(Game, str(tid)).get("household_uid", "")),
			"tax": float(town.get("econ", {}).get("stats", {}).get("lord_tax", 0.0)),
			"allowance": float(town.get("econ", {}).get("stats", {}).get("allowance_total", 0.0)),
			"allowance_uid": str(town.get("econ", {}).get("stats", {}).get("allowance_uid", "")),
		}
	return out


func _add(state: Dictionary, uid: String, key: String, value: float) -> void:
	if uid == "":
		return
	if not state["flows"].has(uid):
		state["flows"][uid] = {}
	var row: Dictionary = state["flows"][uid]
	row[key] = float(row.get(key, 0.0)) + value


func _collect(state: Dictionary, before: Dictionary) -> void:
	var after: Dictionary = _snapshot()
	var rulers: Dictionary = _rulers()
	for uid in rulers:
		var f: Dictionary = rulers[uid]["family"]
		var pre: Dictionary = before["houses"].get(uid, {})
		var post: Dictionary = after["houses"][uid]
		if pre.is_empty():
			continue # Do not count a new ruler's inherited history as this year's income.
		var span: float = float(post["last"]) - float(pre["last"])
		if span > 0.0:
			var parts: Dictionary = f.get("income_parts", {})
			_add(state, str(uid), "land", float(parts.get("land", 0.0)) * span / 7.0)
			_add(state, str(uid), "business", (float(parts.get("business profit", 0.0)) + float(parts.get("business funding", 0.0))) * span / 7.0)
			_add(state, str(uid), "wages", (float(parts.get("staff wages", 0.0)) + float(parts.get("casual work", 0.0))) * span / 7.0)
		_add(state, str(uid), "staff", maxf(0.0, float(post["staff"]) - float(pre["staff"])))
		_add(state, str(uid), "improvements", maxf(0.0, float(post["improvements"]) - float(pre["improvements"])))
		for key in f.get("improvements", {}):
			if str(post["builds"][key]) != str(pre["builds"].get(key, "")):
				_add(state, str(uid), "builds", float(f["improvements"][key].get("total_cost", 0.0)))
	for tid in after["taxes"]:
		var post_tax: Dictionary = after["taxes"][tid]
		var pre_tax: Dictionary = before["taxes"].get(tid, post_tax)
		_add(state, str(pre_tax["uid"]), "lord_tax", maxf(0.0, float(post_tax["tax"]) - float(pre_tax["tax"])))
		_add(state, str(post_tax["allowance_uid"]), "allowance", maxf(0.0, float(post_tax["allowance"]) - float(pre_tax["allowance"])))
	var day: int = int(floor(Game.day))
	for tid in Game.world.get("feudal", {}).get("towns", {}):
		var row: Dictionary = Game.world["feudal"]["towns"][tid]
		if int(row.get("tribute_day", -1)) != day:
			continue
		var parent: String = str(row.get("liege_town_id", ""))
		var amount: float = float(row.get("tribute", 0.0))
		var payer: String = str(Feudal.tax_recipient(Game, str(tid)).get("household_uid", ""))
		var recipient: String = str(Feudal.tax_recipient(Game, parent).get("household_uid", ""))
		_add(state, recipient, "tribute", amount)
		_add(state, payer, "tribute_out", amount)
	for dragon: Dictionary in Game.world.get("dragons", {}).get("records", {}).values():
		var receipt: Dictionary = dragon.get("care", {}).get("last", {})
		if int(receipt.get("day", -1)) == day:
			_add(state, str(receipt.get("payer_household_uid", "")), "dragon", float(receipt.get("food_cost", 0.0)) + float(receipt.get("upkeep_cost", 0.0)))
	state["days"] = int(state["days"]) + 1
	state["pending"] = {}


func _pair(coin: float, wage: float) -> String:
	if wage <= 0.0:
		return "%.2fc/NAld" % coin
	return "%.2fc/%.2fld" % [coin, coin / wage]


func _report(state: Dictionary, checkpoint: int, ran: int) -> Dictionary:
	var rulers: Dictionary = _rulers()
	var rows: Array = rulers.values()
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var an: int = a["towns"].size()
		var bn: int = b["towns"].size()
		return an > bn if an != bn else str(a["uid"]) < str(b["uid"])
	)
	var day: int = int(floor(Game.day))
	var days: int = int(state["days"])
	var scale: float = float(YEAR) / float(maxi(1, days))
	var pending: bool = not (state["pending"] as Dictionary).is_empty()
	var complete: bool = not pending and day >= int(state["end"])
	print("YEARS checkpoint=%d day=%d calendar_year=%d days_ran=%d year_days_settled=%d/120 complete=%s pending_work=%d save=%s" % [
		checkpoint, day, int(state["year"]), ran, days, str(complete),
		(Game.world.get("work", []) as Array).size(), _path(checkpoint)])
	print("YEARS basis=observed_flows_annualized_120/settled_days; income_parts=weekly*turn_span/7; troop_and_court=BUDGETS_not_receipts; units=c_coin/ld_labourer_days; classes=small_0-1,medium_2-4,great_5+; holdings=direct_offices_by_household")
	var previous: Dictionary = state["previous"]
	var current: Dictionary = {}
	var ratios: Array[String] = []
	var classes: Dictionary = {"small": [], "medium": [], "great": []}
	for row: Dictionary in rows:
		var uid: String = str(row["uid"])
		var f: Dictionary = row["family"]
		var home: Dictionary = Dynasty._household(Game, uid)
		var town: Dictionary = home.get("town", {})
		var wage: float = Barge.day_wage(town.get("econ", {}))
		var flow: Dictionary = state["flows"].get(uid, {})
		var count: int = row["towns"].size()
		var category: String = "small" if count <= 1 else ("medium" if count <= 4 else "great")
		var wealth: float = _wealth(uid, f)
		current[uid] = wealth
		var name: String = str(f.get("name", uid)).replace("\n", " ").replace("\r", " ")
		var role: String = "player" if uid == str(Game.world.get("player_house", {}).get("household_uid", "")) else "AI"
		var income: float = 0.0
		var bits: Array[String] = []
		for key in ["land", "business", "lord_tax", "tribute", "wages", "allowance"]:
			var amount: float = float(flow.get(key, 0.0)) * scale
			income += amount
			bits.append("%s=%s" % [key, _pair(amount, wage)])
		if wage > 0.0:
			classes[category].append(income / wage)
		for key in ["staff", "improvements", "builds", "tribute_out", "dragon"]:
			bits.append("%s_sink=%s" % [key, _pair(float(flow.get(key, 0.0)) * scale, wage)])
		var troop: float = TroopUpkeep.expected_yearly_cost(Game, uid)
		var wage_share: float = TroopUpkeep.WAGE_WEEK / (TroopUpkeep.WAGE_WEEK + TroopUpkeep.KEEP_WEEK)
		bits.append("troop_wages_budget=%s" % _pair(troop * wage_share, wage))
		bits.append("troop_kit_budget=%s" % _pair(troop * (1.0 - wage_share), wage))
		var repair: float = float(Game.world.get("troop_upkeep", {}).get("houses", {}).get(uid, {}).get("repair", 0.0))
		bits.append("troop_repair_due=%s" % _pair(repair, wage))
		bits.append("court_budget=%s" % _pair(float(CourtEvents.expected_yearly_cost(Game, uid)), wage))
		bits.append("disposable_year=%s" % _pair(HouseUpkeep.recent_income(f), wage))
		print("YEARS day=%d %s uid=%s name=%s towns=%d class=%s wage=%.4fc/day wage_town=%s purse=%s hoard=%s treasury=%s income_year=%s %s" % [
			day, role, uid, JSON.stringify(name), count, category, wage, str(town.get("id", "")),
			_pair(float(f.get("purse", 0.0)), wage), _pair(wealth - float(f.get("purse", 0.0)), wage),
			_pair(float(row["treasury"]), wage), _pair(income, wage), " ".join(bits)])
		var base: float = float(previous.get(uid, 0.0))
		var ratio: String = "%.4f" % (wealth / base) if previous.has(uid) and base > 0.0 else "NA"
		ratios.append("%s=%s" % [uid, ratio])
	print("YEARS day=%d purse_plus_hoard/previous_year_end year=%d previous_day=%d partial=%s %s" % [
		day, int(state["year"]), int(state["previous_day"]), str(not complete), " ".join(ratios)])
	var means: Array[String] = []
	for key in ["small", "medium", "great"]:
		var values: Array = classes[key]
		var total: float = 0.0
		for value in values:
			total += float(value)
		var mean: String = "%.2fld" % (total / float(values.size())) if not values.is_empty() else "NA"
		means.append("%s_n=%d mean_income_year=%s" % [key, values.size(), mean])
	print("YEARS day=%d classes %s" % [day, " ".join(means)])
	var extinct: int = 0
	var vacancies: Array[String] = []
	for town: Dictionary in Game.world.get("towns", {}).values():
		for f: Dictionary in town.get("econ", {}).get("fams", []):
			if not Population.is_cohort(f) and f.get("extinct", false): extinct += 1
		var tid: String = str(town["id"])
		if Feudal.tax_recipient(Game, tid).is_empty():
			vacancies.append("%s:%s:heirs=%d" % [tid, Dynasty.law(Game, tid), Dynasty.heirs(Game, tid).size()])
	print("YEARS living_households=%d extinct_households=%d vacant_offices=%s" % [Ennoble.house_count(Game), extinct, ",".join(vacancies)])
	return current


func _choose_start() -> String:
	# Match diag_economy_flow: prefer the local owner of a living adult dragon.
	for dragon: Dictionary in Dragons.records(Game):
		if str(dragon.get("stage", "")) != "adult" or not bool(dragon.get("alive", false)):
			continue
		var owner: Dictionary = Dragons._person(Game, str(dragon.get("owner_person_uid", "")))
		if owner.is_empty() or str(dragon.get("location_town_id", "")) != str(owner.get("town_id", "")):
			continue
		if bool(HouseOnboarding.begin(Game, str(owner["town_id"]), str(owner["household_uid"])).get("ok", false)):
			return str(owner["town_id"])
	return DevTools.choose_house(Game)


func _run(tree: SceneTree, checkpoint: int) -> void:
	var target: String = _path(checkpoint)
	if FileAccess.file_exists(target):
		print("YEARS stopped: checkpoint already exists; use the next --year number: %s" % target)
		return
	if DirAccess.make_dir_recursive_absolute(ROOT) != OK:
		print("YEARS stopped: cannot create checkpoint directory")
		return
	if checkpoint == 1:
		Game.settings["guide_seen"] = true
		if not await DevTools.start_world(tree, target):
			print("YEARS stopped: DevTools.start_world failed")
			return
		var tid: String = _choose_start()
		if tid == "":
			print("YEARS stopped: no eligible player house")
			return
		DevTools.stand_at(Game, tid)
		var origin: int = int(floor(Game.day))
		Game.world[META] = {"year": 1, "end": origin + YEAR, "days": 0, "flows": {},
			"pending": {}, "previous": _balances(), "previous_day": origin}
	else:
		Game.SAVE_PATH = _path(checkpoint - 1)
		if not Game.load_game() or not Game.world.has(META):
			print("YEARS stopped: previous diagnostic checkpoint missing or invalid: %s" % Game.SAVE_PATH)
			return
	Game.SAVE_PATH = target
	var state: Dictionary = Game.world[META]
	if (state["pending"] as Dictionary).is_empty() and int(floor(Game.day)) >= int(state["end"]):
		state["year"] = int(state["year"]) + 1
		state["end"] = int(state["end"]) + YEAR
		state["days"] = 0
		state["flows"] = {}
	var start_days: int = int(state["days"])
	while true:
		if not (state["pending"] as Dictionary).is_empty():
			while not (Game.world.get("work", []) as Array).is_empty() and Time.get_ticks_msec() - _started < DRAIN_MS:
				CampaignWorld.work_slice(Game, 100000)
				await tree.process_frame
			if not (Game.world.get("work", []) as Array).is_empty():
				break
			Game.world["encounter"] = ""
			_collect(state, state["pending"])
		if int(floor(Game.day)) >= int(state["end"]) or Time.get_ticks_msec() - _started >= STOP_MS:
			break
		state["pending"] = _snapshot()
		Game.advance_time(1.0, false, 0, 0)
		await tree.process_frame
	var current: Dictionary = _report(state, checkpoint, int(state["days"]) - start_days)
	if (state["pending"] as Dictionary).is_empty() and int(floor(Game.day)) >= int(state["end"]):
		state["previous"] = current
		state["previous_day"] = int(floor(Game.day))
	# Persist the real ordered work queue, partial-year totals and prior-year balances together.
	Game.save_game()
	Game.wait_save()
	print("YEARS checkpoint_written=%s elapsed_ms=%d path=%s" % [
		str(bool(Game.save_stats().get("last_ok", false))), Time.get_ticks_msec() - _started, target])


func run(tree: SceneTree) -> int:
	_started = Time.get_ticks_msec()
	var checkpoint: int = 1
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--year="):
			checkpoint = int(arg.substr(7))
	Game.wait_save()
	var old_path: String = Game.SAVE_PATH
	if checkpoint < 1:
		print("YEARS stopped: --year must be a positive checkpoint number")
	else:
		await _run(tree, checkpoint)
	Game.wait_save()
	Game.SAVE_PATH = old_path
	return 0
