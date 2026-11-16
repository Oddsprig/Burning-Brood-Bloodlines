class_name ArmyDayJob
extends "res://campaign/campaign_checkpoint_job.gd"
## Shared transaction owner, save barrier and pre-start slice admission.
## Atomic Army/ArmsSalvage entry points remain the independent reference.
var day: int = 0
var _header: Array = []
var _s: Dictionary = {"stage": "open", "i": 0}

func _init(game: Variant, header: Array) -> void:
	day = int(header[1]) if header[0] in ["army_misc", "arms_supply", "army_sweep"] else int(game.day)
	_header = header.duplicate()
	if header[0] in ["army", "army_tree"]:
		day = int(header[2])

func _run(game: Variant) -> void:
	while not await _part(game):
		await _checkpoint(String(_header[0]) + "/" + String(_s["stage"]))
	_finished = true
	_checkpoint_game = null

func _part(game: Variant) -> bool:
	match String(_header[0]):
		"arms_supply": return await _supply_part(game)
		"army_misc": return await _misc_part(game)
		"army_sweep": return await _sweep_part(game)
		"army": return await _army_part(game)
		"army_pay": return await _pay_part(game)
		"army_tree": return await _tree_part(game)
	return true

func _supply_part(game: Variant) -> bool:
	var w: Dictionary = game.world
	match String(_s["stage"]):
		"open":
			var st: Dictionary = w.get("arms", {})
			if st.is_empty():
				w["arms"] = ArmsTrade.new_state()
				st = w["arms"]
			if day % ArmsSalvage.SUPPLY_EVERY != 0 or day <= int(st.get("supply_day", -1)):
				return true
			var ids: Array = w["towns"].keys()
			ids.sort()
			_s.merge({"st": st, "ids": ids, "rows": {}, "moved": 0, "stage": "reserve"}, true)
		"reserve":
			var ids: Array = _s["ids"]
			var i: int = int(_s["i"])
			if i >= ids.size():
				_s["shortlists"] = ArmsSalvage._supply_shortlists(w, _s["rows"], ids)
				_s["i"] = 0
				_s["stage"] = "source"
			else:
				_s["i"] = i + 1
				var tid: Variant = ids[i]
				var town: Dictionary = w["towns"][tid]
				if TownEcon.has_econ(town):
					ArmsTrade.refresh_reserve(game, town)
					var have: Dictionary = ArmsTrade.role_counts(town["econ"]["arms_have"])
					var target: Dictionary = ArmsTrade.role_counts(town["econ"]["arms_tgt"])
					have["arrows"] = ArmsTrade.arrow_stock(town)
					target["arrows"] = int(town["econ"]["arrow_reserve"])
					_s["rows"][tid] = {"have": have, "target": target}
		"source":
			var ids: Array = _s["ids"]
			var i: int = int(_s["i"])
			if i >= ids.size():
				_s["final_ids"] = _s["rows"].keys()
				_s["i"] = 0
				_s["stage"] = "final"
			else:
				_s["i"] = i + 1
				var sid: Variant = ids[i]
				if _s["rows"].has(sid):
					var source: Dictionary = w["towns"][sid]
					var arm: Array = ArmsTrade.armory(source)
					_s.merge({"source": source, "sid": sid, "row": _s["rows"][sid],
						"candidates": _s["shortlists"].get(source.get("faction", ""), {}),
						"arm": arm, "j": arm.size() - 1, "routes": {}, "stage": "item"}, true)
		"item":
			var i: int = int(_s["j"])
			if i < 0:
				_s["route_ids"] = _s["routes"].keys()
				_s["j"] = 0
				_s["stage"] = "notes"
			else:
				_s["j"] = i - 1
				var it: Item = _s["arm"][i]
				var c: String = ArmsTrade.cls(it.tid)
				if c == "": return false
				var r: String = ArmsTrade.cls_role(c)
				var row: Dictionary = _s["row"]
				if int(row["have"].get(r, 0)) <= int(row["target"].get(r, 0)): return false
				var did: String = ArmsSalvage._supply_destination(w, _s["rows"], _s["candidates"].get(r, []), String(_s["sid"]), r)
				if did == "": return false
				var dest: Dictionary = w["towns"][did]
				(_s["arm"] as Array).remove_at(i)
				ArmsTrade.armory(dest).append(it)
				row["have"][r] = int(row["have"][r]) - 1
				_s["rows"][did]["have"][r] = int(_s["rows"][did]["have"].get(r, 0)) + 1
				_s["routes"][did] = int(_s["routes"].get(did, 0)) + 1
				Legends.note(it, float(game.day), "Transferred internally from %s to our faction's garrison at %s." % [_s["source"]["name"], dest["name"]])
				_s["moved"] = int(_s["moved"]) + 1
		"notes":
			var ids: Array = _s["route_ids"]
			var i: int = int(_s["j"])
			if i < ids.size():
				_s["j"] = i + 1
				ArmsSalvage._supply_note(_s["source"], w["towns"][ids[i]], "arms", int(_s["routes"][ids[i]]))
			else:
				var kinds: Array = DB.arrows.keys()
				kinds.sort()
				_s["kinds"] = kinds
				_s["arrows"] = _s["source"]["econ"].get("armory", {})
				_s["j"] = 0
				_s["stage"] = "arrow"
		"arrow":
			var kinds: Array = _s["kinds"]
			var i: int = int(_s["j"])
			if i >= kinds.size():
				_s["stage"] = "source"
			else:
				var k: Variant = kinds[i]
				var arrows: Dictionary = _s["arrows"]
				var row: Dictionary = _s["row"]
				if int(arrows.get(k, 0)) <= 0 or int(row["have"]["arrows"]) <= int(row["target"]["arrows"]):
					_s["j"] = i + 1
					return false
				var did: String = ArmsSalvage._supply_destination(w, _s["rows"], _s["candidates"].get("arrows", []), String(_s["sid"]), "arrows")
				if did == "":
					_s["j"] = i + 1
					return false
				var source: Dictionary = _s["source"]
				var dest: Dictionary = w["towns"][did]
				var dr: Dictionary = _s["rows"][did]
				var n: int = mini(int(arrows[k]), mini(int(row["have"]["arrows"]) - int(row["target"]["arrows"]), int(dr["target"]["arrows"]) - int(dr["have"]["arrows"])))
				if not dest["econ"].has("armory"): dest["econ"]["armory"] = {}
				var da: Dictionary = dest["econ"]["armory"]
				arrows[k] = int(arrows[k]) - n
				da[k] = int(da.get(k, 0)) + n
				row["have"]["arrows"] = int(row["have"]["arrows"]) - n
				dr["have"]["arrows"] = int(dr["have"]["arrows"]) + n
				for pair: Array in [[source, "out"], [dest, "in"]]:
					await _checkpoint("army:loop")
					var e: Dictionary = pair[0]["econ"]
					if not e.has("supply_ledger"): e["supply_ledger"] = {"in": {}, "out": {}}
					var book: Dictionary = e["supply_ledger"][pair[1]]
					book[k] = int(book.get(k, 0)) + n
				ArmsSalvage._supply_note(source, dest, "arrows", n)
				_s["moved"] = int(_s["moved"]) + n
		"final":
			var ids: Array = _s["final_ids"]
			var i: int = int(_s["i"])
			if i < ids.size():
				_s["i"] = i + 1
				ArmsTrade.refresh_reserve(game, w["towns"][ids[i]])
			else:
				var st: Dictionary = _s["st"]
				st["supply_day"] = day
				st["supply_moved"] = int(st.get("supply_moved", 0)) + int(_s["moved"])
				return true
	return false

func _army_part(game: Variant) -> bool:
	var w: Dictionary = game.world
	var fid: String = String(_header[1])
	match String(_s["stage"]):
		"open":
			_s["r"] = Army.rec(w, fid)
			_s["units"] = Army.members(game, fid)
			_s["cul"] = Army.cul_of_faction(fid)
			_s["stage"] = "sort"
		"sort":
			var units: Array = _s["units"]
			if not units.is_empty(): ArmsPool.day(game, fid, true)
			var order: Array = units.duplicate()
			order.sort_custom(func(a: Unit, b: Unit) -> bool: return a.rank > b.rank if a.rank != b.rank else a.uid < b.uid)
			_s["order"] = order
			var fac: Dictionary = w["factions"].get(fid, {})
			if not fac.has("treasury"): fac["treasury"] = 0.0
			_s["stage"] = "queue"
		"queue":
			var r: Dictionary = _s["r"]
			var order: Array = _s["order"]
			r["pay_queue"] = order.map(func(u: Unit) -> int: return u.uid)
			r["bill"] = 0.0
			r["paid"] = 0.0
			r["unpaid_n"] = 0
			r["pay_lo"] = Army.low_officer(order, "army")
			r["pay_day"] = day
			_s["front"] = []
			if order.is_empty(): (_s["front"] as Array).append(["army_pay", fid, 0])
			for start: int in range(0, order.size(), 400):
				await _checkpoint("army:loop")
				(_s["front"] as Array).append(["army_pay", fid, start])
			_s["stage"] = "rekit"
		"rekit":
			var front: Array = _s["front"]
			for tid: Variant in ArmsTrade.rekit_towns(game, fid):
				await _checkpoint("army:loop")
				front.append(["army_rk", fid, tid])
			front.append(["army_tree", fid, day])
			var work: Array = w["work"]
			# Publish generated headers together only at this logical completion.
			for i: int in range(front.size() - 1, -1, -1):
				work.push_front(front[i])
			return true
	return false

func _pay_part(game: Variant) -> bool:
	var w: Dictionary = game.world
	var fid: String = String(_header[1])
	var start: int = int(_header[2])
	match String(_s["stage"]):
		"open":
			var r: Dictionary = Army.rec(w, fid)
			_s["r"] = r
			_s["queue"] = r.get("pay_queue", [])
			_s["cul"] = Army.cul_of_faction(fid)
			var fac: Dictionary = w["factions"].get(fid, {})
			if not fac.has("treasury"): fac["treasury"] = 0.0
			_s.merge({"fac": fac, "members": Army.members(game, fid), "by": {}, "stage": "index"}, true)
		"index":
			var units: Array = _s["members"]
			var i: int = int(_s["i"])
			if i < units.size():
				var u: Unit = units[i]
				_s["by"][int(u.uid)] = u
				_s["i"] = i + 1
			else:
				_s.merge({"i": start, "chunk": [], "stage": "chunk"}, true)
		"chunk":
			var queue: Array = _s["queue"]
			var i: int = int(_s["i"])
			if i < mini(start + 400, queue.size()):
				var u: Unit = _s["by"].get(int(queue[i]), null)
				if u != null and not u.dead: (_s["chunk"] as Array).append(u)
				_s["i"] = i + 1
			else:
				Army.sign_on(game, fid, [], _s["fac"])
				_s["i"] = 0
				_s["stage"] = "sign"
		"sign":
			var chunk: Array = _s["chunk"]
			var i: int = int(_s["i"])
			if i < chunk.size():
				Army.sign_on(game, fid, [chunk[i]], _s["fac"])
				_s["i"] = i + 1
			else:
				var stored_lo: int = int(_s["r"].get("pay_lo", -2))
				_s["pay_lo"] = stored_lo if stored_lo >= -1 else Army.low_officer(chunk, "army")
				_s.merge({"i": 0, "bill": 0.0, "paid": 0.0, "unpaid": 0, "stage": "pay"}, true)
		"pay":
			var chunk: Array = _s["chunk"]
			var i: int = int(_s["i"])
			if i < chunk.size():
				var res: Dictionary = Army.pay_units(game, [chunk[i]], {"kind": "faction", "fac": _s["fac"]}, "army", _s["cul"], int(_s["pay_lo"]))
				_s["bill"] = float(_s["bill"]) + float(res["bill"])
				_s["paid"] = float(_s["paid"]) + float(res["paid"])
				_s["unpaid"] = int(_s["unpaid"]) + int(res["unpaid"])
				_s["i"] = i + 1
			else:
				var r: Dictionary = _s["r"]
				r["bill"] = float(r.get("bill", 0.0)) + float(_s["bill"])
				r["paid"] = float(r.get("paid", 0.0)) + float(_s["paid"])
				r["unpaid_n"] = int(r.get("unpaid_n", 0)) + int(_s["unpaid"])
				if start + 400 < (_s["queue"] as Array).size(): return true
				_s["ids"] = w["warbands"].keys()
				_s["i"] = 0
				_s["stage"] = "unpaid"
		"unpaid":
			var ids: Array = _s["ids"]
			var i: int = int(_s["i"])
			if i < ids.size():
				_s["i"] = i + 1
				var wb: Dictionary = w["warbands"][ids[i]]
				if wb["faction"] == fid and Army.is_field(wb):
					var n: int = 0
					for u: Unit in wb["units"]:
						await _checkpoint("army:loop")
						if not u.dead and u.unpaid_days > 0: n += 1
					wb["unpaid_n"] = n
			else:
				_s["ids"] = w["warbands"].keys()
				_s["i"] = 0
				_s["stage"] = "supplies"
		"supplies":
			var ids: Array = _s["ids"]
			var i: int = int(_s["i"])
			if i < ids.size():
				_s["i"] = i + 1
				var wb: Dictionary = w["warbands"][ids[i]]
				if wb["faction"] == fid and Army.is_field(wb):
					Supplies.eat(wb)
					Supplies.provision(game, wb, {"kind": "faction", "fac": _s["fac"]}, int(_s["r"].get("pay_day", game.day)))
			else:
				_s.merge({"ids": w["warbands"].keys(), "i": 0, "deserted": 0, "dd": int(Army.A()["desert_days"]), "stage": "desert"}, true)
		"desert":
			var ids: Array = _s["ids"]
			var i: int = int(_s["i"])
			if i >= ids.size():
				if int(_s["deserted"]) > 0: Army._hist(game, fid, "%d unpaid soldiers walked home." % int(_s["deserted"]))
				(_s["r"] as Dictionary).erase("pay_queue")
				return true
			_s["i"] = i + 1
			var wb: Dictionary = w["warbands"].get(ids[i], {})
			if wb.is_empty() or wb["faction"] != fid or not Army.is_field(wb): return false
			var gone: Array = []
			for u: Unit in wb["units"]:
				await _checkpoint("army:loop")
				if not u.dead and u.unpaid_days >= int(_s["dd"]): gone.append(u)
			_s.merge({"wb": wb, "wid": ids[i], "gone": gone, "j": 0, "stage": "release"}, true)
		"release":
			var gone: Array = _s["gone"]
			var i: int = int(_s["j"])
			var wb: Dictionary = _s["wb"]
			if i < gone.size():
				var u: Unit = gone[i]
				(wb["units"] as Array).erase(u)
				Army.release(game, u, "deserted", Army.force_word(w, wb))
				_s["deserted"] = int(_s["deserted"]) + 1
				_s["j"] = i + 1
			else:
				if (wb["units"] as Array).is_empty(): CampaignWorld.remove_warband(game, _s["wid"])
				_s["stage"] = "desert"
	return false

func _sweep_part(game: Variant) -> bool:
	var w: Dictionary = game.world
	var here: Dictionary = {}
	_s["stage"] = "sweep_units"
	for wid: Variant in w.get("warbands", {}):
		for unit: Unit in w["warbands"][wid]["units"]:
			await _checkpoint("army_sweep/units")
			if not unit.dead:
				here[str(unit.uid)] = true
			else:
				Horses.return_mount(game, unit)
	_s["stage"] = "sweep_mustering"
	for unit: Unit in CampaignWorld.mustering_units(w):
		await _checkpoint("army_sweep/mustering")
		here[str(unit.uid)] = true
	_s["stage"] = "sweep_prisoners"
	for unit: Unit in Prisoners.units(game):
		await _checkpoint("army_sweep/prisoners")
		here[str(unit.uid)] = true
	var roll: Dictionary = Army.state(w)["roll"]
	var ids: Array = roll.keys()
	var at: int = 0
	_s["stage"] = "sweep_roll"
	while at < ids.size():
		at = Army.sweep_roll_chunk(game, roll, ids, here, at, 1000 if budgeted else 0)
		# The native TownSweep scope has already been restored before suspension.
		await _checkpoint("army_sweep/roll")
	return true

func _misc_part(game: Variant) -> bool:
	match String(_s["stage"]):
		"open":
			_s["lids"] = game.world.get("lairs", {}).keys()
			_s["stage"] = "camp"
		"camp":
			var ids: Array = _s["lids"]
			var i: int = int(_s["i"])
			if i < ids.size():
				_s["i"] = i + 1
				await _camp_day(game, ids[i])
			else:
				Bandits.deserters_day(game, day)
				_s["stage"] = "company"
		"company":
			await _army_company_desertion(game)
			return true
	return false

func _tree_part(game: Variant) -> bool:
	var w: Dictionary = game.world
	var fid: String = String(_header[1])
	match String(_s["stage"]):
		"open":
			var r: Dictionary = Army.rec(w, fid)
			var units: Array = Army.members(game, fid)
			var cul: Dictionary = Army.cul_of_faction(fid)
			var rl: Array = ArmyRanks.ranks(cul, "army")
			var span: int = maxi(2, int(cul.get("span", 5)))
			var fo: int = ArmyRanks.first_officer("army")
			_s.merge({"r": r, "units": units, "cul": cul, "rl": rl, "span": span, "fo": fo,
				"by": {}, "posts": r["posts"], "stage": "by"}, true)
		"by":
			var units: Array = _s["units"]
			var i: int = int(_s["i"])
			if i < units.size():
				var u: Unit = units[i]
				_s["by"][u.uid] = u
				_s["i"] = i + 1
			else:
				_s["lv"] = ArmyRanks.levels_for(units.size(), int(_s["span"]), maxi(0, (_s["rl"] as Array).size() - int(_s["fo"])))
				_s["old_lv"] = int(_s["r"]["levels"])
				_s["stage"] = "shape"
		"shape":
			var lv: int = int(_s["lv"])
			var old_lv: int = int(_s["old_lv"])
			var posts: Array = _s["posts"]
			if lv != old_lv:
				var n: int = ArmyRanks.offset(lv, int(_s["span"]))
				if posts.size() > n:
					var uid: int = int(posts.pop_back())
					if _s["by"].has(uid): ArmyRanks._demote(_s["by"][uid])
					return false
				if posts.size() < n:
					posts.append(-1)
					return false
				_s["r"]["levels"] = lv
				_s["r"]["fights"] = (_s["r"]["fights"] as Array).filter(func(x: Dictionary) -> bool: return int(x["p"]) < n)
				if lv < old_lv:
					ArmyRanks._hist(game, fid, "The army shrank; the %s posts are gone." % _s["rl"][ArmyRanks.rank_at(lv, _s["rl"])])
			_s.merge({"holds": {}, "i": 0, "stage": "holders"}, true)
		"holders":
			var posts: Array = _s["posts"]
			var i: int = int(_s["i"])
			if i >= posts.size():
				_s["i"] = 0
				_s["stage"] = "ranks"
				return false
			_s["i"] = i + 1
			var uid: int = int(posts[i])
			if uid < 0: return false
			if not _s["by"].has(uid):
				posts[i] = -1
				return false
			var u: Unit = _s["by"][uid]
			if not ArmyRanks.house_born(u):
				posts[i] = -1
				ArmyRanks._demote(u)
				return false
			if i == 0 and String(_s["cul"].get("rank_rule", "")) == "strength" and ArmyRanks._ruled_out(fid, u):
				posts[i] = -1
				ArmyRanks._demote(u)
				return false
			_s["holds"][uid] = i
			u.rank = ArmyRanks.rank_at(ArmyRanks.level_of(i, int(_s["span"])), _s["rl"])
			u.role = "officer"
		"ranks":
			var units: Array = _s["units"]
			var i: int = int(_s["i"])
			if i < units.size():
				_s["i"] = i + 1
				var u: Unit = units[i]
				if not _s["holds"].has(u.uid):
					if u.rank >= int(_s["fo"]): ArmyRanks._demote(u)
					elif u.rank == 0 and u.battles >= 1: u.rank = 1
			else:
				_s["vacant"] = (_s["posts"] as Array).filter(func(x: Variant) -> bool: return int(x) < 0).size()
				_s.merge({"free": 0, "i": 0, "stage": "free"}, true)
		"free":
			var units: Array = _s["units"]
			var i: int = int(_s["i"])
			if i < units.size():
				_s["i"] = i + 1
				var u: Unit = units[i]
				if not _s["holds"].has(u.uid) and ArmyRanks.house_born(u): _s["free"] = int(_s["free"]) + 1
			elif int(_s["vacant"]) > int(_s["free"]):
				_s["noble"] = {"stage": "open", "out": [], "most": mini(10, int(_s["vacant"]) - int(_s["free"]))}
				_s["stage"] = "nobles"
			else:
				_s["stage"] = "busy"
		"nobles":
			if await _noble_part(game, fid):
				_s["i"] = 0
				_s["stage"] = "append"
		"append":
			var out: Array = _s["noble"]["out"]
			var i: int = int(_s["i"])
			if i < out.size():
				var nu: Unit = out[i]
				_s["by"][nu.uid] = nu
				(_s["units"] as Array).append(nu)
				_s["i"] = i + 1
			else:
				_s["stage"] = "busy"
		"busy":
			var busy: Dictionary = {}
			for fgt: Dictionary in _s["r"]["fights"]:
				await _checkpoint("army:loop")
				busy[int(fgt["p"])] = true
			_s.merge({"busy": busy, "i": 0, "stage": "fill"}, true)
		"fill":
			var posts: Array = _s["posts"]
			var i: int = int(_s["i"])
			if i < posts.size():
				_s["i"] = i + 1
				if int(posts[i]) < 0 and not _s["busy"].has(i):
					ArmyRanks.fill(game, fid, i, _s["by"], false, int(_header[2]), false)
			else:
				if not (_s["r"]["fights"] as Array).is_empty(): ArmyRanks._queue_fight(w, fid)
				_s["stage"] = "link"
		"link":
			ArmyRanks._link_field_commands(game, fid)
			return true
	return false

## Native call_up_nobles traversal, including the early-return position inside
## the person loop: later empty family registers still receive their lazy pp.
func _noble_part(game: Variant, fid: String) -> bool:
	var w: Dictionary = game.world
	var n: Dictionary = _s["noble"]
	match String(n["stage"]):
		"open":
			if int(n["most"]) <= 0: return true
			n.merge({"band": {}, "ids": w["warbands"].keys(), "i": 0, "stage": "band"}, true)
		"band":
			var ids: Array = n["ids"]
			var i: int = int(n["i"])
			if i < ids.size():
				n["i"] = i + 1
				var wb: Dictionary = w["warbands"][ids[i]]
				var band: Dictionary = n["band"]
				if wb["faction"] == fid and Army.is_field(wb) and Army.is_people_band(wb) and (band.is_empty() or (wb["units"] as Array).size() > (band["units"] as Array).size()):
					n["band"] = wb
			else:
				if (n["band"] as Dictionary).is_empty(): return true
				n.merge({"roll": Army.state(w)["roll"], "ids": w["towns"].keys(), "i": 0, "stage": "town"}, true)
		"town":
			var ids: Array = n["ids"]
			var i: int = int(n["i"])
			if i >= ids.size(): return true
			n["i"] = i + 1
			var tid: Variant = ids[i]
			var town: Dictionary = w["towns"][tid]
			if str(town.get("faction", "")) != fid or not TownEcon.has_econ(town): return false
			var e: Dictionary = town["econ"]
			n.merge({"tid": tid, "town": town, "econ": e, "ab": People.ages(Persons.race_of(e)),
				"head": str(e.get("head", {}).get("person_uid", "")), "fams": e.get("fams", []), "j": 0, "stage": "family"}, true)
		"family":
			var fams: Array = n["fams"]
			var j: int = int(n["j"])
			if j >= fams.size():
				n["stage"] = "town"
				return false
			n["j"] = j + 1
			var f: Dictionary = fams[j]
			if f.get("cohort", false) or f.get("estate", false) or f.get("gone", false) or str(f.get("household_uid", "")) == "": return false
			n.merge({"family": f, "people": Persons.pp(f), "k": 0, "called": false, "stage": "person"}, true)
		"person":
			var people: Array = n["people"]
			var k: int = int(n["k"])
			if k >= people.size():
				if bool(n.get("called", false)): Families.reassign(n["econ"], n["family"])
				n["stage"] = "family"
				return false
			if (n["out"] as Array).size() >= int(n["most"]):
				# v0.100: mirror native call_up_nobles: reassignment on leaving.
				if bool(n.get("called", false)): Families.reassign(n["econ"], n["family"])
				return true
			n["k"] = k + 1
			var p: Array = people[k]
			if str(p[4]) != "" or int(p[5]) >= 0 or int(p[6]) != 0: return false
			if str(Persons.g(p, Persons.PERSON_UID, "")) == String(n["head"]): return false
			var e: Dictionary = n["econ"]
			var age: float = Persons.age_of(p, float(e.get("day", game.day)))
			if age < int(n["ab"]["adult"]) or age >= int(n["ab"]["elder"]): return false
			var town: Dictionary = n["town"]
			var f: Dictionary = n["family"]
			var u: Unit = CampaignWorld.make_resident_troop(game.rng, fid, town)
			Persons.log_life(p, float(game.day), "serve", "army")
			p[4] = "army"
			var sv: Dictionary = f["serve"]
			sv["army"] = int(sv.get("army", 0)) + 1
			People.last_person = p
			People.bind(town, int(f["id"]), u, "army")
			u.family = int(f["id"])
			u.home_town = str(n["tid"])
			u.faction = fid
			n["roll"][str(u.uid)] = [str(n["tid"]), int(f["id"]), "army", u.name]
			(n["band"]["units"] as Array).append(u)
			Families.event(f, "joined", [u.name, "army", Army.force_word(w, n["band"])], float(game.day))
			n["called"] = true
			(n["out"] as Array).append(u)
	return false

func _camp_day(game: Variant, lid: Variant) -> void:
	var w: Dictionary = game.world
	var cul: Dictionary = TownEcon.data()["cultures"]["middle"]
	var l: Dictionary = w["lairs"].get(lid, {})
	if l.get("kind", "") != "bandit_camp":
		return
	var bands: Array = []
	var g: Dictionary = w["warbands"].get(String(l.get("resident", "")), {})
	if not g.is_empty():
		bands.append(g)
	for wid: Variant in Bandits.bands_of(game, String(lid)):
		await _checkpoint("army:loop")
		bands.append(w["warbands"][wid])
	var men: Array = []
	for b: Dictionary in bands:
		await _checkpoint("army:loop")
		for u: Unit in b["units"]:
			await _checkpoint("army:loop")
			if not u.dead:
				men.append(u)
	men.sort_custom(func(a: Unit, b2: Unit) -> bool: return a.is_officer() and not b2.is_officer())
	var need: float = float(men.size()) * float(Army.A()["wage"]["bandit"])
	var tries: int = 0
	while float(l.get("gold", 0.0)) < need and tries < 3 and not (l.get("stock", []) as Array).is_empty():
		await _checkpoint("army:loop")
		if not Army._fence(w, l):
			break
		tries += 1
	await _army_pay_units(game, men, {"kind": "camp", "l": l}, "bandit", cul)
	for b: Dictionary in bands:
		await _checkpoint("army:loop")
		Supplies.eat(b)
	for b: Dictionary in bands:
		await _checkpoint("army:loop")
		var sd: int = int(Army.A()["scatter_days"])
		if b["kind"] == "bandit":
			if (b["units"] as Array).any(func(u: Unit) -> bool: return not u.dead and u.unpaid_days >= sd):
				for u: Unit in b["units"]:
					await _checkpoint("army:loop")
					if not u.dead:
						Army.release(game, u, "deserted", "an outlaw band")
				CampaignWorld.log_event(game, "An unpaid outlaw gang near %s scattered." % CampaignWorld.nearest_town_name(w, b["pos"]))
				CampaignWorld.remove_warband(game, b["id"])
		else:
			var gone: Array = (b["units"] as Array).filter(func(u: Unit) -> bool: return not u.dead and u.unpaid_days >= sd and u.name != String(b.get("named", "")))
			for u: Unit in gone:
				await _checkpoint("army:loop")
				(b["units"] as Array).erase(u)
				Army.release(game, u, "deserted", "an outlaw band")


func _step_label() -> String:
	return String(_header[0]) + "/" + String(_s["stage"])

func _army_pay_units(game: Variant, units: Array, payer: Dictionary, tier: String, cul: Dictionary, lo_override: int = -2) -> Dictionary:
	await _checkpoint("Army.pay_units:enter")
	var w: Dictionary = game.world
	var mix: Dictionary = cul.get("pay", {"coin": 1.0})
	if String(payer["kind"]) == "camp":
		mix = {"coin": 1.0}
	var lo: Variant = lo_override if lo_override >= -1 else Army.low_officer(units, tier)
	var bill: Variant = 0.0; var paid: Variant = 0.0; var unpaid: Variant = 0
	for u: Variant in units:
		await _checkpoint("Army.pay_units:loop")
		if u.dead:
			continue
		var wg: Variant = Army.wage(tier, u.rank, lo, u)
		bill += wg
		var town: Dictionary = w["towns"].get(u.home_town, {})
		var f: Variant = People.fam_of(town, u.family)
		if f.is_empty() or f["gone"]:
			u.unpaid_days = 0   # nobody at home to pay (an orphaned record): he serves for his keep
			continue
		var e: Dictionary = town["econ"]
		var coin: Variant = wg * float(mix.get("coin", 0.0))
		var loot: Variant = wg * float(mix.get("loot", 0.0))
		var took_loot: Variant = 0.0
		if loot > 0.0 and String(payer["kind"]) == "faction":
			took_loot = minf(loot, float(payer["fac"].get("loot", 0.0)))
		coin += loot - took_loot
		# kind: food (grain, then meat) and beer from the home market
		var buys: Variant = []
		var kind_cost: Variant = 0.0
		for part: Variant in [["food", ["grain", "meat"]], ["beer", ["beer"]]]:
			await _checkpoint("Army.pay_units:loop")
			var val: Variant = wg * float(mix.get(part[0], 0.0))
			if val <= 0.0:
				continue
			for g: Variant in part[1]:
				await _checkpoint("Army.pay_units:loop")
				if val <= 0.01:
					break
				var p: Variant = float(e["price"].get(g, 1.0))
				var q: Variant = mini(int(val / p), int(e["stock"].get(g, 0)))
				if q > 0:
					buys.append([g, q, part[0]])
					kind_cost += float(q) * p
					val -= float(q) * p
			coin += val   # what the market could not supply comes as coin
		var need: Variant = coin + kind_cost
		if Army._funds(payer) < need:
			u.unpaid_days += 1
			u.last_pay = 0.0
			unpaid += 1
			continue
		Army._spend(payer, need)
		if String(payer["kind"]) == "camp":
			TownEcon.gold_out(-need)   # stolen coin comes back into a town purse
		if took_loot > 0.0:
			payer["fac"]["loot"] = float(payer["fac"]["loot"]) - took_loot
			TownEcon.gold_out(-took_loot)   # loot comes back into a town purse
		f["purse"] = float(f["purse"]) + coin + took_loot
		if kind_cost > 0.0:
			var mkt: Dictionary = e["biz"][int(e["mkt"])]
			mkt["till"] = float(mkt["till"]) + kind_cost
			var rates: Variant = Families.daily_rates(e, f)
			for b: Variant in buys:
				await _checkpoint("Army.pay_units:loop")
				e["stock"][b[0]] = int(e["stock"][b[0]]) - int(b[1])
				e["hh"][b[0]] = int(e["hh"].get(b[0], 0)) + int(b[1])
				var key: Variant = "food" if b[2] == "food" else "drink"
				f["store"][key] = float(f["store"][key]) + float(b[1]) / maxf(0.5, float(rates[key]))
		u.unpaid_days = 0
		u.last_pay = need + took_loot
		paid += need + took_loot
	return {"bill": bill, "paid": paid, "unpaid": unpaid}

func _army_company_desertion(game: Variant) -> void:
	await _checkpoint("Army.company_desertion:enter")
	var dd: Variant = int(Army.A()["company_desert_days"])
	var gone: Array = game.company.filter(func(u: Variant) -> bool: return not u.dead and u.unpaid_days >= dd)
	for u: Variant in gone:
		await _checkpoint("Army.company_desertion:loop")
		if Mobilization.manages(game, u):
			var unpaid: int = u.unpaid_days
			var home: Dictionary = game.world.get("towns", {}).get(u.home_town, {})
			var family: Dictionary = People.fam_of(home, u.family)
			var person: Array = Persons.by_uid(family, u.uid)
			if not Mobilization.return_home(game, u):
				continue # never strip/erase a registered physical person after a failed return
			Persons.remember_unpaid(person, "company", unpaid, float(game.day), float(game.day) - Persons.served_since(person, "company"))
			Families.event(family, "deserted", [u.name, "a mercenary company"], float(game.day))
			Families.add_hist(family, "%s came home from the company, unpaid for %d days." % [u.name, unpaid], float(game.day))
			CampaignWorld.log_event(game, "%s deserted the company: unpaid for %d days." % [u.name, unpaid])
			continue
		Horses.return_mount(game, u)
		game.company.erase(u)
		game.squads.erase(u.uid)
		ArmsTrade.kit_home(game, u)   # arms trade: he takes his kit home and hands it in for coin
		for t: Variant in game.company:
			await _checkpoint("Army.company_desertion:loop")
			if t.squad == u.uid:
				t.squad = -1
		var town: Dictionary = game.world["towns"].get(u.home_town, {})
		var f: Variant = People.fam_of(town, u.family)
		if not f.is_empty() and not f["gone"]:
			# back on the family row (he left it when hired): his own register record comes home with him
			var p: Variant = Persons.by_uid(f, u.uid)
			var s: Variant = "m"
			if not p.is_empty():
				s = "old" if int(p[6]) == 1 else ("m" if int(p[2]) == 0 else "f")
				Persons.set_home(p)
			f[s] = int(f[s]) + 1
			town["econ"]["pop"] = int(town["econ"]["pop"]) + 1
			Census.record_move(town["econ"], int(p[0]) if not p.is_empty() else -1, "in", "", float(game.day), "home from the company")   # the census
			if s != "old":
				town["econ"]["adults"] = int(town["econ"]["adults"]) + 1
			Families.event(f, "deserted", [u.name, "a mercenary company"], float(game.day))
			Families.add_hist(f, "%s came home from the company, unpaid for %d days." % [u.name, u.unpaid_days], float(game.day))
			Families.reassign(town["econ"], f)
		CampaignWorld.log_event(game, "%s deserted the company: unpaid for %d days." % [u.name, u.unpaid_days])
	if not gone.is_empty():
		if game.has_method("invalidate_deploy"):
			game.invalidate_deploy()
		Diplomacy.roster_changed(game)
