extends RefCounted
## Health report wording for the newer tissues: tendon, nerve, vessel (throat artery), airway.

var fails := 0

func check(cond: bool, what: String) -> void:
	if not cond:
		fails += 1
		printerr("FAIL: ", what)
	else:
		print("ok: ", what)

func _hit(u: Unit, pid: String, tissue_or_name: String, kind: String, dmg: float = 0.6) -> void:
	for l in u.body.parts[pid]["layers"]:
		if l["tissue"] == tissue_or_name or l.get("name", "") == tissue_or_name:
			l["dmg"] = dmg
			l["kind"] = kind
			return

func _lines(u: Unit, pid: String) -> Dictionary:
	for p in HealthReport.describe(u)["parts"]:
		if p["part"] == pid:
			return p
	return {}

func run(_tree: SceneTree) -> int:
	var rng := RandomNumberGenerator.new(); rng.seed = 3
	var u := Factory.make_troop(rng, "middle_kingdom", DB.factions["middle_kingdom"]["troops"][0], 1)
	_hit(u, "neck", "vessel", "cut")
	_hit(u, "neck", "airway", "pierced")
	var p := _lines(u, "neck")
	print(p.get("text", ""))
	check(p.get("lines", []).has("throat artery opened"), "throat artery wording")
	check(p.get("lines", []).has("windpipe punctured"), "airway wording")
	check(int(p.get("severity", 0)) == 3, "opened throat artery is critical")
	var arm := ""
	for pid in u.body.parts:
		for l in u.body.parts[pid]["layers"]:
			if l["tissue"] == "tendon" and arm == "":
				arm = pid
	_hit(u, arm, "tendon", "cut")
	_hit(u, arm, "nerve", "torn")
	p = _lines(u, arm)
	print(p.get("text", ""))
	check(p.get("lines", []).has("tendon severed"), "tendon wording")
	check(String(" ".join(PackedStringArray(p.get("lines", [])))).contains("nerve torn"), "nerve wording")
	check(int(p.get("severity", 0)) >= 2, "cut tendon is serious")
	return fails
