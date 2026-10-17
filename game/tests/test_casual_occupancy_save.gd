extends RefCounted
var checks := 0
var fails := 0
var children := 0
var fractional_towns := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: fails += 1; printerr("FAIL ", message)

func assigned(e: Dictionary, eligible: bool = true) -> Dictionary:
	var used := {}
	var share := float(Barge.B()["labour"]["kid_share"])
	for f in e["fams"]:
		if f.get("gone", false): continue
		for j in f.get("cj", {}): used[j] = float(used.get(j, 0)) + int(f["cj"][j])
		for pid in f.get("child_cj", {}):
			var p := Persons.by_pid(f, int(pid))
			if eligible: check(not p.is_empty() and Shelter.cleanup_child_eligible(e, p, Game.day), "reserved child shift belongs to an actual eligible child")
			var j := String(f["child_cj"][pid])
			used[j] = float(used.get(j, 0)) + share
			children += 1
	return used

func occupancy(eligible: bool = true) -> Dictionary:
	var result := {}
	for t in Game.world["towns"].values():
		if not TownEcon.has_econ(t): continue
		var e: Dictionary = t["econ"]
		var real := assigned(e, eligible)
		var jobs: Array = TownEcon.data()["casual_jobs"].keys()
		var values := {}
		for j in jobs:
			var recorded := float(e.get("cjused", {}).get(j, 0))
			var count := float(real.get(j, 0))
			check(absf(recorded - count) < 0.00001, "town occupancy equals actual adult and child assignments: %s/%s" % [t["id"], j])
			if absf(count - roundf(count)) > 0.00001: fractional_towns += 1
			values[j] = [recorded, int(e.get("cjcap", {}).get(j, 0)), Shelter.available_casual(e, String(j)), maxf(0, float(e.get("cjcap", {}).get(j, 0)) - count)]
		result[t["id"]] = values
	return result

func run(_tree: SceneTree) -> int:
	WorldGen.gen_size = "normal"
	Game.new_game(2026)
	# Real generated adults retain their places. Limit the cleanup budget to an
	# adult occupancy plus one short child shift, moving the rest to the estate's
	# purse, then return it after assignment. All money comes from existing funds.
	var coins_at_start := Barge.holdings(Game)
	for t in Game.world["towns"].values():
		if not TownEcon.has_econ(t): continue
		var e: Dictionary = t["econ"]
		var used := assigned(e)
		var adult_count := float(used.get("street_sweeper", 0))
		var budget := Barge.casual_wage(e, "street_sweeper") * 7 * (adult_count + float(Barge.B()["labour"]["kid_share"]))
		if float(e["treasury"]) < budget: continue
		if not e.has("cjcap"): e["cjcap"] = {}
		for j in TownEcon.data()["casual_jobs"]: e["cjcap"][j] = int(ceil(float(used.get(j, 0))))
		e["cjcap"]["street_sweeper"] = int(ceil(adult_count + 1))
		e["cjused"] = used
		var deposit := float(e["treasury"]) - budget
		e["treasury"] = budget
		e["fams"][0]["purse"] = float(e["fams"][0]["purse"]) + deposit
		Shelter.assign_child_cleanup(e, Game.day)
		e["treasury"] = float(e["treasury"]) + deposit
		e["fams"][0]["purse"] = float(e["fams"][0]["purse"]) - deposit
	check(absf(Barge.holdings(Game) - coins_at_start) < 0.01, "partial cleanup budget uses only existing money")
	var before := occupancy()
	check(children > 0 and fractional_towns > 0, "normal simulation supplies actual fractional cleanup reservations")
	var coins := Barge.holdings(Game)
	Game.save_game()
	check(Game.load_game(), "campaign with reserved fractional shifts loads")
	var after := occupancy()
	for tid in before:
		for j in before[tid]:
			var a: Array = before[tid][j]
			var b: Array = after[tid][j]
			check(absf(float(a[0]) - float(b[0])) < 0.00001, "fractional town occupancy survives load")
			check(int(a[1]) == int(b[1]) and int(a[2]) == int(b[2]), "integer caps and actually funded available slots survive load")
			check(absf(float(a[3]) - float(b[3])) < 0.00001, "unreserved fractional shift capacity survives load")
	check(absf(Barge.holdings(Game) - coins) < 0.01, "occupancy migration does not move or create money")
	# Continue ordinary hiring and the next weekly reassessment after loading.
	for d in 7: Game.advance_time(1.0, true)
	occupancy(false)
	print("CASUAL OCCUPANCY SAVE checks=%d eligible_child_observations=%d fractional_job_observations=%d failures=%d" % [checks, children, fractional_towns, fails])
	return fails
