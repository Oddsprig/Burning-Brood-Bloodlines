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
	Game.save_game()
	check(Game.load_game(), "active raid loads in isolated save")
	check(HerdRaids.fights.is_empty(), "same-seed load discards old combat references")
	check(not HerdRaids.benchmark_fixed_steps, "load turns diagnostic quota off")
	var loaded: Dictionary = Game.world["warbands"][wid]
	check(not is_same(loaded["units"][0], wolf), "loaded force owns deserialized unit objects")
	HerdRaids.step(Game, loaded, 0.01, Game.day, rng)
	check(String(loaded["raid"]["phase"]) == "travelling", "saved fighting raid reconstitutes through existing contact path")
	check(old_state == JSON.stringify(defender.to_dict(), "", true, true), "loaded raid cannot mutate old world's defender")
	# Install a known stale reference with a matching ID before the next same-seed new game.
	HerdRaids.fights[wid] = {"sim": sim, "defenders": [defender]}
	HerdRaids.benchmark_fixed_steps = true
	Game.new_game(35017)
	check(HerdRaids.fights.is_empty() and not HerdRaids.benchmark_fixed_steps, "same-seed new game clears battle references and diagnostic mode")
	check(old_state == JSON.stringify(defender.to_dict(), "", true, true), "new campaign leaves previous Units untouched")
	print("PASTURE LIFECYCLE checks=%d failures=%d" % [checks, failures])
	return failures
