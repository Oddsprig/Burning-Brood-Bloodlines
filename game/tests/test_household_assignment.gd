extends RefCounted
var checks := 0
var fails := 0
func check(ok: bool, why: String) -> void:
	checks += 1
	if not ok: fails += 1; printerr("FAIL: ", why)
func assigned(f: Dictionary) -> int:
	var n := int(f.get("hands", 0)) + Families.job_total(f) + int(f.get("idle", 0)) + (f.get("keeps", []) as Array).size()
	for j in f.get("cj", {}): n += int(f["cj"][j])
	return n
func scenario(seed_v: int) -> void:
	Game.new_game(seed_v)
	var unassigned := []
	for t in Game.world["towns"].values():
		var e: Dictionary = t["econ"]
		for f in e["fams"]:
			if f.get("estate", false) or f.get("gone", false): continue
			var expected := maxi(0, Families.adults(f) - Families.serving(f))
			check(assigned(f) == expected, "generated household's real civilian adults are assigned exactly once")
			if assigned(f) != expected: unassigned.append([t, f])
	# Property-selected families already in a generated register reproduce the old-save gap.
	# Reassign is not called directly: only their ordinary weekly turn can recover.
	for x in unassigned:
		var town: Dictionary = x[0]; var f: Dictionary = x[1]; var e: Dictionary = town["econ"]
		var before_people := Families.people(f)
		var before_register := Persons.pp(f).size() + Persons.kp(f).size()
		f["purse"] = maxf(10000.0, float(f["purse"]))
		f["store"] = {"food": 1000.0, "drink": 1000.0, "wood": 1000.0}
		f["cond"] = 1.0; f["hungry"] = 0; f["unpaid"] = 0; f["tax_season"] = e["tax"]["season"]
		f["last"] = 0.0; e["day"] = 1.0; Game.day = 1.0
		f["nxa"] = 100.0
		var rng := RandomNumberGenerator.new(); rng.seed = 9912
		Families.turn(Game, town, e, f, 1.0, rng)
		check(assigned(f) == maxi(0, Families.adults(f) - Families.serving(f)), "ordinary healthy landless household turn recovers missing assignment")
		check(Families.people(f) == before_people and Persons.pp(f).size() + Persons.kp(f).size() == before_register, "assignment recovery preserves real population and register")
	# Preserve the generated home households but reproduce a legacy missing assignment.
	var sampled := 0
	for town in Game.world["towns"].values():
		var e: Dictionary = town["econ"]
		for f in e["fams"]:
			if sampled >= 7: break
			if f.get("estate", false) or f.get("gone", false) or Families.adults(f) == 0 or Families.serving(f) > 0 or Families.acres(f) > 0 or Families.heads(f) > 0 or not (f["owns"] as Array).is_empty(): continue
			for k in f["jobs"].keys(): Families.set_job(e, f, int(k), 0)
			Shelter.release_casual(e, f)
			e["idle_n"] = maxi(0, int(e["idle_n"]) - int(f["idle"])); f["idle"] = 0
			f["purse"] = 10000.0; f["store"] = {"food": 1000.0, "drink": 1000.0, "wood": 1000.0}
			f["cond"] = 1.0; f["hungry"] = 0; f["unpaid"] = 0; f["tax_season"] = e["tax"]["season"]
			f["last"] = 0.0; e["day"] = 1.0; Game.day = 1.0; f["nxa"] = 100.0
			var before_people := Families.people(f)
			if sampled == 6:
				var tid := String(town["id"]); var fid := int(f["id"])
				Game.save_game()
				check(Game.load_game(), "legacy missing assignment survives actual campaign load")
				town = Game.world["towns"][tid]; e = town["econ"]; f = e["fams"][fid]
				check(assigned(f) == 0 and Families.adults(f) > 0, "load preserves the missing assignment until ordinary turn")
			var rng := RandomNumberGenerator.new(); rng.seed = 9912
			Families.turn(Game, town, e, f, 1.0, rng)
			check(assigned(f) == Families.adults(f), "existing healthy unassigned household recovers through ordinary turn")
			check(Families.people(f) == before_people, "legacy recovery does not invent adults")
			if Families.new().has_method("assignments_stale"):
				check(not Families.new().call("assignments_stale", f), "balanced household does not trigger redundant recovery")
			f["idle"] = int(f["idle"]) + 1; e["idle_n"] = int(e["idle_n"]) + 1
			f["last"] = 1.0; e["day"] = 2.0; Game.day = 2.0
			f["store"] = {"food": 1000.0, "drink": 1000.0, "wood": 1000.0}; f["cond"] = 1.0
			Families.turn(Game, town, e, f, 2.0, rng)
			check(assigned(f) == Families.adults(f), "ordinary turn also repairs an overassigned civilian household")
			check(Families.people(f) == before_people, "overassignment recovery preserves real population")
			sampled += 1
	check(sampled == 7, "legacy assignment cases selected by household properties")
func run(_tree: SceneTree) -> int:
	for seed_v in [901, 2026, 8801]: scenario(seed_v)
	print("HOUSEHOLD ASSIGNMENT checks=", checks, " failures=", fails)
	return fails
