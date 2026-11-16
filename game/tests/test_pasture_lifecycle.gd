extends RefCounted
## Same-seed world replacement must never reuse old BattleSim/Unit references.
var failures := 0
var checks := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", label)

func run(_tree: SceneTree) -> int:
	WorldGen.gen_size = "normal"
	Game.new_game(35017)
	check(not HerdRaids.benchmark_fixed_steps and HerdRaids.fights.is_empty(), "fresh game defaults to ordinary battle budget")
	var town := {}
	var herd := {}
	for t in Game.world["towns"].values():
		if not TownEcon.has_econ(t) or Militia.units_of(Game, String(t["id"])).is_empty(): continue
		for h in Herds.herds(t["econ"]).values():
			if Herds.GRAZE.has(String(h["k"])) and Herds.head(h) > 0:
				town = t; herd = h; break
		if not town.is_empty(): break
	check(not town.is_empty(), "generated world contains a defended herd")
	if town.is_empty(): return failures
	var rng := RandomNumberGenerator.new(); rng.seed = 35017
	var defender: Unit = Militia.units_of(Game, String(town["id"]))[0]
	var wolf := Unit.create("wolf", "beasts")
	var wid := CampaignWorld.spawn_warband(Game, "beasts", town["pos"], 1, "beasts", rng, {"units": [wolf]})
	var wb: Dictionary = Game.world["warbands"][wid]
	wb["raid"] = {"town": town["id"], "herd": herd["id"], "goal": town["pos"], "wolves": true, "phase": "fighting", "day": Game.day}
	var sim := BattleSim.new()
	sim.setup([defender], [wolf], 357, {"w": 24, "h": 12, "hold0": true, "hold1": true, "verbose": false, "log_moves": false})
	HerdRaids.fight_seed = int(Game.world["seed"])
	HerdRaids.fights[wid] = {"sim": sim, "defenders": [defender]}
	HerdRaids.benchmark_fixed_steps = true
	HerdRaids.step(Game, wb, 0.01, Game.day, rng)
	check(sim.tick == 200 and not sim.over, "diagnostic call advances exactly 200 live battle ticks")
	var old_state := JSON.stringify(defender.to_dict(), "", true, true)
	var saved_raid: String = HerdRaids.save_state()
	check(saved_raid != "", "active raid capture contains its native fight graph")
	check(Game.save_game(), "active raid saves in isolated path")
	check(Game.load_game(), "active raid loads in isolated save")
	check(HerdRaids.fights.size() == 1 and HerdRaids.fights.has(wid), "same-seed load restores exactly the saved active fight")
	var loaded_fight: Dictionary = HerdRaids.fights.get(wid, {})
	var loaded_sim: BattleSim = loaded_fight.get("sim")
	var loaded_defenders: Array = loaded_fight.get("defenders", [])
	var loaded_militia: Array = Militia.units_of(Game, String(town["id"]))
	check(loaded_sim != null and not is_same(loaded_sim, sim) and loaded_sim.tick == 200 and not loaded_sim.over
		and loaded_sim.rng.state == sim.rng.state, "loaded fight owns a fresh simulation at the exact saved progress and RNG")
	check(HerdRaids.benchmark_fixed_steps and HerdRaids.fight_seed == int(Game.world["seed"]), "load preserves the saved diagnostic quota and world seed")
	check(HerdRaids.save_state() == saved_raid, "every captured combat field and alias survives the same-seed load")
	var loaded: Dictionary = Game.world["warbands"][wid]
	check(not is_same(loaded["units"][0], wolf), "loaded force owns deserialized unit objects")
	check(loaded_defenders.size() == 1 and not loaded_militia.is_empty() and loaded_sim != null and loaded_sim.fighters.size() == 2
		and not is_same(loaded_defenders[0], defender) and loaded_defenders[0].uid == defender.uid
		and is_same(loaded_defenders[0], loaded_militia[0])
		and is_same(loaded_sim.fighters[0].unit, loaded_defenders[0])
		and is_same(loaded_sim.fighters[1].unit, loaded["units"][0]) and loaded["units"][0].uid == wolf.uid,
		"restored fighters and campaign rosters share the newly loaded native actors")
	HerdRaids.step(Game, loaded, 0.01, Game.day, rng)
	check(loaded_sim != null and loaded_sim.tick == 400 and not loaded_sim.over and loaded.has("raid") and String(loaded["raid"]["phase"]) == "fighting"
		and HerdRaids.fights.has(wid) and is_same(HerdRaids.fights[wid]["sim"], loaded_sim),
		"saved fighting raid continues the same restored simulation for exactly 200 further ticks")
	check(sim.tick == 200, "loaded raid never advances the old world's simulation")
	check(old_state == JSON.stringify(defender.to_dict(), "", true, true), "loaded raid cannot mutate old world's defender")
	# Install a known stale reference with a matching ID before the next same-seed new game.
	HerdRaids.fights[wid] = {"sim": sim, "defenders": [defender]}
	HerdRaids.benchmark_fixed_steps = true
	Game.new_game(35017)
	check(HerdRaids.fights.is_empty() and not HerdRaids.benchmark_fixed_steps, "same-seed new game clears battle references and diagnostic mode")
	check(old_state == JSON.stringify(defender.to_dict(), "", true, true), "new campaign leaves previous Units untouched")
	print("PASTURE LIFECYCLE checks=%d failures=%d" % [checks, failures])
	return failures
