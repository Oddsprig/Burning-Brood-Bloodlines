extends RefCounted
## Diagnostic only. Real midnight via Game.advance_time, same start as claude_campaign.gd.
## No Settlement.start, no purse or treasury grants. Prints coin flows every 10 days.

var _prev_save: String = ""
var _log: FileAccess
const DAYS := 120
const SIM_BUDGET_MS := 100000


func _p(s: String) -> void:
	print(s)
	if _log != null:
		_log.store_line(s)
		_log.flush()


func _i(v: float) -> int:
	return int(round(v))


func _purse_of(tid: String) -> Dictionary:
	var rec: Dictionary = Feudal.tax_recipient(Game, tid)
	if Settlement.is_player_town(Game, tid):
		rec = Feudal._payer(Game)
	return rec


func _town_index(tid: String) -> int:
	var ids: Array = Game.world["towns"].keys()
	ids.sort()
	return ids.find(tid)


func _snap(tid: String) -> Dictionary:
	var town: Dictionary = Game.world["towns"][tid]
	var e: Dictionary = town["econ"]
	var st: Dictionary = e.get("stats", {})
	var rec: Dictionary = _purse_of(tid)
	var pub := 0.0
	for b in e["biz"]:
		pub += float(b.get("public_paid", 0.0))
	var projs: Array = e.get("projects", [])
	var pkey := ""
	var pleft := 0
	if not projs.is_empty() and projs[0] is Dictionary:
		pkey = str((projs[0] as Dictionary).get("key", ""))
		pleft = int((projs[0] as Dictionary).get("days_left", 0))
	var mtax := -1.0
	if st.has("mtax"):
		mtax = float(st["mtax"])
	var purses := 0.0
	for f in e["fams"]:
		purses += float(f.get("purse", 0.0))
	return {
		"purse": float(rec.get("purse", 0.0)),
		"huid": str(rec.get("household_uid", "")),
		"hh": int(rec.get("households", 1)),
		"treasury": float(e.get("treasury", 0.0)),
		"lord_tax": float(st.get("lord_tax", 0.0)),
		"tax_in": float(st.get("tax_in", 0.0)),
		"tribute_coin": float(st.get("tribute_coin", 0.0)),
		"mtax": mtax,
		"tax_month": float(st.get("tax_month", 0.0)),
		"public_paid": pub,
		"market_lvl": Settlement.building_level(e, "market"),
		"proj_key": pkey,
		"proj_left": pleft,
		"proj_n": projs.size(),
		"ai_day": int(e.get("ai_project_day", -999)),
		"purses": purses,
		"army_levy": float(st.get("army_levy", 0.0)),
		"militia": float(st.get("militia_wages", 0.0)),
		"fam_last": float(rec.get("last", -1.0)),
		"land": float(rec.get("income_parts", {}).get("land", 0.0)),
		"wages": float(rec.get("income_parts", {}).get("staff wages", 0.0)),
		"casual": float(rec.get("income_parts", {}).get("casual work", 0.0)),
		"biz": float(rec.get("income_parts", {}).get("business profit", 0.0)),
		"fund": float(rec.get("income_parts", {}).get("business funding", 0.0)),
		"arms": float(st.get("arms_spend", 0.0)),
	}


func _market_bonus(pre: Dictionary) -> float:
	var lvl := int(pre["market_lvl"])
	if str(pre["proj_key"]) == "market" and int(pre["proj_left"]) <= 1 and int(pre["proj_n"]) > 0:
		lvl += 1
	if lvl <= 0:
		return 0.0
	var base := float(pre["tax_month"]) / 30.0
	if float(pre["mtax"]) >= 0.0:
		base = float(pre["mtax"]) / 30.0
	if base < 2.0:
		base = 2.0
	return base * float(lvl) * Settlement.MARKET_BONUS_PER_LEVEL


func _tribute_sent(tid: String, day: int) -> float:
	var row: Dictionary = Game.world.get("feudal", {}).get("towns", {}).get(tid, {})
	if int(row.get("tribute_day", -2)) != day:
		return 0.0
	return float(row.get("tribute", 0.0))


func _tribute_in(tid: String, day: int) -> float:
	var got := 0.0
	for child in Feudal._vassals(Game.world, tid):
		got += _tribute_sent(str(child), day)
	return got


func _dragon(huid: String, day: int) -> float:
	if huid == "":
		return 0.0
	var cost := 0.0
	var records: Dictionary = Game.world.get("dragons", {}).get("records", {})
	for uid in records:
		var row: Dictionary = records[uid]
		var last: Dictionary = row.get("care", {}).get("last", {})
		if int(last.get("day", -1)) != day:
			continue
		if str(last.get("payer_household_uid", "")) != huid:
			continue
		cost += float(last.get("food_cost", 0.0)) + float(last.get("upkeep_cost", 0.0))
	return cost


func _blank_acc() -> Dictionary:
	return {
		"tax": 0.0, "trib_in": 0.0, "trib_out": 0.0, "mkt": 0.0, "care": 0.0,
		"proj_p": 0.0, "proj_t": 0.0, "tax_tre": 0.0, "mtax": 0.0, "tcoin": 0.0,
		"mil": 0.0, "fac": 0.0, "levy": 0.0, "works": 0.0, "pub": 0.0, "drain": 0.0,
		"purse_d": 0.0, "tre_d": 0.0,
		"land": 0.0, "wages": 0.0, "casual": 0.0, "biz": 0.0, "fund": 0.0, "arms": 0.0,
	}


func _add(acc: Dictionary, key: String, v: float) -> void:
	acc[key] = float(acc.get(key, 0.0)) + v


func _delta(now: Dictionary, then: Dictionary, key: String) -> float:
	return float(now.get(key, 0.0)) - float(then.get(key, 0.0))


func _line(label: String, day: int, purse: float, tre: float, dpurse: float, dtre: float, flow: Dictionary) -> void:
	var explained := float(flow["tax"]) + float(flow["trib_in"]) + float(flow["mkt"]) - float(flow["trib_out"]) - float(flow["care"]) - float(flow["proj_p"])
	var res := float(flow["purse_d"]) - explained
	var tre_known := float(flow["tax_tre"]) + float(flow["mtax"]) + float(flow["tcoin"]) - float(flow["mil"]) - float(flow["fac"]) - float(flow["levy"]) - float(flow["works"]) - float(flow["pub"]) - float(flow["proj_t"]) - float(flow["drain"])
	var tres := float(flow["tre_d"]) - tre_known
	_p("DIAG d=%d %s purse=%d (%d) tre=%d (%d) tax=%d trib_in=%d trib_out=%d mkt=%d care=%d projP=%d pres=%d land=%d wages=%d casual=%d biz=%d fund=%d | taxT=%d mtax=%d tcoin=%d mil=%d fac=%d levy=%d works=%d pub=%d projT=%d drain=%d arms=%d tres=%d" % [
		day, label, _i(purse), _i(dpurse), _i(tre), _i(dtre),
		_i(flow["tax"]), _i(flow["trib_in"]), _i(flow["trib_out"]), _i(flow["mkt"]), _i(flow["care"]), _i(flow["proj_p"]), _i(res),
		_i(flow["land"]), _i(flow["wages"]), _i(flow["casual"]), _i(flow["biz"]), _i(flow["fund"]),
		_i(flow["tax_tre"]), _i(flow["mtax"]), _i(flow["tcoin"]), _i(flow["mil"]), _i(flow["fac"]), _i(flow["levy"]),
		_i(flow["works"]), _i(flow["pub"]), _i(flow["proj_t"]), _i(flow["drain"]), _i(flow["arms"]), _i(tres),
	])


func run(tree: SceneTree) -> int:
	_log = FileAccess.open("C:/Users/bligh/AppData/Local/Temp/diag_economy_flow_report.txt", FileAccess.WRITE)
	await tree.process_frame
	Game.wait_save()
	_prev_save = Game.SAVE_PATH
	Game.settings["guide_seen"] = true
	_p("DIAG note: claude_balance_v042 uses Game.advance_time(1, true) until 60s wall, then a partial tick (TownEcon.queue_day/do_job + Settlement.daily + Feudal.daily) and forces player Settlement.start every 30 days. It never grants coin.")
	_p("DIAG note: this run is Game.advance_time(1, false) plus a full work drain, no builds forced, no coin granted.")
	if not await DevTools.start_world(tree, "user://diag_economy_flow-test.json"):
		printerr("DIAG FAIL start world")
		if _prev_save != "":
			Game.SAVE_PATH = _prev_save
		return 1
	var tid := ""
	for dragon: Dictionary in Dragons.records(Game):
		if str(dragon.get("stage", "")) != "adult" or not bool(dragon.get("alive", false)):
			continue
		var owner: Dictionary = Dragons._person(Game, str(dragon.get("owner_person_uid", "")))
		if owner.is_empty() or str(dragon.get("location_town_id", "")) != str(owner.get("town_id", "")):
			continue
		if bool(HouseOnboarding.begin(Game, str(owner["town_id"]), str(owner["household_uid"])).get("ok", false)):
			tid = str(owner["town_id"])
			break
	if tid == "":
		tid = DevTools.choose_house(Game)
	if tid == "":
		printerr("DIAG FAIL no house")
		if _prev_save != "":
			Game.SAVE_PATH = _prev_save
		return 1
	DevTools.stand_at(Game, tid)
	var towns: Dictionary = Game.world["towns"]
	var ai: Array[String] = []
	for k in towns.keys():
		var id := str(k)
		if id != tid and not Settlement.is_player_town(Game, id) and TownEcon.has_econ(towns[id]):
			ai.append(id)
	ai.sort_custom(func(a: String, b: String) -> bool:
		var pa := int(towns[a].get("econ", {}).get("pop", 0))
		var pb := int(towns[b].get("econ", {}).get("pop", 0))
		if pa != pb:
			return pa > pb
		return a < b
	)
	var tracked: Array[Dictionary] = [{"label": "player", "tid": tid}]
	for i in mini(3, ai.size()):
		tracked.append({"label": "ai%d" % (i + 1), "tid": ai[i]})
	var all_ids: Array[String] = []
	for k2 in towns.keys():
		if TownEcon.has_econ(towns[k2]):
			all_ids.append(str(k2))
	all_ids.sort()
	var dr := float(Barge.B()["coin"]["drain"])
	for entry in tracked:
		var id2 := str(entry["tid"])
		var town: Dictionary = towns[id2]
		var row: Dictionary = Game.world.get("feudal", {}).get("towns", {}).get(id2, {})
		var pre0 := _snap(id2)
		_p("DIAG start %s %s tier=%s liege=%s vassals=%d pop=%d mktLv=%d purse=%d hh=%d tre=%d lord_tax=%d tax_in=%d" % [
			entry["label"], str(town.get("name", id2)), str(row.get("tier", "")), str(row.get("liege_town_id", "")),
			Feudal._vassals(Game.world, id2).size(), int(town["econ"].get("pop", 0)), int(pre0["market_lvl"]),
			_i(pre0["purse"]), int(pre0["hh"]), _i(pre0["treasury"]), _i(pre0["lord_tax"]), _i(pre0["tax_in"]),
		])
	var acc := {}
	var shown := {}
	var prev := {}
	var lord0 := {}
	var open_bal := {}
	var day112 := {}
	for id3 in all_ids:
		var s0 := _snap(id3)
		prev[id3] = s0
		open_bal[id3] = {"purse": float(s0["purse"]), "treasury": float(s0["treasury"])}
		lord0[id3] = float(s0["lord_tax"])
		acc[id3] = _blank_acc()
		shown[id3] = _blank_acc()
	var coin0: Dictionary = Game.world.get("coin", {})
	var cast0 := float(coin0.get("cast", 0.0))
	var melt0 := float(coin0.get("melted", 0.0))
	var drain0 := float(coin0.get("drained", 0.0))
	var hold0 := Barge.holdings(Game)
	var mkt_all := 0.0
	var t_sim := Time.get_ticks_msec()
	var ran := 0
	for step in DAYS:
		if Time.get_ticks_msec() - t_sim > SIM_BUDGET_MS:
			_p("DIAG stop budget at day step %d" % step)
			break
		var pre_mkt := {}
		for id4 in all_ids:
			pre_mkt[id4] = _market_bonus(prev[id4])
		Game.advance_time(1.0, false, 0, 0)
		var guard := 0
		while not (Game.world.get("work", []) as Array).is_empty() and guard < 100000:
			if Time.get_ticks_msec() - t_sim > SIM_BUDGET_MS:
				break
			CampaignWorld.work_slice(Game, 100000)
			guard += 1
		if not (Game.world.get("work", []) as Array).is_empty():
			_p("DIAG warn work left %d on step %d" % [(Game.world.get("work", []) as Array).size(), step])
		Game.world["encounter"] = ""
		var day := int(floor(Game.day))
		for id5 in all_ids:
			var pre: Dictionary = prev[id5]
			var post := _snap(id5)
			var bonus := float(pre_mkt[id5])
			mkt_all += bonus
			var tax_d := float(post["lord_tax"]) - float(pre["lord_tax"])
			var sent := _tribute_sent(id5, day)
			var got := _tribute_in(id5, day)
			var care := _dragon(str(post["huid"]), day)
			var proj_p := 0.0
			var proj_t := 0.0
			if int(post["ai_day"]) == day and int(pre["ai_day"]) != day:
				var projs: Array = Game.world["towns"][id5]["econ"].get("projects", [])
				var cost := 0.0
				if not projs.is_empty() and projs[0] is Dictionary:
					cost = float((projs[0] as Dictionary).get("cost", 0))
				if float(pre["treasury"]) >= Settlement.AI_RICH_TREASURY and float(pre["treasury"]) >= cost:
					proj_t = cost
				elif float(pre["purse"]) >= Settlement.AI_RICH_PURSE and float(pre["purse"]) >= cost:
					proj_p = cost
			var idx := _town_index(id5)
			var mtax_in := 0.0
			var works := 0.0
			if (day + idx) % 7 == 0:
				if float(post["mtax"]) >= 0.0:
					mtax_in = float(post["mtax"])
				works = float(Game.world["towns"][id5]["econ"].get("stats", {}).get("works", 0.0))
			var fac := 0.0
			var levy := 0.0
			if day % 7 == 3:
				var st: Dictionary = Game.world["towns"][id5]["econ"].get("stats", {})
				fac = float(st.get("to_faction", 0.0))
				if not is_equal_approx(float(post["army_levy"]), float(pre["army_levy"])):
					levy = float(post["army_levy"])
			var mil := float(Game.world["towns"][id5]["econ"].get("stats", {}).get("militia_wages", 0.0))
			var pub_d := float(post["public_paid"]) - float(pre["public_paid"])
			var drain_est := maxf(0.0, float(pre["treasury"])) * dr
			var a: Dictionary = acc[id5]
			_add(a, "tax", tax_d)
			_add(a, "trib_in", got)
			_add(a, "trib_out", sent)
			_add(a, "mkt", bonus)
			_add(a, "care", care)
			_add(a, "proj_p", proj_p)
			_add(a, "proj_t", proj_t)
			_add(a, "tax_tre", float(post["tax_in"]) - float(pre["tax_in"]))
			_add(a, "mtax", mtax_in)
			_add(a, "tcoin", float(post["tribute_coin"]) - float(pre["tribute_coin"]))
			_add(a, "mil", mil)
			_add(a, "fac", fac)
			_add(a, "levy", levy)
			_add(a, "works", works)
			_add(a, "pub", pub_d)
			_add(a, "drain", drain_est)
			_add(a, "purse_d", float(post["purse"]) - float(pre["purse"]))
			_add(a, "tre_d", float(post["treasury"]) - float(pre["treasury"]))
			_add(a, "arms", float(post["arms"]) - float(pre["arms"]))
			if not is_equal_approx(float(post["fam_last"]), float(pre["fam_last"])):
				var span := maxf(1.0, float(post["fam_last"]) - float(pre["fam_last"]))
				var scale := span / 7.0
				_add(a, "land", float(post["land"]) * scale)
				_add(a, "wages", float(post["wages"]) * scale)
				_add(a, "casual", float(post["casual"]) * scale)
				_add(a, "biz", float(post["biz"]) * scale)
				_add(a, "fund", float(post["fund"]) * scale)
			prev[id5] = post
		ran += 1
		if ran == 112:
			for idr in all_ids:
				var snap112: Dictionary = prev[idr]
				day112[idr] = {"purse": float(snap112["purse"]), "treasury": float(snap112["treasury"])}
		if ran % 10 == 0 or ran == DAYS:
			var coin: Dictionary = Game.world.get("coin", {})
			var dcast := float(coin.get("cast", 0.0)) - cast0
			var dmelt := float(coin.get("melted", 0.0)) - melt0
			var ddrain := float(coin.get("drained", 0.0)) - drain0
			var dhold := Barge.holdings(Game) - hold0
			var unled := dhold - dcast + dmelt + ddrain
			var lord_now := 0.0
			for id6 in all_ids:
				lord_now += float(prev[id6]["lord_tax"]) - float(lord0[id6])
			_p("DIAG d=%d WORLD days=%d hold_d=%d cast_d=%d melt_d=%d drain_d=%d unledgered=%d mkt_bonus_all=%d lord_tax_all=%d ms=%d" % [
				ran, int(floor(Game.day)), _i(dhold), _i(dcast), _i(dmelt), _i(ddrain), _i(unled), _i(mkt_all), _i(lord_now), Time.get_ticks_msec() - t_sim,
			])
			for entry2 in tracked:
				var id7 := str(entry2["tid"])
				var flow := {}
				for key in acc[id7]:
					flow[key] = _delta(acc[id7], shown[id7], str(key))
				var post2: Dictionary = prev[id7]
				_line(str(entry2["label"]), ran, float(post2["purse"]), float(post2["treasury"]), float(flow["purse_d"]), float(flow["tre_d"]), flow)
				shown[id7] = (acc[id7] as Dictionary).duplicate()
		if ran % 5 == 0:
			await tree.process_frame
	_p("DIAG FINAL days=%d" % ran)
	for entry3 in tracked:
		var id8 := str(entry3["tid"])
		var post3: Dictionary = prev[id8]
		var flow3: Dictionary = acc[id8]
		_line(str(entry3["label"]) + "_TOTAL", ran, float(post3["purse"]), float(post3["treasury"]), float(flow3["purse_d"]), float(flow3["tre_d"]), flow3)
		var parts: Array = [
			["lord_tax_to_purse", float(flow3["tax"])],
			["tribute_in", float(flow3["trib_in"])],
			["market_bonus", float(flow3["mkt"])],
			["tribute_out", -float(flow3["trib_out"])],
			["dragon_care", -float(flow3["care"])],
			["project_purse", -float(flow3["proj_p"])],
			["purse_residual", float(flow3["purse_d"]) - (float(flow3["tax"]) + float(flow3["trib_in"]) + float(flow3["mkt"]) - float(flow3["trib_out"]) - float(flow3["care"]) - float(flow3["proj_p"]))],
			["treasury_tax", float(flow3["tax_tre"])],
			["market_tax_to_treasury", float(flow3["mtax"])],
			["harvest_tribute_to_treasury", float(flow3["tcoin"])],
			["militia_wages", -float(flow3["mil"])],
			["to_faction", -float(flow3["fac"])],
			["army_levy", -float(flow3["levy"])],
			["public_works", -float(flow3["works"])],
			["public_till_topup", -float(flow3["pub"])],
			["project_treasury", -float(flow3["proj_t"])],
			["coin_drain_est", -float(flow3["drain"])],
			["land", float(flow3["land"])],
			["staff_wages", float(flow3["wages"])],
			["casual_work", float(flow3["casual"])],
			["business_profit", float(flow3["biz"])],
			["business_funding", float(flow3["fund"])],
			["armory_spend", -float(flow3["arms"])],
		]
		parts.sort_custom(func(a, b): return absf(float(a[1])) > absf(float(b[1])))
		var bits := ""
		for n in mini(5, parts.size()):
			bits += "%s=%d " % [str(parts[n][0]), _i(float(parts[n][1]))]
		_p("DIAG TOP %s %s" % [entry3["label"], bits])
	var purse_ok := 0
	var tre_ok := 0
	var band_day := 112 if not day112.is_empty() else ran
	for entry4 in tracked:
		var id9 := str(entry4["tid"])
		var p0 := float(open_bal[id9]["purse"])
		var t0 := float(open_bal[id9]["treasury"])
		var got112: bool = day112.has(id9)
		# a run stopped early (wall-clock budget) is judged on its last measured day
		var band_snap: Dictionary = day112[id9] if got112 else prev.get(id9, {})
		var have_b: bool = not band_snap.is_empty() and ran > 0
		var p1 := float(band_snap.get("purse", 0.0)) if have_b else 0.0
		var t1 := float(band_snap.get("treasury", 0.0)) if have_b else 0.0
		var pr := p1 / p0 if have_b and p0 > 1.0 else -1.0
		var tr := t1 / t0 if have_b and t0 > 1.0 else -1.0
		var p_in := pr >= 0.5 and pr <= 3.0
		var t_in := tr >= 0.3 and tr <= 2.0
		if p_in:
			purse_ok += 1
		if t_in:
			tre_ok += 1
		_p("DIAG BAND %s day%d/day0 purse %.3f (%d/%d) %s treasury %.3f (%d/%d) %s" % [
			entry4["label"], band_day, pr, _i(p1), _i(p0), "in" if p_in else "OUT", tr, _i(t1), _i(t0), "in" if t_in else "OUT",
		])
	var band_checks := 2
	var band_failures := 0
	if purse_ok < 3:
		band_failures += 1
	if tre_ok < 3:
		band_failures += 1
	# Diagnostic only: the bands are reported, not enforced (the economy pass left the open balance question to the user).
	_p("economy bands (report only): %d of %d out" % [band_failures, band_checks])
	if _prev_save != "":
		Game.SAVE_PATH = _prev_save
	_p("DIAG done")
	return 0
