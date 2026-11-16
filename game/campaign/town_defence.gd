class_name TownDefence
extends RefCounted

static func eligible(town: Dictionary) -> int:
	if not TownEcon.has_econ(town): return 0
	return Population.available(town)

static func militia_target(town: Dictionary) -> int:
	if not TownEcon.has_econ(town): return 0
	var e: Dictionary = town["econ"]
	# Both terms are nonnegative; only their capped sum is needed. Keep pp()
	# for EVERY family: its lazy empty register is part of the saved state.
	var budget: int = int(maxf(0, float(e["treasury"])) / maxf(1, Army.wage("militia", 0)) / 7)
	var limit: int = mini(budget, militia_cap(town))
	var available: int = 0
	for f: Dictionary in e["fams"]:
		var rows: Array = Persons.pp(f)
		if available >= limit: continue
		available += Population.spare(f)
		for p: Array in rows:
			if available >= limit: break
			# Private stood-down troops belong to the player's reserve.
			if int(p[5]) >= 0 and (f.get("player_reserve_uids", {}) as Dictionary).has(str(int(p[5]))): continue
			if String(p[4]) in ["reserve", "militia"]: available += 1
	return mini(available, limit)

static func militia_cap(town: Dictionary) -> int:
	return 6 + 5 * clampi(int(town.get("size", 1)), 0, 4)

static func guard_band(game, tid: String) -> Dictionary:
	return game.world["warbands"].get(String(game.world.get("town_guards", {}).get(tid, "")), {})

static func guards(game, tid: String) -> Array:
	return guard_band(game, tid).get("units", [])

static func garrison(game, tid: String) -> Array:
	return Militia.units_of(game, tid) + guards(game, tid)

## Political orders persist in the existing saved world; absent orders use the
## original threat/drill policy. Guards are professional and remain independent.
static func defence_policy(game, town: Dictionary) -> String:
	var policy := str(game.world.get("feudal", {}).get("towns", {}).get(str(town.get("id", "")), {}).get("defence_policy", "auto_defence"))
	return policy if policy in ["muster", "stand_down", "auto_defence"] else "auto_defence"

## known_policy is a pure read from this same synchronous call, before any
## fight/political mutation. Other callers retain the fresh native lookup.
static func set_muster(game, town: Dictionary, active: bool, drill: bool = false, known_policy: String = "") -> void:
	var policy: String = defence_policy(game, town) if known_policy == "" else known_policy
	match policy:
		"muster": active = true
		"stand_down": active = false; drill = false
	var wb := Militia.band_of(game, String(town["id"]))
	if wb.is_empty(): return
	wb["mustered"] = active
	wb["drill_today"] = drill
	var e: Dictionary = town["econ"]
	var families: Array = e.get("fams", []) if TownEcon.has_econ(town) else []
	var wanted := "militia" if active or drill else "reserve"
	var affected := []
	# Several hundred reservists can share one anonymous household record.
	# Resolve its native person rows once within this transition, retaining the
	# first UID match just like Persons.by_uid. Only JOB changes before reassign.
	var person_rows := {}
	for u in wb["units"]:
		# Complete the actual service transitions before households choose their
		# civilian work. Several units can belong to the same household.
		if u.family < 0 or u.family >= families.size(): continue
		var f: Dictionary = families[u.family]
		if f.is_empty(): continue
		if not person_rows.has(u.family):
			person_rows[u.family] = _muster_rows(f, wanted)
		var p: Array = person_rows[u.family].get(u.uid, [])
		if p.is_empty(): continue
		var old := String(p[4])
		if old == wanted: continue
		if old == "militia": f["serve"]["militia"] = maxi(0, int(f["serve"].get("militia", 0)) - 1)
		if active or drill: f["serve"]["militia"] = int(f["serve"].get("militia", 0)) + 1
		p[4] = wanted
		if not affected.has(int(u.family)): affected.append(int(u.family))
	for fid in affected:
		Families.reassign(e, families[int(fid)])
	if not affected.is_empty():
		# Departing hands can release funded places after an idle household's
		# weekly turn. Match those civilians after every affected household has
		# released its places, using the ordinary funding and wage-claim rules.
		Families.match_idle(e)
	if not active:
		wb["path"] = []; wb["pos"] = town["pos"]

## Only needed within one muster transition. If every native adult row already
## has the wanted job, no possible UID match needs a service change. Otherwise
## reverse assignment retains Persons.by_uid's FIRST match, including duplicate
## UIDs and shared Array aliases, without a second hash lookup for every row.
static func _muster_rows(f: Dictionary, wanted: String) -> Dictionary:
	var rows := Persons.pp(f)
	var change_possible := false
	for row: Array in rows:
		if String(row[4]) != wanted:
			change_possible = true
			break
	if not change_possible: return {}
	var by_uid := {}
	var n := rows.size()
	for i in n:
		var row: Array = rows[n - 1 - i]
		by_uid[int(row[5])] = row
	return by_uid

## Runtime-only value snapshots: catch in-place edits as well as replacement,
## growth, capture and save/load without adding keys to the saved plot state.
## Native packed-array equality replaces daily GDScript scans of every plot.
static var _pay_plot_layouts: Dictionary = {}

static func _pay_plot_layout(tid: String, P: Dictionary) -> Dictionary:
	var count: int = Plots.count(P)
	var uses: Variant = P["use"]
	var subs: Variant = P["sub"]
	var cached: Dictionary = _pay_plot_layouts.get(tid, {})
	if int(cached.get("count", -1)) == count and cached.get("use") == uses and cached.get("sub") == subs:
		return cached
	var gates: int = 0
	var pastures: Array = []
	for i: int in count:
		var use: int = int(uses[i])
		if use == Plots.ROAD and int(subs[i]) == 1: gates += 1
		if use == Plots.PASTURE: pastures.append(i)
	cached = {"count": count, "use": uses.duplicate(), "sub": subs.duplicate(), "gates": gates, "pastures": pastures}
	if _pay_plot_layouts.size() >= 128: _pay_plot_layouts.clear()
	_pay_plot_layouts[tid] = cached
	return cached

static func daily(game, town: Dictionary) -> void:
	var e: Dictionary = town["econ"]
	var tid := String(town["id"])
	var w: Dictionary = game.world
	if not w.has("town_guards"): w["town_guards"] = {}
	var P: Dictionary = e.get("plots", {})
	var posts: int = int(_pay_plot_layout(tid, P)["gates"])
	var affordable := int(maxf(0, float(e["treasury"])) / maxf(1, Army.wage("guard", 0)) / 14)
	var target := mini(posts * 3, affordable) # three eight-hour watches at each actual gate
	var gb := guard_band(game, tid)
	if gb.is_empty() and target > 0:
		var rng := RandomNumberGenerator.new(); rng.seed = hash([w.get("seed", 0), tid, "guards"])
		var units: Array = []
		# Only gear withdrawals/returns interleave here; share one ephemeral stock index.
		var guard_stock: Dictionary = {}
		for i: int in mini(target, eligible(town)):
			var fid := People.draw(town, rng, "guard")
			if fid < 0: break
			var u := CampaignWorld.make_resident_troop(rng, String(town["faction"]), town, int(town["wealth"]))
			People.bind(town, fid, u, "guard")
			u.home_town = tid; u.title = "town guard"
			ArmsTrade.outfit_guard(town, u, guard_stock)
			units.append(u)
			Army.state(w)["roll"][str(u.uid)] = [tid, fid, "guard", u.name]
		if not units.is_empty():
			var wid := CampaignWorld.spawn_warband(game, String(town["faction"]), town["pos"], units.size(), "militia", rng,
				{"units": units, "home": tid, "anchor": town["pos"], "professional": true, "marching": false})
			w["town_guards"][tid] = wid
			gb = guard_band(game, tid)
	if not gb.is_empty():
		var living: Array = gb["units"].filter(func(u): return not u.dead)
		var paid := Army.pay_units(game, living, {"kind": "town", "e": e}, "guard", TownEcon.culture_of(e))
		e["stats"]["guard_wages"] = paid["paid"]
		var leaving := []
		for u in living:
			if u.unpaid_days >= int(Army.A()["desert_days"]): leaving.append(u)
		for u in leaving:
			Army.release(game, u, "deserted", "the town guard")
			gb["units"].erase(u)
		gb["units"] = gb["units"].filter(func(u): return not u.dead)
		# A patrol visits the real pasture plots, returning to the gate between rounds.
		if not gb.get("marching", false) and not gb["units"].is_empty():
			# Revalidate after native recruitment/pay/release, before reading indices.
			var pastures: Array = _pay_plot_layout(tid, P)["pastures"]
			if not pastures.is_empty():
				var index := posmod(int(game.day), pastures.size())
				gb["patrol_goal"] = HerdRaids.plot_pos(town, P, int(pastures[index]))
				gb["path"] = CampaignWorld.find_path(w, gb["pos"], gb["patrol_goal"])
				gb["marching"] = not gb["path"].is_empty()
	var mil := Militia.band_of(game, tid)
	if not mil.is_empty():
		var drill := defence_policy(game, town) != "stand_down" and posmod(int(game.day), 7) == posmod(int(town.get("size", 0)), 7)
		set_muster(game, town, bool(mil.get("mustered", false)), drill)
		if drill: mil["drill_days"] = int(mil.get("drill_days", 0)) + 1
	e["barracks_beds"] = maxi(garrison(game, tid).size(), militia_target(town) + target)

static func guard_step(game, wb: Dictionary, dt: float) -> void:
	if not wb.get("marching", false): return
	if CampaignWorld._step_along(game.world, wb, CampaignWorld.WARBAND_SPEED * dt):
		if (wb["pos"] as Vector2).distance_to(wb["anchor"]) > 1:
			wb["path"] = CampaignWorld.find_path(game.world, wb["pos"], wb["anchor"])
		else: wb["marching"] = false
