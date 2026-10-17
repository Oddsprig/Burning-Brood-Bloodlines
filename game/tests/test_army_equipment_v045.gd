extends RefCounted
## Full v0.044 ArmsTrade oracle; only its class_name is renamed in the fixture.
## Original git blob: 2eee834efbd0bb42a54fca31a310c2b28b7b9602:game/campaign/arms_trade.gd.
## LF source SHA256: 15f0e062f8e7fc0a2c160f8950c68b3aecfdce9c445c1623caaad859d4f179ba.
## Same physical objects are restored between calls: equality covers identity, insertion
## order, marks, damage, money, ledgers, misses, RNG and creation counters.
const Original = preload("res://tests/fixtures/army_v045_baseline.gd")
const ORIGINAL_SHA := "15f0e062f8e7fc0a2c160f8950c68b3aecfdce9c445c1623caaad859d4f179ba"
var checks := 0
var fails := 0
var cases := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		fails += 1
		printerr("FAIL: ", label)

func run(_tree: SceneTree) -> int:
	var fixture := FileAccess.get_file_as_string("res://tests/fixtures/army_v045_baseline.gd")
	check(fixture.replace("class_name ArmyV045Baseline", "class_name ArmsTrade").sha256_text() == ORIGINAL_SHA,
		"complete frozen ArmsTrade source matches verified v044 git blob after sole class rename")
	_direct_selection()
	_shared_counts()
	_all_loadouts()
	Game.new_game(5159)
	compare_real_jobs("fresh seed5159", 3)
	print("ARMY EQUIPMENT cases=%d checks=%d failures=%d" % [cases, checks, fails])
	return fails

func _town(items: Array, targets: Dictionary = {}) -> Dictionary:
	return {"id": "equipment_fixture", "armory_items": items.duplicate(), "shop": [],
		"econ": {"stock": {}, "price": {}, "arms_tgt": targets.duplicate(true),
			"treasury": 1.0e9, "mkt": 0, "biz": [{"till": 123.0}], "stats": {"sales": 0.0},
			"led": {"used": {}}}}

func _item(tid: String, index: int) -> Item:
	var mats: Array = DB.template(tid).get("materials", ["copper"])
	var it := Item.make(tid, String(mats[index % mats.size()]), index % (DB.LEGEND + 1))
	it.wear = index % 4
	it.dull = float(index % 3) / 2.0
	it.broken = index % 5 == 0
	it.vr = 0.95 + 0.01 * (index % 11)
	it.mark = {"n": "fixture maker %d" % index, "b": index, "t": "fixture", "r": "human"}
	if it.is_legend():
		it.legend = {"nm": "fixture legend %d" % index, "by": "fixture maker", "h": [[3, "earlier carrier"]], "k": 7}
	return it

func _alternates(tids: Array, slot: String, same_class: bool) -> Array:
	var out := []
	var want := String(tids[0])
	for tid in DB.weapons.keys() + DB.armor.keys():
		if tids.has(tid): continue
		var probe := Item.new(); probe.tid = tid
		if probe.slot() != slot: continue
		if same_class and Original.cls(tid) == Original.cls(want): out.append(tid)
		elif not same_class and Original.cls(tid) != Original.cls(want) and Original.role(tid) == Original.role(want): out.append(tid)
	return out

func _direct_selection() -> void:
	var rows := 0
	for fid in DB.factions:
		for troop in DB.factions[fid].get("troops", []):
			var lo := Original.troop_loadout(troop)
			check(lo == ArmsTrade.troop_loadout(troop), "loadout definition unchanged " + fid + "/" + String(troop["name"]))
			for slot in lo:
				rows += 1
				var tids: Array = lo[slot]["tids"]
				var tid := String(tids[0]); var cls := Original.cls(tid)
				var first := _item(tid, 0); var better := _item(tid, DB.LEGEND)
				var label: String = String(fid) + "/" + String(troop["name"]) + "/" + String(slot)
				_select(label + " empty", [], tids, slot, false, {}, null)
				_select(label + " physical exact tie", [first, better], tids, slot, false, {}, first)
				_select(label + " exact reserve boundary", [first, better], tids, slot, true, {cls: 2}, null)
				_select(label + " exact above reserve", [first, better], tids, slot, true, {cls: 1}, first)
				_select(label + " missing target means zero", [first], tids, slot, true, {}, first)
				_select(label + " negative reserve target", [first], tids, slot, true, {cls: -1}, first)
				var alts := _alternates(tids, slot, true)
				if not alts.is_empty():
					var alt := _item(String(alts[0]), 1)
					_select(label + " later exact beats class", [alt, first, better], tids, slot, false, {}, first)
					_select(label + " first class fallback", [alt, _item(String(alts[0]), 5)], tids, slot, false, {}, alt)
					_select(label + " optional class fallback above reserve", [alt], tids, slot, true, {}, alt)
				var foreign := _alternates(tids, slot, false)
				if not foreign.is_empty():
					var other := _item(String(foreign[0]), 2)
					_select(label + " foreign same role", [other], tids, slot, false, {}, other)
					_select(label + " optional forbids foreign", [other], tids, slot, true, {}, null)
					_select(label + " exact beats foreign", [other, first], tids, slot, false, {}, first)
				if tids.size() > 1:
					var second_tid := _item(String(tids[1]), 3)
					_select(label + " exact list uses stock order", [second_tid, first], tids, slot, false, {}, second_tid)
	check(rows > 0, "all faction troop armory loadouts exercised")
	var empty_classes := 0
	for tid in DB.armor:
		if Original.cls(tid) != "": continue
		empty_classes += 1
		var cloth := _item(tid, 0)
		_select("non-armory class " + tid, [cloth], [tid], cloth.slot(), true, {"": -1}, cloth)
		_select("non-armory class at reserve " + tid, [cloth], [tid], cloth.slot(), true, {"": 1}, null)
	check(empty_classes > 0, "empty-class templates cover the changed optional count branch")
	print("ARMY EQUIPMENT selection loadout_slots=%d" % rows)

func _shared_counts() -> void:
	# Find classes by semantics, without town/person-specific equipment rules.
	var tids := []
	for tid in DB.weapons:
		if Original.role(tid) == "main_hand_1h" and Original.cls(tid) != "": tids.append(tid)
	check(tids.size() > 1, "shared-count fixture has actual one-handed templates")
	if tids.size() < 2: return
	var first_tid := String(tids[0]); var other_tid := ""
	for tid in tids:
		if Original.cls(tid) != Original.cls(first_tid): other_tid = tid; break
	check(other_tid != "", "shared-count fixture has a foreign role-compatible class")
	if other_tid == "": return
	var stock := [_item(other_tid, 5), _item(first_tid, 0), _item(first_tid, 1), _item(first_tid, 2), _item(other_tid, 4)]
	var old := _town(stock); var new := _town(stock); var scratch := {}
	var first_class := Original.cls(first_tid); var other_class := Original.cls(other_tid)
	var calls := [
		{"tids": [first_tid, other_tid], "opt": true, "target": {first_class: 2}},
		{"tids": [first_tid], "opt": false, "target": {first_class: 2}},
		{"tids": [other_tid], "opt": true, "target": {other_class: 1}},
		{"tids": [first_tid], "opt": true, "target": {first_class: 1}},
		{"tids": [first_tid], "opt": true, "target": {first_class: 0}},
		{"tids": [first_tid], "opt": false, "target": {}},
		{"tids": [first_tid], "opt": true, "target": {}}
	]
	for i in calls.size():
		var call: Dictionary = calls[i]
		old["econ"]["arms_tgt"] = call["target"].duplicate(true)
		new["econ"]["arms_tgt"] = call["target"].duplicate(true)
		var expected := Original._take_fit(old, call["tids"], "main_hand", call["opt"])
		var actual := ArmsTrade._take_fit(new, call["tids"], "main_hand", call["opt"], scratch)
		cases += 1
		check(expected == actual and old["armory_items"] == new["armory_items"], "shared optional count physical choice/removal through mixed-class exact, required and target changes %d" % i)
		check(JSON.stringify(Game._serialize(old), "", false, true) == JSON.stringify(Game._serialize(new), "", false, true), "shared count complete mutation %d" % i)
		if scratch.has("counts"):
			var remaining := {}
			for it in new["armory_items"]:
				var cls := Original.cls(it.tid); remaining[cls] = int(remaining.get(cls, 0)) + 1
			for cls in scratch["counts"]:
				check(int(scratch["counts"][cls]) == int(remaining.get(cls, 0)), "scratch count equals actual remaining selected class %d/%s" % [i, cls])
	# Scratch is bounded to one shrinking pass; a later pass must observe new stock.
	var replenished := _item(first_tid, 6)
	old["armory_items"].append(replenished); new["armory_items"].append(replenished)
	var expected := Original._take_fit(old, [first_tid], "main_hand", true)
	var actual := ArmsTrade._take_fit(new, [first_tid], "main_hand", true, {})
	check(expected == replenished and actual == expected, "new pass sees replenished stock after previous scratch became empty")

func _select(label: String, stock: Array, tids: Array, slot: String, opt: bool, target: Dictionary, explicit: Item) -> void:
	cases += 1
	var baseline := _town(stock, target); var candidate := _town(stock, target)
	var before := JSON.stringify(Game._serialize(stock), "", false, true)
	var expected := Original._take_fit(baseline, tids, slot, opt)
	var actual := ArmsTrade._take_fit(candidate, tids, slot, opt)
	check(expected == explicit and actual == expected, label + " selected physical Item")
	check(baseline["armory_items"] == candidate["armory_items"], label + " remaining physical Items/order")
	check(JSON.stringify(Game._serialize(baseline), "", false, true) == JSON.stringify(Game._serialize(candidate), "", false, true), label + " complete town/ledger mutation")
	check(before == JSON.stringify(Game._serialize(stock), "", false, true), label + " item damage/material/quality/marks/history unchanged")

func _unit(fid: String, title: String) -> Unit:
	var u := Unit.create(String(DB.factions[fid].get("race", "human")), fid, false)
	u.title = title
	u.name = "equipment fixture"
	return u

func _all_loadouts() -> void:
	var troops := 0; var optional := 0; var cultures := {}
	for fid in DB.factions:
		for troop in DB.factions[fid].get("troops", []):
			var title := String(troop["name"])
			var lo := Original.troop_loadout(troop)
			if lo.is_empty(): continue
			troops += 1; cultures[String(DB.factions[fid].get("culture", ""))] = true
			for slot in lo:
				if bool(lo[slot]["opt"]): optional += 1
			for mode in ["empty", "exact", "foreign", "reserve", "shop", "shop_unfunded"]:
				for full in [false, true]:
					var town := _town([]); var serial := 0
					for slot in lo:
						var tids: Array = lo[slot]["tids"]
						var chosen_tid := String(tids[0])
						if mode == "foreign":
							var alts := _alternates(tids, slot, false)
							if not alts.is_empty(): chosen_tid = String(alts[0])
						for i in 3:
							var it := _item(chosen_tid, serial); serial += 1
							if mode in ["shop", "shop_unfunded"]: town["shop"].append(it)
							elif mode != "empty": town["armory_items"].append(it)
						if mode == "reserve": town["econ"]["arms_tgt"][Original.cls(String(tids[0]))] = 3
					if mode == "shop_unfunded": town["econ"]["treasury"] = 0.0
					var first := _unit(fid, title); var second := _unit(fid, "militia " + title)
					var already := _unit(fid, title)
					var keep_slot := String(lo.keys()[0])
					already.equip[keep_slot] = _item(String(lo[keep_slot]["tids"][0]), 7)
					var dead := _unit(fid, title); dead.dead = true
					_pair_units(fid + "/" + title + " " + mode + " full=" + str(full), town, [first, second, already, dead, null], true, full)
					# A second call is a new pass: a replenished stock must be searched anew.
					for slot in lo: town["armory_items"].append(_item(String(lo[slot]["tids"][0]), serial)); serial += 1
					_pair_units(fid + "/" + title + " replenished " + mode, town, [first, second], false, full)
	check(troops > 0 and optional > 0, "all troop cultures and optional loadouts represented")
	print("ARMY EQUIPMENT rekit troops=%d cultures=%d optional_slots=%d" % [troops, cultures.size(), optional])

func _pair_units(label: String, town: Dictionary, units: Array, use_shop: bool, full: bool) -> void:
	cases += 1
	var input := town.duplicate(true); var equips := []
	for u in units: equips.append(u.equip.duplicate() if u is Unit else {})
	var rng0 := Game.rng.state; var iid := Item._next_uid; var uid := Unit._next_uid
	var ledger0 := ArmsTrade.ledger.duplicate(true)
	Original.ledger = ledger0.duplicate(true)
	var miss_old := {}; var miss_new := {}
	var old_n := Original.rekit_units(Game, town, units, use_shop, miss_old, full)
	var expected := _local_view(town, units, miss_old, Original.ledger)
	var expected_equips := []
	for u in units: expected_equips.append(u.equip.duplicate() if u is Unit else {})
	town.clear(); town.merge(input.duplicate(true))
	for i in units.size():
		if units[i] is Unit: units[i].equip = equips[i].duplicate()
	ArmsTrade.ledger = ledger0.duplicate(true)
	var new_n := ArmsTrade.rekit_units(Game, town, units, use_shop, miss_new, full)
	check(new_n == old_n and _local_view(town, units, miss_new, ArmsTrade.ledger) == expected, label + " exact issued count, complete state/miss/ledger")
	for i in units.size():
		if units[i] is Unit: check(units[i].equip == expected_equips[i], label + " same physical equip references and slot insertion order")
	check(Game.rng.state == rng0 and Item._next_uid == iid and Unit._next_uid == uid, label + " no RNG or creation-counter change")
	ArmsTrade.ledger = ledger0

func _local_view(town: Dictionary, units: Array, miss: Dictionary, ledger: Dictionary) -> String:
	return JSON.stringify([Game._serialize(town), Game._serialize(units), miss, ledger], "", false, true)

func _collect_equips(value, rows: Array, seen: Dictionary) -> void:
	if value is Unit:
		var key: int = value.get_instance_id()
		if not seen.has(key): rows.append([value, value.equip.duplicate()]); seen[key] = true
	elif value is Dictionary:
		for v in value.values(): _collect_equips(v, rows, seen)
	elif value is Array:
		for v in value: _collect_equips(v, rows, seen)

func capture_world() -> Dictionary:
	var equips := []; _collect_equips(Game.world, equips, {})
	return {"world": Game.world.duplicate(true), "equips": equips, "rng": Game.rng.state,
		"unit_uid": Unit._next_uid, "item_uid": Item._next_uid, "ledger": ArmsTrade.ledger.duplicate(true),
		"lost": TownEcon.goods_lost.duplicate(true), "gone": TownEcon.gold_gone}

func restore_world(input: Dictionary) -> void:
	Game.world = input["world"].duplicate(true)
	for row in input["equips"]: row[0].equip = row[1].duplicate()
	Game.rng.state = input["rng"]; Unit._next_uid = input["unit_uid"]; Item._next_uid = input["item_uid"]
	ArmsTrade.ledger = input["ledger"].duplicate(true); Original.ledger = input["ledger"].duplicate(true)
	TownEcon.goods_lost = input["lost"].duplicate(true); TownEcon.gold_gone = input["gone"]

func world_view(ledger: Dictionary) -> String:
	return JSON.stringify([Game._serialize(Game.world), str(Game.rng.state), Unit._next_uid, Item._next_uid,
		ledger, TownEcon.goods_lost, TownEcon.gold_gone], "", false, true)

func _physical(value, out: Array) -> void:
	if value is Item: out.append(["item", value.get_instance_id()])
	elif value is Unit:
		out.append(["unit", value.get_instance_id(), value.equip.keys()])
		for it in value.equip.values(): _physical(it, out)
	elif value is Dictionary:
		out.append(["keys", value.keys()])
		for v in value.values(): _physical(v, out)
	elif value is Array:
		for v in value: _physical(v, out)

## Actual generated/saved town jobs, ordinary stock and existing missing slots.
## Timings surround only whole rekit_town calls; reconstruction and full comparison are outside.
func compare_real_jobs(label: String, repeats: int = 3) -> Dictionary:
	var jobs := []
	for fid in Game.world.get("factions", {}):
		var old_towns := Original.rekit_towns(Game, fid)
		check(old_towns == ArmsTrade.rekit_towns(Game, fid), label + " actual town job order " + fid)
		for tid in old_towns: jobs.append([fid, tid])
	check(not jobs.is_empty(), label + " actual field-town rekit jobs exist")
	var input := capture_world(); var initial := world_view(ArmsTrade.ledger)
	var expected := ""; var expected_physical := []; var timing := {"original": [], "candidate": []}
	var per_job := {"original": {}, "candidate": {}}
	var issued := 0; var pairs := []; var discarded_warmup := {}
	for lap in repeats + 1:
		var pair := {"lap": lap, "order": ["original", "candidate"] if lap % 2 == 0 else ["candidate", "original"]}
		for candidate in ([false, true] if lap % 2 == 0 else [true, false]):
			restore_world(input)
			check(world_view(ArmsTrade.ledger) == initial, label + " full initial reconstruction")
			var version := "candidate" if candidate else "original"
			var total_us := 0
			for job in jobs:
				var start := Time.get_ticks_usec()
				if candidate: ArmsTrade.rekit_town(Game, String(job[0]), String(job[1]))
				else: Original.rekit_town(Game, String(job[0]), String(job[1]))
				var elapsed := Time.get_ticks_usec() - start; total_us += elapsed
				var key := String(job[0]) + "/" + String(job[1])
				if lap > 0:
					if not per_job[version].has(key): per_job[version][key] = []
					per_job[version][key].append(elapsed)
			pair[version + "_us"] = total_us
			if lap > 0: timing[version].append(total_us)
			var ledger: Dictionary = ArmsTrade.ledger if candidate else Original.ledger
			var after := world_view(ledger); var physical := []; _physical(Game.world, physical)
			if expected.is_empty():
				expected = after; expected_physical = physical
				issued = int(ledger.get("rekit", 0)) - int(input["ledger"].get("rekit", 0))
			check(after == expected and physical == expected_physical, label + " actual jobs full state and every physical Item/Unit/order")
			check(Game.rng.state == input["rng"] and Item._next_uid == input["item_uid"] and Unit._next_uid == input["unit_uid"], label + " jobs preserve RNG and creation counters")
		if lap == 0: discarded_warmup = pair
		else: pairs.append(pair)
	var job_rows := []
	for key in per_job["original"]:
		var old: Array = per_job["original"][key]; var new: Array = per_job["candidate"][key]
		var old_stats := _time_stats(old); var new_stats := _time_stats(new)
		job_rows.append({"job": key, "original": old_stats, "candidate": new_stats,
			"median_delta_us": int(new_stats["median_us"]) - int(old_stats["median_us"])})
		print("ARMY EQUIPMENT JOB %s %s original_ms=%.3f candidate_ms=%.3f delta_ms=%.3f" % [label, key,
			float(old_stats["median_us"]) / 1000.0, float(new_stats["median_us"]) / 1000.0,
			float(int(new_stats["median_us"]) - int(old_stats["median_us"])) / 1000.0])
	var report := {"label": label, "day": Game.day, "jobs": jobs.size(), "issued": issued,
		"recorded_pairs": repeats, "discarded_warmup": discarded_warmup, "pairs": pairs,
		"original": _time_stats(timing["original"]), "candidate": _time_stats(timing["candidate"]),
		"per_job": job_rows, "output_sha256": expected.sha256_text(),
		"input_sha256": initial.sha256_text(), "rng_state": str(input["rng"]),
		"next_unit_uid": input["unit_uid"], "next_item_uid": input["item_uid"], "failures": fails}
	print("ARMY EQUIPMENT PAIRED %s jobs=%d issued=%d recorded_pairs=%d discarded_warmup=1 original_us=%s candidate_us=%s sha256=%s" % [label,
		jobs.size(), issued, repeats, str(timing["original"]), str(timing["candidate"]), expected.sha256_text()])
	restore_world(input)
	check(world_view(ArmsTrade.ledger) == initial, label + " complete state restored after all paired trials")
	return report

func _time_stats(raw: Array) -> Dictionary:
	var ordered := raw.duplicate(); ordered.sort()
	return {"raw_us": raw.duplicate(), "min_us": ordered[0], "median_us": ordered[ordered.size() / 2], "max_us": ordered[-1]}
