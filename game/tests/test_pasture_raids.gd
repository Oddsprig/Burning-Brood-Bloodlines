extends RefCounted
var fails := 0
func check(ok: bool, msg: String) -> void:
	if not ok: fails += 1; printerr("FAIL ", msg)
func run(_tree: SceneTree) -> int:
	WorldGen.gen_size = "normal"
	for seed_v in [713, 2026, 8801]:
		Game.new_game(seed_v)
		var town: Dictionary = {}
		var herd: Dictionary = {}
		var goal := Vector2.ZERO
		for t in Game.world["towns"].values():
			if not TownEcon.has_econ(t) or TownDefence.garrison(Game, String(t["id"])).is_empty(): continue
			var e: Dictionary = t["econ"]
			for h in Herds.herds(e).values():
				if not Herds.GRAZE.has(String(h["k"])) or Herds.head(h) == 0: continue
				for i in h.get("pl", []):
					if int(e["plots"]["use"][int(i)]) == Plots.PASTURE:
						town = t; herd = h; goal = HerdRaids.plot_pos(t, e["plots"], int(i)); break
				if not herd.is_empty(): break
			if not herd.is_empty(): break
		check(not herd.is_empty(), "generated world has a defended physical pasture")
		if herd.is_empty(): continue
		var rng := RandomNumberGenerator.new(); rng.seed = seed_v
		var wid := CampaignWorld.spawn_warband(Game, "beasts", goal + Vector2(30, 0), 1, "beasts", rng, {"units": [Unit.create("wolf", "beasts")]})
		var wb: Dictionary = Game.world["warbands"][wid]
		wb["raid"] = {"town": town["id"], "herd": herd["id"], "goal": goal, "wolves": true, "phase": "travelling", "day": Game.day}
		wb["path"] = [goal]
		var heads := Herds.head(herd)
		HerdRaids.step(Game, wb, 0.001, Game.day, rng)
		check(Herds.head(herd) == heads and wb.has("raid"), "distant travel cannot remove animals")
		Game.save_game(); check(Game.load_game(), "a travelling raid saves and loads")
		wb = Game.world["warbands"][wid]; town = Game.world["towns"][String(wb["raid"]["town"])]
		herd = Herds.herds(town["econ"])[str(int(wb["raid"]["herd"]))]
		check(wb["raid"]["goal"] is Vector2 and wb["raid"]["phase"] == "travelling" and Herds.head(herd) == heads, "raid position, phase and livestock survive load")
		for force in [Militia.band_of(Game, String(town["id"])), TownDefence.guard_band(Game, String(town["id"]))]:
			if not force.is_empty(): force["pos"] = goal
		wb["pos"] = goal; wb["path"] = []
		HerdRaids.step(Game, wb, 0.01, Game.day, rng)
		check(HerdRaids.fights.has(wid) or not wb.has("raid"), "contact starts existing battle simulation")
		for i in 2000:
			if not wb.has("raid"): break
			HerdRaids.step(Game, wb, 0.01, Game.day, rng)
		check(not wb.has("raid"), "pasture combat resolves")
		check(Herds.head(herd) <= heads and Herds.head(herd) >= 0, "combat leaves real nonnegative livestock")
		for force in Game.world["warbands"].values():
			check(not force.get("pasture_defence", false), "temporary registered herders return after combat")
	print("Pasture raids: %d failures" % fails)
	return fails
