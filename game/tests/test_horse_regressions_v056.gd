extends RefCounted
## Bounded native regression cases: reuse the existing supply/army assertions,
## then check mounted movement, unpaid care and actual home returns directly.
var checks := 0
var fails := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		fails += 1
		printerr("FAIL horse regressions: " + message)

func mounted_paths(snapshot: Dictionary, enemy: Dictionary) -> String:
	var signature: Array = []
	for outcome: String in ["rider fled", "rider dead", "rider KO", "horse routed", "horse prone"]:
		var sim := BattleSim.new()
		sim.setup([Unit.from_dict(snapshot.duplicate(true))], [Unit.from_dict(enemy.duplicate(true))], 5602,
			{"w": 10, "h": 8, "cells0": [Vector2i(2, 3)], "cells1": [Vector2i(7, 3)], "combat_journal": false})
		var rider: Fighter = sim.fighters[0]
		var horse: Fighter = sim.fighters[rider.mount_idx]
		match outcome:
			"rider fled":
				rider.routed = true
				sim._do_move(rider, Vector2i(0, 3))
				sim._flee_step(rider)
			"rider dead": sim._kill(rider, 1, "native fixture casualty")
			"rider KO": sim._knock_out(rider, "pain")
			"horse routed": horse.routed = true
			"horse prone": sim._fall(horse, "pain", 0)
		var rng_before := sim.rng.state
		MountedCombat.sync(sim)
		check(not horse.mount_attached and rider.mount_idx == -1 and sim.rng.state == rng_before,
			outcome + ": detach consumes no random rolls")
		match outcome:
			"rider fled":
				check(horse.state == "fled" and not horse.active() and not horse.unit.dead \
					and horse.cell == rider.cell and sim.occ[sim._ci(horse.cell)] == -1,
					"the living attached horse leaves the field with its fled rider")
				check(sim.events.filter(func(e): return e["type"] == "flee").size() == 2,
					"both native bodies record their departure once")
			"rider dead", "rider KO":
				check(horse.standing() and sim.occ[sim._ci(horse.cell)] == horse.idx,
					outcome + ": the surviving horse occupies its own tile")
			"horse routed":
				var from := rider.cell
				sim._decide(horse)
				check(horse.cell.x < from.x and sim.occ[sim._ci(from)] == rider.idx \
					and sim.occ[sim._ci(horse.cell)] == horse.idx,
					"a detached routed horse moves without clearing its standing rider's tile")
				sim._do_move(horse, Vector2i(0, 3))
				sim._decide(horse)
				check(horse.state == "fled" and sim.occ[sim._ci(horse.cell)] == -1,
					"a detached routed horse can reach the edge and flee")
			"horse prone":
				check(horse.prone and sim.occ[sim._ci(horse.cell)] == -1,
					"a fallen detached horse leaves the tile open until it stands")
				horse.knockdown_left = 0
				sim._decide(horse)
				check(not horse.prone and sim.occ[sim._ci(horse.cell)] == horse.idx,
					"a detached horse performs native prone recovery")
		var events := sim.events.size()
		MountedCombat.sync(sim)
		check(sim.events.size() == events, outcome + ": repeated sync cannot repeat departure or detachment")
		signature.append([outcome, rider.cell, rider.state, horse.cell, horse.state, horse.prone, sim.occ, sim.events])
	return JSON.stringify(signature)

func return_paths() -> void:
	# Copy one real AI soldier and its native town fixture for each boundary. No
	# simulated campaign days, duplicate people within a world, or invented horses.
	var snapshot: Dictionary = {}
	for wb: Dictionary in Game.world["warbands"].values():
		if not Army.is_field(wb): continue
		for u: Unit in wb["units"]:
			var town: Dictionary = Game.world["towns"].get(u.home_town, {})
			if u.dead or u.horse != null or u.family < 0 or not TownEcon.has_econ(town): continue
			if int(Herds.town_heads(town["econ"]).get("horses", 0)) < 1: continue
			if DevTools.offer_horses(town) > 0:
				snapshot = u.to_dict().duplicate(true)
				break
		if not snapshot.is_empty(): break
	check(not snapshot.is_empty(), "a real AI soldier has an actual horse market at home")
	if snapshot.is_empty(): return
	var campaign: Dictionary = Game.world
	var company: Array = Game.company
	var squads: Dictionary = Game.squads
	var qa: RefCounted = load("res://tests/test_horses_v056.gd").new()
	for outcome: String in ["release", "beaten alive", "beaten dead", "AI desertion", "company desertion",
			"prisoner freed", "prisoner freed off roll", "prisoner dead", "captive dead", "captive register dead",
			"succession dead", "field wiped", "sweep dead", "company victory dead", "horse dead"]:
		Game.world = campaign.duplicate(true)
		Game.company = []
		Game.squads = {}
		Game.world.erase("mobilization")
		Game.world["prisoners"] = []
		Game.world["captives"] = []
		Game.world["ransom"] = {"log": [], "day": -1}
		var u := Unit.from_dict(snapshot.duplicate(true))
		u.equip.clear() # isolate mount custody from gear sale/salvage
		u.role = "soldier" if outcome == "AI desertion" else "officer"
		u.title = "Cavalry" if outcome == "AI desertion" else "Officer"
		var town: Dictionary = Game.world["towns"][u.home_town]
		var band := {"id": "horse_review", "kind": "patrol", "faction": u.faction,
			"units": [u], "home": u.home_town, "pos": town["pos"], "stores": {}}
		Game.world["warbands"] = {"horse_review": band}
		Game.world["army"] = {"v": 1, "f": {}, "roll": {str(u.uid): [u.home_town, u.family, "army", u.name]}}
		var heads := int(Herds.town_heads(town["econ"]).get("horses", 0))
		DevTools.offer_horses(town)
		Horses.band_day(Game, band, {"kind": "faction", "fac": Game.world["factions"][u.faction]}, int(Game.day) + 1)
		check(u.horse != null and int(Herds.town_heads(town["econ"]).get("horses", 0)) == heads - 1,
			outcome + ": AI supply buys one counted horse")
		if u.horse == null: continue
		if outcome == "AI desertion":
			var e: Dictionary = town["econ"]
			var stock := int(e["stock"].get("grain", 0))
			var used := int(e["led"]["used"].get("grain", 0))
			var lost: Dictionary = TownEcon.goods_lost.duplicate(true)
			Supplies.provision(Game, band, {"kind": "faction", "fac": Game.world["factions"][u.faction]}, int(Game.day) + 1)
			var grain := int(band["stores"].get("grain", 0))
			check(grain > Horses.GRAIN_DAY + 2 and int(e["stock"]["grain"]) == stock - grain \
				and int(e["led"]["used"].get("grain", 0)) == used + grain,
				"AI provisioning books its counted grain once at export")
			Horses.band_day(Game, band, {"kind": "faction", "fac": Game.world["factions"][u.faction]}, int(Game.day) + 2)
			check(int(band["stores"].get("grain", 0)) == grain - Horses.GRAIN_DAY \
				and TownEcon.goods_lost == lost and int(e["led"]["used"].get("grain", 0)) == used + grain,
				"AI care consumes provisioned grain without a second export or global loss")
		var horse_uid := u.horse.uid
		var body: Dictionary = u.horse.body.to_dict().duplicate(true)
		var coin_total: float = qa.coins()
		var rec := {"uid": u.uid, "unit": u, "name": u.name, "home_town": u.home_town,
			"family": u.family, "role": "army"}
		match outcome:
			"release": Army.release(Game, u, "fled")
			"beaten alive": Army.band_beaten(Game, band, null, 1.0)
			"beaten dead":
				u.dead = true
				Army.band_beaten(Game, band, null, 1.0)
			"AI desertion":
				u.unpaid_days = int(Army.A()["desert_days"])
				Army.desertion(Game, u.faction)
			"company desertion":
				Game.company = [u]
				u.unpaid_days = int(Army.A()["company_desert_days"])
				check(not Mobilization.manages(Game, u), "legacy company fixture uses the non-Mobilization branch")
				Army.company_desertion(Game)
				check(not Game.company.has(u), "the unpaid non-Mobilization rider leaves the company")
			"prisoner freed", "prisoner freed off roll":
				if outcome == "prisoner freed off roll": Army.state(Game.world)["roll"].clear()
				Prisoners.held(Game).append(rec)
				Prisoners._free_enemy(Game, rec, "released")
				check(Prisoners.held(Game).is_empty(), outcome + ": the held record leaves custody")
			"prisoner dead", "captive dead", "captive register dead":
				if outcome == "captive register dead":
					Persons.by_uid(People.fam_of(town, u.family), u.uid)[4] = "dead"
				else: u.dead = true
				var list: Array = Prisoners.held(Game) if outcome == "prisoner dead" else Prisoners.captives(Game)
				list.append(rec)
				Prisoners.daily(Game, int(Game.day) + 1)
				check(list.is_empty(), outcome + ": the dead record leaves custody")
			"succession dead":
				u.dead = true
				ArmyRanks._bury(Game, u)
				check(not Game.world["warbands"].has("horse_review"), "succession burial removes the empty band")
			"field wiped":
				u.dead = true
				band["units"] = [] # aggregate AI clashes remove Units before the family sweep
				ArmsTrade.field(Game, [u], {}, town["pos"])
				Army.sweep(Game)
			"sweep dead":
				u.dead = true
				Army.sweep(Game)
			"company victory dead":
				u.dead = true
				ArmsTrade.after_company_battle(Game, {"winner": 0}, band, {}, [])
			"horse dead":
				u.horse.dead = true
				Army.release(Game, u, "fled")
		var expected := heads - 1 if outcome == "horse dead" else heads
		check(u.horse == null and int(Herds.town_heads(town["econ"]).get("horses", 0)) == expected,
			outcome + ": surviving horses return exactly once and dead horses stay dead")
		check(absf(qa.coins() - coin_total) < 0.0001, outcome + ": return creates no sale proceeds")
		var matches := 0
		for h: Dictionary in Herds.herds(town["econ"]).values():
			for saved: Dictionary in h.get("mount_bodies", []):
				if int(saved["uid"]) == horse_uid:
					matches += 1
					check(saved["body"] == body, outcome + ": the returned body keeps its injuries and identity")
		check(matches == (0 if outcome == "horse dead" else 1), outcome + ": there is one saved body per returned head")
		Horses.return_mount(Game, u)
		check(int(Herds.town_heads(town["econ"]).get("horses", 0)) == expected, outcome + ": replay cannot create another head")
	Game.world = campaign
	Game.company = company
	Game.squads = squads

func art_report() -> void:
	var sheet := Image.create(640, 640, false, Image.FORMAT_RGBA8)
	sheet.fill(Color("#222830"))
	for coat_index in HorseArt.COATS.size():
		var coat: String = HorseArt.COATS.keys()[coat_index]
		for row in HorseArt.ANIMATIONS.size():
			var animation: String = HorseArt.ANIMATIONS.keys()[row]
			for frame_index in int(HorseArt.ANIMATIONS[animation]):
				var frame := HorseArt.frame(coat, animation, frame_index).get_image()
				sheet.blit_rect(frame, Rect2i(Vector2i.ZERO, HorseArt.SIZE),
					Vector2i((coat_index % 2) * 320 + frame_index * 80, (coat_index / 2) * 320 + row * 64))
	var path := ProjectSettings.globalize_path("res://").path_join("../test-results/v0.056_2026-10-23_horse_frames.png").simplify_path()
	check(sheet.save_png(path) == OK, "code-drawn coat and animation frames export for visual inspection")

func run(tree: SceneTree) -> int:
	var started := Time.get_ticks_msec()
	check(HorseArt._frames.is_empty(), "reset_between clears the previous test's horse frames")
	check(TownEcon.goods_lost.is_empty(), "reset_between clears losses from the previous test")
	if not await DevTools.start_world(tree, Game.SAVE_PATH):
		check(false, "Normal one-day supply fixture loads")
		return fails
	# Run the relevant existing assertions on one saved world, without the old
	# multi-seed generation, migration or multi-day campaign simulations.
	var supply: RefCounted = load("res://tests/test_military_supply.gd").new()
	var towns: Array = supply.towns()
	check(towns.size() == 4, "existing supply fixture has its four native garrison towns")
	if towns.size() == 4:
		supply.policy_and_money(towns)
		supply.distribution(towns)
		supply.substitutes(supply.towns())
	checks += supply.checks
	fails += supply.fails
	print("Bounded military supply: %d checks, %d failures." % [supply.checks, supply.fails])
	if not await DevTools.start_world(tree, Game.SAVE_PATH):
		check(false, "Normal one-day army fixture reloads")
		return fails
	var army: RefCounted = load("res://tests/test_army_equipment_v045.gd").new()
	army._direct_selection()
	army._shared_counts()
	army._all_loadouts()
	army.compare_real_jobs("v056 Normal one-day fixture", 1)
	checks += army.checks
	fails += army.fails
	print("Bounded army equipment: %d checks, %d failures." % [army.checks, army.fails])
	if not await DevTools.start_world(tree, Game.SAVE_PATH):
		check(false, "Normal one-day horse fixture reloads")
		return fails
	var tid := DevTools.choose_house(Game, func(choice: Dictionary):
		return str(Dynasty.person(Game, str(choice["ruler_uid"])).get("race", "")) == "human" \
			and not DevTools.horse_fixture(Game.world["towns"][str(choice["town_id"])]).is_empty())
	check(tid != "" and DevTools.raise_army(Game, tid, 2) == 2, "two actual residents muster at a horse market")
	if Game.company.size() < 2: return fails
	var town: Dictionary = Game.world["towns"][tid]
	var rider: Unit = Game.company[0]
	var enemy: Dictionary = Game.company[1].to_dict().duplicate(true)
	DevTools.offer_horses(town)
	check(bool(Horses.buy(Game, town, rider).get("ok", false)), "one real mount is purchased")
	if rider.horse == null: return fails
	var horse: Unit = rider.horse
	var snapshot: Dictionary = rider.to_dict().duplicate(true)
	var campaign_rng := Game.rng.state
	check(mounted_paths(snapshot, enemy) == mounted_paths(snapshot, enemy) and Game.rng.state == campaign_rng,
		"mounted flee, death, KO, rout and recovery paths repeat deterministically without campaign RNG")
	var sim := BattleSim.new()
	sim.setup([rider], [Unit.from_dict(enemy)], 5601,
		{"w": 10, "h": 8, "cells0": [Vector2i(2, 3)], "cells1": [Vector2i(7, 3)], "combat_journal": false})
	var mounted: Fighter = sim.fighters[0]
	var carrier: Fighter = sim.fighters[mounted.mount_idx]
	var rider_exertion := rider.body.exertion
	var horse_exertion := horse.body.exertion
	sim._do_move(mounted, Vector2i(3, 3))
	check(carrier.cell == mounted.cell and carrier.prev_cell == mounted.prev_cell \
		and sim.occ[sim._ci(mounted.cell)] == mounted.idx, "mounted movement shares one native occupied tile")
	check(horse.body.exertion > horse_exertion and rider.body.exertion == rider_exertion,
		"the carrier spends movement exertion instead of its rider")
	sim._kill(mounted, 1, "native fixture casualty")
	MountedCombat.sync(sim)
	sim._check_end()
	check(sim.is_over() and sim.winner == 1 and not horse.dead, "a surviving support horse cannot win without its rider")
	# Restore the staged rider flag to exercise home return and later care directly.
	rider.dead = false
	var wallet := Game.gold
	var before_return := int(Herds.town_heads(town["econ"]).get("horses", 0))
	var horse_uid := horse.uid
	var horse_body := horse.body.to_dict().duplicate(true)
	Horses.return_mount(Game, rider)
	check(rider.horse == null and Game.gold == wallet \
		and int(Herds.town_heads(town["econ"]).get("horses", 0)) == int(before_return) + 1,
		"home return moves one surviving horse to its native owner without a sale")
	var returned: Dictionary = {}
	var returned_herd: Dictionary = {}
	for h: Dictionary in Herds.herds(town["econ"]).values():
		for body: Dictionary in h.get("mount_bodies", []):
			if int(body["uid"]) == horse_uid:
				returned = body
				returned_herd = h
	check(not returned.is_empty() and returned["body"] == horse_body, "returned stock retains the exact horse identity and body")
	if returned_herd.is_empty(): return fails
	# Exercise the real AI supply hook with an existing horse, counted grain and
	# a real faction payer. No additional market stock or animals are created.
	Herds.H(town["econ"])["of"] = [[int(returned_herd["id"]), "g", 1, ""]]
	check(bool(Horses.buy(Game, town, rider).get("ok", false)) and rider.horse.uid == horse_uid,
		"the market resells the same returned horse without a second body or head")
	if rider.horse == null: return fails
	var band := {"units": [rider], "home": tid, "pos": town["pos"] + Vector2(200, 0), "stores": {"grain": 20}}
	var fac: Dictionary = Game.world["factions"][str(town["faction"])]
	var payer := {"kind": "faction", "fac": fac}
	var next_day := int(Game.day) + 1
	var faction_coin := float(fac["treasury"])
	var lost: Dictionary = TownEcon.goods_lost.duplicate(true)
	var used := int(town["econ"]["led"]["used"].get("grain", 0))
	Horses.band_day(Game, band, payer, next_day)
	check(int(band["stores"]["grain"]) == 20 - Horses.GRAIN_DAY \
		and float(fac["treasury"]) == faction_coin - Horses.COIN_DAY and Horses.can_field(rider),
		"AI cavalry pays and consumes counted grain while away from its home")
	check(TownEcon.goods_lost == lost and int(town["econ"]["led"]["used"].get("grain", 0)) == used,
		"eating AI stores does not book already exported grain a second time")
	Horses.band_day(Game, band, payer, next_day)
	check(int(band["stores"]["grain"]) == 20 - Horses.GRAIN_DAY \
		and float(fac["treasury"]) == faction_coin - Horses.COIN_DAY, "the AI supply boundary cannot charge twice")
	# Export actual player grain and then eat it: the town ledger changes only at
	# packing, while physical provisions fall by exactly the horse's daily ration.
	Game.gold = 100000
	Food.init_company(Game, 0.0)
	Food.add_stock(Game, "meal", 2 * Food.eaters(Game).size(), 0, "grain", "grain")
	var market_grain := int(town["econ"]["stock"].get("grain", 0))
	used = int(town["econ"]["led"]["used"].get("grain", 0))
	var packed := Supplies.pack_horse_grain(Game, town, 2)
	check(bool(packed.get("ok", false)) and int(town["econ"]["stock"].get("grain", 0)) == market_grain - int(packed.get("grain", 0)) \
		and int(town["econ"]["led"]["used"].get("grain", 0)) == used + int(packed.get("grain", 0)),
		"packing horse grain records one actual market export")
	var meals := Food.stock(Game, "meal")
	used = int(town["econ"]["led"]["used"].get("grain", 0))
	Horses.company_day(Game, next_day + 1)
	check(Food.stock(Game, "meal") == meals - Horses.GRAIN_DAY and TownEcon.goods_lost == lost \
		and int(town["econ"]["led"]["used"].get("grain", 0)) == used,
		"player horse care consumes its packed ration without a second town or global loss entry")
	Game.gold = 0
	Food.init_company(Game, 0.0)
	Food.add_stock(Game, "meal", 2 * Food.eaters(Game).size(), 0, "grain", "grain")
	var soldiers_food := Food.stock(Game, "meal")
	Horses.company_day(Game, next_day + 2)
	check(not Horses.can_field(rider) and not bool(rider.horse_care["paid"]) \
		and not bool(rider.horse_care["fed"]) and Food.stock(Game, "meal") == soldiers_food,
		"unpaid hungry cavalry stands down and preserves the soldiers' last meals")
	return_paths()
	art_report()
	TownEcon.goods_lost = {"grain": 123, "arms": 2}
	await tree.current_scene.reset_between(tree.root.get_children())
	check(TownEcon.goods_lost.is_empty(), "the real runner reset clears every global goods loss key")
	check(Time.get_ticks_msec() - started < 60000, "bounded horse regressions finish under one minute")
	print("Horse regressions v056: %d checks, %d failures." % [checks, fails])
	return fails
