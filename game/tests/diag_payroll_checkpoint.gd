extends RefCounted

var selected := {}
var legacy := {}
var checks := 0
var failures := 0

func check_legacy() -> float:
	var total := 0.0
	var seen := {}
	for tid in Game.world["towns"]:
		var t: Dictionary = Game.world["towns"][tid]
		if not TownEcon.has_econ(t): continue
		for b in t["econ"]["biz"]:
			var key := str(tid) + ":" + str(int(b["id"]))
			var amount := float(b.get("owed_unattributed", 0.0))
			total += amount
			checks += 1; seen[key] = true
			if absf(amount - float(legacy.get(key, 0.0))) > 0.00001:
				failures += 1; printerr("FAIL: older wage balance changed at ", key)
	for key in legacy:
		if not seen.has(key) and float(legacy[key]) > 0.00001:
			failures += 1; printerr("FAIL: older creditor book disappeared at ", key)
	return total

func observation() -> Dictionary:
	var towns := []
	for tid in selected:
		var town: Dictionary = Game.world["towns"][tid]
		var e: Dictionary = town["econ"]
		var farms := []
		var idle := 0
		for f in e["fams"]:
			if not f.get("gone", false): idle += int(f.get("idle", 0))
		for bid in selected[tid]:
			var b: Dictionary = e["biz"][bid]
			var owner: Dictionary = e["fams"][int(b["owner"])]
			var staff := []
			for f in e["fams"]:
				var n := int(f["jobs"].get(str(bid), 0))
				if n > 0:
					staff.append({"family": int(f["id"]), "n": n, "last": f["last"], "unpaid": f["unpaid"], "wage_income": f.get("income_parts", {}).get("staff wages", 0.0)})
			farms.append({"id": bid, "owner": b["owner"], "cap": b["cap"], "workers": b["workers"], "wage": b["wage"],
				"till": b["till"], "owed": b["owed"], "claims": (b.get("wage_claims", {}) as Dictionary).duplicate(true), "legacy": b.get("owed_unattributed", 0.0), "takeable": Businesses.takeable(b),
				"owner_purse": owner["purse"], "owner_last": owner["last"], "owner_land_week": owner.get("lpay", 0.0), "owner_funding_week": owner.get("income_parts", {}).get("business funding", 0.0),
				"state": b["state"], "health": b.get("health", ""), "unpaid_day": b.get("unpaid_d", -1), "staff": staff})
		towns.append({"id": tid, "idle": idle, "farms": farms})
	return {"day": Game.day, "towns": towns}

func run(_tree: SceneTree) -> int:
	var source := OS.get_environment("PAYROLL_CHECKPOINT")
	var target := OS.get_environment("PAYROLL_TRACE")
	if source == "" or target == "" or not FileAccess.file_exists(source):
		printerr("PAYROLL_CHECKPOINT and PAYROLL_TRACE must name existing checkpoint and output file")
		return 1
	var old: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(source))
	for tid in old["world"]["towns"]:
		for b in old["world"]["towns"][tid].get("econ", {}).get("biz", []):
			legacy[str(tid) + ":" + str(int(b["id"]))] = float(b.get("owed", 0.0))
	var save := FileAccess.open(Game.SAVE_PATH, FileAccess.WRITE)
	save.store_string(JSON.stringify(old)); save.close()
	old.clear()
	if not Game.load_game(): return 1
	var legacy_before := 0.0
	for amount in legacy.values(): legacy_before += float(amount)
	var legacy_after := check_legacy()
	# Select by evidence rule; no town or family name/ID controls selection or behavior.
	for tid in Game.world["towns"]:
		var town: Dictionary = Game.world["towns"][tid]
		if not TownEcon.has_econ(town): continue
		var e: Dictionary = town["econ"]
		var idle := 0
		for f in e["fams"]:
			if not f.get("gone", false): idle += int(f.get("idle", 0))
		var funded := 0
		for b in e["biz"]: funded += Businesses.takeable(b)
		if mini(idle, funded) <= 10: continue
		var farms := []
		for b in e["biz"]:
			if String(b["type"]) == "farm" and Businesses.takeable(b) > 0: farms.append(int(b["id"]))
		if not farms.is_empty(): selected[tid] = farms
	var observations := [observation()]
	for i in 14:
		CampaignWorld.presim_step(Game, 1)
		legacy_after = check_legacy()
		observations.append(observation())
	var file := FileAccess.open(target, FileAccess.WRITE)
	file.store_string(JSON.stringify({"selected": selected, "trace": observations, "legacy_before": legacy_before, "legacy_after": legacy_after, "balance_checks": checks, "failures": failures})); file.close()
	print("PAYROLL CHECKPOINT ordinary-days=14 selected=", selected, " trace=", target)
	print("LEGACY WAGE BALANCES before=", legacy_before, " after=", legacy_after, " checks=", checks, " failures=", failures)
	return failures
