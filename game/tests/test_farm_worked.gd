extends RefCounted

var fails := 0
var checks := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: fails += 1; printerr("FAIL: ", message)

# Synthetic households vary acreage and culture; no named family/town is targeted.
func fixture(culture: String, hands_needed: int) -> Dictionary:
	var owner := Families._blank(1)
	owner["m"] = 1; owner["hands"] = 1; owner["farm"] = 0
	owner["land"] = {"grain": hands_needed * int(TownEcon.data()["land"]["acres_per_hand"])}
	# This focused legacy-total fixture has no saved ox count or age records.
	# The real-record ox-care rule is independently covered by farm_work_rules.
	owner["ox"] = -1
	owner["worked"] = 1.0 / float(hands_needed)
	owner["purse"] = 1000.0
	var worker := Families._blank(2)
	worker["m"] = hands_needed
	var estate := Families._blank(0); estate["estate"] = true
	var farm := {"id": 0, "type": "farm", "owner": 1, "cap": hands_needed - 1, "workers": 0, "closed": false, "till": 5000.0, "wage": 100.0, "owed": 200.0}
	return {"culture": culture, "day": 30, "fams": [estate, owner, worker], "biz": [farm], "wacres": {"grain": float(owner["land"]["grain"]) * float(owner["worked"])}, "wherd": {}, "cum": {"grain": 12.0}, "farm_till": 1234.0, "open_n": hands_needed - 1}

func staffing_changes(e: Dictionary) -> void:
	var owner: Dictionary = e["fams"][1]; var worker: Dictionary = e["fams"][2]; var farm: Dictionary = e["biz"][0]
	var capacity := int(farm["cap"])
	var acres := float(owner["land"]["grain"])
	var purse := float(owner["purse"])
	var cum: Dictionary = owner["cum"].duplicate()
	Families.set_job(e, worker, 0, capacity)
	check(absf(float(owner["worked"]) - 1.0) < 0.000001, "new hired hands immediately work the owner's fields")
	check(absf(float(e["wacres"]["grain"]) - acres) < 0.000001, "town acreage includes the new hands before the next owner turn")
	check(int(farm["workers"]) == capacity and Families.job_total(worker) == capacity, "the new worker assignment is counted once")
	Families.set_job(e, worker, 0, capacity)
	check(absf(float(e["wacres"]["grain"]) - acres) < 0.000001, "repeating the same assignment does not duplicate worked acreage")
	Families.set_job(e, worker, 0, 0)
	check(absf(float(owner["worked"]) - 1.0 / float(capacity + 1)) < 0.000001, "departing hands stop working the fields immediately")
	check(absf(float(e["wacres"]["grain"]) - acres / float(capacity + 1)) < 0.000001, "departure removes exactly its worked acreage")
	check(float(owner["purse"]) == purse and owner["cum"] == cum and float(e["farm_till"]) == 1234.0, "staff changes do not pay or rewrite past harvest claims")
	check(float(farm["till"]) == 5000.0 and float(farm["owed"]) == 200.0, "staff changes preserve the existing wage books")
	owner["hungry"] = 2
	Families.set_job(e, worker, 0, capacity)
	check(absf(float(owner["worked"]) - Barge.output_mult(2)) < 0.000001, "hired hands still follow the existing hunger output rule")
	# The same staffing rule applies to fields inherited by the town estate.
	Families.set_job(e, worker, 0, 0)
	var estate: Dictionary = e["fams"][0]
	estate["land"] = owner["land"].duplicate(); estate["ox"] = owner["ox"]; estate["farm"] = 0
	owner["land"] = {}; owner["farm"] = -1
	e["wacres"]["grain"] = 0.0; estate["worked"] = 0.0
	farm["type"] = "estate"; farm["owner"] = -1; farm["cap"] = capacity + 1; e["estate_biz"] = 0
	Families.set_job(e, worker, 0, capacity + 1)
	check(absf(float(estate["worked"]) - 1.0) < 0.000001 and absf(float(e["wacres"]["grain"]) - acres) < 0.000001, "town estate workers update the same acreage totals")
	Families.set_job(e, worker, 0, 0)
	check(float(estate["worked"]) == 0.0 and absf(float(e["wacres"]["grain"])) < 0.000001, "unstaffed town fields do not keep producing as staffed")

func run(_tree: SceneTree) -> int:
	for culture in TownEcon.data()["cultures"]:
		for need in [2, 4, 9]:
			staffing_changes(fixture(culture, need))
			land_transfer(fixture(culture, need))
		herd_transfer(fixture(culture, 2))
	print("FARM WORKED checks=", checks, " failures=", fails)
	return fails

func land_transfer(e: Dictionary) -> void:
	var owner: Dictionary = e["fams"][1]; var estate: Dictionary = e["fams"][0]
	var acres := Families.acres(owner)
	var need := Families.need_hands(owner)
	estate["land"] = owner["land"].duplicate(); estate["ox"] = owner["ox"]
	estate["worked"] = 1.0; estate["farm"] = 1; estate["cum"] = {"grain": 12.0}
	owner["cum"] = {"grain": 12.0}
	e["biz"].append({"id": 1, "type": "estate", "owner": -1, "workers": int(need), "cap": int(need), "closed": false})
	e["estate_biz"] = 1; e["wacres"]["grain"] += acres
	Families.move_land(e, owner, estate, "grain", acres)
	check(Families.acres(owner) == 0 and Families.acres(estate) == acres * 2, "land transfer conserves physical acres")
	check(absf(float(estate["worked"]) - 0.5) < 0.000001, "inheriting twice the land does not invent twice the staff")
	check(absf(float(e["wacres"]["grain"]) - acres) < 0.000001, "transferred land immediately uses its new holder's actual hands")
	check(float(owner["purse"]) == 1000.0 and float(e["farm_till"]) == 1234.0, "current-acreage correction does not alter already settled claims")

func herd_transfer(e: Dictionary) -> void:
	var owner: Dictionary = e["fams"][1]; var estate: Dictionary = e["fams"][0]
	var heads := int(Herds.kind("sheep")["per_hand"])
	owner["land"] = {}; owner["herd"] = {"sheep": heads * 2}
	owner["cum"] = {"herd": 0.0}; owner["worked"] = 0.5
	e["wacres"] = {}; e["wherd"] = {"sheep": float(heads)}
	estate["farm"] = 1
	e["biz"].append({"id": 1, "type": "estate", "owner": -1, "workers": 1, "cap": 1, "closed": false})
	e["estate_biz"] = 1
	Families.move_herd(e, owner, estate, "sheep", heads * 2)
	check(Families.heads(owner) == 0 and Families.heads(estate) == heads * 2, "herd transfer conserves physical animals")
	check(float(owner["worked"]) == 0.0 and absf(float(estate["worked"]) - 0.5) < 0.000001, "transferred herds use their new holder's actual hands")
	check(absf(float(e["wherd"]["sheep"]) - heads) < 0.000001, "town worked herd total follows the same transfer rule")
