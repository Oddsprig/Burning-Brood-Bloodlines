extends RefCounted
## v0.100 triage: why test_barge finds families holding more places than people at home, and why
## test_biz_people finds working businesses with no named keeper. Read-only; prints what it finds.

func run(_tree: SceneTree) -> int:
	Game.new_game(733)
	var w: Dictionary = Game.world
	var shown := 0
	var bad_cohort := 0
	var bad_named := 0
	for tid in w["towns"]:
		var t: Dictionary = w["towns"][tid]
		if not TownEcon.has_econ(t): continue
		var e: Dictionary = t["econ"]
		for f in e["fams"]:
			if f["gone"] or f.has("estate") or not f.has("pp"):
				continue
			var at_home := 0
			var states := {}
			for p in Persons.pp(f):
				states[String(p[4])] = int(states.get(String(p[4]), 0)) + 1
				if int(p[6]) == 0 and String(p[4]) in ["", "hire", "reserve"]:
					at_home += 1
			var held: int = int(f["hands"]) + Families.job_total(f) + f.get("keeps", []).size()
			for j in f.get("cj", {}):
				held += int(f["cj"][j])
			if held > at_home:
				if Population.is_cohort(f): bad_cohort += 1
				else: bad_named += 1
				if shown < 6:
					shown += 1
					print("DIAG_PLACES %s fam %d cohort=%s households=%d adults=%d serving=%d pp=%d states=%s at_home=%d hands=%d jobs=%d keeps=%d cj=%s" % [
						t["name"], int(f["id"]), Population.is_cohort(f), Population.households(f), Families.adults(f), Families.serving(f),
						Persons.pp(f).size(), states, at_home, int(f["hands"]), Families.job_total(f), f.get("keeps", []).size(), f.get("cj", {})])
	print("DIAG_PLACES totals: cohort families over %d, named families over %d" % [bad_cohort, bad_named])
	var nokeeper := 0
	var by := {}
	shown = 0
	for tid in w["towns"]:
		var t: Dictionary = w["towns"][tid]
		if not TownEcon.has_econ(t): continue
		var e: Dictionary = t["econ"]
		for b in e["biz"]:
			if b.get("closed", false): continue
			if (int(b["workers"]) > 0 or int(b.get("kw", 0)) > 0) and RecData.keeper(e, b).is_empty():
				nokeeper += 1
				var owner := int(b["owner"])
				var kind := "no owner"
				if owner >= 0:
					var f: Dictionary = e["fams"][owner]
					kind = "cohort owner" if Population.is_cohort(f) else "named owner"
				by[kind] = int(by.get(kind, 0)) + 1
				if shown < 6:
					shown += 1
					print("DIAG_KEEPER %s %s owner=%d (%s) workers=%d kw=%d" % [t["name"], b["type"], owner, kind, int(b["workers"]), int(b.get("kw", 0))])
	print("DIAG_KEEPER totals: %d working businesses name no keeper %s" % [nokeeper, by])
	return 0
