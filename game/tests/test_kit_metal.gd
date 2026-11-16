extends RefCounted
## v0.014: the company's opening kit and a recruit's gear come in the metals the town's own smiths make
## (Factory.town_metal: the metal pieces on its stalls and in its armory), not a fixed tin-heavy roll.

var fails := 0

func check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("  FAIL: ", what)

func share(items: Array, mat: String) -> float:
	var n := 0
	var m := 0
	for it in items:
		if String(it.mat().get("kind", "")) == "metal":
			n += 1
			if it.material == mat:
				m += 1
	return float(m) / maxf(1.0, n)

func run(tree: SceneTree) -> int:
	# v0.100: every seed keeps its 100-troop/30-recruit sample; invoke each seed separately.
	var selected: String = OS.get_environment("KIT_METAL_SEED")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seed="): selected = arg.trim_prefix("--seed=")
	check(selected in ["11", "12", "13"], "v0.100: run kit metal --seed=11, --seed=12 and --seed=13 separately")
	if fails > 0: return fails
	var previous_size: String = WorldGen.gen_size
	var previous_span: int = CampaignWorld.presim_span_days
	WorldGen.gen_size = "normal"
	CampaignWorld.presim_span_days = 1
	await tree.process_frame
	for sd in [int(selected)]:
		Game.new_game(sd)
		var town: Dictionary = Game.world["towns"][Game.world["start_town"]]
		var made: Array = (town.get("shop", []) as Array) + (town.get("armory_items", []) as Array)
		# v0.100: v0.017 (e460f8b) deliberately starts with an unraised army.
		# v0.100: exercise the opening-kit adapter on explicit troops, leaving that start intact.
		check(Game.company.is_empty(), "v0.100: the native starting company is unraised")
		var kit_rng := RandomNumberGenerator.new()
		kit_rng.seed = sd
		var troops := Factory.make_warband(kit_rng, String(town["faction"]), 100, int(town["wealth"]))
		ArmsTrade.outfit_opening_kit({"world": Game.world, "company": troops})
		var kit := []
		for u in troops:
			kit.append_array(u.equip.values())
		check(troops.size() == 100 and kit.any(func(it): return String(it.mat().get("kind", "")) == "metal"), "v0.100: the explicit opening-kit sample contains real metal equipment")
		var ts := share(made, "tin")
		var ks := share(kit, "tin")
		print("  seed %d %s: town makes %.0f%% tin, opening kit %.0f%% tin" % [sd, town["name"], ts * 100, ks * 100])
		check(absf(ks - ts) < 0.25, "seed %d: the opening kit follows the town's metal mix" % sd)
		for it in kit:
			if String(it.mat().get("kind", "")) == "metal":
				var seen := made.any(func(x): return x.material == it.material)
				check(seen, "seed %d: %s is a metal this town's smiths made" % [sd, it.display_name()])
		# a recruit from the town
		var rng := RandomNumberGenerator.new()
		rng.seed = sd
		var rec := []
		for i in 30:
			var r := Recruits.make_recruit(rng, town, Recruits.kit_for({"kind": "service", "title": "guard"}))
			rec.append_array(r.equip.values())
		check(absf(share(rec, "tin") - ts) < 0.3, "seed %d: recruits' gear follows the town (%.0f%% tin)" % [sd, share(rec, "tin") * 100])
	# a town with nothing on hand falls back to its bars, then the old roll
	var rng2 := RandomNumberGenerator.new()
	check(Factory.town_metal(rng2, {"econ": {"stock": {"iron_bars": 5}}}, "arming_sword") == "iron", "bars fallback")
	check(Factory.town_metal(rng2, {}, "tunic") == "linen" and Factory.town_metal(rng2, {}, "self_bow") == "wood", "cloth and bows keep their material")
	WorldGen.gen_size = previous_size
	CampaignWorld.presim_span_days = previous_span
	return fails
