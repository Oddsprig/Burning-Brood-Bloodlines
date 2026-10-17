extends RefCounted
## Bounded native health/identity reads; no complete battle or world generation.
const HealthUtil = preload("res://tests/health_util.gd")
const SimUtil = preload("res://tests/sim_util.gd")
var checks: int = 0
var fails: int = 0

func check(ok: bool, why: String) -> void:
	checks += 1
	if not ok:
		fails += 1
		printerr("FAIL battle result summary: ", why)

static func _person(uid: int, name: String) -> Unit:
	var u := Unit.new()
	u.uid = uid; u.name = name; u.title = "Native fixture troop"; u.attrs = {"REC": 1000}
	u.body = BodyState.new()
	u.body.init_from_plan(DB.bodies["humanoid"], 70.0)
	return u

## Shared with focused UI tests: actual native wounds, no RNG/UID allocations.
static func fixture(n: int = 8) -> Dictionary:
	var result: Dictionary = {"player_units": [], "enemy_units": [], "player_fled": [], "enemy_fled": [],
		"enemy_fallen": [], "fighter_units": [], "fighter_states": [], "side_names": ["Our company and allies", "Opposing realm"],
		"winner": 0, "loot_gold": 71, "loot_items": [], "events": [], "growth": {}}
	for side in 2:
		var prefix: String = "player" if side == 0 else "enemy"
		for i in n:
			var u: Unit = _person(10000 + side * n + i, "Native %d-%d" % [side, i])
			var state: String = "ready"
			match i % 8:
				0:
					u.dead = true; u.role = "officer"; state = "dead"
				1: HealthUtil.wound(u, "arm_upper_l", "bone", "fractured", 0.6)
				2: HealthUtil.wound(u, "head", "skin", "bruised", 0.1)
				3: state = "fled"
				4:
					var part: Dictionary = u.body.wound_part("hand_l")
					part["severed"] = true; part["stump_assessed"] = true
					u.body.permanent.append("left hand lost")
				5: state = "unconscious" # Native fighter-state evidence, body alone healthy.
				6:
					HealthUtil.wound(u, "head", "skin", "bruised", 0.1)
					state = "fled"
			result[prefix + "_units"].append(u)
			result["fighter_units"].append(u); result["fighter_states"].append(state)
			if state == "fled": result[prefix + "_fled"].append(u)
			if side == 1 and state in ["dead", "fled"]: result["enemy_fallen"].append(u)
	return result

static func _fingerprint(result: Dictionary) -> String:
	var records: Array = []
	var seen: Dictionary = {}
	for key in ["player_units", "enemy_units", "player_fled", "enemy_fled", "enemy_fallen", "fighter_units"]:
		for value in result.get(key, []):
			if not value is Unit or seen.has(value.get_instance_id()): continue
			seen[value.get_instance_id()] = true
			var u: Unit = value
			var row: Dictionary = u.to_dict() if u.body != null else {"uid": u.uid, "name": u.name, "role": u.role, "dead": u.dead, "body": null}
			# Sparse clean parts are intentionally omitted by to_dict; retain raw state for purity.
			row["raw_parts"] = u.body.parts.duplicate(true) if u.body != null else null
			row["metas"] = {}
			for meta in u.get_meta_list(): row["metas"][str(meta)] = u.get_meta(meta)
			records.append(row)
	return JSON.stringify({"records": records, "metadata": result})

func _partition(side: Dictionary, label: String) -> void:
	check(int(side["slain"]) + int(side["seriously_wounded"]) + int(side["wounded"]) + int(side["unhurt"]) == int(side["total"]), label + " health categories partition participants")
	check(side["other_wounded"] == side["wounded"], label + " other-wounded alias is exact")
	check(side["rows"]["fallen"].size() == int(side["slain"]), label + " fallen details match count")
	check(side["rows"]["wounded"].size() == int(side["seriously_wounded"]) + int(side["wounded"]), label + " wounded details include serious and other injuries")
	check(int(side["fled"]) <= int(side["total"]) - int(side["slain"]) and int(side["wounded_fled"]) <= int(side["fled"]), label + " retreat overlaps only survivors")

func _scale(n: int) -> void:
	var result: Dictionary = fixture(n)
	var before: String = _fingerprint(result)
	var rng_before: int = Game.rng.state
	var unit_before: int = Unit._next_uid
	var item_before: int = Item._next_uid
	var gold_before: int = Game.gold
	var summary: Dictionary = BattleResultSummary.build(result)
	var expected: Dictionary = {"slain": 0, "seriously_wounded": 0, "wounded": 0, "unhurt": 0, "fled": 0, "wounded_fled": 0}
	for i in n:
		var kind: int = i % 8
		expected["slain" if kind == 0 else "seriously_wounded" if kind in [1, 4, 5] else "wounded" if kind in [2, 6] else "unhurt"] += 1
		if kind in [3, 6]: expected["fled"] += 1
		if kind == 6: expected["wounded_fled"] += 1
	for side in 2:
		var row: Dictionary = summary["sides"][side]
		_partition(row, "%d participants side %d" % [n, side])
		check(row["total"] == n and row["name"] == result["side_names"][side], "native count and side name")
		for key: String in expected: check(row[key] == expected[key], "native %d-side %d %s count" % [n, side, key])
		check(row["officers_slain"] == expected["slain"], "actual dead officers counted")
		var wounds: Array = row["rows"]["wounded"]
		var actual: Unit = result["player_units" if side == 0 else "enemy_units"][1]
		check(is_same(wounds[0]["unit"], actual), "detail row borrows exact native fractured person")
		var report: Dictionary = HealthReport.describe(actual)
		check(wounds[0]["status"] == report["status"] and wounds[0]["heal_days"] == report["heal_days"] and wounds[0]["recovery"] == report["recovery"], "detail uses native status and recovery estimate")
		check(wounds[2]["serious"] and wounds[2]["heal_days"] == 0.0, "healed permanent loss remains serious despite zero recovery days")
		check(wounds[3]["status"] == "unconscious" and wounds[3]["serious"], "actual fighter unconscious state is retained without Unit meta mutation")
	check(JSON.stringify(BattleResultSummary.build(result)) == JSON.stringify(summary), "repeated summary is deterministic")
	check(_fingerprint(result) == before, "summary preserves every native body/gear/meta and result field")
	check(Game.rng.state == rng_before and Unit._next_uid == unit_before and Item._next_uid == item_before and Game.gold == gold_before, "summary consumes no RNG/UIDs/coins")
	print("Battle result summary checkpoint: ", n, "/", n, " complete")

func _aliases_and_sparse() -> void:
	var a: Unit = _person(41, "Our actual officer")
	a.dead = true; a.role = "officer"
	var b: Unit = _person(41, "Different instance, same UID")
	var minor: Unit = _person(42, "Minor fleeing injury")
	HealthUtil.wound(minor, "head", "skin", "bruised", 0.1)
	var enemy: Unit = _person(43, "Actual enemy")
	var result: Dictionary = {"player_units": [a, a, b, minor], "enemy_units": [enemy, enemy, a],
		"player_fled": [a, minor, enemy], "enemy_fallen": [enemy, a, enemy], "fighter_units": [a, a, b],
		"fighter_states": ["fled", "dead", "prone"], "side_names": ["", "Their realm"]}
	var before: String = _fingerprint(result)
	var rows: Array = BattleResultSummary.build(result)["sides"]
	_partition(rows[0], "alias player"); _partition(rows[1], "alias enemy")
	check(rows[0]["total"] == 3 and rows[1]["total"] == 1, "actual roster side wins off-side aliases and references deduplicate by instance")
	check(rows[0]["slain"] == 1 and rows[0]["unhurt"] == 1, "distinct same-UID native instance survives; prone alone is unhurt")
	check(rows[0]["fled"] == 1 and rows[0]["wounded_fled"] == 1, "dead/fled conflict prioritizes death without double counting")
	check(rows[1]["fled"] == 1, "missing explicit enemy fled list derives living historical fallen")
	result["enemy_fled"] = []
	check(BattleResultSummary.build(result)["sides"][1]["fled"] == 0, "explicit empty retreat metadata suppresses legacy inference")
	result.erase("enemy_fled")
	check(_fingerprint(result) == before, "alias/fallback reads preserve native records")
	var sparse := Unit.new()
	sparse.uid = 44; sparse.name = "No allocated body"
	var permanent := Unit.new()
	permanent.uid = 45; permanent.body = BodyState.new()
	permanent.body.parts = {"hand_l": {"severed": true}}
	var sparse_result: Dictionary = {"player_units": [sparse, permanent], "enemy_units": [null, "invalid"]}
	var raw: Dictionary = permanent.body.parts.duplicate(true)
	var summary: Dictionary = BattleResultSummary.build(sparse_result)
	check(summary["sides"][0]["total"] == 2 and summary["sides"][0]["seriously_wounded"] == 1 and summary["sides"][0]["unhurt"] == 1, "sparse input partitions recorded injury without inventing bodies")
	check(not summary["sides"][0]["rows"]["wounded"][0]["health_available"] and sparse.body == null and permanent.body.parts == raw, "unavailable native report leaves sparse state untouched")
	check(summary["sides"][1]["total"] == 0 and BattleResultSummary.build({})["sides"].size() == 2, "empty and invalid handcrafted participants are bounded")
	print("Battle result summary checkpoint: identity/sparse fallbacks complete")

func _native_ticks() -> void:
	var left: Array = [SimUtil.soldier("copper"), SimUtil.soldier("copper")]
	var right: Array = [SimUtil.soldier("copper"), SimUtil.soldier("copper")]
	var sim := BattleSim.new()
	sim.setup(left, right, 713, {"w": 8, "h": 4, "log_moves": false})
	for i in 24:
		if sim.is_over(): break
		sim.step()
	var result: Dictionary = {"player_units": left, "enemy_units": right, "fighter_units": [], "fighter_states": []}
	for f: Fighter in sim.fighters:
		result["fighter_units"].append(f.unit); result["fighter_states"].append(f.state)
	var before: String = _fingerprint(result)
	var state: int = sim.rng.state
	var unit_uid: int = Unit._next_uid
	var item_uid: int = Item._next_uid
	var summary: Dictionary = BattleResultSummary.build(result)
	_partition(summary["sides"][0], "native advanced player"); _partition(summary["sides"][1], "native advanced enemy")
	check(summary["sides"][0]["total"] == 2 and summary["sides"][1]["total"] == 2, "bounded actual native simulation retains all participants")
	check(_fingerprint(result) == before and sim.rng.state == state and Unit._next_uid == unit_uid and Item._next_uid == item_uid, "summary of advanced native fighters changes no combat state or identities")
	print("Battle result summary checkpoint: bounded native ticks complete")

func _physiology() -> void:
	var pain: Unit = _person(71, "Unconscious from real pain")
	pain.body.pain = Healing.PAIN_KO
	var blood: Unit = _person(72, "Unconscious from real blood loss")
	blood.body.blood = blood.body.blood_max * 0.1
	var native_dead: Unit = _person(73, "Native fighter death metadata")
	var result: Dictionary = {"player_units": [pain, blood, native_dead], "player_fled": [native_dead],
		"fighter_units": [native_dead], "fighter_states": ["dead"]}
	var before: String = _fingerprint(result)
	var side: Dictionary = BattleResultSummary.build(result)["sides"][0]
	check(side["seriously_wounded"] == 2 and side["slain"] == 1 and side["fled"] == 0, "real pain/blood knockout and native dead metadata have correct priorities")
	for detail: Dictionary in side["rows"]["wounded"]:
		var report: Dictionary = HealthReport.describe(detail["unit"])
		check(detail["status"] == "unconscious" and detail["status"] == report["status"] and detail["recovery"] == report["recovery"], "physiological unconsciousness keeps actual native status/recovery")
	check(not native_dead.dead and _fingerprint(result) == before, "native state metadata classification never writes Unit/body flags")

func run(_tree: SceneTree) -> int:
	var rng_before: int = Game.rng.state
	var gold_before: int = Game.gold
	var unit_before: int = Unit._next_uid
	var item_before: int = Item._next_uid
	_scale(100); _scale(200)
	_aliases_and_sparse()
	_physiology()
	_native_ticks()
	# Only the tiny native sim fixture allocates Units/Items; do not leak its counters.
	Unit._next_uid = unit_before; Item._next_uid = item_before
	check(Game.rng.state == rng_before and Game.gold == gold_before, "all fixture work preserves actual campaign RNG and money")
	print("Battle result summary v014: ", checks, " assertions; failures=", fails)
	return fails
