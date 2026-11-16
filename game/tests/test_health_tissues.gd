extends RefCounted
## v0.100: Health report wording for tendon and nerve, and for the throat part (throat artery, windpipe).

var fails := 0

func check(cond: bool, what: String) -> void:
	if not cond:
		fails += 1
		printerr("FAIL: ", what)
	else:
		print("ok: ", what)

func _hit(u: Unit, pid: String, tissue_or_name: String, kind: String, dmg: float = 0.6) -> void:
	# v0.100: sparse bodies (v0.013): wound_part makes the stored, writable copy of an unhurt part.
	for l in u.body.wound_part(pid)["layers"]:
		if l["tissue"] == tissue_or_name or l.get("name", "") == tissue_or_name:
			l["dmg"] = dmg
			l["kind"] = kind
			return
	check(false, "wound fixture found %s/%s" % [pid, tissue_or_name])

func _lines(u: Unit, pid: String) -> Dictionary:
	for p in HealthReport.describe(u)["parts"]:
		if p["part"] == pid:
			return p
	return {}

func run(_tree: SceneTree) -> int:
	var rng := RandomNumberGenerator.new(); rng.seed = 3
	var u := Factory.make_troop(rng, "middle_kingdom", DB.factions["middle_kingdom"]["troops"][0], 1)
	# v0.100: since v0.013 the throat is its own part, one layer carrying the major artery and the
	# v0.100: airway, so the cut and the pierce are described one after the other, not side by side.
	_hit(u, "throat", "throat", "cut")
	var p := _lines(u, "throat")
	print(p.get("text", ""))
	check(p.get("lines", []).has("throat artery opened"), "throat artery wording")
	check(int(p.get("severity", 0)) == 3, "opened throat artery is critical")
	_hit(u, "throat", "throat", "pierced")
	p = _lines(u, "throat")
	print(p.get("text", ""))
	check(p.get("lines", []).has("windpipe punctured"), "airway wording")
	check(int(p.get("severity", -1)) == 3, "punctured windpipe is critical")
	# v0.100: a throat bruise and a plain neck skin cut must keep their previous severity.
	_hit(u, "throat", "throat", "bruised", 0.1)
	p = _lines(u, "throat")
	check(p.get("lines", []) == ["throat bruised"], "bruised throat wording")
	check(int(p.get("severity", -1)) == 0, "bruised throat is a scratch")
	_hit(u, "neck", "skin", "cut")
	p = _lines(u, "neck")
	check(p.get("lines", []) == ["skin cut"], "neck skin wording stays generic")
	check(int(p.get("severity", -1)) == 1, "neck skin cut stays minor")
	var arm := ""
	# v0.100: sparse bodies (v0.013) store no unhurt parts, so find the tendon in the plan.
	for pd in u.body.plan()["parts"]:
		for l in pd["layers"]:
			if l["tissue"] == "tendon" and arm == "":
				arm = pd["id"]
	check(arm != "", "a tendon part exists")
	if arm == "":
		return fails
	_hit(u, arm, "tendon", "cut")
	# v0.100: check the tendon before nerve marks can mask its severity with their critical rating.
	p = _lines(u, arm)
	print(p.get("text", ""))
	check(int(p.get("severity", 0)) >= 2, "cut tendon is serious")
	# v0.100: limb nerves are no longer layers; a cut muscle severs them as part marks (v0.013).
	var ap := u.body.wound_part(arm)
	ap["nerve_m"] = true
	ap["nerve_s"] = true
	p = _lines(u, arm)
	print(p.get("text", ""))
	check(p.get("lines", []).has("tendon severed"), "tendon wording")
	check(p.get("lines", []).has("motor nerve severed - limp"), "nerve wording")
	check(p.get("lines", []).has("sensory nerve severed - numb"), "sensory nerve wording")
	check(bool(p.get("permanent", false)), "severed nerve is permanent")
	return fails
