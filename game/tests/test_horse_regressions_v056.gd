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
	Horses.band_day(Game, band, payer, next_day)
	check(int(band["stores"]["grain"]) == 20 - Horses.GRAIN_DAY \
		and float(fac["treasury"]) == faction_coin - Horses.COIN_DAY and Horses.can_field(rider),
		"AI cavalry pays and consumes counted grain while away from its home")
	Horses.band_day(Game, band, payer, next_day)
	check(int(band["stores"]["grain"]) == 20 - Horses.GRAIN_DAY \
		and float(fac["treasury"]) == faction_coin - Horses.COIN_DAY, "the AI supply boundary cannot charge twice")
	Game.gold = 0
	Food.init_company(Game, 0.0)
	Food.add_stock(Game, "meal", 2 * Food.eaters(Game).size(), 0, "grain", "grain")
	var soldiers_food := Food.stock(Game, "meal")
	Horses.company_day(Game, next_day + 1)
	check(not Horses.can_field(rider) and not bool(rider.horse_care["paid"]) \
		and not bool(rider.horse_care["fed"]) and Food.stock(Game, "meal") == soldiers_food,
		"unpaid hungry cavalry stands down and preserves the soldiers' last meals")
	art_report()
	check(Time.get_ticks_msec() - started < 60000, "bounded horse regressions finish under one minute")
	print("Horse regressions v056: %d checks, %d failures." % [checks, fails])
	return fails
