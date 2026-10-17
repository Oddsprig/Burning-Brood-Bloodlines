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
	await tree.process_frame
	for sd in [11, 12, 13]:
		Game.new_game(sd)
		var town: Dictionary = Game.world["towns"][Game.world["start_town"]]
		var made: Array = (town.get("shop", []) as Array) + (town.get("armory_items", []) as Array)
		var kit := []
		for u in Game.company:
			kit.append_array(u.equip.values())
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
	return fails
