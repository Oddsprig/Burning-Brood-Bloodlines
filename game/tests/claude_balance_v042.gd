extends RefCounted
## Roadmap v0.042 balance pass: print metrics, then band-check the v0.042 targets.
## Measures v0.037-v0.041 systems (settlement, breeding, tactics, inheritance laws, character designer)
## on the default small world with a one-day history and prints "balance042: <key>=<value>".
## Run headless: -- --test=res://tests/claude_balance_v042.gd

var previous_save_path: String = ""
var checks: int = 0
var fails: int = 0
var metrics: Dictionary = {}


func _metric(key: String, val: float) -> void:
	metrics[key] = val
	print("balance042: %s=%.2f" % [key, val])


func _band(key: String, lo: float, hi: float) -> void:
	checks += 1
	var val: float = float(metrics.get(key, -999999.0))
	var shown: float = float("%.2f" % val)
	if shown < lo or shown > hi:
		fails += 1
		printerr("FAIL balance042: %s=%.2f outside %.2f..%.2f" % [key, shown, lo, hi])


func _apply_bands() -> void:
	_band("settlement_catalog_all_buildings_total_cost", 40000.0, 50000.0)
	_band("settlement_player_food_stock_capacity_ratio", 0.2, 0.95)
	_band("settlement_player_famine_days", 0.0, 10.0)
	_band("settlement_player_no_build_famine_days", 0.0, 25.0)
	for tactic_name in ["charge", "hold", "flank", "skirmish", "feint"]:
		_band("tactics_winrate_%s_vs_ai_adapted" % tactic_name, 38.0, 52.0)
	_band("tactics_winrate_hills_hold_vs_ai_r1", 42.0, 58.0)
	_band("tactics_max_raw_edge", 0.15, 0.25)
	_band("tactics_max_eff_edge_skill10", 0.20, 0.30)
	_band("breeding_days_to_reach_cap", 450.0, 660.0)
	checks += 1
	if float(metrics.get("settlement_player_winter_days", 0.0)) <= 0.0:
		fails += 1
		printerr("FAIL balance042: 120-day run did not cross a winter")


func _ruler_purse(tid: String) -> float:
	if Settlement.is_player_town(Game, tid):
		var payer: Dictionary = Feudal._payer(Game)
		return float(payer.get("purse", 0.0))
	var rec: Dictionary = Feudal.tax_recipient(Game, tid)
	return float(rec.get("purse", 0.0))


func _market_income_per_level(town: Dictionary) -> float:
	var e: Dictionary = Settlement.ensure_town(town)
	var stats: Dictionary = e.get("stats", {}) if e.get("stats") is Dictionary else {}
	var base_trade: float = Settlement._num(stats.get("mtax", stats.get("tax_month", 0.0)), 0.0) / 30.0
	if base_trade < 2.0:
		base_trade = 2.0
	return base_trade * Settlement.MARKET_BONUS_PER_LEVEL


func _measure_catalog() -> void:
	var total_cost_all: int = 0
	var total_days_all: int = 0
	for k in Settlement.KEYS:
		var key: String = str(k)
		var b_cost: int = 0
		var b_days: int = 0
		for lvl in range(1, Settlement.MAX_LEVEL + 1):
			var c: int = Settlement.cost_for_level(key, lvl)
			var d: int = Settlement.days_for_level(key, lvl)
			b_cost += c
			b_days += d
			_metric("settlement_catalog_%s_lv%d_cost" % [key, lvl], float(c))
			_metric("settlement_catalog_%s_lv%d_days" % [key, lvl], float(d))
		total_cost_all += b_cost
		total_days_all += b_days
		_metric("settlement_catalog_%s_total_cost" % key, float(b_cost))
		_metric("settlement_catalog_%s_total_days" % key, float(b_days))
	_metric("settlement_catalog_all_buildings_total_cost", float(total_cost_all))
	_metric("settlement_catalog_all_buildings_total_days", float(total_days_all))


func _measure_laws(player_tid: String) -> void:
	var lock_days: int = Dynasty.law_lock_days()
	var grievance: float = float(Dynasty.LAW_GRIEVANCE)
	var st: Dictionary = Dynasty.law_status(Game, player_tid)
	var cur_law: String = str(st.get("law", "male_preference"))
	var alt_law: String = "absolute" if cur_law != "absolute" else "elective"
	var prev: Dictionary = Dynasty.change_law_preview(Game, alt_law, player_tid)
	if prev.has("grievance"):
		grievance = float(prev["grievance"])
	_metric("laws_grievance_per_change", grievance)
	_metric("laws_lock_days", float(lock_days))
	_metric("laws_lock_years", float(Dynasty.LAW_LOCK_YEARS))


func _measure_character_designer() -> void:
	var bonus: int = int(CharacterDesign.FOCUS_BONUS)
	_metric("character_design_focus_bonus", float(bonus))
	_metric("character_design_focus_count", float(CharacterDesign.FOCUS_SKILLS.size()))


func _measure_breeding() -> void:
	var ph: Dictionary = Game.world.get("player_house", {})
	var house_uid: String = str(ph.get("house_uid", ""))
	var mother_uid: String = ""
	var father_uid: String = ""
	var records: Dictionary = Game.world.get("dragons", {}).get("records", {})
	var ids: Array = records.keys()
	ids.sort()
	for id_v in ids:
		var uid: String = str(id_v)
		var row: Dictionary = records[uid]
		if not bool(row.get("alive", false)) or str(row.get("stage", "")) != "adult":
			continue
		if str(row.get("owner_house_uid", "")) != house_uid:
			continue
		if str(row.get("sex", "")) == "female" and mother_uid == "":
			mother_uid = uid
		elif str(row.get("sex", "")) == "male" and father_uid == "":
			father_uid = uid
	var initial_count: int = DragonBreeding.house_dragon_count(Game, house_uid)
	var prev: Dictionary = DragonBreeding.pair_preview(Game, mother_uid, father_uid)
	var lay_days: int = int(prev.get("lay_days", DragonBreeding._lay_delay(Game, mother_uid, father_uid, 0)))
	var clutch_size: int = int(prev.get("clutch_estimate", DragonBreeding._clutch_count(Game, mother_uid, father_uid, 0, DragonLife.MAX_DRAGONS_PER_HOUSE - initial_count)))
	var lay_sum: float = 0.0
	var lay_min: int = 999
	var lay_max: int = 0
	var clutch_sum: float = 0.0
	var clutch_min: int = 999
	var clutch_max: int = 0
	for s in 100:
		var ld: int = DragonBreeding._lay_delay(Game, mother_uid, father_uid, s)
		var cs: int = DragonBreeding._clutch_count(Game, mother_uid, father_uid, s, 3)
		lay_sum += float(ld)
		lay_min = mini(lay_min, ld)
		lay_max = maxi(lay_max, ld)
		clutch_sum += float(cs)
		clutch_min = mini(clutch_min, cs)
		clutch_max = maxi(clutch_max, cs)
	# Pure function simulation of clutches until house cap is reached (restoring state afterwards).
	var saved_dragons: Dictionary = (Game.world["dragons"] as Dictionary).duplicate(true)
	var saved_log: Array = (Game.world.get("log", []) as Array).duplicate(true)
	var saved_day: float = float(Game.day)
	var clutches_to_cap: int = 0
	var days_to_cap: int = 0
	var count_at_120d: int = initial_count
	var cap_reached_120d: int = 0
	var cap_reached_ever: int = 0
	if mother_uid != "" and father_uid != "" and bool(prev.get("ok", false)):
		var start_day: int = int(floor(saved_day))
		DragonBreeding.pair(Game, mother_uid, father_uid, prev)
		var reg: Dictionary = Game.world["dragons"]["records"]
		for d_offset in range(1, 1001):
			var sim_day: int = start_day + d_offset
			Game.day = float(sim_day)
			var laid: Array = DragonBreeding.breed_chosen_pairs(Game, reg, sim_day)
			var cur_count: int = DragonBreeding.house_dragon_count(Game, house_uid)
			if d_offset == 120:
				count_at_120d = cur_count
				if cur_count >= DragonLife.MAX_DRAGONS_PER_HOUSE:
					cap_reached_120d = 1
			if not laid.is_empty():
				clutches_to_cap += 1
				if cur_count >= DragonLife.MAX_DRAGONS_PER_HOUSE and cap_reached_ever == 0:
					cap_reached_ever = 1
					days_to_cap = d_offset
					if d_offset >= 120:
						break
	Game.day = saved_day
	Game.world["dragons"] = saved_dragons
	Game.world["log"] = saved_log

	_metric("breeding_days_to_first_clutch", float(lay_days))
	_metric("breeding_lay_days_min", float(lay_min))
	_metric("breeding_lay_days_max", float(lay_max))
	_metric("breeding_lay_days_avg", lay_sum / 100.0)
	_metric("breeding_clutch_size", float(clutch_size))
	_metric("breeding_clutch_size_min", float(clutch_min))
	_metric("breeding_clutch_size_max", float(clutch_max))
	_metric("breeding_clutch_size_avg", clutch_sum / 100.0)
	_metric("breeding_hatch_days_full_care", float(DragonLife.HATCH_DAYS))
	_metric("breeding_hatch_days_no_keeper", float(DragonLife.HATCH_DAYS) * 2.0)
	_metric("breeding_mature_days", float(DragonLife.MATURE_DAYS))
	_metric("breeding_cooldown_days", float(DragonLife.BREED_COOLDOWN))
	_metric("breeding_house_cap", float(DragonLife.MAX_DRAGONS_PER_HOUSE))
	_metric("breeding_house_initial_count", float(initial_count))
	_metric("breeding_house_count_at_120d", float(count_at_120d))
	_metric("breeding_cap_reached_120d", float(cap_reached_120d))
	_metric("breeding_cap_reached", float(cap_reached_ever))
	_metric("breeding_clutches_to_reach_cap", float(clutches_to_cap))
	_metric("breeding_days_to_reach_cap", float(days_to_cap))


func _measure_tactics() -> void:
	var terrains: Array[String] = ["grassland", "forest", "hills"]
	var max_raw_edge: float = 0.0
	var max_eff_edge_sk10: float = 0.0
	var max_mult_above_one_sk0: float = 0.0
	var max_side_diff_avg_sk0: float = 0.0
	var max_side_diff_sum_sk0: float = 0.0
	var max_side_diff_avg_sk10: float = 0.0

	for terrain in terrains:
		for t0 in BattleTactics.ORDER:
			for t1 in BattleTactics.ORDER:
				var st0: Dictionary = {
					"round": 1,
					"terrain": terrain,
					"tactics": [t0, t1],
					"tactician": [0, 0],
					"defender_side": 1,
				}
				var mods0: Dictionary = BattleTactics.modifiers(null, st0)
				var s0: Dictionary = mods0["side0"]
				var s1: Dictionary = mods0["side1"]
				var s0_att: float = float(s0["attack"])
				var s0_def: float = float(s0["defence"])
				var s0_mor: float = float(s0["morale"])
				var s1_att: float = float(s1["attack"])
				var s1_def: float = float(s1["defence"])
				var s1_mor: float = float(s1["morale"])

				var prefix: String = "tactics_%s_%s_vs_%s" % [terrain, t0, t1]
				_metric(prefix + "_s0_attack", s0_att)
				_metric(prefix + "_s0_defence", s0_def)
				_metric(prefix + "_s0_morale", s0_mor)
				_metric(prefix + "_s1_attack", s1_att)
				_metric(prefix + "_s1_defence", s1_def)
				_metric(prefix + "_s1_morale", s1_mor)

				for side_idx in 2:
					var my_t: String = t0 if side_idx == 0 else t1
					var foe_t: String = t1 if side_idx == 0 else t0
					var raw_e: float = absf(BattleTactics.counter_mod(my_t, foe_t) + BattleTactics.terrain_mod(terrain, my_t, side_idx, 1))
					if raw_e > max_raw_edge:
						max_raw_edge = raw_e
					var eff_e10: float = raw_e * BattleTactics.tactician_scale(10) + BattleTactics.tactician_bonus(10) * 0.12
					if eff_e10 > max_eff_edge_sk10:
						max_eff_edge_sk10 = eff_e10

				var m_above: float = maxf(maxf(absf(s0_att - 1.0), absf(s0_def - 1.0)), maxf(absf(s1_att - 1.0), absf(s1_def - 1.0)))
				if m_above > max_mult_above_one_sk0:
					max_mult_above_one_sk0 = m_above

				var sum0: float = s0_att + s0_def + s0_mor
				var sum1: float = s1_att + s1_def + s1_mor
				var diff_sum: float = absf(sum0 - sum1)
				var diff_avg: float = diff_sum / 3.0
				if diff_sum > max_side_diff_sum_sk0:
					max_side_diff_sum_sk0 = diff_sum
				if diff_avg > max_side_diff_avg_sk0:
					max_side_diff_avg_sk0 = diff_avg

				var st10: Dictionary = {
					"round": 1,
					"terrain": terrain,
					"tactics": [t0, t1],
					"tactician": [10, 0],
					"defender_side": 1,
				}
				var mods10: Dictionary = BattleTactics.modifiers(null, st10)
				var m10_0: Dictionary = mods10["side0"]
				var m10_1: Dictionary = mods10["side1"]
				var diff10_avg: float = absf(
					(float(m10_0["attack"]) + float(m10_0["defence"]) + float(m10_0["morale"]))
					- (float(m10_1["attack"]) + float(m10_1["defence"]) + float(m10_1["morale"]))
				) / 3.0
				if diff10_avg > max_side_diff_avg_sk10:
					max_side_diff_avg_sk10 = diff10_avg

	# Win-rate of each tactic vs ai_pick over 200 seeded math-only rounds.
	for t0 in BattleTactics.ORDER:
		var wins_all_r1: float = 0.0
		var wins_all_adapted: float = 0.0
		var total_all: int = 0
		for terrain in terrains:
			var wins_r1: float = 0.0
			var wins_adapted: float = 0.0
			for i in range(1, 201):
				var bseed: int = i * 97 + 13
				# Round 1: AI picks without knowing player's tactic.
				var st_r1: Dictionary = {
					"round": 1,
					"terrain": terrain,
					"seed": bseed,
					"tactician": [0, 0],
					"defender_side": 1,
					"log": [],
				}
				var ai_t_r1: String = BattleTactics.ai_pick(st_r1, 1, 1)
				st_r1["tactics"] = [t0, ai_t_r1]
				var m_r1: Dictionary = BattleTactics.modifiers(null, st_r1)
				var m0_r1: Dictionary = m_r1["side0"]
				var m1_r1: Dictionary = m_r1["side1"]
				var str0_r1: float = float(m0_r1["attack"]) + float(m0_r1["defence"]) + float(m0_r1["morale"])
				var str1_r1: float = float(m1_r1["attack"]) + float(m1_r1["defence"]) + float(m1_r1["morale"])
				if is_equal_approx(str0_r1, str1_r1):
					wins_r1 += 0.5
				elif str0_r1 > str1_r1:
					wins_r1 += 1.0

				# Round 2+: AI adapts to player's previous tactic (t0).
				var st_ad: Dictionary = {
					"round": 2,
					"terrain": terrain,
					"seed": bseed,
					"tactician": [0, 0],
					"defender_side": 1,
					"last_tactics": [t0, ai_t_r1],
					"log": [{"tactics": [t0, ai_t_r1]}],
				}
				var ai_t_ad: String = BattleTactics.ai_pick(st_ad, 1, 2)
				st_ad["tactics"] = [t0, ai_t_ad]
				var m_ad: Dictionary = BattleTactics.modifiers(null, st_ad)
				var m0_ad: Dictionary = m_ad["side0"]
				var m1_ad: Dictionary = m_ad["side1"]
				var str0_ad: float = float(m0_ad["attack"]) + float(m0_ad["defence"]) + float(m0_ad["morale"])
				var str1_ad: float = float(m1_ad["attack"]) + float(m1_ad["defence"]) + float(m1_ad["morale"])
				if is_equal_approx(str0_ad, str1_ad):
					wins_adapted += 0.5
				elif str0_ad > str1_ad:
					wins_adapted += 1.0

			_metric("tactics_winrate_%s_%s_vs_ai_r1" % [terrain, t0], (wins_r1 / 200.0) * 100.0)
			_metric("tactics_winrate_%s_%s_vs_ai_adapted" % [terrain, t0], (wins_adapted / 200.0) * 100.0)
			wins_all_r1 += wins_r1
			wins_all_adapted += wins_adapted
			total_all += 200
		_metric("tactics_winrate_%s_vs_ai" % t0, (wins_all_r1 / float(total_all)) * 100.0)
		_metric("tactics_winrate_%s_vs_ai_adapted" % t0, (wins_all_adapted / float(total_all)) * 100.0)

	_metric("tactics_max_raw_edge", max_raw_edge)
	_metric("tactics_max_eff_edge_skill10", max_eff_edge_sk10)
	_metric("tactics_max_mult_edge_skill0", max_mult_above_one_sk0)
	_metric("tactics_max_total_edge", max_side_diff_sum_sk0)
	_metric("tactics_max_avg_edge_skill0", max_side_diff_avg_sk0)
	_metric("tactics_max_avg_edge_skill10", max_side_diff_avg_sk10)


func _measure_settlements_120d(tree: SceneTree, player_tid: String) -> void:
	var towns_dict: Dictionary = Game.world["towns"]
	var ai_ids: Array[String] = []
	for k in towns_dict.keys():
		var tid_s: String = str(k)
		if tid_s != player_tid and not Settlement.is_player_town(Game, tid_s):
			ai_ids.append(tid_s)
	ai_ids.sort_custom(func(a: String, b: String) -> bool:
		var pa: int = int(towns_dict[a].get("econ", {}).get("pop", 0))
		var pb: int = int(towns_dict[b].get("econ", {}).get("pop", 0))
		if pa != pb:
			return pa > pb
		return a < b
	)
	var tracked: Array[Dictionary] = [{"label": "player", "tid": player_tid}]
	for i in mini(5, ai_ids.size()):
		tracked.append({"label": "ai%d" % (i + 1), "tid": ai_ids[i]})

	var purse0: Dictionary = {}
	var treasury0: Dictionary = {}
	var pop0: Dictionary = {}
	var init_levels: Dictionary = {}
	var famine_days: Dictionary = {}
	var market_income_sum: Dictionary = {}
	for entry in tracked:
		var tid: String = str(entry["tid"])
		var town: Dictionary = towns_dict[tid]
		var e: Dictionary = Settlement.ensure_town(town)
		purse0[tid] = _ruler_purse(tid)
		treasury0[tid] = float(e.get("treasury", 0.0))
		pop0[tid] = int(e.get("pop", 0))
		famine_days[tid] = 0
		market_income_sum[tid] = 0.0
		var lvls: Dictionary = {}
		for k in Settlement.KEYS:
			var bkey: String = str(k)
			lvls[bkey] = Settlement.building_level(e, bkey)
		init_levels[tid] = lvls

	# Also track passive food simulation on player town (if player built no Granary)
	var p_town0: Dictionary = towns_dict[player_tid]
	var p_cap0: int = Settlement._calc_food_capacity(p_town0)
	var passive_stock: int = clampi(p_cap0 / 2, 0, p_cap0)
	var passive_last_stock: int = passive_stock
	var passive_famine: bool = false
	var passive_famine_days: int = 0
	var player_winter_days: int = 0
	var player_winter_low: float = 1.0

	var sim_start_ms: int = Time.get_ticks_msec()
	for d_step in 120:
		# Have the player town start a building project on the same 30-day cooldown as AI towns so player building is measured too.
		if d_step % Settlement.AI_COOLDOWN_DAYS == 0:
			var pe: Dictionary = Settlement.ensure_town(towns_dict[player_tid])
			var p_projs: Array = pe.get("projects", [])
			if p_projs.is_empty():
				var best_k: String = ""
				var best_l: int = Settlement.MAX_LEVEL
				for k in Settlement.KEYS:
					var bk: String = str(k)
					var lvl: int = Settlement.building_level(pe, bk)
					if lvl < best_l:
						best_l = lvl
						best_k = bk
				if best_k != "":
					var sp: Dictionary = Settlement.start_preview(Game, player_tid, best_k)
					if bool(sp.get("ok", false)):
						Settlement.start(Game, player_tid, best_k, sp)

		if Time.get_ticks_msec() - sim_start_ms < 60000:
			Game.advance_time(1.0, true, 0, 0)
			while not (Game.world.get("work", []) as Array).is_empty():
				CampaignWorld.work_slice(Game, 100000)
			Game.world["encounter"] = ""
		else:
			Game.day += 1.0
			var cur_d: int = int(floor(Game.day))
			Game.world["last_day"] = cur_d
			TownEcon.queue_day(Game.world, cur_d)
			while not (Game.world.get("work", []) as Array).is_empty():
				var job: Array = (Game.world["work"] as Array).pop_front()
				TownEcon.do_job(Game, job)
			Settlement.daily(Game, cur_d)
			Feudal.daily(Game, cur_d)
			Feudal.finish(Game)

		if d_step % 15 == 14:
			await tree.process_frame

		# Passive player food step (granary level 0)
		var p_cons: int = Settlement.daily_consumption(towns_dict[player_tid])
		var p_harv: int = Settlement.daily_harvest(towns_dict[player_tid], float(Game.day))
		var p_cap: int = p_cons * 30 if p_cons > 0 else Settlement.BASE_FOOD_CAP
		var p_net: int = p_harv - p_cons
		var p_new: int = passive_stock
		if passive_stock <= 0 and passive_last_stock != 0:
			p_new = 0
		elif passive_last_stock <= 0 and passive_stock > 0:
			p_new = clampi(passive_stock + maxi(0, p_net), 1, p_cap)
		else:
			p_new = clampi(passive_stock + p_net, 0, p_cap)
		passive_stock = p_new
		passive_last_stock = p_new
		if p_new <= 0:
			passive_famine = true
		elif passive_famine:
			passive_famine = false
		if passive_famine:
			passive_famine_days += 1

		for entry in tracked:
			var tid: String = str(entry["tid"])
			var town: Dictionary = towns_dict[tid]
			var e: Dictionary = Settlement.ensure_town(town)
			var food: Dictionary = e.get("food", {})
			if bool(e.get("famine", false)) or bool(food.get("store_famine", false)) or int(food.get("stock", 1)) <= 0:
				famine_days[tid] = int(famine_days[tid]) + 1
			if tid == player_tid and Settlement.harvest_season_index(float(Game.day)) == 3:
				player_winter_days += 1
				var wratio: float = float(int(food.get("stock", 0))) / maxf(1.0, float(int(food.get("capacity", 1))))
				if player_winter_days == 1 or wratio < player_winter_low:
					player_winter_low = wratio
			var m_lvl: int = Settlement.building_level(e, "market")
			if m_lvl > 0:
				market_income_sum[tid] = float(market_income_sum[tid]) + _market_income_per_level(town) * float(m_lvl)

	for entry in tracked:
		var label: String = str(entry["label"])
		var tid: String = str(entry["tid"])
		var town: Dictionary = towns_dict[tid]
		var e: Dictionary = Settlement.ensure_town(town)
		var food: Dictionary = e.get("food", {})
		var stock: float = float(food.get("stock", 0))
		var cap: float = maxf(1.0, float(food.get("capacity", Settlement.BASE_FOOD_CAP)))
		var food_ratio: float = stock / cap
		var completed: int = 0
		var spent: int = 0
		var lvls0: Dictionary = init_levels[tid]
		for k in Settlement.KEYS:
			var bkey: String = str(k)
			var l0: int = int(lvls0.get(bkey, 0))
			var l1: int = Settlement.building_level(e, bkey)
			if l1 > l0:
				completed += l1 - l0
				for lv in range(l0 + 1, l1 + 1):
					spent += Settlement.cost_for_level(bkey, lv)
		var projs: Array = e.get("projects", [])
		for p_item in projs:
			if p_item is Dictionary:
				spent += int((p_item as Dictionary).get("cost", 0))

		var p0: float = float(purse0[tid])
		var p120: float = _ruler_purse(tid)
		var spend_pct: float = (float(spent) / maxf(1.0, p0)) * 100.0
		var purse_ratio: float = p120 / maxf(1.0, p0)
		var m_lvl_now: int = Settlement.building_level(e, "market")
		var m_inc_per_lvl: float = _market_income_per_level(town)
		var m_inc_day: float = m_inc_per_lvl * float(m_lvl_now)

		var pref: String = "settlement_%s" % label
		_metric(pref + "_pop_day0", float(pop0[tid]))
		_metric(pref + "_pop_day120", float(e.get("pop", 0)))
		_metric(pref + "_daily_harvest", float(Settlement.daily_harvest(town, float(Game.day))))
		_metric(pref + "_daily_consumption", float(Settlement.daily_consumption(town)))
		var reported_ratio: float = food_ratio
		if label == "player" and player_winter_days > 0:
			reported_ratio = player_winter_low
		_metric(pref + "_food_stock_capacity_ratio", reported_ratio)
		if label == "player":
			_metric(pref + "_food_stock_capacity_ratio_year_end", food_ratio)
			_metric(pref + "_winter_days", float(player_winter_days))
			print("balance042: settlement_player_food_stock_capacity_ratio measured at winter low (%d winter days in the 120-day run)" % player_winter_days)
		_metric(pref + "_famine_days", float(famine_days[tid]))
		_metric(pref + "_buildings_completed", float(completed))
		_metric(pref + "_coin_spent_on_projects", float(spent))
		_metric(pref + "_coin_spent_pct_day0_purse", spend_pct)
		_metric(pref + "_purse_day0", p0)
		_metric(pref + "_purse_day120", p120)
		_metric(pref + "_purse_day120_vs_day0_ratio", purse_ratio)
		_metric(pref + "_purse_day120_vs_day0_delta", p120 - p0)
		_metric(pref + "_treasury_day0", float(treasury0[tid]))
		_metric(pref + "_treasury_day120", float(e.get("treasury", 0.0)))
		_metric(pref + "_market_income_per_day", m_inc_day)
		_metric(pref + "_market_income_per_level_day", m_inc_per_lvl)
		_metric(pref + "_market_income_avg_day", float(market_income_sum[tid]) / 120.0)

	var p_cons_end: int = Settlement.daily_consumption(towns_dict[player_tid])
	var p_cap_end: float = maxf(1.0, float(p_cons_end * 30 if p_cons_end > 0 else Settlement.BASE_FOOD_CAP))
	_metric("settlement_player_no_build_food_stock_capacity_ratio", float(passive_stock) / p_cap_end)
	_metric("settlement_player_no_build_famine_days", float(passive_famine_days))


func run(tree: SceneTree) -> int:
	await tree.process_frame
	Game.wait_save()
	previous_save_path = Game.SAVE_PATH
	Game.settings["guide_seen"] = true
	if not await DevTools.start_world(tree, "user://claude_balance_v042-test.json"):
		printerr("FAIL: the start world did not load")
		if previous_save_path != "":
			Game.SAVE_PATH = previous_save_path
		return 1

	# Choose a ruling house that owns an adult dragon at home (same setup as tests/claude_campaign.gd).
	var tid: String = ""
	for dragon: Dictionary in Dragons.records(Game):
		if str(dragon.get("stage", "")) != "adult" or not bool(dragon.get("alive", false)):
			continue
		var owner: Dictionary = Dragons._person(Game, str(dragon.get("owner_person_uid", "")))
		if owner.is_empty() or str(dragon.get("location_town_id", "")) != str(owner["town_id"]):
			continue
		if bool(HouseOnboarding.begin(Game, str(owner["town_id"]), str(owner["household_uid"])).get("ok", false)):
			tid = str(owner["town_id"])
			break
	if tid == "":
		tid = DevTools.choose_house(Game)
	if tid == "":
		printerr("FAIL: could not choose a ruling house")
		if previous_save_path != "":
			Game.SAVE_PATH = previous_save_path
		return 1
	DevTools.stand_at(Game, tid)

	_measure_catalog()
	_measure_laws(tid)
	_measure_character_designer()
	_measure_breeding()
	_measure_tactics()
	await _measure_settlements_120d(tree, tid)
	_apply_bands()

	Game.wait_save()
	if previous_save_path != "":
		Game.SAVE_PATH = previous_save_path
	print("balance042: %d checks, %d failures" % [checks, fails])
	print("balance042: done")
	return fails
