extends "res://tests/test_econ_army.gd"
## Focused regression for the real Bandits.spawn_band camp funding reference.
## Shares the broad suite's conserved setup, but runs no performance scenarios.
const CohortOracle = preload("res://tests/test_campaign_caravans.gd")

func _cash_total() -> float:
	return Barge.holdings(Game)

func _people_and_goods(frozen_rates: Dictionary = {}) -> Dictionary:
	var goods: Dictionary = {}
	var rates: Dictionary = {}
	var meals: float = 0.0
	var errors: Array = []
	for town: Dictionary in Game.world.get("towns", {}).values():
		if not TownEcon.has_econ(town): continue
		var tid: String = str(town.get("id", ""))
		var economy: Dictionary = town["econ"]
		if tid == "" or not economy.has_all(["stock", "hh", "barn", "fams"]):
			errors.append("missing physical ledgers/families in " + tid); continue
		goods[tid] = {"stock": economy["stock"].duplicate(true), "hh": economy["hh"].duplicate(true), "barn": economy["barn"].duplicate(true)}
		rates[tid] = {}
		for family: Dictionary in economy["fams"]:
			var store: Dictionary = family.get("store", {})
			if not family.has("id") or not store.has("food"):
				errors.append("missing household identity/food store in " + tid); continue
			var fid: int = int(family["id"])
			var rate: float = 0.0
			if frozen_rates.is_empty():
				var daily: Dictionary = Families.daily_rates(economy, family)
				if not daily.has("food"): errors.append("missing household meal rate in " + tid); continue
				rate = float(daily["food"])
			else:
				if not frozen_rates.get(tid, {}).has(fid):
					errors.append("missing original household meal rate in " + tid); continue
				rate = float(frozen_rates[tid][fid])
			rates[tid][fid] = rate
			meals += float(store["food"]) * rate
	return {"people": CohortOracle.cohort_snapshot(Game.world), "goods": goods,
		"household_meals": meals, "meal_rates": rates, "fixture_errors": errors}

func _check_people_and_goods(before: Dictionary, label: String) -> void:
	# Freeze the pre-transfer conversion rates; enlistment may change current daily service demand.
	var after: Dictionary = _people_and_goods(before["meal_rates"])
	check(before["fixture_errors"].is_empty() and after["fixture_errors"].is_empty(),
		label + ": complete household stores/rates: " + str(before["fixture_errors"]) + str(after["fixture_errors"]))
	var errors: Array = CohortOracle.materialization_errors(before["people"], after["people"])
	check(errors.is_empty(), label + ": exact population, existing life facts and matched-bin debits: " + str(errors))
	check(after["goods"] == before["goods"], label + ": physical stock, household goods and barns remain identical")
	# Same physical-meals conversion and unchanged 1e-4 budget as _prepare_outlaws.
	check(absf(float(after["household_meals"]) - float(before["household_meals"])) < 0.0001, label + ": all household meal transfers conserve their physical total")

func run(_tree: SceneTree) -> int:
	# Preserve the existing no-argument two-seed contract; explicit seeds are the bounded test lane units.
	var selected_seeds: Array[int] = [5150, 5158]
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--camp-seed="):
			check(arg in ["--camp-seed=5150", "--camp-seed=5158"], "camp seed must be exactly 5150 or 5158")
			if fails > 0: return fails
			selected_seeds.assign([int(arg.trim_prefix("--camp-seed="))])
	for seed_value: int in selected_seeds:
		Game.new_game(seed_value)
		var facts0 := _people_and_goods()
		var cash0 := _cash_total()
		var lid := _funded_camp()
		_check_people_and_goods(facts0, "seed %d: camp setup/recruitment" % seed_value)
		check(absf(_cash_total() - cash0) < 0.01, "seed %d: camp setup/recruitment created or lost cash" % seed_value)
		if lid == "": continue
		var w: Dictionary = Game.world
		var l: Dictionary = w["lairs"][lid]
		var gangs := Bandits.bands_of(Game, lid)
		check(not gangs.is_empty(), "seed %d: funded camp produced no gang" % seed_value)
		for wid in gangs:
			var wb: Dictionary = w["warbands"][wid]
			check(wb["home"] == lid and wb.get("lair", "") == lid, "gang does not carry its actual camp home/funding reference")
			check(not (wb["units"] as Array).is_empty(), "funded gang has no registered men")
			for u in wb["units"]:
				var town: Dictionary = w["towns"].get(u.home_town, {})
				var f := People.fam_of(town, u.family)
				var p := Persons.by_uid(f, u.uid)
				check(not p.is_empty() and String(p[4]) == "bandit" and int(f["serve"].get("bandit", 0)) > 0, "funded recruit is not its household's registered outlaw")
				var served: int = int(f["serve"].get("bandit", 0))
				var original_pid: int = int(p[0]) if not p.is_empty() else -1
				var original_person_uid: String = str(Persons.g(p, Persons.PERSON_UID, ""))
				Army.release(Game, u, "fled")
				check(not p.is_empty() and String(p[4]) == "" and int(p[5]) < 0 and int(f["serve"].get("bandit", 0)) == served - 1,
					"gang release did not return the same person and remove exactly one service claim")
				check(original_pid >= 0 and original_person_uid != "" and is_same(Persons.by_pid(f, original_pid), p) and str(Persons.g(p, Persons.PERSON_UID, "")) == original_person_uid,
					"release returns the exact original PID/person UID to the same household")
				# Real kit fencing may pay this household on release. Transfer those
				# proceeds to the hoard so its volunteers still face the staged loss.
				_move_cash(f, "purse", l, "gold", float(f["purse"]))
			CampaignWorld.remove_warband(Game, wid)
		# Withdraw the existing hoard to an existing town; nobody accepts an unfunded
		# offer without food. The same real volunteers remain available at home.
		var dest: Dictionary = w["towns"][CampaignWorld.nearest_town(w, l["pos"])]
		var hoard := float(l["gold"])
		_move_cash(l, "gold", dest["econ"], "treasury", hoard)
		var rng := RandomNumberGenerator.new()
		rng.seed = 91
		var before := _people_and_goods()
		var before_cash := _cash_total()
		var refused := Bandits.spawn_band(Game, lid, rng)
		check(refused == "", "an unfunded camp without provisions recruited a roaming gang")
		check(_people_and_goods() == before and absf(_cash_total() - before_cash) < 0.01,
			"refused recruitment changed real people, food or cash")
		_move_cash(dest["econ"], "treasury", l, "gold", hoard)
		var accepted := Bandits.spawn_band(Game, lid, rng)
		check(accepted != "", "restoring the same existing hoard did not fund genuine volunteers")
		if accepted != "":
			var wb: Dictionary = w["warbands"][accepted]
			check(wb["home"] == lid and wb.get("lair", "") == lid, "replacement gang has the wrong funding source")
		_check_people_and_goods(before, "seed %d: funded recruitment" % seed_value)
		check(absf(_cash_total() - before_cash) < 0.01, "funded recruitment conserves exactly the existing cash within the unchanged 0.01 roundoff budget")
		if fails > 0: return fails
	print("  actual camp funding: positive recruitment, zero-fund refusal, same-person release and conserved setup")
	return fails
