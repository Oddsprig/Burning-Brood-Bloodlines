extends RefCounted
## Supply --identity-save=<absolute copied save>. Uses the runner's isolated save.

func units(v: Variant, out: Dictionary) -> void:
	if v is Dictionary:
		if v.has("__unit"):
			var u: Dictionary = v["__unit"]
			if not u.get("dead", false):
				if not out.has(int(u["uid"])): out[int(u["uid"])] = []
				(out[int(u["uid"])] as Array).append(u)
			return
		for x in v.values(): units(x, out)
	elif v is Array:
		for x in v: units(x, out)

func items(v: Variant, out: Dictionary) -> void:
	if v is Dictionary:
		if v.has("__unit"):
			for it in v["__unit"].get("equip", {}).values(): record_item(it, out)
			return
		if v.has("__item"):
			record_item(v["__item"], out)
			return
		for x in v.values(): items(x, out)
	elif v is Array:
		for x in v: items(x, out)

func record_item(d: Dictionary, out: Dictionary) -> void:
	var it := Item.from_dict(d).to_dict()
	if not out.has(int(it["uid"])): out[int(it["uid"])] = []
	(out[int(it["uid"])] as Array).append(it)

func item_inventory(d: Dictionary) -> Dictionary:
	var out := {}
	items(d.get("world", {}), out)
	items(d.get("contract", {}), out)
	for u in d.get("company", []):
		for it in u.get("equip", {}).values(): record_item(it, out)
	for it in d.get("stash", []): record_item(it, out)
	return out

func goods(w: Dictionary) -> Dictionary:
	var out := {}
	for t in w.get("towns", {}).values():
		for field in ["stock", "barn", "hh", "armory", "gh"]:
			for good in t.get("econ", {}).get(field, {}):
				var key: String = String(field) + "/" + String(good)
				out[key] = float(out.get(key, 0)) + float(t["econ"][field][good])
		out["granary/grain"] = float(out.get("granary/grain", 0)) + float(t.get("econ", {}).get("granary", 0))
	return out

## JSON restores integer counters as floats. Compare numeric values exactly,
## while recursively retaining every history entry, key, creditor and amount.
func exact_facts(a: Variant, b: Variant) -> bool:
	if typeof(a) in [TYPE_INT, TYPE_FLOAT] and typeof(b) in [TYPE_INT, TYPE_FLOAT]: return float(a) == float(b)
	if a is Dictionary and b is Dictionary:
		if a.size() != b.size(): return false
		for key in a:
			if not b.has(key) or not exact_facts(a[key], b[key]): return false
		return true
	if a is Array and b is Array:
		if a.size() != b.size(): return false
		for i in a.size():
			if not exact_facts(a[i], b[i]): return false
		return true
	return a == b

func fact_changes(a: Dictionary, b: Dictionary, samples: Array, counts: Dictionary, exact_values: bool) -> int:
	var n := 0
	for tid in a["world"]["towns"]:
		var e: Dictionary = a["world"]["towns"][tid]["econ"]
		var f: Dictionary = b["world"]["towns"][tid]["econ"]
		var same: bool = exact_facts(e.get("census"), f.get("census")) if exact_values else e.get("census") == f.get("census")
		if not same:
			n += 1
			counts["census"] = int(counts.get("census", 0)) + 1
			if samples.size() < 5: samples.append([tid, "census"])
		for i in (e.get("biz", []) as Array).size():
			for key in ["wage_claims", "owed", "owed_unattributed"]:
				var x: Variant = e["biz"][i].get(key)
				var y: Variant = f["biz"][i].get(key)
				same = exact_facts(x, y) if exact_values else x == y
				if not same:
					n += 1
					counts[key] = int(counts.get(key, 0)) + 1
					if samples.size() < 5: samples.append([tid, i, key, x, y])
	return n

func cash(d: Dictionary) -> float:
	var w: Dictionary = d["world"]
	var n := 0.0
	for t in w.get("towns", {}).values():
		var e: Dictionary = t.get("econ", {})
		n += float(e.get("treasury", 0)) + float(e.get("farm_till", 0))
		for f in e.get("fams", []): n += float(f.get("purse", 0))
		for b in e.get("biz", []): n += float(b.get("till", 0))
	for f in w.get("factions", {}).values(): n += float(f.get("treasury", 0)) + float(f.get("loot", 0))
	for l in w.get("lairs", {}).values(): n += float(l.get("gold", 0))
	for b in w.get("warbands", {}).values(): n += float(b.get("gold", 0))
	return n + float(d.get("gold", 0))

func cash_owners(d: Dictionary) -> Dictionary:
	var w: Dictionary = d["world"]
	var out := {}
	for tid in w.get("towns", {}):
		var e: Dictionary = w["towns"][tid].get("econ", {})
		out[String(tid) + "/treasury"] = e.get("treasury", 0)
		out[String(tid) + "/farm_till"] = e.get("farm_till", 0)
		for f in e.get("fams", []): out[String(tid) + "/family/" + str(int(f["id"]))] = f.get("purse", 0)
		for i in (e.get("biz", []) as Array).size(): out[String(tid) + "/business/" + str(i)] = e["biz"][i].get("till", 0)
	for fid in w.get("factions", {}):
		for field in ["treasury", "loot"]: out["faction/" + String(fid) + "/" + String(field)] = w["factions"][fid].get(field, 0)
	for lid in w.get("lairs", {}): out["lair/" + String(lid)] = w["lairs"][lid].get("gold", 0)
	for wid in w.get("warbands", {}): out["force/" + String(wid)] = w["warbands"][wid].get("gold", 0)
	out["company"] = d.get("gold", 0)
	return out

func same_cash_owners(a: Dictionary, b: Dictionary) -> bool:
	# A new empty militia band may add a zero-balance slot. Every actual amount
	# still matches its same owner exactly; missing nonzero balances always fail.
	for key in a:
		if not exact_facts(a[key], b.get(key, 0)): return false
	for key in b:
		if not a.has(key) and not exact_facts(0, b[key]): return false
	return true

func people(w: Dictionary) -> int:
	var n := 0
	for t in w.get("towns", {}).values(): n += Census.people(t["econ"])
	return n

func run(_tree: SceneTree) -> int:
	var path := OS.get_environment("IDENTITY_SAVE")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--identity-save="): path = arg.substr(16)
	if path == "" or not FileAccess.file_exists(path):
		printerr("identity diagnostic requires --identity-save=<absolute copied save>")
		return 1
	var raw := FileAccess.get_file_as_string(path)
	var before: Dictionary = JSON.parse_string(raw)
	var expected_path := OS.get_environment("IDENTITY_EXPECTED")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--identity-expected="): expected_path = arg.substr(20)
	var expected := {}
	if expected_path != "":
		if not FileAccess.file_exists(expected_path): return 1
		expected = JSON.parse_string(FileAccess.get_file_as_string(expected_path))
		if expected.get("seed") != before.get("seed") or expected.get("day") != before.get("day"):
			printerr("normalized baseline must describe the same seed and save day")
			return 1
	var before_units := {}
	units(before, before_units)
	# Top-level company Units do not use the world type tag.
	for u in before.get("company", []):
		if not u.get("dead", false): before_units[int(u["uid"])] = [u]
	var before_items := item_inventory(before)
	var file := FileAccess.open(Game.SAVE_PATH, FileAccess.WRITE)
	file.store_string(raw); file.close()
	if not Game.load_game(): return 1
	var report := ServiceIdentity.last_report.duplicate(true)
	var after := Game._save_tree()
	var after_units := {}
	units(after, after_units)
	for u in after.get("company", []):
		if not u.get("dead", false): after_units[int(u["uid"])] = [u]
	var changed := []
	for uid in before_units:
		if not after_units.has(uid) or (before_units[uid] as Array).size() != 1 or (after_units[uid] as Array).size() != 1:
			changed.append([uid, "missing/duplicate"])
			continue
		# Apply the unchanged current Unit.from_dict normalization on both sides
		# (for example legacy blank drink preferences), then compare every field.
		var a := Unit.from_dict(before_units[uid][0]).to_dict()
		var b := Unit.from_dict(after_units[uid][0]).to_dict()
		a.erase("home_town"); a.erase("family")
		b.erase("home_town"); b.erase("family")
		if a != b:
			var fields := []
			for key in a:
				if a.get(key) != b.get(key): fields.append(key)
			changed.append([uid, fields])
	var item_equal := before_items == item_inventory(after)
	var goods_equal := goods(before["world"]) == goods(after["world"])
	var misses := []
	for tid in Game.world.get("militia", {}):
		var town: Dictionary = Game.world["towns"][tid]
		var on := {}
		for u in Militia.units_of(Game, tid):
			on[u.uid] = u
			var f := People.fam_of(town, u.family)
			var p := Persons.by_uid(f, u.uid)
			if f.is_empty() or f.get("gone", false) or u.home_town != tid or p.is_empty() or String(p[4]) not in ["reserve", "militia"]: misses.append([tid, u.uid, "forward"])
		for f in town["econ"]["fams"]:
			if f.get("gone", false): continue
			for p in f.get("pp", []):
				if String(p[4]) not in ["reserve", "militia"]: continue
				var u: Unit = on.get(int(p[5]))
				if u == null or u.family != int(f["id"]) or u.home_town != tid: misses.append([tid, p[5], "reverse"])
	var cash_delta := cash(after) - cash(before)
	# The baseline snapshot has been serialized and parsed. Use the same full-
	# precision representation on this side; keep raw double differences visible.
	var serialized_after: Dictionary = JSON.parse_string(JSON.stringify(after, "", true, true))
	var expected_cash := cash_owners(expected if not expected.is_empty() else before)
	var raw_cash := cash_owners(after)
	var cash_samples := []
	var cash_raw_changes := 0
	for owner in expected_cash:
		if not exact_facts(expected_cash[owner], raw_cash.get(owner, 0)):
			cash_raw_changes += 1
			if cash_samples.size() < 8: cash_samples.append([owner, expected_cash[owner], raw_cash.get(owner, 0)])
	var cash_equal := same_cash_owners(expected_cash, cash_owners(serialized_after if not expected.is_empty() else after))
	var people_delta := people(after["world"]) - people(before["world"])
	var raw_samples := []
	var raw_counts := {}
	var raw_changed := fact_changes(before, after, raw_samples, raw_counts, false)
	var expected_samples := []
	var expected_counts := {}
	var facts_changed := raw_changed
	if not expected.is_empty():
		# The supplied v0.034 baseline is a saved snapshot of its ordinary load.
		# Compare the same serialized representation, not different float printers.
		facts_changed = fact_changes(expected, serialized_after, expected_samples, expected_counts, true)
	ServiceIdentity.after_load(Game)
	var idempotent := Game._save_tree() == after
	print(JSON.stringify({"repair": report, "living_units_before": before_units.size(), "living_units_after": after_units.size(), "unit_changes": changed.size(), "unit_change_sample": changed.slice(0, 5), "items_exact": item_equal, "goods_exact": goods_equal, "cash_delta": cash_delta, "cash_owners_exact": cash_equal, "cash_raw_owner_changes": cash_raw_changes, "cash_raw_owner_samples": cash_samples, "people_delta": people_delta, "raw_census_or_wage_changes": raw_changed, "raw_changes_by_field": raw_counts, "raw_change_sample": raw_samples, "census_or_wage_changes": facts_changed, "normalized_baseline": expected_path, "baseline_change_sample": expected_samples, "roster_misses": misses.size(), "roster_miss_sample": misses.slice(0, 5), "idempotent": idempotent}, "", true, true))
	return 0 if before_units.size() == after_units.size() and changed.is_empty() and item_equal and goods_equal and cash_equal and people_delta == 0 and facts_changed == 0 and misses.is_empty() and idempotent else 1
