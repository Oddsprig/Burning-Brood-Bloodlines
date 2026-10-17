extends RefCounted
var fails := 0
var checks := 0
func check(ok: bool, msg: String) -> void:
	checks += 1
	if not ok: fails += 1; printerr("FAIL ", msg)
func run(_tree: SceneTree) -> int:
	var worked := 0
	WorldGen.gen_size = "normal"
	for seed_v in [713, 2026, 8801]:
		Game.new_game(seed_v)
		for t in Game.world["towns"].values():
			if not TownEcon.has_econ(t): continue
			var e: Dictionary = t["econ"]
			e["treasury"] = 1000000.0
			e["cjcap"] = {"street_sweeper": 1, "rat_catcher": 1, "night_soil_man": 0}
			e["cjused"] = {}
			var before := {}
			for f in e["fams"]:
				f.erase("child_cj"); f.erase("cj"); f.erase("cjearned")
				before[str(int(f["id"]))] = Barge.helper_hands(e, f, Game.day)
			Shelter.assign_child_cleanup(e, Game.day)
			for j in e["cjused"]:
				check(float(e["cjused"][j]) <= float(e["cjcap"][j]) + 0.00001, "short shifts fit actual cleanup places")
			Shelter.accrue_sanitation(e, Game.day)
			for f in e["fams"]:
				var child_jobs: Dictionary = f.get("child_cj", {})
				var share := float(Barge.B()["labour"]["kid_share"])
				check(absf(float(before[str(int(f["id"]))]) - Barge.helper_hands(e, f, Game.day) - child_jobs.size() * share) < 0.0001, "cleanup children are not also farm helpers")
				var expected := 0.0
				for pid in child_jobs:
					var p := Persons.by_pid(f, int(pid))
					check(not p.is_empty() and Shelter.cleanup_child_eligible(e, p, Game.day), "every child cleaner is a real person of helper age")
					var job: Dictionary = Persons.work(e, f).get(int(pid), {})
					check(not job.is_empty() and float(job.get("share", 0)) == share, "family record reports the child's short paid shift")
					var c := Sickness.case_of(f, int(pid))
					if c.is_empty() or int(c[Sickness.C_BED]) != 1 or not Sickness.sick_phase(c, Game.day): expected += Barge.casual_wage(e, String(child_jobs[pid])) * share
					worked += 1
				var purse := float(f["purse"])
				var coins := Barge.holdings(Game)
				Shelter.pay_casual(e, f, 1)
				check(absf(float(f["purse"]) - purse - expected) < 0.01, "child cleanup pay equals attended partial work")
				check(absf(Barge.holdings(Game) - coins) < 0.01, "child cleanup transfers existing money")
		var saved := {}
		for t in Game.world["towns"].values():
			if not TownEcon.has_econ(t): continue
			for f in t["econ"]["fams"]:
				if not f.get("child_cj", {}).is_empty(): saved[str(t["id"]) + ":" + str(f["id"])] = f["child_cj"].duplicate(true)
		Game.save_game(); check(Game.load_game(), "child cleanup campaign loads")
		for key in saved:
			var parts := String(key).split(":")
			check(Game.world["towns"][parts[0]]["econ"]["fams"][int(parts[1])].get("child_cj", {}) == saved[key], "child assignments survive save/load")
	check(worked > 0, "generated children actually take cleanup shifts")
	print("Child cleanup: %d checks, %d workers, %d failures" % [checks, worked, fails])
	return fails
