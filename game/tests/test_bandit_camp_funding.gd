extends "res://tests/test_econ_army.gd"
## Focused regression for the real Bandits.spawn_band camp funding reference.
## Shares the broad suite's conserved setup, but runs no performance scenarios.

func _cash_total() -> float:
	return Barge.holdings(Game)

func _people_and_goods() -> Dictionary:
	var facts := {}
	for town in Game.world["towns"].values():
		if not TownEcon.has_econ(town): continue
		var e: Dictionary = town["econ"]
		var rows := []
		for f in e["fams"]:
			var people := []
			for p in Persons.pp(f):
				# Current service and uid intentionally change; identity and life facts do not.
				people.append([p[0], p[1], p[2], p[3], p[6], p[7], p[8], p[9], p[10]])
			rows.append([f["id"], f["m"], f["f"], f["old"], f["kids"], people])
		facts[town["id"]] = {"pop": e["pop"], "adults": e["adults"], "rows": rows,
			"stock": e["stock"].duplicate(true), "hh": e["hh"].duplicate(true), "barn": e["barn"].duplicate(true)}
	return facts

func run(_tree: SceneTree) -> int:
	for seed_value in [5150, 5158]:
		Game.new_game(seed_value)
		var facts0 := _people_and_goods()
		var cash0 := _cash_total()
		var lid := _funded_camp()
		check(_people_and_goods() == facts0, "seed %d: camp setup/recruitment changed population, identities or physical food" % seed_value)
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
				var served := int(f["serve"].get("bandit", 0))
				Army.release(Game, u, "fled")
				check(not p.is_empty() and String(p[4]) == "" and int(p[5]) < 0 and int(f["serve"].get("bandit", 0)) == served - 1,
					"gang release did not return the same person and remove exactly one service claim")
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
		check(_people_and_goods() == before and absf(_cash_total() - before_cash) < 0.01,
			"funded recruitment changed real people, food or cash")
	print("  actual camp funding: positive recruitment, zero-fund refusal, same-person release and conserved setup")
	return fails
