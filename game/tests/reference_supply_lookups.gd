extends RefCounted
## Frozen v0.033 supply selector and redistribution body; only unchanged helper calls are qualified.
## Do not replace this oracle with the optimized function. The counted copy is never timed.

static func _supply_destination(w: Dictionary, rows: Dictionary, ids: Array, source_id: String, role_name: String) -> String:
	var source: Dictionary = w["towns"][source_id]
	var best := ""; var score := 0.0
	for tid in ids:
		if tid == source_id or not rows.has(tid): continue
		var town: Dictionary = w["towns"][tid]
		if String(source.get("faction", "")) == "" or town.get("faction", "") != source["faction"]: continue
		var row: Dictionary = rows[tid]
		var target := int(row["target"].get(role_name, 0))
		var shortage := target - int(row["have"].get(role_name, 0))
		if shortage <= 0: continue
		var ratio := float(shortage) / float(maxi(1, target))
		if ratio > score:
			best = String(tid); score = ratio
	return best

static func redistribute(game, checkpoint: int) -> int:
	var w: Dictionary = game.world
	var st: Dictionary = w.get("arms", {})
	if st.is_empty(): w["arms"] = ArmsTrade.new_state(); st = w["arms"]
	if checkpoint % ArmsTrade.SUPPLY_EVERY != 0 or checkpoint <= int(st.get("supply_day", -1)): return 0
	var ids: Array = w["towns"].keys(); ids.sort()
	var rows := {}; var moved := 0
	for tid in ids:
		var town: Dictionary = w["towns"][tid]
		if not TownEcon.has_econ(town): continue
		ArmsTrade.refresh_reserve(game, town)
		var have := ArmsTrade.role_counts(town["econ"]["arms_have"])
		var target := ArmsTrade.role_counts(town["econ"]["arms_tgt"])
		have["arrows"] = ArmsTrade.arrow_stock(town)
		target["arrows"] = int(town["econ"]["arrow_reserve"])
		rows[tid] = {"have": have, "target": target}
	for source_id in ids:
		if not rows.has(source_id): continue
		var source: Dictionary = w["towns"][source_id]
		var row: Dictionary = rows[source_id]
		var arm := ArmsTrade.armory(source)
		var routes := {}
		for i in range(arm.size() - 1, -1, -1):
			var it: Item = arm[i]
			var c := ArmsTrade.cls(it.tid)
			if c == "": continue
			var r := ArmsTrade.cls_role(c)
			if int(row["have"].get(r, 0)) <= int(row["target"].get(r, 0)): continue
			var dest_id := _supply_destination(w, rows, ids, String(source_id), r)
			if dest_id == "": continue
			var dest: Dictionary = w["towns"][dest_id]
			arm.remove_at(i); ArmsTrade.armory(dest).append(it)
			row["have"][r] = int(row["have"][r]) - 1
			rows[dest_id]["have"][r] = int(rows[dest_id]["have"].get(r, 0)) + 1
			routes[dest_id] = int(routes.get(dest_id, 0)) + 1
			Legends.note(it, float(game.day), "Transferred internally from %s to our faction's garrison at %s." % [source["name"], dest["name"]])
			moved += 1
		for dest_id in routes: ArmsTrade._supply_note(source, w["towns"][dest_id], "arms", int(routes[dest_id]))
		# Arrow types remain real counted goods; distribute in type-preserving batches.
		var arrows: Dictionary = source["econ"].get("armory", {})
		var kinds: Array = DB.arrows.keys(); kinds.sort()
		for k in kinds:
			while int(arrows.get(k, 0)) > 0 and int(row["have"]["arrows"]) > int(row["target"]["arrows"]):
				var dest_id := _supply_destination(w, rows, ids, String(source_id), "arrows")
				if dest_id == "": break
				var dest: Dictionary = w["towns"][dest_id]
				var dr: Dictionary = rows[dest_id]
				var n := mini(int(arrows[k]), mini(int(row["have"]["arrows"]) - int(row["target"]["arrows"]), int(dr["target"]["arrows"]) - int(dr["have"]["arrows"])))
				if not dest["econ"].has("armory"): dest["econ"]["armory"] = {}
				var da: Dictionary = dest["econ"]["armory"]
				arrows[k] = int(arrows[k]) - n; da[k] = int(da.get(k, 0)) + n
				row["have"]["arrows"] = int(row["have"]["arrows"]) - n; dr["have"]["arrows"] = int(dr["have"]["arrows"]) + n
				# Stored arrows already left the market/household commodity ledger
				# when bought. Reserve-to-reserve transfer is neither further use
				# nor production; record it in the physical supply movement book.
				for pair in [[source, "out"], [dest, "in"]]:
					var e: Dictionary = pair[0]["econ"]
					if not e.has("supply_ledger"): e["supply_ledger"] = {"in": {}, "out": {}}
					var book: Dictionary = e["supply_ledger"][pair[1]]
					book[k] = int(book.get(k, 0)) + n
				ArmsTrade._supply_note(source, dest, "arrows", n); moved += n
	for tid in rows: ArmsTrade.refresh_reserve(game, w["towns"][tid])
	st["supply_day"] = checkpoint
	st["supply_moved"] = int(st.get("supply_moved", 0)) + moved
	return moved


static var work: Dictionary = {}
static var shortlists: Dictionary = {}

static func _counted_destination(w: Dictionary, rows: Dictionary, ids: Array, source_id: String, role_name: String) -> String:
	work["queries"] = int(work.get("queries", 0)) + 1
	work["full_id_visits"] = int(work.get("full_id_visits", 0)) + ids.size()
	var roles: Dictionary = shortlists.get(w["towns"][source_id].get("faction", ""), {})
	work["shortlist_id_visits"] = int(work.get("shortlist_id_visits", 0)) + (roles.get(role_name, []) as Array).size()
	return _supply_destination(w, rows, ids, source_id, role_name)

static func redistribute_counted(game, checkpoint: int) -> int:
	var w: Dictionary = game.world
	var st: Dictionary = w.get("arms", {})
	if st.is_empty(): w["arms"] = ArmsTrade.new_state(); st = w["arms"]
	if checkpoint % ArmsTrade.SUPPLY_EVERY != 0 or checkpoint <= int(st.get("supply_day", -1)): return 0
	var ids: Array = w["towns"].keys(); ids.sort()
	var rows := {}; var moved := 0
	for tid in ids:
		var town: Dictionary = w["towns"][tid]
		if not TownEcon.has_econ(town): continue
		ArmsTrade.refresh_reserve(game, town)
		var have := ArmsTrade.role_counts(town["econ"]["arms_have"])
		var target := ArmsTrade.role_counts(town["econ"]["arms_tgt"])
		have["arrows"] = ArmsTrade.arrow_stock(town)
		target["arrows"] = int(town["econ"]["arrow_reserve"])
		rows[tid] = {"have": have, "target": target}
	for source_id in ids:
		if not rows.has(source_id): continue
		var source: Dictionary = w["towns"][source_id]
		var row: Dictionary = rows[source_id]
		var arm := ArmsTrade.armory(source)
		var routes := {}
		for i in range(arm.size() - 1, -1, -1):
			var it: Item = arm[i]
			var c := ArmsTrade.cls(it.tid)
			if c == "": continue
			var r := ArmsTrade.cls_role(c)
			if int(row["have"].get(r, 0)) <= int(row["target"].get(r, 0)): continue
			var dest_id := _counted_destination(w, rows, ids, String(source_id), r)
			if dest_id == "": continue
			var dest: Dictionary = w["towns"][dest_id]
			arm.remove_at(i); ArmsTrade.armory(dest).append(it)
			row["have"][r] = int(row["have"][r]) - 1
			rows[dest_id]["have"][r] = int(rows[dest_id]["have"].get(r, 0)) + 1
			routes[dest_id] = int(routes.get(dest_id, 0)) + 1
			Legends.note(it, float(game.day), "Transferred internally from %s to our faction's garrison at %s." % [source["name"], dest["name"]])
			moved += 1
		for dest_id in routes: ArmsTrade._supply_note(source, w["towns"][dest_id], "arms", int(routes[dest_id]))
		# Arrow types remain real counted goods; distribute in type-preserving batches.
		var arrows: Dictionary = source["econ"].get("armory", {})
		var kinds: Array = DB.arrows.keys(); kinds.sort()
		for k in kinds:
			while int(arrows.get(k, 0)) > 0 and int(row["have"]["arrows"]) > int(row["target"]["arrows"]):
				var dest_id := _counted_destination(w, rows, ids, String(source_id), "arrows")
				if dest_id == "": break
				var dest: Dictionary = w["towns"][dest_id]
				var dr: Dictionary = rows[dest_id]
				var n := mini(int(arrows[k]), mini(int(row["have"]["arrows"]) - int(row["target"]["arrows"]), int(dr["target"]["arrows"]) - int(dr["have"]["arrows"])))
				if not dest["econ"].has("armory"): dest["econ"]["armory"] = {}
				var da: Dictionary = dest["econ"]["armory"]
				arrows[k] = int(arrows[k]) - n; da[k] = int(da.get(k, 0)) + n
				row["have"]["arrows"] = int(row["have"]["arrows"]) - n; dr["have"]["arrows"] = int(dr["have"]["arrows"]) + n
				# Stored arrows already left the market/household commodity ledger
				# when bought. Reserve-to-reserve transfer is neither further use
				# nor production; record it in the physical supply movement book.
				for pair in [[source, "out"], [dest, "in"]]:
					var e: Dictionary = pair[0]["econ"]
					if not e.has("supply_ledger"): e["supply_ledger"] = {"in": {}, "out": {}}
					var book: Dictionary = e["supply_ledger"][pair[1]]
					book[k] = int(book.get(k, 0)) + n
				ArmsTrade._supply_note(source, dest, "arrows", n); moved += n
	for tid in rows: ArmsTrade.refresh_reserve(game, w["towns"][tid])
	st["supply_day"] = checkpoint
	st["supply_moved"] = int(st.get("supply_moved", 0)) + moved
	return moved
