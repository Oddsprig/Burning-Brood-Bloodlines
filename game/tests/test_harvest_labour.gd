extends RefCounted

var checks := 0
var fails := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: fails += 1; printerr("FAIL: ", message)

func fixture(culture: String, own: int, crop_need: int, herd_need: int) -> Dictionary:
	var estate := Families._blank(0); estate["estate"] = true
	estate["land"] = {"grain": 32}; estate["ox"] = 4; estate["farm"] = 1
	var owner := Families._blank(1); owner["m"] = own; owner["farm"] = 0
	owner["land"] = {"grain": crop_need * 8}; owner["ox"] = crop_need
	owner["herd"] = {"sheep": herd_need * 25}
	var hired := Families._blank(2); hired["m"] = 1
	var farm := {"id": 0, "type": "farm", "owner": 1, "cap": 0, "workers": 0, "closed": false, "till": 100000.0, "wage": 100.0, "kw": 0}
	var eb := {"id": 1, "type": "estate", "owner": -1, "cap": 4, "workers": 0, "closed": false, "till": 100000.0, "wage": 100.0}
	return {"culture": culture, "day": 0.0, "fams": [estate, owner, hired], "biz": [farm, eb], "estate_biz": 1, "idle_n": 0, "hands": 0, "wacres": {}, "wherd": {}, "cjcap": {}, "cjused": {}}

func seasonal(e: Dictionary) -> void:
	var owner: Dictionary = e["fams"][1]
	var farm: Dictionary = e["biz"][0]
	var need := Families.need_hands(owner)
	var crop_need := float(Families.acres(owner)) / 8.0
	for day in [0, 30, 60, 61, 90, 120, 150, 180, 210]:
		e["day"] = float(day)
		var si := Calendar.season_index(float(day))
		var hh := float(Barge.B()["labour"]["harvest_hands"]) if si in [1, 2] else 1.0
		Families.reassign(e, owner)
		var own := int(owner["hands"])
		var expected_cap := maxi(0, int(ceil(need + crop_need * (hh - 1.0) - own - 0.3)))
		check(int(farm["cap"]) == expected_cap, "farm capacity includes seasonal hands once (%s day%d)" % [e["culture"], day])
		Families.reassign(e, owner)
		check(int(farm["cap"]) == expected_cap and int(farm["cap"]) >= 0, "repeat ordinary family assignment preserves nonnegative seasonal capacity")
		# Estate's ordinary weekly turn sets its real seasonal places, separately
		# verified by test_harvest_scope. The quote must count them once.
		e["biz"][1]["cap"] = int(4.0 * hh)
		var expected_dem := float(expected_cap) + float(e["biz"][1]["cap"])
		for repeat in 3:
			Barge.labour_day(e, si)
			check(absf(float(e["ldem"]) - expected_dem) < 0.051, "labour demand counts seasonal family and estate caps once (day%d repeat%d got%.1f expected%.1f)" % [day, repeat, e["ldem"], expected_dem])
			check(int(farm["cap"]) == expected_cap, "daily wage calculation does not rewrite capacity")
		if expected_cap > 0:
			Families.set_job(e, e["fams"][2], 0, 1)
			Barge.labour_day(e, si)
			check(absf(float(e["ldem"]) - expected_dem) < 0.051 and int(farm["workers"]) == 1, "filled places still count once as demand")
			Families.set_job(e, e["fams"][2], 0, 0)

func run(_tree: SceneTree) -> int:
	for culture in TownEcon.data()["cultures"]:
		for spec in [[1, 4, 0], [2, 3, 2], [2, 1, 0]]:
			seasonal(fixture(culture, spec[0], spec[1], spec[2]))
	print("HARVEST LABOUR checks=", checks, " failures=", fails)
	return fails
