class_name ServiceIdentity
extends RefCounted
## Current service belongs to one living household. Migration copies are history,
## never a second person, force or wage creditor.
static var last_report: Dictionary = {}

static func inventory(game) -> Dictionary:
	var out := {}
	var units: Array = game.company.duplicate()
	for wb in game.world.get("warbands", {}).values(): units.append_array(wb.get("units", []))
	for town in game.world.get("towns", {}).values(): units.append_array(town.get("recruits", []))
	units.append_array(CampaignWorld.mustering_units(game.world))
	units.append_array(Mobilization.reserves(game))
	for u in units:
		if not u is Unit or u.dead: continue
		if not out.has(u.uid): out[u.uid] = []
		(out[u.uid] as Array).append(u)
	return out

static func same_person(a: Array, b: Array) -> bool:
	return a.size() >= 8 and b.size() >= 8 and int(a[1]) == int(b[1]) and int(a[2]) == int(b[2]) and float(a[3]) == float(b[3]) and int(a[6]) == int(b[6]) and String(a[7]) == String(b[7])

static func unit_person(e: Dictionary, f: Dictionary, p: Array, u: Unit) -> bool:
	return p.size() >= 8 and float(p[3]) == u.born and int(p[2]) == u.sex and Persons.name_of(f, p, Persons.race_of(e)) == u.name

static func squads_safe(old: Dictionary, units: Array) -> bool:
	var moving := {}
	for u in units: moving[u.uid] = true
	for u in old.get("units", []):
		if u.dead: continue
		if moving.has(u.uid):
			if u.squad >= 0 and not moving.has(u.squad): return false
		elif moving.has(u.squad): return false
	return true

## Read-only preflight. Call this before any settlement or ownership mutation.
static func reserve_move(game, from: Dictionary, f: Dictionary, to: Dictionary) -> Dictionary:
	var bad := {"ok": false, "units": []}
	if from == to or not TownEcon.has_econ(from) or not TownEcon.has_econ(to) or f.get("gone", false) or f.get("estate", false): return bad
	if People.fam_of(from, int(f.get("id", -1))) != f: return bad
	if Families.serving(f) > 0 or Barge._away(f) or Persons.race_of(from["econ"]) != Persons.race_of(to["econ"]): return bad
	for p in f.get("kp", []):
		if int(p[5]) >= 0: return bad
	var bound := []
	for p in f.get("pp", []):
		if String(p[4]) not in ["", "reserve"]: return bad
		if int(p[5]) >= 0 or String(p[4]) == "reserve": bound.append(p)
	if bound.is_empty(): return {"ok": true, "units": []}
	var band := Militia.band_of(game, String(from["id"]))
	var by := inventory(game)
	var claims := {}
	for town in game.world.get("towns", {}).values():
		for family in town.get("econ", {}).get("fams", []):
			if family.get("gone", false): continue
			for person in family.get("pp", []):
				if int(person[5]) >= 0: claims[int(person[5])] = int(claims.get(int(person[5]), 0)) + 1
	var units := []
	var seen := {}
	for p in bound:
		var uid := int(p[5])
		if String(p[4]) == "militia": return bad
		if uid < 0:
			if String(p[4]) == "reserve": return bad
			continue
		if String(p[4]) != "reserve" or from["faction"] != to["faction"] or band.is_empty() or String(band.get("kind", "")) != "militia" or band.get("professional", false) or band.get("mustered", false) or band.get("drill_today", false): return bad
		var matches: Array = by.get(uid, [])
		if matches.size() != 1 or seen.has(uid): return bad
		var u: Unit = matches[0]
		if not (band.get("units", []) as Array).has(u) or u.family != int(f["id"]) or u.home_town != String(from["id"]) or u.faction != String(from["faction"]) or not unit_person(from["econ"], f, p, u): return bad
		if int(claims.get(uid, 0)) != 1: return bad
		seen[uid] = true
		units.append(u)
	var dest := Militia.band_of(game, String(to["id"]))
	if not dest.is_empty() and (String(dest.get("kind", "")) != "militia" or dest.get("professional", false) or String(dest.get("home", "")) != String(to["id"]) or String(dest.get("faction", "")) != String(to["faction"])): return bad
	if not squads_safe(band, units): return bad
	return {"ok": true, "units": units}

static func recount(f: Dictionary) -> void:
	var n := 0
	for p in f.get("pp", []):
		if String(p[4]) == "militia" and int(p[5]) >= 0: n += 1
	if n > 0: f["serve"]["militia"] = n
	else: f["serve"].erase("militia")

## Transfers actual Units, never recruits replacements or rerolls their kit.
static func transfer(game, from: Dictionary, to: Dictionary, nf: Dictionary, units: Array) -> bool:
	if units.is_empty(): return false
	var serving_before := Families.serving(nf)
	var old := Militia.band_of(game, String(from["id"]))
	var dest := Militia.band_of(game, String(to["id"]))
	if dest.is_empty():
		var rng := RandomNumberGenerator.new()
		rng.seed = hash([game.world.get("seed", 0), to["id"], "reserve-move"])
		var wid := CampaignWorld.spawn_warband(game, String(to["faction"]), to["pos"], units.size(), "militia", rng,
			{"units": units.duplicate(), "home": String(to["id"]), "anchor": to["pos"], "last_recruit": float(game.day), "mustered": false, "drill_today": false})
		game.world["militia"][String(to["id"])] = wid
		dest = Militia.band_of(game, String(to["id"]))
	else:
		(dest["units"] as Array).append_array(units)
	var state := "militia" if dest.get("mustered", false) or dest.get("drill_today", false) else "reserve"
	for u in units:
		(old["units"] as Array).erase(u)
		u.home_town = String(to["id"])
		u.family = int(nf["id"])
		var p := Persons.by_uid(nf, u.uid)
		p[4] = state
		# The existing Unit keeps its actual current illness. A stale historical
		# register copy without an open case must never silently heal him.
		var roll: Dictionary = Army.state(game.world)["roll"]
		if roll.has(str(u.uid)): roll[str(u.uid)] = [u.home_town, u.family, "militia", u.name]
	recount(nf)
	# Vacate former command posts without re-ranking any soldier. The ordinary
	# town service turn can arrange its current ranks later.
	for i in (old.get("posts", []) as Array).size():
		for u in units:
			if int(old["posts"][i]) == u.uid: old["posts"][i] = -1
	return serving_before != Families.serving(nf)

## A gone migration row retains its history but cannot claim current service.
static func detach(p: Array) -> void:
	p[4] = "gone"
	p[5] = -1

static func destination(w: Dictionary, tid: String, fid: int) -> Array:
	var seen := {}
	while true:
		var key := tid + "/" + str(fid)
		if seen.has(key): return []
		seen[key] = true
		var f := People.fam_of(w.get("towns", {}).get(tid, {}), fid)
		if f.is_empty(): return []
		if not f.get("gone", false): return [tid, fid]
		var d: Array = f.get("wage_destination", [])
		if d.size() != 2 or String(f.get("moved", "")) != String(d[0]): return []
		tid = String(d[0]); fid = int(d[1])
	return []

static func release_event(p: Array, since: float) -> Array:
	var found := []
	for ev in Persons.g(p, Persons.HIST, []):
		if String(ev[1]) == "home" and String(ev[2]) == "militia" and float(ev[0]) >= since: found = ev
	return found

## Repairs only exact, unique copied migration identities. Unproved defects stay
## visible in last_report; a global UID match alone is never proof.
static func after_load(game) -> Dictionary:
	var w: Dictionary = game.world
	var by := inventory(game)
	var active := {}
	for tid in w.get("towns", {}):
		for f in w["towns"][tid].get("econ", {}).get("fams", []):
			if f.get("gone", false): continue
			for p in f.get("pp", []):
				if int(p[5]) < 0: continue
				if not active.has(int(p[5])): active[int(p[5])] = []
				(active[int(p[5])] as Array).append([tid, f, p])
	var report := {"transferred": 0, "released": 0, "historical_detached": 0, "unresolved": 0}
	var affected := {}
	for uid in active:
		var rows: Array = active[uid]
		if rows.size() != 1:
			report["unresolved"] += 1
			continue
		var row: Array = rows[0]
		var tid := String(row[0]); var f: Dictionary = row[1]; var p: Array = row[2]
		if String(p[4]) not in ["reserve", "militia"]: continue
		var live: Array = by.get(uid, [])
		if live.size() == 1:
			var u: Unit = live[0]
			if u.home_town == tid and u.family == int(f["id"]): continue
			var source: Dictionary = w["towns"].get(u.home_town, {})
			var sf := People.fam_of(source, u.family)
			var sp := Persons.by_uid(sf, uid)
			var source_matches: Array = (sf.get("pp", []) as Array).filter(func(person): return int(person[5]) == int(uid))
			var d := destination(w, u.home_town, u.family)
			var sb := Militia.band_of(game, u.home_town)
			var db := Militia.band_of(game, tid)
			if source_matches.size() != 1 or not sf.get("gone", false) or d != [tid, int(f["id"])] or not same_person(sp, p) or not unit_person(w["towns"][tid]["econ"], f, p, u) or u.faction != String(w["towns"][tid]["faction"]) or sb.is_empty() or String(sb.get("kind", "")) != "militia" or sb.get("professional", false) or not (sb["units"] as Array).has(u) or not squads_safe(sb, [u]) or (not db.is_empty() and (String(db.get("kind", "")) != "militia" or db.get("professional", false) or String(db.get("home", "")) != tid or String(db.get("faction", "")) != u.faction)):
				report["unresolved"] += 1
				continue
			if transfer(game, source, w["towns"][tid], f, [u]): affected[tid + "/" + str(f["id"])] = row
			report["transferred"] += 1
		elif live.is_empty():
			var releases := []
			var since := Persons.served_since(p, "militia")
			for stid in w["towns"]:
				for sf in w["towns"][stid].get("econ", {}).get("fams", []):
					if not sf.get("gone", false) or destination(w, stid, int(sf["id"])) != [tid, int(f["id"])]: continue
					for sp in sf.get("pp", []):
						if String(sp[4]) != "" or int(sp[5]) >= 0 or not same_person(sp, p): continue
						var ev := release_event(sp, since)
						if since >= 0 and not ev.is_empty(): releases.append([sp, ev])
			if releases.size() != 1:
				report["unresolved"] += 1
				continue
			var sp: Array = releases[0][0]; var ev: Array = releases[0][1]
			var serving_before := Families.serving(f)
			p[4] = ""; p[5] = -1
			Persons.log_life(p, float(ev[0]), "home", "militia")
			(p[Persons.HIST] as Array).sort_custom(func(a, b): return float(a[0]) < float(b[0]))
			var memory: Variant = Persons.g(sp, Persons.SERVICE_MEMORY, {})
			if memory is Dictionary and not memory.is_empty():
				while p.size() <= Persons.SERVICE_MEMORY: p.append(0)
				var kept: Dictionary = Persons.g(p, Persons.SERVICE_MEMORY, {}).duplicate(true) if Persons.g(p, Persons.SERVICE_MEMORY, {}) is Dictionary else {}
				for role in memory:
					if not kept.has(role) or float(memory[role].get("returned", -1)) >= float(kept[role].get("returned", -1)): kept[role] = memory[role].duplicate(true)
				p[Persons.SERVICE_MEMORY] = kept
			recount(f)
			report["released"] += 1
			if serving_before != Families.serving(f): affected[tid + "/" + str(f["id"])] = row
		else: report["unresolved"] += 1
	# Detach only copies whose lineage and invariant identity establish where the
	# person lives now. Older unknown/dead histories are not guessed into claims.
	for stid in w.get("towns", {}):
		for sf in w["towns"][stid].get("econ", {}).get("fams", []):
			if not sf.get("gone", false): continue
			var d := destination(w, stid, int(sf["id"]))
			if d.is_empty(): continue
			var df := People.fam_of(w["towns"][d[0]], int(d[1]))
			for sp in sf.get("pp", []):
				if String(sp[4]) not in ["reserve", "militia"]: continue
				var matches: Array = (df.get("pp", []) as Array).filter(func(p): return same_person(sp, p))
				if matches.size() != 1: continue
				var p: Array = matches[0]
				var live: Array = by.get(int(sp[5]), [])
				if live.size() > 1: continue
				if live.size() == 1:
					var u: Unit = live[0]
					if u.home_town != String(d[0]) or u.family != int(d[1]) or int(p[5]) != u.uid or not unit_person(w["towns"][d[0]]["econ"], df, p, u): continue
				elif String(p[4]) != "" or release_event(p, Persons.served_since(sp, "militia")).is_empty():
					continue
				if int(sp[5]) >= 0 and int(p[5]) != int(sp[5]) and String(p[4]) != "": continue
				detach(sp)
				report["historical_detached"] += 1
			recount(sf)
	for row in affected.values(): Families.reassign(w["towns"][row[0]]["econ"], row[1])
	last_report = report
	return report

## Old saves lack the allocation counter. Retained references provide a safe
## floor, including departed service and pending census fates.
static func uid_floor(game) -> int:
	var floor_uid := 1
	var by := inventory(game)
	for uid in by: floor_uid = maxi(floor_uid, int(uid) + 1)
	for rows in by.values():
		for u in rows: floor_uid = maxi(floor_uid, int(u.squad) + 1)
	for uid in game.squads: floor_uid = maxi(floor_uid, int(uid) + 1)
	for wb in game.world.get("warbands", {}).values():
		for uid in wb.get("posts", []): floor_uid = maxi(floor_uid, int(uid) + 1)
		for person in wb.get("crew", []):
			if person.size() > 3: floor_uid = maxi(floor_uid, int(person[3]) + 1)
	for town in game.world.get("towns", {}).values():
		for f in town.get("econ", {}).get("fams", []):
			for p in f.get("pp", []) + f.get("kp", []) + f.get("dp", []):
				if p.size() > 5: floor_uid = maxi(floor_uid, int(p[5]) + 1)
	for uid in game.world.get("army", {}).get("roll", {}): floor_uid = maxi(floor_uid, int(uid) + 1)
	for faction in game.world.get("army", {}).get("f", {}).values():
		for uid in faction.get("posts", []): floor_uid = maxi(floor_uid, int(uid) + 1)
		for fight in faction.get("fights", []):
			for uid in fight.get("c", []): floor_uid = maxi(floor_uid, int(uid) + 1)
	for uid in game.world.get("census_fate", {}): floor_uid = maxi(floor_uid, int(uid) + 1)
	return floor_uid
