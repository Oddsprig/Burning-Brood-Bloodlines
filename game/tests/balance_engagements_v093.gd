extends RefCounted
## SOURCE ONLY: controller runs this through the native test runner, never as a fresh-fight loop.
const B = preload("res://tests/balance_v070.gd")
const R = preload("res://campaign/battle_rounds.gd")
const BattleScene = preload("res://battle/battle.gd")
const NativeFixture = preload("res://tests/test_dragon_identities.gd")
const DragonFixture = preload("res://tests/test_dragon_combat_v022.gd")
const SEEDS := [93017, 100936]
const ROUND_SIZE := 4
const LIMIT := 32
const WALL_MS := 45000
const WATCHDOG_SECONDS := 55 # External TestBridge watchdog; this script cannot extend it.
const OUT := "user://engagements_v093"
const SCHEMA := "balance_engagements_v093/1"

# The only scene override removes presentation. All twelve aftermath steps are inherited.
class CpuScene extends BattleScene:
	func _banner(_title: String, _sub: String, _secs: float) -> void:
		pass

static func manifest() -> Array:
	var out: Array = []
	for race in B.RACES:
		for role in B.ROLES:
			for seed_value in SEEDS:
				for side in 2:
					out.append({"index": out.size(), "id": "race_%s_%s_%d_s%d" % [race, role, seed_value, side],
						"kind": "race", "race": race, "role": role, "seed": seed_value,
						"subject_side": side, "mirror": race == "human"})
	for size in ["small", "large"]:
		for count in [8, 16, 32]:
			for seed_value in SEEDS:
				for side in 2:
					out.append({"index": out.size(), "id": "dragon_%s_%d_%d_s%d" % [size, count, seed_value, side],
						"kind": "dragon", "size": size, "opponents": count, "role": "spear", "seed": seed_value,
						"subject_side": side, "mirror": false})
	return out

static func partition(all: Array, shard: int, shards: int, only: String = "") -> Array:
	var out: Array = []
	for trial: Dictionary in all:
		if int(trial["index"]) % shards == shard and (only == "" or str(trial["id"]) == only): out.append(trial)
	return out

static func plain(value: Variant) -> Variant:
	# The native serializer owns Unit/Item/Vector encoding. Journals are explicitly disabled below.
	return JSON.parse_string(JSON.stringify(Game._serialize(value), "", true, true))

static func digest(value: Variant) -> String:
	return JSON.stringify(plain(value), "", true, true).sha256_text()

static func json_value_equal(a: Variant, b: Variant) -> bool:
	# JSON represents numbers without preserving the native int/float distinction.
	if (a is int or a is float) and (b is int or b is float): return a == b
	if a is Dictionary and b is Dictionary:
		if a.size() != b.size(): return false
		for key: Variant in a:
			if not b.has(key) or not json_value_equal(a[key], b[key]): return false
		return true
	if a is Array and b is Array:
		if a.size() != b.size(): return false
		for i in a.size():
			if not json_value_equal(a[i], b[i]): return false
		return true
	return typeof(a) == typeof(b) and a == b and typeof(a) in [TYPE_NIL, TYPE_BOOL, TYPE_STRING, TYPE_INT, TYPE_FLOAT]

static func without_labels(value: Variant) -> Variant:
	if value is Dictionary:
		var out: Dictionary = {}
		for key: Variant in value:
			var label := str(key)
			if label in ["uid", "name", "title"] or label.ends_with("_uid"): continue
			out[label] = without_labels(value[key])
		return out
	if value is Array:
		var out: Array = []
		for entry: Variant in value: out.append(without_labels(entry))
		return out
	return value

static func fingerprints() -> Dictionary:
	var paths: Array = ["res://tests/balance_engagements_v093.gd", "res://tests/test_engagement_contract_v093.gd",
		"res://tests/summarize_engagements_v093.py", "res://tests/balance_v070.gd", "res://tests/sim_util.gd",
		"res://tests/test_dragon_combat_v022.gd", "res://tests/test_dragon_identities.gd", "res://battle/battle.gd", Game.get_script().resource_path]
	# Resolve native class paths using the engine's published class registry, not guessed filenames.
	for entry: Dictionary in ProjectSettings.get_global_class_list():
		if str(entry["class"]) in ["BattleSim", "BattleScene", "BattleRounds", "BattleTactics", "DragonCombat", "DragonRiders",
			"DragonCare", "Dragons", "DragonBond", "Unit", "BodyState", "Fighter", "Item", "Factory", "Goods", "TroopUpkeep",
			"HealthReport", "Archery", "ArmsPool", "Ennoble", "Army", "Prisoners", "Mobilization", "Dynasty", "Persons",
			"People", "Families", "CampaignWorld", "Formulas", "NaturalAttacks", "DB"]:
			paths.append(str(entry["path"]))
	paths.sort()
	var source: Dictionary = {}
	for path: String in paths: source[path] = FileAccess.get_sha256(path)
	var data: Dictionary = B.fingerprint()
	data["loaded_races"] = digest(DB.races)
	data["loaded_goods"] = digest(Goods.table())
	data["dragon_catalogs"] = digest(Dragons.catalogs())
	return {"source_sha256": source, "data_sha256": data}

static func save_globals() -> Dictionary:
	return {"world": Game.world, "company": Game.company, "squads": Game.squads, "pending": Game.pending_battle,
		"day": Game.day, "gold": Game.gold, "location": Game.location, "rng": Game.rng.state,
		"unit": Unit._next_uid, "item": Item._next_uid, "round_size": R.round_size}

static func restore_globals(old: Dictionary) -> void:
	Game.world = old["world"]; Game.company = old["company"]; Game.squads = old["squads"]; Game.pending_battle = old["pending"]
	Game.day = float(old["day"]); Game.gold = float(old["gold"]); Game.location = str(old["location"])
	Game.rng.state = int(old["rng"]); Unit._next_uid = int(old["unit"]); Item._next_uid = int(old["item"])
	R.round_size = int(old["round_size"])

static func match_prefixes(a: Dictionary, b: Dictionary) -> Dictionary:
	# All candidates already exist; search reads actual seeded cumulative B costs without touching them.
	for bounds in [[9, 16], [5, LIMIT]]:
		var best := INF
		var result: Dictionary = {}
		for i in range(int(bounds[0]), mini(int(bounds[1]), a["costs"].size() - 1) + 1):
			for j in range(int(bounds[0]), mini(int(bounds[1]), b["costs"].size() - 1) + 1):
				var ca := float(a["costs"][i]); var cb := float(b["costs"][j])
				if ca <= 0.0 or cb <= 0.0: continue
				var gap := absf(ca - cb) / maxf(ca, cb)
				var score := gap * 100.0 + float(absi(i - 12) + absi(j - 12)) / 100.0
				if gap <= B.MAX_GAP and score < best:
					best = score
					result = {"counts": [i, j], "costs": [ca, cb], "gap": gap, "search": bounds.duplicate()}
		if not result.is_empty(): return result
	return {}

static func uids(units: Array) -> Array:
	var out: Array = []
	for u: Unit in units: out.append(str(u.uid))
	return out

static func create_pack(trial: Dictionary) -> Dictionary:
	# Only independent whole battles regenerate fixtures/arms. No call here occurs between engagements.
	Game.pending_battle = {}
	Game.rng.seed = int(trial["seed"])
	var a: Array = []; var b: Array = []; var prices: Dictionary = {}; var package: Dictionary = {}
	var fixture: Variant
	if str(trial["kind"]) == "race":
		fixture = NativeFixture.new(); fixture.fixture(int(trial["seed"]))
		var ac := B.candidates(B.spec(str(trial["race"]), str(trial["role"])), int(trial["seed"]) * 3 + 1, LIMIT)
		var bc := B.candidates(B.spec("human", str(trial["role"])), int(trial["seed"]) * 3 + 2, LIMIT)
		var matched := match_prefixes(ac, bc)
		if matched.is_empty(): return {"error": "unmatched: no actual <=5% prefixes with 5..32 ordinary units", "prefix_costs": [ac["costs"], bc["costs"]]}
		a = ac["units"].slice(0, int(matched["counts"][0])); b = bc["units"].slice(0, int(matched["counts"][1]))
		prices.merge(ac["prices"]); prices.merge(bc["prices"])
		package = {"match": matched, "starting_costs": matched["costs"].duplicate(), "ordinary_counts": matched["counts"].duplicate(),
			"cost_basis": "actual B gear + actual quiver at base goods prices + seven-day ordinary benchmark wages; not paid receipts"}
	else:
		fixture = DragonFixture.new(); fixture.fixture()
		if fixture.fails != 0: return {"error": "native dragon fixture failed"}
		var row: Dictionary = fixture.row()
		row["size_class"] = str(trial.get("size", "small")); row["growth_points"] = 2.0 if row["size_class"] == "large" else 0.0
		if not DragonCombat.sync_profile(Game, fixture.dragon_uid): return {"error": "native size profile sync refused"}
		var review: Dictionary = DragonCombat.participation_preview(Game, fixture.dragon_uid, true)
		var admission: Dictionary = DragonCombat.participation_order(Game, fixture.dragon_uid, true, review)
		if not bool(admission.get("ok", false)): return {"error": "reviewed native participation refused", "admission": admission}
		var admitted: Array = DragonCombat.battle_units(Game)
		if admitted != [fixture.actor()]: return {"error": "native participation did not return the original Ruby actor"}
		a = admitted
		var count := int(trial.get("opponents", 9))
		var bc := B.candidates(B.spec("human", "spear"), int(trial["seed"]) * 3 + 2, count)
		b = bc["units"]; prices.merge(bc["prices"])
		var need := DragonCare.food_need_units(Game, row)
		package = {"starting_costs": [null, bc["costs"][-1]], "ordinary_counts": [0, count],
			"dragon": {"dragon_uid": fixture.dragon_uid, "unit_uid": str(fixture.actor().uid), "gem": row["gem_id"],
				"stage": row["stage"], "size": row["size_class"], "growth_points": row["growth_points"],
				"profile": Dragons.physical_profile(Game, row), "rider_person_uid": row["rider_person_uid"],
				"participation_review": plain(review), "participation_order": plain(admission), "purchase_price": null,
				"food_need_units_per_day": need, "seven_day_food_units": 7 * need,
				"seven_day_base_price_estimates": {"meat": 7 * need * float(Goods.table()["meat"]["price"]),
					"fresh_meat": 7 * need * float(Goods.table()["fresh_meat"]["price"])},
				"provisioning_basis": "separate single-good base-price estimates of pure daily requirement; no elapsed care or paid receipt"},
			"cost_basis": "human opponent actual B gear/quiver/seven-day benchmark wages; dragon and civilian rider have no invented purchase budget"}
		if str(trial["kind"]) == "control":
			var ac := B.candidates(B.spec("human", "sword"), int(trial["seed"]) * 3 + 1, 9)
			a = a + ac["units"]; prices.merge(ac["prices"])
			package["ordinary_counts"] = [9, count]
			package["starting_costs"][0] = ac["costs"][-1]
			# An explicit pre-battle wounded/dead fixture, never a fabricated result or a between-round reset.
			(a[1] as Unit).body.blood *= 0.98; (a[1] as Unit).body.pain = 0.15
			(a[-1] as Unit).dead = true
	var physical := [a, b] if int(trial["subject_side"]) == 0 else [b, a]
	Game.company = (physical[0] as Array).filter(func(u): return not DragonCombat.is_dragon_unit(Game, u))
	Game.squads = {}
	Game.world["warbands"]["engagement_v093"] = {"id": "engagement_v093", "kind": "army", "faction": "middle_kingdom", "home": "b",
		"pos": Game.world["towns"]["b"]["pos"], "units": (physical[1] as Array).duplicate()}
	Game.pending_battle = {"seed": int(trial["seed"]), "terrain": "plains", "warband_id": "engagement_v093",
		"max_ticks": 2 if str(trial["kind"]) == "control" else B.MAX_TICKS, "rider_bodies": {}}
	if str(trial["kind"]) == "control": Game.pending_battle.merge({"hold0": true, "hold1": true})
	return {"pools": physical, "participants": [a, b], "prices": prices, "package": package, "fixture": fixture}

static func remember_refs(pools: Array) -> Dictionary:
	var out: Dictionary = {}
	for pool: Array in pools:
		for u: Unit in pool: out[str(u.uid)] = {"unit": u, "body": u.body}
	for person: String in Game.pending_battle.get("rider_bodies", {}):
		var u: Unit = Game.pending_battle["rider_bodies"][person]
		out[str(u.uid)] = {"unit": u, "body": u.body}
	return out

static func refs_ok(pools: Array, refs: Dictionary) -> bool:
	for pool: Array in pools:
		for u: Unit in pool:
			if not refs.has(str(u.uid)) or refs[str(u.uid)]["unit"] != u or refs[str(u.uid)]["body"] != u.body: return false
	for u: Unit in Game.pending_battle.get("rider_bodies", {}).values():
		if not refs.has(str(u.uid)) or refs[str(u.uid)]["unit"] != u or refs[str(u.uid)]["body"] != u.body: return false
	return true

static func snapshot(pools: Array) -> Dictionary:
	var st: Dictionary = Game.pending_battle["rounds"]
	var roster: Array = []; var bodies: Dictionary = {}; var custody: Array = []; var riders: Dictionary = {}
	for side in 2:
		var side_rows: Array = []
		var fit_ids := uids(R.fit(Game, pools[side], st["captives"][side]))
		for u: Unit in pools[side]:
			var id := str(u.uid)
			bodies[id] = digest(u.body.to_dict())
			side_rows.append({"uid": id, "unit_instance": str(u.get_instance_id()), "body_instance": str(u.body.get_instance_id()),
				"unit_sha256": digest(u.to_dict()), "body_sha256": bodies[id], "gear_sha256": digest(u.equip),
				"quiver_sha256": digest(u.quiver), "dead": u.dead, "fit": fit_ids.has(id), "captured": (st["captives"][side] as Array).has(u),
				"native_dragon": DragonCombat.is_dragon_unit(Game, u), "injury": B.injury(u)})
		roster.append(side_rows); custody.append(uids(st["captives"][side]))
	for person: String in Game.pending_battle.get("rider_bodies", {}):
		var u: Unit = Game.pending_battle["rider_bodies"][person]
		riders[person] = {"uid": str(u.uid), "unit_instance": str(u.get_instance_id()), "body_instance": str(u.body.get_instance_id()),
			"unit_sha256": digest(u.to_dict()), "body_sha256": digest(u.body.to_dict()), "dead": u.dead, "injury": B.injury(u)}
	var holds := {"captives_by_original_side": custody, "prisoners": plain(Game.world.get("prisoners", [])), "captives": plain(Game.world.get("captives", []))}
	var persistent := {"roster": roster, "rider_bodies": riders, "custody": holds,
		"dragon_seats": plain(st.get("dragon_seats", {})), "dragon_downs": plain(st.get("dragon_downs", {}))}
	var hashes := {"body": digest(bodies), "roster": digest(roster), "custody": digest(holds), "rider": digest(riders),
		"seats": digest(persistent["dragon_seats"]), "downs": digest(persistent["dragon_downs"])}
	persistent["hashes"] = hashes
	persistent["continuity_sha256"] = digest(hashes)
	return persistent

static func measure(pools: Array, prices: Dictionary) -> Array:
	var out: Array = []
	var st: Dictionary = Game.pending_battle["rounds"]
	for side in 2:
		var row := {"injury": 0.0, "dead": 0, "captured": 0, "unfit": 0, "ordinary_killed_cost": 0.0,
			"ordinary_captured_cost": 0.0, "ordinary_unfit_cost": 0.0, "unpriced_dragon_deaths": 0}
		var fit: Array = R.fit(Game, pools[side], st["captives"][side])
		for u: Unit in pools[side]:
			row["injury"] += B.injury(u)
			var price := float(prices.get(str(u.uid), 0.0)) # Sums explicitly cover priced ordinary units only.
			if u.dead:
				row["dead"] += 1; row["ordinary_killed_cost"] += price
				if DragonCombat.is_dragon_unit(Game, u): row["unpriced_dragon_deaths"] += 1
			elif (st["captives"][side] as Array).has(u): row["captured"] += 1; row["ordinary_captured_cost"] += price
			elif not fit.has(u): row["unfit"] += 1; row["ordinary_unfit_cost"] += price
		out.append(row)
	return out

static func delta_measure(before: Array, after: Array, sim: BattleSim) -> Array:
	var out: Array = []
	for side in 2:
		var row: Dictionary = {}
		for key: String in before[side]: row[key] = after[side][key] - before[side][key]
		row["native_fighter_kills"] = 0
		for f: Fighter in sim.fighters:
			if f.side == side: row["native_fighter_kills"] += f.kills
		out.append(row)
	return out

static func picks_valid(pools: Array, picks: Array) -> bool:
	var st: Dictionary = Game.pending_battle["rounds"]
	for side in 2:
		var fit: Array = R.fit(Game, pools[side], st["captives"][side])
		if picks[side].size() > ROUND_SIZE or uids(picks[side]).size() != (picks[side] as Array).size(): return false
		var seen: Dictionary = {}
		for u: Unit in picks[side]:
			if not fit.has(u) or seen.has(u.uid) or u.dead or (st["captives"][side] as Array).has(u): return false
			seen[u.uid] = true
	return true

static func termination(st: Dictionary) -> Dictionary:
	var reasons: Array = []
	for side in 2:
		if R.fit(Game, st["pool"][side], st["captives"][side]).is_empty(): reasons.append("side%d_no_fit" % side)
		if float(st["morale"][side]) < R.BREAK_MORALE: reasons.append("side%d_morale" % side)
		if float(int(st["dead"][side]) + int(st["captured"][side])) > R.BREAK_LOSS * float(st["start"][side]): reasons.append("side%d_casualty_share" % side)
	var max_rounds := int(st["round"]) >= R.MAX_ROUNDS
	return {"reason": "native_max_rounds" if reasons.is_empty() and max_rounds else "native_army_break",
		"break_conditions": reasons, "reached_native_max_rounds": max_rounds, "broke_side": int(st["broke"])}

static func all_checks(checks: Dictionary) -> bool:
	for value: Variant in checks.values():
		if value != true: return false
	return true

static func checkpoint(book: Dictionary) -> bool:
	book["checkpoint"] = int(book.get("checkpoint", -1)) + 1
	var path := "%s/%s_%04d.json" % [OUT, book["run_id"], int(book["checkpoint"])]
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT)) != OK: return false
	if FileAccess.file_exists(path): return false
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null: return false
	file.store_string(JSON.stringify(book, "\t", true, true))
	var error := file.get_error(); file.close()
	if error != OK: return false
	print("engagement093 checkpoint: ", ProjectSettings.globalize_path(path))
	return true

static func trial_run(tree: SceneTree, trial: Dictionary, deadline: int, book: Dictionary = {}) -> Dictionary:
	var row := {"trial": trial.duplicate(true), "status": "running", "engagements": [], "final_result": null, "battle_summary": null}
	if not book.is_empty(): book["trials"].append(row)
	var pack := create_pack(trial)
	if pack.has("error"):
		row.merge({"status": "unmatched" if str(pack["error"]).begins_with("unmatched") else "setup_error", "error": pack})
		return row
	var pools: Array = pack["pools"]
	row["package"] = pack["package"]
	row["starting_counts"] = [pools[0].size(), pools[1].size()]
	row["physical_to_participant"] = [0, 1] if int(trial["subject_side"]) == 0 else [1, 0]
	if not R.wanted(pools[0], pools[1]):
		row.merge({"status": "setup_error", "error": "armies do not enter native multi-round path"}); return row
	R.begin(Game, pools[0], pools[1])
	# Native detached rider bodies are created once at the battle boundary and retained in this pending battle.
	var initial_riders: Dictionary = DragonCombat.battle_riders(Game, pools[0] + pools[1])
	row["riders_at_start"] = plain(initial_riders)
	if str(trial["kind"]) != "race":
		var dragon_id := str(pack["package"]["dragon"]["unit_uid"])
		if not initial_riders.has(dragon_id) or not bool(initial_riders[dragon_id].get("detached", false)):
			row.merge({"status": "setup_error", "error": "actual civilian rider was not supplied by native battle_riders"}); return row
	var rider_dictionary: Dictionary = Game.pending_battle["rider_bodies"]
	var refs := remember_refs(pools)
	var inputs: Array = []
	for participant: Array in pack["participants"]:
		var units: Array = []
		for u: Unit in participant: units.append(without_labels(plain(u.to_dict())))
		inputs.append(digest(units))
	row["input_sha256_participants"] = inputs
	row["input_sha256_physical"] = inputs.duplicate() if int(trial["subject_side"]) == 0 else [inputs[1], inputs[0]]
	# Map by actual person identity, never the outer dragon Unit UID key returned by battle_riders.
	var rider_inputs: Dictionary = {}
	var rider_packages: Dictionary = {}
	for person: String in rider_dictionary:
		var rider: Unit = rider_dictionary[person]
		rider_inputs[person] = without_labels(plain(rider.to_dict()))
		var quiver_value := 0.0
		for arrow: String in rider.quiver: quiver_value += int(rider.quiver[arrow]) * float(Goods.table()[arrow]["price"])
		rider_packages[person] = {"unit_uid": str(rider.uid), "native_civilian_battle_body": true,
			"gear_value": float(rider.gear_value()), "quiver_value": quiver_value,
			"seven_day_retainer_wage_benchmark": TroopUpkeep.wage_week({}), "B_body_cost_benchmark": B.body_cost(rider),
			"basis": "actual initial gear/quiver plus ordinary seven-day retainer wage BENCHMARK; civilian is not hired; no paid receipt"}
	row["rider_input_sha256"] = digest(rider_inputs)
	row["rider_packages"] = rider_packages
	row["initial"] = snapshot(pools)
	row["tactics_policy"] = "native begin/setup_round defaults, no choose override; apply_sim(st.tactic_mods) each engagement; physical side 0 default hold, native enemy policy"
	var previous_after := str(row["initial"]["continuity_sha256"])
	var last: Dictionary = {}; var any_cap := false; var any_draw := false
	var st: Dictionary = Game.pending_battle["rounds"]
	while not bool(st["over"]):
		if Time.get_ticks_msec() >= deadline:
			row.merge({"status": "incomplete_wall", "termination": {"reason": "wall_before_engagement"}, "censored": true}); return row
		var picks: Array = [Game.pending_battle["round_side0"], Game.pending_battle["enemy"]]
		var riders: Dictionary = DragonCombat.battle_riders(Game, picks[0] + picks[1])
		var before := snapshot(pools)
		var counts_before := measure(pools, pack["prices"])
		var checks := {"continuity_from_previous": before["continuity_sha256"] == previous_after,
			"original_unit_body_references": refs_ok(pools, refs), "original_rider_dictionary": is_same(rider_dictionary, Game.pending_battle["rider_bodies"]),
			"picks_fit_no_corpse_or_captive": picks_valid(pools, picks), "native_pool_references": st["pool"] == pools,
			"round_number": int(st["round"]) == (row["engagements"] as Array).size() + 1}
		var scene := CpuScene.new()
		var opts: Dictionary = scene.battle_opts(Game.pending_battle, picks[0].size(), picks[1].size())
		opts.merge({"dragon_riders": riders, "combat_journal": false, "log_moves": false, "verbose": false})
		var sim := BattleSim.new()
		sim.setup(picks[0], picks[1], int(Game.pending_battle["seed"]), opts)
		BattleTactics.apply_sim(sim, st["tactic_mods"])
		var engagement := {"trial_id": trial["id"], "seed": trial["seed"], "native_seed": Game.pending_battle["seed"],
			"subject_side": trial["subject_side"], "round": int(st["round"]), "selected_uids": [uids(picks[0]), uids(picks[1])],
			"riders": plain(riders), "before": before, "checks": checks, "status": "running",
			"opts": plain(opts), "tactics": plain(st.get("tactics", {})), "tactic_mods": plain(st["tactic_mods"])}
		while not sim.is_over():
			sim.step()
			if sim.tick % 64 == 0:
				if Time.get_ticks_msec() >= deadline: break
				await tree.process_frame
		engagement["ticks"] = sim.tick; engagement["native_winner"] = sim.winner
		engagement["draw"] = sim.is_over() and sim.winner < 0
		engagement["tick_capped"] = sim.tick >= int(Game.pending_battle["max_ticks"])
		if not sim.is_over():
			engagement.merge({"status": "incomplete_wall", "after": snapshot(pools), "aftermath_applied": false, "round_applied": false})
			row["engagements"].append(engagement)
			row.merge({"status": "incomplete_wall", "termination": {"reason": "wall_during_engagement"}, "censored": true})
			scene.free()
			if not book.is_empty() and not checkpoint(book): row["checkpoint_error"] = true
			return row
		# Exact native CPU result-builder lifecycle. No per-round Game.finish_battle/close/reset/admission.
		scene.sim = sim; scene.side_names = ["Physical side 0", "Physical side 1"]; scene.speed = 1.0
		scene._aftermath(float(BattleScene.AFTER_STEPS) * BattleScene.AFTER_STEP_SECS + 0.001)
		engagement["aftermath"] = plain(scene.aftermath)
		last = scene.build_result()
		var expected: Dictionary = {"dragon_seats": (st.get("dragon_seats", {}) as Dictionary).duplicate(true)}
		DragonCombat.merge_seats(expected, last.get("dragon_seats", {}))
		var downs: Dictionary = (st.get("dragon_downs", {}) as Dictionary).duplicate()
		for id: String in last.get("dragon_downs", {}): downs[id] = bool(downs.get(id, false)) or bool(last["dragon_downs"][id])
		var summary: Dictionary = R.after_round(Game, last)
		var after := snapshot(pools)
		checks.merge({"original_references_after": refs_ok(pools, refs), "rider_dictionary_after": is_same(rider_dictionary, Game.pending_battle["rider_bodies"]),
			"seats_native_merge": st.get("dragon_seats", {}) == expected["dragon_seats"], "downs_native_merge": st["dragon_downs"] == downs,
			"native_log_count": st["log"].size() == int(st["round"]), "aftermath_complete": scene._after_step == BattleScene.AFTER_STEPS})
		var delta := delta_measure(counts_before, measure(pools, pack["prices"]), sim)
		var rider_delta: Dictionary = {}
		for person: String in before["rider_bodies"]:
			rider_delta[person] = {"injury": float(after["rider_bodies"][person]["injury"]) - float(before["rider_bodies"][person]["injury"]),
				"new_death": int(bool(after["rider_bodies"][person]["dead"])) - int(bool(before["rider_bodies"][person]["dead"]))}
		var normalized := delta.duplicate(true)
		if int(trial["subject_side"]) == 1: normalized.reverse()
		engagement.merge({"status": "complete", "after": after, "aftermath_applied": true, "round_applied": true,
			"native_summary": plain(summary), "round_result": plain(last), "delta_physical": delta, "delta_participants": normalized, "delta_riders": rider_delta})
		row["engagements"].append(engagement)
		previous_after = str(after["continuity_sha256"])
		any_cap = any_cap or bool(engagement["tick_capped"]); any_draw = any_draw or bool(engagement["draw"])
		scene.free()
		if not all_checks(checks): row.merge({"status": "contract_error", "censored": true}); return row
		if not book.is_empty() and not checkpoint(book): row.merge({"status": "checkpoint_error", "censored": true}); return row
		if not bool(st["over"]): R.next_round(Game)
	row["termination"] = termination(st)
	row["battle_summary"] = plain(R.battle_summary(Game))
	# Preserve every native final_result field through the native serializer (journal is actually null).
	row["final_result"] = plain(R.final_result(Game, last))
	row["final"] = snapshot(pools)
	row["fit_survivors_physical"] = [R.fit(Game, pools[0], st["captives"][0]).size(), R.fit(Game, pools[1], st["captives"][1]).size()]
	row["totals_physical"] = measure(pools, pack["prices"])
	row["total_rounds"] = int(st["round"])
	row["native_winner"] = int(st["winner"])
	row["winner_participant"] = -1 if int(st["winner"]) < 0 else (int(st["winner"]) if int(trial["subject_side"]) == 0 else 1 - int(st["winner"]))
	row["any_tick_cap"] = any_cap; row["any_draw"] = any_draw
	row["censored"] = any_cap or bool(row["termination"]["reached_native_max_rounds"])
	row["status"] = "complete_censored" if bool(row["censored"]) else "complete"
	return row

static func control(tree: SceneTree, deadline: int) -> Dictionary:
	return await trial_run(tree, {"id": "contract_native_carry", "index": -1, "kind": "control", "size": "small",
		"opponents": 9, "seed": SEEDS[0], "subject_side": 0, "role": "spear", "mirror": false}, deadline)

func run(tree: SceneTree) -> int:
	var phase := ""; var shard := -1; var shards := 0; var only := ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--engagement-phase="): phase = arg.trim_prefix("--engagement-phase=")
		elif arg.begins_with("--engagement-shard="):
			var parts := arg.trim_prefix("--engagement-shard=").split("/")
			if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int(): return 1
			shard = int(parts[0]); shards = int(parts[1])
		elif arg.begins_with("--engagement-trial="): only = arg.trim_prefix("--engagement-trial=")
	if not phase.is_valid_identifier() or shards < 1 or shards > 108 or shard < 0 or shard >= shards:
		printerr("Explicit --engagement-phase=NAME and --engagement-shard=i/n (0-based) required."); return 1
	var all := manifest(); var selected := partition(all, shard, shards, only)
	if selected.is_empty(): printerr("No declared trial in this partition/filter."); return 1
	var old := save_globals(); R.round_size = ROUND_SIZE
	var started := Time.get_ticks_msec()
	var book := {"schema": SCHEMA, "phase": phase, "shard": shard, "shards": shards, "only_trial": only,
		"manifest": all, "manifest_sha256": digest(all), "selected_ids": selected.map(func(t): return t["id"]), "trials": [],
		"round_size": ROUND_SIZE, "max_ticks": B.MAX_TICKS, "internal_wall_ms": WALL_MS, "external_watchdog_seconds": WATCHDOG_SECONDS,
		"run_id": "%s_%dof%d_%d_%d_%d" % [phase, shard, shards, int(Time.get_unix_time_from_system()), OS.get_process_id(), Time.get_ticks_usec()],
		"status": "running", "complete": false, "coverage_claim": "two-seed limited pilot; no balance/fairness pass threshold"}
	book.merge(fingerprints())
	var ok := checkpoint(book)
	for trial: Dictionary in selected:
		if not ok or Time.get_ticks_msec() >= started + WALL_MS: break
		var row: Dictionary = await trial_run(tree, trial, started + WALL_MS, book)
		ok = not row.has("checkpoint_error") and row["status"] in ["complete", "complete_censored"]
		var trial_saved := checkpoint(book)
		ok = ok and trial_saved
		if not ok: break
	book["elapsed_ms"] = Time.get_ticks_msec() - started
	book["complete"] = ok and book["trials"].size() == selected.size()
	book["status"] = "complete" if book["complete"] else "incomplete"
	var saved := checkpoint(book)
	restore_globals(old)
	print("engagement093 %s %d/%d: %s, %d/%d trials, %d ms" % [phase, shard, shards, book["status"], book["trials"].size(), selected.size(), book["elapsed_ms"]])
	return 0 if bool(book["complete"]) and saved else 1
