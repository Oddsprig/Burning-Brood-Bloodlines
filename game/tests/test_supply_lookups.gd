extends RefCounted
## Exact component comparison against frozen v0.033 redistribution, using actual forces and owned stock.
## SUPPLY_SAVE is required for the authentic day-600 case; reads only into isolated user:// storage.
## SUPPLY_CASE=all (default), fresh, or saved; SUPPLY_BENCH=1 prints three paired whole-call timings.
## No timing gate is relaxed. Fixture pooling only relocates existing reserve Items and arrows.
const Original = preload("res://tests/reference_supply_lookups.gd")
var fails := 0
var checks := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		fails += 1
		printerr("FAIL: ", label)

func run(_tree: SceneTree) -> int:
	var mode := OS.get_environment("SUPPLY_CASE")
	if mode.is_empty(): mode = "all"
	check(mode in ["all", "fresh", "saved"], "recognized supply case")
	var source := OS.get_environment("SUPPLY_SAVE")
	if mode in ["all", "saved"]:
		check(not source.is_empty() and FileAccess.file_exists(source), "authentic day-600 checkpoint supplied")
	if fails > 0: return fails
	_pure_selectors()
	if mode in ["all", "fresh"]:
		WorldGen.gen_size = "large"
		CampaignWorld.presim_years = 5
		Game.new_game(2026)
		check(Game.world["warbands"].size() > 0, "fresh world contains real registered forces")
		_compare("fresh ordinary", false)
		_pool_reserves()
		_compare("fresh pooled existing reserves", true)
	if mode in ["all", "saved"]:
		var copy := FileAccess.open(Game.SAVE_PATH, FileAccess.WRITE)
		check(copy != null, "isolated checkpoint copy writable")
		if copy != null:
			copy.store_string(FileAccess.get_file_as_string(source)); copy.close()
			check(Game.load_game(), "authentic campaign checkpoint loads")
			check(int(Game.day) == 600, "saved case is the actual day-600 campaign")
			if fails == 0:
				_compare("day600 ordinary", false)
				_pool_reserves()
				_compare("day600 pooled existing reserves", true)
	print("SUPPLY LOOKUPS checks=%d failures=%d" % [checks, fails])
	return fails

func _pure_selectors() -> void:
	var rng := RandomNumberGenerator.new(); rng.seed = 34028
	for trial in 100:
		var w := {"towns": {}}; var rows := {}; var ids := []
		for i in 68:
			var id := "t%03d" % i; ids.append(id)
			w["towns"][id] = {"faction": ["a", "b", "c", ""][rng.randi_range(0, 3)]}
			if i % 11 == 0: continue
			var have := {}; var target := {}
			for role in ["melee", "bow", "body", "arrows"]:
				target[role] = rng.randi_range(0, 20)
				have[role] = rng.randi_range(0, 30)
			rows[id] = {"have": have, "target": target}
		var lists := ArmsTrade._supply_shortlists(w, rows, ids)
		# Persistent lists remain valid as an original donor supplies real shortages monotonically.
		for source_id in ids:
			if not rows.has(source_id): continue
			var candidates: Dictionary = lists.get(w["towns"][source_id]["faction"], {})
			for role in ["melee", "bow", "body", "arrows"]:
				var old := Original._supply_destination(w, rows, ids, source_id, role)
				var selected := ArmsTrade._supply_destination(w, rows, candidates.get(role, []), source_id, role)
				check(old == selected, "same proportional shortage/tie order trial %d" % trial)
				if old != "" and int(rows[source_id]["have"][role]) > int(rows[source_id]["target"][role]):
					rows[source_id]["have"][role] -= 1
					rows[old]["have"][role] += 1
	# Explicit equal ratios, fulfilled list entry, missing role, foreign and empty faction.
	var w := {"towns": {"a": {"faction": "f"}, "b": {"faction": "f"}, "c": {"faction": "f"}, "d": {"faction": "other"}, "e": {"faction": ""}}}
	var rows := {"a": {"target": {"r": 2}, "have": {"r": 7}},
		"b": {"target": {"r": 10}, "have": {"r": 5}}, "c": {"target": {"r": 20}, "have": {"r": 10}},
		"d": {"target": {"r": 40}, "have": {"r": 0}}, "e": {"target": {"r": 50}, "have": {"r": 0}}}
	var ids := ["a", "b", "c", "d", "e"]; var lists := ArmsTrade._supply_shortlists(w, rows, ids)
	check(ArmsTrade._supply_destination(w, rows, lists["f"]["r"], "a", "r") == "b", "sorted ID wins equal ratio")
	rows["b"]["have"]["r"] = 10
	check(ArmsTrade._supply_destination(w, rows, lists["f"]["r"], "a", "r") == "c", "fulfilled listed recipient skipped")
	check(ArmsTrade._supply_destination(w, rows, [], "a", "missing") == "", "absent role has no destination")
	check(ArmsTrade._supply_destination(w, rows, [], "e", "r") == "", "unaffiliated source remains excluded")

func _pool_reserves() -> void:
	var before := _owned()
	var ids: Array = Game.world["towns"].keys(); ids.sort()
	var donors := {}; var pooled := 0; var arrows_pooled := 0
	for tid in ids:
		var town: Dictionary = Game.world["towns"][tid]
		if not TownEcon.has_econ(town): continue
		var faction := String(town.get("faction", ""))
		if faction == "": continue
		if not donors.has(faction): donors[faction] = tid
		if donors[faction] == tid: continue
		var dest: Dictionary = Game.world["towns"][donors[faction]]
		var arm := ArmsTrade.armory(town)
		pooled += arm.size()
		ArmsTrade.armory(dest).append_array(arm); arm.clear()
		var stock: Dictionary = town["econ"].get("armory", {})
		if not dest["econ"].has("armory"): dest["econ"]["armory"] = {}
		for k in DB.arrows:
			var n := int(stock.get(k, 0))
			if n <= 0: continue
			stock[k] = 0
			dest["econ"]["armory"][k] = int(dest["econ"]["armory"].get(k, 0)) + n
			arrows_pooled += n
	check(before == _owned(), "pool fixture preserves all actual item and unit identities, kit and arrow quantities")
	print("SUPPLY fixture relocated existing items=%d arrows=%d; no people/items/goods created" % [pooled, arrows_pooled])

func _state() -> Dictionary:
	return {"world": Game._serialize(Game.world), "rng": Game.rng.state,
		"unit_uid": Unit._next_uid, "item_uid": Item._next_uid,
		"ledger": ArmsTrade.ledger.duplicate(true), "lost": TownEcon.goods_lost.duplicate(true),
		"gold_gone": TownEcon.gold_gone}

func _restore(state: Dictionary) -> void:
	Game.world = _clone_fixture(state["world"].duplicate(true))
	Game.rng.state = state["rng"]
	Unit._next_uid = state["unit_uid"]; Item._next_uid = state["item_uid"]
	ArmsTrade.ledger = state["ledger"].duplicate(true)
	TownEcon.goods_lost = state["lost"].duplicate(true); TownEcon.gold_gone = state["gold_gone"]

## Clone current runtime objects without applying the old-save blank-drink migration.
## Unit.from_dict fills a blank favourite even on a current generated Unit. Retain
## the captured value here; the complete pre-call snapshot must still match exactly.
func _clone_fixture(value):
	if value is Dictionary:
		if value.has("__unit"):
			var unit := Unit.from_dict(value["__unit"])
			unit.fav_drink = String(value["__unit"].get("fav_drink", unit.fav_drink))
			return unit
		if value.has("__item"): return Item.from_dict(value["__item"])
		if value.has("__v2"): return Vector2(value["__v2"][0], value["__v2"][1])
		for key in value: value[key] = _clone_fixture(value[key])
	elif value is Array:
		for i in value.size(): value[i] = _clone_fixture(value[i])
	return value

func _snapshot() -> String:
	var out := Game._save_tree()
	out["verification_rng_state"] = str(Game.rng.state)
	out["verification_next_unit_uid"] = Unit._next_uid
	out["verification_next_item_uid"] = Item._next_uid
	out["verification_arms_ledger"] = ArmsTrade.ledger
	out["verification_goods_lost"] = TownEcon.goods_lost
	out["verification_gold_gone"] = TownEcon.gold_gone
	# Preserve insertion order as well as every ordinary Item/Unit list position.
	return JSON.stringify(out, "", false, true)

func _collect(v, items: Array, units: Array) -> void:
	if v is Item:
		items.append(v.uid)
	elif v is Unit:
		units.append(JSON.stringify(v.to_dict(), "", false, true))
		for it in v.equip.values(): items.append(it.uid)
	elif v is Dictionary:
		for x in v.values(): _collect(x, items, units)
	elif v is Array:
		for x in v: _collect(x, items, units)

func _owned() -> Dictionary:
	var items := []; var units := []
	_collect(Game.world, items, units); _collect(Game.company, items, units)
	_collect(Game.stash, items, units); _collect(Game.contract, items, units)
	items.sort(); units.sort()
	var arrows := {}
	for town in Game.world["towns"].values():
		for k in DB.arrows:
			arrows[k] = int(arrows.get(k, 0)) + int(town.get("econ", {}).get("armory", {}).get(k, 0))
	return {"items": items, "units": units, "reserve_arrows": arrows}

func _lookup_rows() -> Dictionary:
	var rows := {}
	for tid in Game.world["towns"]:
		var town: Dictionary = Game.world["towns"][tid]
		if not TownEcon.has_econ(town): continue
		ArmsTrade.refresh_reserve(Game, town)
		var have := ArmsTrade.role_counts(town["econ"]["arms_have"])
		var target := ArmsTrade.role_counts(town["econ"]["arms_tgt"])
		have["arrows"] = ArmsTrade.arrow_stock(town); target["arrows"] = int(town["econ"]["arrow_reserve"])
		rows[tid] = {"have": have, "target": target}
	return rows

func _compare(label: String, require_transfers: bool) -> void:
	var checkpoint := (maxi(int(Game.day), int(Game.world.get("arms", {}).get("supply_day", -1))) / ArmsTrade.SUPPLY_EVERY + 1) * ArmsTrade.SUPPLY_EVERY
	var input := _state(); var owned := _owned(); var cash := Barge.holdings(Game)
	var input_encoded := JSON.stringify(input, "", false, true)
	var before := _snapshot()
	var legend_locations := {}
	for tid in Game.world["towns"]:
		for it in Game.world["towns"][tid].get("armory_items", []):
			if it.is_legend(): legend_locations[it.uid] = tid
	var repeats := 3 if OS.get_environment("SUPPLY_BENCH") == "1" else 1
	var old_times := []; var new_times := []; var expected := ""; var expected_moved := -1
	for repeat in repeats:
		# Alternate call order; cloning, invariant checks and snapshots are outside measured calls.
		for candidate in ([false, true] if repeat % 2 == 0 else [true, false]):
			_restore(input)
			check(_snapshot() == before, label + " independent reconstruction preserves complete initial state before transfer")
			var begin := Time.get_ticks_usec()
			var moved := ArmsTrade.redistribute(Game, checkpoint) if candidate else Original.redistribute(Game, checkpoint)
			var elapsed := Time.get_ticks_usec() - begin
			if candidate: new_times.append(elapsed)
			else: old_times.append(elapsed)
			var after := _snapshot()
			if expected == "": expected = after; expected_moved = moved
			check(after == expected and moved == expected_moved, label + " complete state and returned movement match original")
			check(_owned() == owned and Barge.holdings(Game) == cash, label + " actual identities/equipment/items/arrows and cash conserved")
			check(Game.rng.state == input["rng"] and Unit._next_uid == input["unit_uid"] and Item._next_uid == input["item_uid"],
				label + " random stream and creation counters unchanged")
			check(JSON.stringify(input, "", false, true) == input_encoded, label + " independent reconstruction leaves source fixture unchanged")
	if require_transfers: check(expected_moved > 0, label + " actual owned stock transfers occur")
	_restore(input)
	var ids: Array = Game.world["towns"].keys(); ids.sort()
	Original.work = {}; Original.shortlists = ArmsTrade._supply_shortlists(Game.world, _lookup_rows(), ids)
	var counted_moved := Original.redistribute_counted(Game, checkpoint)
	check(counted_moved == expected_moved and _snapshot() == expected, label + " untimed query counter preserves original result")
	var legends_moved := 0
	for tid in Game.world["towns"]:
		for it in Game.world["towns"][tid].get("armory_items", []):
			if legend_locations.has(it.uid) and legend_locations[it.uid] != tid: legends_moved += 1
	old_times.sort(); new_times.sort()
	print("SUPPLY component %s towns=%d moved=%d original=%.3fms shortlist=%.3fms repetitions=%d sha256=%s queries=%d full_ids=%d shortlist_ids=%d" % [
		label, ids.size(), expected_moved, float(old_times[old_times.size() / 2]) / 1000.0,
		float(new_times[new_times.size() / 2]) / 1000.0, repeats, expected.sha256_text(),
		int(Original.work.get("queries", 0)), int(Original.work.get("full_id_visits", 0)), int(Original.work.get("shortlist_id_visits", 0))])
	print("SUPPLY actual legend coverage reserve_pieces=%d transferred=%d; full output preserves every legend history and stock-list order" % [legend_locations.size(), legends_moved])
	_restore(input)
