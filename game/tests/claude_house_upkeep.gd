extends RefCounted
## Feature test for campaign/house_upkeep.gd:
##   1) Household staff wages scale with observed income, are charged from f["purse"] and credited to real town folk (coin conserved)
##   2) Staff tier steps down when unaffordable (with prestige loss, never below MIN_TIER, purse never < 0)
##   3) Improvement preview/start charges coin + market materials from e["stock"] (coin conserved)
##   4) AI ruling house buys only from surplus above 8-week keep and within income share caps, at most once per 30 days, never into debt
##   5) Save/load + HouseUpkeep.after_load preserves state and integer types

const SAVE: String = "user://claude_house_upkeep-test.json"

var checks: int = 0
var fails: int = 0


func _ok(cond: bool, msg: String) -> void:
	checks += 1
	if not cond:
		fails += 1
		print("FAIL: " + msg)


func _folk_purses(e: Dictionary, exclude_f: Dictionary) -> float:
	var sum: float = 0.0
	for cand in e.get("fams", []):
		if not (cand is Dictionary):
			continue
		var cf: Dictionary = cand
		if is_same(cf, exclude_f):
			continue
		sum += float(cf.get("purse", 0.0))
	return sum


func _seed_income(f: Dictionary, day_now: float, yearly_income: float, final_purse: float = -1.0) -> void:
	var end_purse: float = final_purse if final_purse >= 0.0 else float(f.get("purse", 0.0))
	var yr_days: float = float(EconGen.YEAR_DAYS)
	f.erase("house_budget")
	f["debt"] = float(f.get("debt", 0.0))
	var start_day: float = day_now - yr_days
	f["purse"] = end_purse - yearly_income
	HouseUpkeep.observe_income(f, start_day)
	var steps: int = 12
	for i in range(1, steps + 1):
		var d: float = start_day + yr_days * float(i) / float(steps)
		f["purse"] = end_purse - yearly_income + yearly_income * float(i) / float(steps)
		HouseUpkeep.observe_income(f, d)
	f["purse"] = end_purse


func _reserve_floor(e: Dictionary, f: Dictionary) -> float:
	var food: float = EconomyRules.essential_food_cost(e, float(Families.daily_rates(e, f)["food"]) * 30.0)
	return food + Barge.day_wage(e) * 28.0 + maxf(0.0, float(f.get("debt", 0.0)))


func _find_ai_ruling_house(exclude_tid: String) -> Dictionary:
	var towns: Dictionary = Game.world.get("towns", {})
	for tid_key in towns.keys():
		var tid: String = str(tid_key)
		if tid == exclude_tid:
			continue
		var town: Dictionary = towns[tid]
		var e: Dictionary = town.get("econ", {})
		if e.is_empty():
			continue
		for cand in e.get("fams", []):
			if not (cand is Dictionary):
				continue
			var f: Dictionary = cand
			if HouseUpkeep._is_ruling(Game, town, e, f) and not HouseUpkeep._is_player_house(Game, f):
				return {"town_id": tid, "town": town, "econ": e, "family": f}
	return {}


func run(tree: SceneTree) -> int:
	if not await DevTools.start_world(tree, SAVE):
		print("FAIL: start world")
		return 1
	var tid: String = DevTools.choose_house(Game)
	_ok(tid != "", "chose a starting ruling house")
	var selected: Dictionary = Dynasty.selected(Game)
	var uid: String = str(selected.get("household_uid", ""))
	_ok(uid != "", "selected household has a household_uid")
	var hit: Dictionary = Dynasty._household(Game, uid)
	var town: Dictionary = hit["town"]
	var e: Dictionary = town["econ"]
	var f: Dictionary = hit["family"]

	# ------------------------------------------------------------------ 1. Wages, income scaling & coin conservation
	HouseUpkeep.ensure(Game, town, e, f)
	f["improvements"] = {}
	f["debt"] = 0.0
	f["upkeep"]["tier"] = 1

	_seed_income(f, float(Game.day), 20000.0, 100000.0)
	var poor_sizing: Dictionary = HouseUpkeep.expected_yearly_cost(Game, uid)
	var poor_wage_1: float = HouseUpkeep.staff_cost(e, f, 1)
	var reject_t3: Dictionary = HouseUpkeep.set_staff_tier(Game, uid, 3)
	_ok(not bool(reject_t3.get("ok", false)), "cannot raise staff tier to 3 when trailing income budget is too small")

	_seed_income(f, float(Game.day), 1000000.0, 100000.0)
	var rich_sizing: Dictionary = HouseUpkeep.expected_yearly_cost(Game, uid)
	var rich_wage_1: float = HouseUpkeep.staff_cost(e, f, 1)
	_ok(float(rich_sizing["target_yearly_upkeep"]) > float(poor_sizing["target_yearly_upkeep"]) and rich_wage_1 > poor_wage_1, "richer income history yields larger upkeep budgets than poorer income history")

	var set_res: Dictionary = HouseUpkeep.set_staff_tier(Game, uid, 3)
	_ok(bool(set_res.get("ok", false)) and int(f["upkeep"]["tier"]) == 3, "set ruling house staff tier to 3")

	var town_gold_0: float = TownEcon.town_gold(e)
	var world_gold_0: float = Barge.holdings(Game)
	var folk_purse_0: float = _folk_purses(e, f)
	var house_purse_0: float = float(f["purse"])
	var expected_wage_3: float = HouseUpkeep.staff_cost(e, f, 3)

	var w1: Dictionary = HouseUpkeep.weekly(Game, town, e, f)
	_ok(bool(w1.get("ok", false)), "weekly upkeep ran on ruling house")
	_ok(expected_wage_3 > 0.0 and absf(float(w1.get("wage_paid", 0.0)) - expected_wage_3) < 0.01, "tier 3 weekly wage charged (%.1f)" % expected_wage_3)
	_ok(absf(float(f["purse"]) - (house_purse_0 - expected_wage_3)) < 0.05, "house purse debited by exact weekly wage")
	_ok(absf(_folk_purses(e, f) - (folk_purse_0 + expected_wage_3)) < 0.05, "town common folk purses credited with exact weekly wage")
	_ok(absf(TownEcon.town_gold(e) - town_gold_0) < 0.05, "town gold strictly conserved after staff wages")
	_ok(absf(Barge.holdings(Game) - world_gold_0) < 0.05, "world coin holdings strictly conserved after staff wages")

	# ------------------------------------------------------------------ 2. Tier steps down when poor
	var reserve: float = _reserve_floor(e, f)
	var wage_t2: float = HouseUpkeep.tier_cost(2) * HouseUpkeep.service_scale(e)
	var wage_t1: float = HouseUpkeep.tier_cost(1) * HouseUpkeep.service_scale(e)
	f["purse"] = reserve + wage_t2 + 200.0   # spend_room is below Tier 3 wage, above Tier 2 wage
	var prestige_before: float = float(f["upkeep"]["prestige"])
	var town_gold_poor0: float = TownEcon.town_gold(e)
	var w_poor1: Dictionary = HouseUpkeep.weekly(Game, town, e, f)
	_ok(bool(w_poor1.get("stepped_down", false)) and int(f["upkeep"]["tier"]) == 2, "staff tier stepped down from 3 to 2 when purse could not cover tier 3")
	_ok(float(f["upkeep"]["prestige"]) < prestige_before, "stepping down staff tier reduced house prestige (%.2f -> %.2f)" % [prestige_before, float(f["upkeep"]["prestige"])])
	_ok(float(f["purse"]) >= 0.0 and absf(float(w_poor1.get("wage_paid", 0.0)) - wage_t2) < 0.05, "stepped-down house paid tier 2 wage without going negative")
	_ok(absf(TownEcon.town_gold(e) - town_gold_poor0) < 0.05, "town gold conserved during tier step-down")

	# Step down again to MIN_TIER (1) with a small spend_room, then verify it never drops below MIN_TIER or goes negative
	var partial_room: float = minf(250.0, wage_t1 * 0.5)
	f["purse"] = reserve + partial_room
	var w_poor2: Dictionary = HouseUpkeep.weekly(Game, town, e, f)
	_ok(int(f["upkeep"]["tier"]) == HouseUpkeep.MIN_TIER, "staff tier stepped down to MIN_TIER (1)")
	_ok(float(f["purse"]) >= 0.0 and absf(float(w_poor2.get("wage_paid", 0.0)) - partial_room) < 0.05, "partial wage paid down to reserve floor without going negative")

	f["purse"] = 0.0
	var w_poor3: Dictionary = HouseUpkeep.weekly(Game, town, e, f)
	_ok(int(f["upkeep"]["tier"]) == HouseUpkeep.MIN_TIER and float(f["purse"]) >= 0.0 and not bool(w_poor3.get("stepped_down", false)), "house at MIN_TIER with 0 purse stays at MIN_TIER and never goes negative")

	# ------------------------------------------------------------------ 3. Improvements preview & start
	_seed_income(f, float(Game.day), 1000000.0, 250000.0)
	HouseUpkeep.set_staff_tier(Game, uid, 3)
	var st: Dictionary = e["stock"]
	st["wood"] = maxi(int(st.get("wood", 0)), 50)
	st["stone"] = maxi(int(st.get("stone", 0)), 50)
	st["tools"] = maxi(int(st.get("tools", 0)), 10)
	st["furniture"] = maxi(int(st.get("furniture", 0)), 10)
	st["iron_bars"] = maxi(int(st.get("iron_bars", 0)), 10)

	var sizing_0: Dictionary = HouseUpkeep.expected_yearly_cost(Game, uid)
	var prev1: Dictionary = HouseUpkeep.improvement_preview(Game, uid, "manor_hall")
	_ok(bool(prev1.get("ok", false)) and int(prev1.get("next_level", 0)) == 1, "manor_hall level 1 preview is ok")
	var req_mats1: Dictionary = prev1["materials"]
	var wood_0: int = int(st["wood"])
	var stone_0: int = int(st["stone"])
	var tools_0: int = int(st["tools"])
	var mkt_till_0: float = float(e["biz"][int(e["mkt"])]["till"])
	var folk_0: float = _folk_purses(e, f)
	var town_gold_imp0: float = TownEcon.town_gold(e)

	var built1: Dictionary = HouseUpkeep.start_improvement(Game, uid, "manor_hall", prev1["review"])
	_ok(bool(built1.get("ok", false)) and int(built1.get("level", 0)) == 1, "started manor_hall level 1")
	_ok(int(st["wood"]) == wood_0 - int(req_mats1["wood"]) and int(st["stone"]) == stone_0 - int(req_mats1["stone"]) and int(st["tools"]) == tools_0 - int(req_mats1["tools"]), "market stock deducted for manor_hall level 1 materials")
	_ok(absf(float(e["biz"][int(e["mkt"])]["till"]) - (mkt_till_0 + float(prev1["material_cost"]))) < 0.05, "market till credited with material cost")
	_ok(absf(_folk_purses(e, f) - (folk_0 + float(prev1["coin_cost"]))) < 0.05, "town folk credited with improvement builder coin cost")
	_ok(absf(TownEcon.town_gold(e) - town_gold_imp0) < 0.05, "town gold strictly conserved when starting improvement")

	# Upgrade manor_hall to level 2 (uses wood, stone, furniture, iron_bars)
	var prev2: Dictionary = HouseUpkeep.improvement_preview(Game, uid, "manor_hall")
	var iron_0: int = int(st["iron_bars"])
	var furn_0: int = int(st["furniture"])
	var built2: Dictionary = HouseUpkeep.start_improvement(Game, uid, "manor_hall", prev2["review"])
	_ok(bool(built2.get("ok", false)) and int(f["improvements"]["manor_hall"]["level"]) == 2, "upgraded manor_hall to level 2")
	_ok(int(st["iron_bars"]) == iron_0 - int(prev2["materials"]["iron_bars"]) and int(st["furniture"]) == furn_0 - int(prev2["materials"]["furniture"]), "iron_bars and furniture deducted from market stock for level 2")

	HouseUpkeep.weekly(Game, town, e, f)
	var sizing_1: Dictionary = HouseUpkeep.expected_yearly_cost(Game, uid)
	_ok(float(sizing_1["yearly_upkeep"]) > float(sizing_0["yearly_upkeep"]), "expected_yearly_cost increased after building manor_hall")
	_ok(int(f["upkeep"]["opinion_bonus"]) >= 8 and int(f["upkeep"]["skill_bonus"]) >= 2, "funded improvement opinion and skill bonuses applied to upkeep state")

	# ------------------------------------------------------------------ 4. AI ruling house surplus & cooldown rules
	var ai_hit: Dictionary = _find_ai_ruling_house(tid)
	_ok(not ai_hit.is_empty(), "found an AI ruling house in another settlement")
	var ai_town: Dictionary = ai_hit["town"]
	var ai_e: Dictionary = ai_hit["econ"]
	var ai_f: Dictionary = ai_hit["family"]
	HouseUpkeep.ensure(Game, ai_town, ai_e, ai_f)
	ai_f["improvements"] = {}
	ai_f["debt"] = 0.0
	ai_f["upkeep"]["tier"] = 1
	ai_f["upkeep"]["ai_purchases"] = 0
	ai_f["upkeep"]["last_ai_buy_day"] = -100
	ai_e["stock"]["wood"] = maxi(int(ai_e["stock"].get("wood", 0)), 50)
	ai_e["stock"]["stone"] = maxi(int(ai_e["stock"].get("stone", 0)), 50)
	ai_e["stock"]["tools"] = maxi(int(ai_e["stock"].get("tools", 0)), 10)

	# 4a. Below 8-week keep: AI must not buy anything
	Game.day = 40.0
	_seed_income(ai_f, float(Game.day), 1000000.0, 1500.0)
	ai_f["purse"] = HouseUpkeep.SAFE_KEEP_WEEKS * HouseUpkeep.staff_cost(ai_e, ai_f, 1) * 0.5
	var ai_w_low: Dictionary = HouseUpkeep.weekly(Game, ai_town, ai_e, ai_f)
	var ai_act_low: Dictionary = ai_w_low["ai_action"]
	_ok(not bool(ai_act_low.get("acted", false)) and int(ai_f["upkeep"]["ai_purchases"]) == 0, "AI house does not buy when purse is below 8-week keep")
	_ok(float(ai_f["purse"]) >= 0.0 and float(ai_f.get("debt", 0.0)) == 0.0, "AI house never goes into debt")

	# 4b. Rich surplus: AI makes at most 1 purchase and retains >= 8 weeks of new upkeep
	_seed_income(ai_f, float(Game.day), 1000000.0, 150000.0)
	var ai_gold_0: float = TownEcon.town_gold(ai_e)
	var ai_w_rich: Dictionary = HouseUpkeep.weekly(Game, ai_town, ai_e, ai_f)
	var ai_act_rich: Dictionary = ai_w_rich["ai_action"]
	_ok(bool(ai_act_rich.get("acted", false)) and int(ai_f["upkeep"]["ai_purchases"]) == 1, "AI house with surplus made 1 purchase")
	var ai_new_weekly: float = HouseUpkeep.staff_cost(ai_e, ai_f, int(ai_f["upkeep"]["tier"])) + HouseUpkeep.improvement_cost(ai_e, ai_f)
	_ok(float(ai_f["purse"]) >= HouseUpkeep.SAFE_KEEP_WEEKS * ai_new_weekly and float(ai_f.get("debt", 0.0)) == 0.0, "AI house kept >= 8 weeks of upkeep after purchase and stayed out of debt")
	_ok(absf(TownEcon.town_gold(ai_e) - ai_gold_0) < 0.05, "AI house purchase conserved town gold")

	# 4c. Within 30 days: AI respects monthly cooldown
	Game.day = 50.0
	var ai_w_cool: Dictionary = HouseUpkeep.weekly(Game, ai_town, ai_e, ai_f)
	var ai_act_cool: Dictionary = ai_w_cool["ai_action"]
	_ok(not bool(ai_act_cool.get("acted", false)) and int(ai_f["upkeep"]["ai_purchases"]) == 1, "AI house makes at most 1 purchase per 30 days")

	# 4d. After 30 days with surplus: AI makes its next purchase (raises staff tier)
	Game.day = 75.0
	ai_f["purse"] = 180000.0
	var ai_w_next: Dictionary = HouseUpkeep.weekly(Game, ai_town, ai_e, ai_f)
	var ai_act_next: Dictionary = ai_w_next["ai_action"]
	_ok(bool(ai_act_next.get("acted", false)) and int(ai_f["upkeep"]["ai_purchases"]) == 2 and int(ai_f["upkeep"]["tier"]) >= 2, "AI house raised staff tier from surplus after 30-day cooldown")

	# ------------------------------------------------------------------ 5. Save / load persistence & int casting
	var saved_tier: int = int(f["upkeep"]["tier"])
	var saved_prestige: float = float(f["upkeep"]["prestige"])
	var saved_imp_lvl: int = int(f["improvements"]["manor_hall"]["level"])
	var saved_ai_buys: int = int(ai_f["upkeep"]["ai_purchases"])
	var ai_uid: String = str(ai_f["household_uid"])

	Game.save_game()
	Game.wait_save()
	var loaded_ok: bool = Game.load_game()
	HouseUpkeep.after_load(Game)
	_ok(loaded_ok, "saved and reloaded campaign state")

	var hit_after: Dictionary = Dynasty._household(Game, uid)
	var f_after: Dictionary = hit_after["family"]
	var ai_after_hit: Dictionary = Dynasty._household(Game, ai_uid)
	var ai_f_after: Dictionary = ai_after_hit["family"]

	_ok(int(f_after["upkeep"]["tier"]) == saved_tier and absf(float(f_after["upkeep"]["prestige"]) - saved_prestige) < 0.05, "player house upkeep tier and prestige persisted across save/load")
	_ok(int(f_after["improvements"]["manor_hall"]["level"]) == saved_imp_lvl, "player house manor_hall level persisted across save/load")
	_ok(int(ai_f_after["upkeep"]["ai_purchases"]) == saved_ai_buys, "AI house purchase count persisted across save/load")
	_ok(typeof(f_after["upkeep"]["tier"]) == TYPE_INT and typeof(f_after["improvements"]["manor_hall"]["level"]) == TYPE_INT, "HouseUpkeep.after_load restored TYPE_INT on upkeep and improvements")

	print("upkeep: %d checks, %d failures" % [checks, fails])
	return 1 if fails > 0 else 0
