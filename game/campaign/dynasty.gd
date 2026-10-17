class_name Dynasty
extends RefCounted
## Political references point to native people; no copied population, Units or
## accounts. Local PIDs/household indices remain the economic system's keys.
## v0.001 uses birth-house affiliation, retained through marriage/migration.
## Political offices may succeed; their native economic owners remain separate.

static func _eligible(e: Dictionary, f: Dictionary, day: float) -> Array:
	var head := Persons.head_of(f)
	var candidates: Array = [head] if not head.is_empty() else []
	candidates.append_array(f.get("pp", []))
	for p in candidates:
		if int(p[6]) != 2 and String(p[4]) != "gone" and Persons.age_of(p, day) >= int(People.ages(Persons.race_of(e))["adult"]):
			return p
	return []

## Called once during native town generation. Never changes an already-linked
## office holder, including after death; e.ruler fiscal metadata is untouched.
static func bind_head(town: Dictionary) -> void:
	var e: Dictionary = town.get("econ", {})
	var head: Dictionary = e.get("head", {})
	if head.is_empty() or String(head.get("person_uid", "")) != "": return
	var f := People.fam_of(town, int(head.get("fam", -1)))
	if f.is_empty() or f.get("estate", false) or f.get("gone", false): return
	var p := _eligible(e, f, float(e.get("day", 0)))
	if p.is_empty(): return
	Persons.identity(e, f, p)
	if str(Persons.g(p, Persons.PERSON_UID, "")) == "": return
	head["name"] = Persons.name_of(f, p, Persons.race_of(e))
	head["pid"] = int(p[0])
	head["person_uid"] = str(p[Persons.PERSON_UID])
	head["house_uid"] = str(p[Persons.HOUSE_UID])
	head["household_uid"] = String(f["household_uid"])
	head["home_town"] = String(town["id"])
	f["named"] = true

## Explicit initialization boundary after full generation/presimulation. Reads
## below never generate identities, appoint rulers, settle claims or move coin.
static func prepare_world(game) -> void:
	var w: Dictionary = game.world
	for tid in w.get("towns", {}):
		var town: Dictionary = w["towns"][tid]
		var e: Dictionary = town.get("econ", {})
		if e.is_empty(): continue
		if String(e.get("identity_scope", "")) == "":
			e["identity_scope"] = "%d:%s" % [int(w.get("seed", 0)), String(tid)]
		for f in e.get("fams", []):
			if f.get("estate", false): continue
			Families.identity(e, f)
			for p in f.get("pp", []) + f.get("kp", []) + f.get("dp", []): Persons.identity(e, f, p)
		for f in e.get("fams", []):
			for p in f.get("pp", []) + f.get("kp", []): Persons.identity_kin(e, p)
		bind_head(town)
	_index_world(game)

static func _living(game, town_id: String, f: Dictionary, p: Array) -> bool:
	if f.get("estate", false) or String(p[4]) in ["gone", "dead"]: return false
	if not f.get("gone", false): return true
	# Economic extinction concerns the home row; company members are counted
	# outside it. A real bound living company member still belongs to the lineage.
	if String(f.get("moved", "")) == "" and String(p[4]) == "company":
		for u in game.company:
			if not u.dead and u.uid == int(p[5]) and u.home_town == town_id and u.family == int(f["id"]): return true
	if String(f.get("moved", "")) == "" and String(p[4]) == "captive":   # v0.033: held captive, still alive
		var held: Unit = Prisoners.captive_unit(game, int(p[5]))
		return held != null and held.home_town == town_id and held.family == int(f["id"])
	return false

## Locate by stable identity; remembered/departed records are never live people.
static func _person(game, uid: String, remembered: bool = false) -> Dictionary:
	if uid == "": return {}
	var memory := {}
	var towns: Dictionary = game.world.get("towns", {})
	var ordered := []
	var parts := uid.split(":")
	var origin := String(parts[2]) if parts.size() == 4 else ""
	if towns.has(origin): ordered.append(towns[origin])
	for tid in towns:
		if String(tid) != origin: ordered.append(towns[tid])
	for town in ordered:
		var e: Dictionary = town.get("econ", {})
		for f in e.get("fams", []):
			for p in f.get("pp", []) + f.get("kp", []):
				if str(Persons.g(p, Persons.PERSON_UID, "")) != uid: continue
				if _living(game, String(town.get("id", "")), f, p): return {"town": town, "econ": e, "family": f, "person": p, "alive": true}
				if remembered: memory = {"town": town, "econ": e, "family": f, "person": p, "alive": false}
			if remembered:
				for p in f.get("dp", []):
					if str(Persons.g(p, Persons.PERSON_UID, "")) == uid:
						memory = {"town": town, "econ": e, "family": f, "person": p, "alive": false}
	return memory

static func _household(game, uid: String) -> Dictionary:
	if uid == "": return {}
	for town in game.world.get("towns", {}).values():
		for f in town.get("econ", {}).get("fams", []):
			if String(f.get("household_uid", "")) == uid and not f.get("gone", false):
				return {"town": town, "family": f}
	return {}

static func _row(loc: Dictionary, day: float, title: String = "") -> Dictionary:
	if loc.is_empty(): return {}
	var town: Dictionary = loc["town"]
	var e: Dictionary = loc["econ"]
	var f: Dictionary = loc["family"]
	var p: Array = loc["person"]
	return {"person_uid": str(Persons.g(p, Persons.PERSON_UID, "")),
		"house_uid": str(Persons.g(p, Persons.HOUSE_UID, "")), "town_id": String(town.get("id", "")),
		"town_name": String(town.get("name", "")), "family_id": int(f["id"]),
		"household_uid": String(f.get("household_uid", "")), "family_name": String(f.get("name", "")),
		"pid": int(p[0]), "name": Persons.name_of(f, p, Persons.race_of(e)), "sex": int(p[2]),
		"race": Persons.race_of(e), "age": Persons.age_of(p, day), "state": String(p[4]),
		"unit_uid": int(p[5]), "alive": bool(loc["alive"]), "title": title,
		"spouse_pid": int(Persons.g(p, Persons.SP, -1)), "mother_pid": int(Persons.g(p, Persons.MO, -1)),
		"father_pid": int(Persons.g(p, Persons.FA, -1)), "spouse_uid": str(Persons.g(p, Persons.SPOUSE_UID, "")),
		"mother_uid": str(Persons.g(p, Persons.MOTHER_UID, "")), "father_uid": str(Persons.g(p, Persons.FATHER_UID, "")),
		"kin": Persons.kin_of(e, f, p, Persons.head_of(f)) if loc["alive"] else "remembered ruler"}

## Existing offices only: valid registered adults, never fake names or new houses.
static func choices(game) -> Array:
	var out := []
	for town in game.world.get("towns", {}).values():
		var e: Dictionary = town.get("econ", {})
		var head: Dictionary = e.get("head", {})
		var loc := _person(game, String(head.get("person_uid", "")))
		if loc.is_empty(): continue
		var p: Array = loc["person"]
		var f: Dictionary = loc["family"]
		if f.get("gone", false): continue
		out.append({"town_id": String(town["id"]), "town_name": String(town["name"]),
			"faction_id": String(town.get("faction", "")), "culture": String(e.get("culture", "middle")),
			"house_uid": String(head["house_uid"]), "household_uid": String(f["household_uid"]),
			"estate_household_uid": str(head.get("household_uid", f["household_uid"])),
			"house_name": String(f["name"]), "family_id": int(loc["family"]["id"]),
			"ruler_town_id": String(loc["town"]["id"]), "ruler_uid": String(head["person_uid"]),
			"ruler_name": Persons.name_of(loc["family"], p, Persons.race_of(loc["econ"])),
			"ruler_age": Persons.age_of(p, float(game.day)), "ruler_sex": int(p[2]), "title": String(head.get("title", "Ruler"))})
	out.sort_custom(func(a, b): return String(a["town_name"]) < String(b["town_name"]) if a["town_name"] != b["town_name"] else String(a["town_id"]) < String(b["town_id"]))
	return out

## One initial choice. Position the existing party; troop and money owners stay
## exactly as generated. A repeated choice cannot switch houses or reset travel.
static func select_city(game, town_id: String) -> bool:
	if not (game.world.get("player_house", {}) as Dictionary).is_empty(): return false
	var pick := {}
	for row in choices(game):
		if String(row["town_id"]) == town_id: pick = row; break
	if pick.is_empty(): return false
	var town: Dictionary = game.world["towns"][town_id]
	var party: Dictionary = game.world.get("party", {})
	if party.is_empty(): return false
	game.world["player_house"] = {"town_id": town_id, "house_uid": pick["house_uid"],
		"household_uid": pick["household_uid"], "ruler_uid": pick["ruler_uid"],
		"estate_household_uid": pick["estate_household_uid"],
		"house_name": pick["house_name"], "ruler_name": pick["ruler_name"], "title": pick["title"],
		"ruler_sex": pick["ruler_sex"], "ruler_race": Persons.race_of(town["econ"]),
		"leader_uid": pick["ruler_uid"], "native_house_name": pick["house_name"], "selection_kind": "office", "leadership_mode": "office", "holds_office": true}
	var pos: Vector2 = town["pos"]
	party["pos"] = CampaignWorld.nearest_passable(game.world, pos) if String(game.world.get("terrain", "")) != "" else pos
	party["target"] = party["pos"]; party["path"] = []; party["dest_town"] = ""
	party["arrived"] = ""; party["waiting"] = false
	game.world["start_town"] = town_id
	game.location = town_id
	game.changed.emit()
	return true

static func selected(game) -> Dictionary:
	var state: Dictionary = game.world.get("player_house", {})
	if state.is_empty(): return {}
	var out := state.duplicate(true)
	var town: Dictionary = game.world.get("towns", {}).get(String(state.get("town_id", "")), {})
	out["town_name"] = String(town.get("name", "")); out["faction_id"] = String(town.get("faction", ""))
	var loc := _person(game, String(state.get("ruler_uid", "")))
	out["current_town_id"] = String(loc.get("town", {}).get("id", ""))
	out["current_family_id"] = int(loc.get("family", {}).get("id", -1))
	var home := _household(game, String(state.get("household_uid", "")))
	out["house_town_id"] = String(home.get("town", {}).get("id", ""))
	out["house_family_id"] = int(home.get("family", {}).get("id", -1))
	out["native_house_name"] = str(home.get("family", {}).get("name", state.get("native_house_name", state.get("house_name", "House"))))
	out["house_name"] = str(state.get("customization", {}).get("display_name", out["native_house_name"]))
	out["leader_uid"] = str(state.get("ruler_uid", ""))
	out["holds_office"] = holds_office(game, loc)
	out["selection_kind"] = "office" if out["holds_office"] else "household"
	out["leadership_mode"] = out["selection_kind"]
	return out

## Exact office identity, not a cosmetic name or shared birth-house affiliation.
static func holds_office(game, loc: Dictionary = {}) -> bool:
	var state: Dictionary = game.world.get("player_house", {})
	if state.is_empty(): return false
	var h: Dictionary = game.world.get("towns", {}).get(str(state.get("town_id", "")), {}).get("econ", {}).get("head", {})
	var uid := str(state.get("ruler_uid", ""))
	if uid == "" or uid != str(h.get("person_uid", "")): return false
	if loc.is_empty(): loc = _person(game, uid)
	return not loc.is_empty() and loc.get("alive", false) and str(loc["family"].get("household_uid", "")) == str(state.get("household_uid", ""))

## Reads never appoint; succession_day is the explicit mutation boundary.
static func ruler(game) -> Dictionary:
	var state: Dictionary = game.world.get("player_house", {})
	if state.is_empty(): return {}
	var uid := String(state.get("ruler_uid", ""))
	var loc := _person(game, uid, true)
	if not loc.is_empty():
		var title := "House leader"
		if holds_office(game, loc): title = str(game.world["towns"][state["town_id"]]["econ"]["head"].get("title", "Ruler"))
		var row: Dictionary = _row(loc, float(game.day), title)
		var unit: Unit = bound_unit(game, row)
		if unit != null and unit.dead: row["alive"] = false
		row["holds_office"] = holds_office(game, loc)
		return row
	return {"person_uid": uid, "house_uid": String(state.get("house_uid", "")),
		"name": String(state.get("ruler_name", "Unknown ruler")), "title": String(state.get("title", "Ruler")),
		"race": String(state.get("ruler_race", "human")), "sex": int(state.get("ruler_sex", 0)),
		"alive": false, "town_id": "", "family_id": -1, "pid": -1}

static func living_members(game) -> Array:
	var state: Dictionary = game.world.get("player_house", {})
	if state.is_empty(): return []
	var house_uid := String(state.get("house_uid", ""))
	var out := []
	var seen := {}
	for town in game.world.get("towns", {}).values():
		var e: Dictionary = town.get("econ", {})
		for f in e.get("fams", []):
			for p in f.get("pp", []) + f.get("kp", []):
				var uid := str(Persons.g(p, Persons.PERSON_UID, ""))
				if not _living(game, String(town.get("id", "")), f, p) or uid == "" or seen.has(uid) or str(Persons.g(p, Persons.HOUSE_UID, "")) != house_uid: continue
				seen[uid] = true
				out.append(_row({"town": town, "econ": e, "family": f, "person": p, "alive": true}, float(game.day), String(state.get("title", "")) if uid == String(state.get("ruler_uid", "")) else ""))
	out.sort_custom(func(a, b): return String(a["person_uid"]) < String(b["person_uid"]))
	return out

static func is_extinct(game) -> bool:
	return not (game.world.get("player_house", {}) as Dictionary).is_empty() and living_members(game).is_empty()

## Four real holders. There is no dynasty wallet and no alias of company gold.
static func accounts(game) -> Dictionary:
	var state: Dictionary = game.world.get("player_house", {})
	if state.is_empty(): return {}
	var town: Dictionary = game.world.get("towns", {}).get(String(state["town_id"]), {})
	var fid := String(town.get("faction", ""))
	var home := _household(game, String(state["household_uid"]))
	return {"house_purse": float(home.get("family", {}).get("purse", 0.0)),
		"city_treasury": float(town.get("econ", {}).get("treasury", 0.0)),
		"faction_treasury": float(game.world.get("factions", {}).get(fid, {}).get("treasury", 0.0)),
		"company_wallet": float(game.gold), "household_uid": String(state["household_uid"]),
		"estate_household_uid": str(state.get("estate_household_uid", state["household_uid"])),
		"house_town_id": String(home.get("town", {}).get("id", "")),
		"house_family_id": int(home.get("family", {}).get("id", -1)), "city_town_id": String(state["town_id"]), "faction_id": fid}

## Native Portrait.set_spec input. Stable person seed; no temporary combat Unit.
static func portrait_spec(game) -> Dictionary:
	var r := ruler(game)
	return portrait_for(game, r, game.world.get("player_house", {}).get("customization", {}))

## Pure candidate/current leader appearance without selecting a campaign house.
static func portrait_for(game, r: Dictionary, custom: Dictionary = {}) -> Dictionary:
	if r.is_empty(): return {}
	var town: Dictionary = game.world.get("towns", {}).get(str(r.get("town_id", "")), {})
	var race := String(r.get("race", "human"))
	var cols := FigurePainter.faction_colors(String(town.get("faction", "")))
	var seed_v := int(hash(String(r.get("person_uid", "")))) & 0x7fffffff
	var spec := FigurePainter.spec_generic(race, cols[0], cols[1], seed_v)
	# Reuse an existing registered unit's identity and actual traded equipment.
	# Household-only people keep their deterministic native person appearance.
	var bound: Unit = bound_unit(game, r)
	if bound != null: spec = FigurePainter.spec_for_unit(bound)
	spec["sex"] = "female" if int(r.get("sex", 0)) == 1 else "male"
	spec["age"] = int(r.get("age", 30))
	if int(r.get("sex", 0)) == 1:
		spec["beard"] = false
		spec["female_set"] = FigurePainter.female_variant(spec)
	elif bool(spec.get("beard", false)) and race in ["human", "orc", "dwarf"]:
		spec["beard_style"] = FigurePainter.beard_style(spec)
	spec["dead"] = not bool(r.get("alive", false)); spec["role"] = "ruler"
	for entry in [["primary_color", "prim"], ["secondary_color", "sec"]]:
		var color := str(custom.get(entry[0], ""))
		if color.length() == 7 and Color.html_is_valid(color): spec[entry[1]] = Color(color)
	return spec

static func bound_unit(game, r: Dictionary) -> Unit:
	var uid := int(r.get("unit_uid", -1))
	if uid < 0: return null
	var tid := str(r.get("town_id", "")); var fid := int(r.get("family_id", -1)); var race := str(r.get("race", ""))
	var reserve: Unit = Mobilization.reserve_unit(game, uid, tid, fid)
	if reserve != null and reserve.race == race: return reserve
	for u in game.company:
		if u is Unit and u.uid == uid and u.home_town == tid and u.family == fid and u.race == race: return u
	for u in game.world.get("towns", {}).get(tid, {}).get("recruits", []):
		if u is Unit and u.uid == uid and u.home_town == tid and u.family == fid and u.race == race: return u
	for band in game.world.get("warbands", {}).values():
		for u in band.get("units", []):
			if u is Unit and u.uid == uid and u.home_town == tid and u.family == fid and u.race == race: return u
	for u in CampaignWorld.mustering_units(game.world):
		if u is Unit and u.uid == uid and u.home_town == tid and u.family == fid and u.race == race: return u
	return null

# v0.002: genealogy is a reference index, never another population/account.
# Dead ancestors remain here after bounded household memories are trimmed.
static func _book(w: Dictionary) -> Dictionary:
	if not w.has("dynasty"): w["dynasty"] = {"kin": {}, "houses": {}, "rulers": {}, "day": -1}
	return w["dynasty"]

static func _remember(w: Dictionary, e: Dictionary, f: Dictionary, p: Array, alive: bool, race: String = "") -> void:
	var uid := str(Persons.g(p, Persons.PERSON_UID, ""))
	var house := str(Persons.g(p, Persons.HOUSE_UID, ""))
	if uid == "" or house == "": return
	var b := _book(w)
	# Anonymous pool owners need no genealogy until one actually holds office.
	if f.get("cohort", false) and not b["houses"].has(house) and house != str(w.get("player_house", {}).get("house_uid", "")): return
	var old: Dictionary = b["kin"].get(uid, {})
	b["kin"][uid] = {"house_uid": house, "born": float(p[3]), "sex": int(p[2]),
		"race": race if race != "" else Persons.race_of(e), "mother_uid": str(Persons.g(p, Persons.MOTHER_UID, old.get("mother_uid", ""))),
		"father_uid": str(Persons.g(p, Persons.FATHER_UID, old.get("father_uid", ""))), "alive": alive}

## Native birth/death callers preserve ancestry before household memory trimming.
static func record_person(e: Dictionary, f: Dictionary, p: Array, alive: bool = true) -> void:
	# Native forget/sync also records false; Mobilization retains proven living
	# physical holders, and retires only exact unheld/dead identity bookkeeping.
	if not alive: Mobilization.retire_person(Game, e, f, p)
	_remember(Game.world, e, f, p, alive)

## Only a current reigning mother's newborns keep her political lineage when
## marriage placed her in another household. Existing adults/owners stay put.
static func birth_house(_e: Dictionary, _f: Dictionary, mother: Array) -> String:
	var uid := str(Persons.g(mother, Persons.PERSON_UID, ""))
	return str(Game.world.get("dynasty", {}).get("rulers", {}).get(uid, ""))

static func _index_world(game) -> void:
	var b := _book(game.world)
	var kin: Dictionary = b["kin"]
	var houses: Dictionary = b["houses"]
	b["rulers"] = {}
	for town in game.world.get("towns", {}).values():
		var h: Dictionary = town.get("econ", {}).get("head", {})
		if str(h.get("house_uid", "")) != "": b["houses"][str(h["house_uid"])] = true
		if str(h.get("person_uid", "")) != "": b["rulers"][str(h["person_uid"])] = str(h.get("house_uid", ""))
	for uid in kin: kin[uid]["alive"] = false
	var races := {}
	# Memories first; the single current living record wins over migration copies.
	for memory in [true, false]:
		var is_memory: bool = memory
		var books: Array = ["dp"] if is_memory else ["pp", "kp"]
		for tid in game.world.get("towns", {}):
			var town: Dictionary = game.world["towns"][tid]
			var town_id := str(town.get("id", ""))
			var e: Dictionary = town.get("econ", {})
			var race := str(races.get(tid, ""))
			for f in e.get("fams", []):
				var cohort: bool = f.get("cohort", false)
				var estate: bool = f.get("estate", false)
				var gone: bool = f.get("gone", false)
				for key in books:
					for p in f.get(key, []):
						var size: int = p.size()
						var house := str(p[Persons.HOUSE_UID]) if size > Persons.HOUSE_UID else ""
						# Apply exactly _remember's exclusion before any live-record
						# lookup; individual pool members can retain another lineage.
						if house == "" or (cohort and not houses.has(house) and house != str(game.world.get("player_house", {}).get("house_uid", ""))): continue
						var uid := str(p[Persons.PERSON_UID]) # HOUSE_UID follows PERSON_UID.
						if uid == "": continue
						var live := false
						if not is_memory and not estate:
							var state := String(p[4])
							if state != "gone" and state != "dead":
								live = not gone or _living(game, town_id, f, p)
						var old: Dictionary = kin.get(uid, {})
						if not live and old.get("alive", false): continue
						if race == "": race = Persons.race_of(e); races[tid] = race
						# Already-validated _remember construction. Avoid resolving
						# identities/flags twice, and read remembered parent fallback
						# only when the native slot is genuinely absent.
						kin[uid] = {"house_uid": house, "born": float(p[3]), "sex": int(p[2]),
							"race": race, "mother_uid": str(p[Persons.MOTHER_UID]) if size > Persons.MOTHER_UID else str(old.get("mother_uid", "")),
							"father_uid": str(p[Persons.FATHER_UID]) if size > Persons.FATHER_UID else str(old.get("father_uid", "")), "alive": live}

static func law(game, town_id: String) -> String:
	var e: Dictionary = game.world.get("towns", {}).get(town_id, {}).get("econ", {})
	match Persons.race_of(e):
		"human", "dwarf": return "male_preference"
		"elf", "moon_elf", "high_elf", "wood_elf": return "absolute"
		"orc": return "strength"
	return "native_" + str(TownEcon.culture_of(e).get("rank_rule", "renown")) if not e.is_empty() else "vacant"

## Query-local indexes retain native references; no read cache survives a call.
static func _child_index(nodes: Dictionary, house: String, policy: String) -> Dictionary:
	var children := {}
	for child in nodes:
		var n: Dictionary = nodes[child]
		if str(n["house_uid"]) != house: continue
		var mother := str(n["mother_uid"]); var father := str(n["father_uid"])
		var parents: Array = [mother] if mother == father else [mother, father]
		for parent in parents:
			# The old OR test included a child once when both links agreed.
			if parent == "": continue
			if not children.has(parent): children[parent] = []
			children[parent].append(str(child))
	for rows in children.values():
		rows.sort_custom(func(a, b):
			if policy == "male_preference" and int(nodes[a]["sex"]) != int(nodes[b]["sex"]): return int(nodes[a]["sex"]) < int(nodes[b]["sex"])
			return float(nodes[a]["born"]) < float(nodes[b]["born"]) if float(nodes[a]["born"]) != float(nodes[b]["born"]) else str(a) < str(b))
	return children

static func _live_town_addresses(game, town: Dictionary) -> Dictionary:
	var addresses := {}
	var e: Dictionary = town.get("econ", {})
	for f in e.get("fams", []):
		for key in ["pp", "kp"]:
			for p in f.get(key, []):
				var uid := str(Persons.g(p, Persons.PERSON_UID, ""))
				if uid == "" or addresses.has(uid) or not _living(game, str(town.get("id", "")), f, p): continue
				addresses[uid] = {"town": town, "econ": e, "family": f, "person": p, "alive": true}
	return addresses

static func _query_person(game, uid: String, query: Dictionary) -> Dictionary:
	if uid == "": return {}
	if not query.has("town_addresses"): query["town_addresses"] = {}
	var towns: Dictionary = game.world.get("towns", {})
	var parts := uid.split(":")
	var origin := str(parts[2]) if parts.size() == 4 else ""
	var local: Dictionary = query["town_addresses"]
	if towns.has(origin):
		if not local.has(origin): local[origin] = _live_town_addresses(game, towns[origin])
		if local[origin].has(uid): return local[origin][uid]
	if not query.has("addresses"):
		var addresses := {}
		for tid in towns:
			if not local.has(tid): local[tid] = _live_town_addresses(game, towns[tid])
			for person_uid in local[tid]:
				if not addresses.has(person_uid): addresses[person_uid] = local[tid][person_uid]
		query["addresses"] = addresses
	return query["addresses"].get(uid, {})

static func _branch(nodes: Dictionary, uid: String, house: String, children: Dictionary, seen: Dictionary, out: Array) -> void:
	if uid == "" or seen.has(uid) or not nodes.has(uid) or str(nodes[uid]["house_uid"]) != house: return
	seen[uid] = true
	if nodes[uid].get("alive", false): out.append(uid)
	for child in children.get(uid, []): _branch(nodes, child, house, children, seen, out)

## Descendant branches precede siblings; a dead eldest child's children retain
## that branch's precedence. Same-house ancestors provide real collateral kin.
static func heirs(game, town_id: String) -> Array:
	var h: Dictionary = game.world.get("towns", {}).get(town_id, {}).get("econ", {}).get("head", {})
	var policy := law(game, town_id)
	return _lineage_heirs(game, str(h.get("person_uid", "")), str(h.get("house_uid", "")), policy)

static func _lineage_heirs(game, uid: String, house: String, policy: String) -> Array:
	return _lineage_query(game, uid, house, policy, {})

static func _lineage_query(game, uid: String, house: String, policy: String, query: Dictionary) -> Array:
	if not policy in ["male_preference", "absolute"]: return []
	var nodes: Dictionary = game.world.get("dynasty", {}).get("kin", {})
	if not nodes.has(uid): return []
	var children := _child_index(nodes, house, policy)
	var seen := {uid: true}; var ordered := []
	for child in children.get(uid, []): _branch(nodes, child, house, children, seen, ordered)
	var ancestors := [uid]; var walked := {}
	while not ancestors.is_empty():
		var ancestor: String = ancestors.pop_front()
		if walked.has(ancestor) or not nodes.has(ancestor): continue
		walked[ancestor] = true
		for field in ["father_uid", "mother_uid"]:
			var parent := str(nodes[ancestor].get(field, ""))
			if parent == "" or not nodes.has(parent) or str(nodes[parent]["house_uid"]) != house: continue
			for child in children.get(parent, []): _branch(nodes, child, house, children, seen, ordered)
			# A still-living parent is real kin after descendant/sibling branches.
			_branch(nodes, parent, house, children, seen, ordered)
			ancestors.append(parent)
	var out := []
	for person_uid in ordered:
		var loc := _query_person(game, str(person_uid), query)
		if not loc.is_empty(): out.append(_row(loc, float(game.day)))
	return out

## Private assets follow the stored owner's real lineage, never a replacement
## title holder or estate's current culture. Safe for living gifted non-rulers
## and retained dead ancestors after their bounded household memory is trimmed.
static func asset_heirs(game, owner_person_uid: String, owner_house_uid: String) -> Array:
	var nodes: Dictionary = game.world.get("dynasty", {}).get("kin", {})
	var owner: Dictionary = nodes.get(owner_person_uid, {})
	if owner_person_uid == "" or owner_house_uid == "" or owner.is_empty() or str(owner.get("house_uid", "")) != owner_house_uid: return []
	var policy := ""
	match str(owner.get("race", "")):
		"human", "dwarf": policy = "male_preference"
		"elf", "moon_elf", "high_elf", "wood_elf": policy = "absolute"
		"orc": policy = "strength"
		_: return [] # Unconfigured native civil laws have no invented asset law.
	var candidates: Array = []
	var query := {}
	if policy == "strength":
		# Reuse an already-bound native winner; do not calculate a new contest.
		# An unrelated usurper cannot acquire the dead house's private assets.
		var town_ids: Array = game.world.get("towns", {}).keys(); town_ids.sort()
		var seen := {}
		for tid in town_ids:
			if law(game, str(tid)) != "strength": continue
			var head: Dictionary = game.world["towns"][tid].get("econ", {}).get("head", {})
			var uid := str(head.get("person_uid", ""))
			if uid == "" or uid == owner_person_uid or seen.has(uid) or str(head.get("house_uid", "")) != owner_house_uid: continue
			var fac: Dictionary = game.world.get("factions", {}).get(str(game.world["towns"][tid].get("faction", "")), {})
			var leader: Dictionary = fac.get("war_leader", {})
			if str(fac.get("capital", "")) == str(tid) and leader.has("person_uid") and str(leader["person_uid"]) != uid: continue
			seen[uid] = true
			var loc: Dictionary = _query_person(game, uid, query)
			if not loc.is_empty(): candidates.append(_row(loc, float(game.day), str(head.get("title", "Ruler"))))
	else: candidates = _lineage_query(game, owner_person_uid, owner_house_uid, policy, query)
	var out := []
	for candidate in candidates:
		var uid := str(candidate.get("person_uid", ""))
		var loc: Dictionary = _query_person(game, uid, query)
		if loc.is_empty(): continue
		var f: Dictionary = loc["family"]; var p: Array = loc["person"]
		if f.get("cohort", false) or f.get("estate", false): continue
		var household := str(f.get("household_uid", ""))
		if household == "" or str(Persons.g(p, Persons.PERSON_UID, "")) != uid or str(Persons.g(p, Persons.HOUSE_UID, "")) != owner_house_uid: continue
		if str(candidate.get("household_uid", "")) != household or str(candidate.get("house_uid", "")) != owner_house_uid: continue
		out.append(candidate)
	return out

static func heir(game, town_id: String) -> Dictionary:
	var rows := heirs(game, town_id)
	return rows[0] if not rows.is_empty() else {}

## Private campaign leadership is independent of the settlement's lord. Real
## office holders retain exactly the existing town succession policy above.
static func leadership_law(game) -> String:
	var state: Dictionary = game.world.get("player_house", {})
	if state.is_empty(): return "vacant"
	if holds_office(game): return law(game, str(state.get("town_id", "")))
	var owner: Dictionary = game.world.get("dynasty", {}).get("kin", {}).get(str(state.get("ruler_uid", "")), {})
	var race := str(owner.get("race", state.get("ruler_race", "")))
	match race:
		"human", "dwarf": return "male_preference"
		"elf", "moon_elf", "high_elf", "wood_elf": return "absolute"
	return "household_head" # Existing civilian head rule, not an orc military contest.

static func selected_heir(game) -> Dictionary:
	var state: Dictionary = game.world.get("player_house", {})
	if state.is_empty(): return {}
	if holds_office(game): return heir(game, str(state.get("town_id", "")))
	var policy := leadership_law(game)
	if policy in ["male_preference", "absolute"]:
		var rows: Array = _lineage_heirs(game, str(state.get("ruler_uid", "")), str(state.get("house_uid", "")), policy)
		return rows[0] if not rows.is_empty() else {}
	var home: Dictionary = _household(game, str(state.get("household_uid", "")))
	var f: Dictionary = home.get("family", {})
	if f.is_empty() or not f.has("pp"): return {}
	var view: Dictionary = f.duplicate()
	view["pp"] = f["pp"].filter(func(p):
		return str(Persons.g(p, Persons.HOUSE_UID, "")) == str(state.get("house_uid", "")) and str(Persons.g(p, Persons.PERSON_UID, "")) != str(state.get("ruler_uid", "")) and _living(game, str(home["town"]["id"]), f, p))
	var p: Array = Persons.head_of(view)
	if p.is_empty(): return {}
	return _row({"town": home["town"], "econ": home["town"]["econ"], "family": f, "person": p, "alive": true}, float(game.day), "House leader")

static func selected_office(game) -> Dictionary:
	var state: Dictionary = game.world.get("player_house", {})
	if state.is_empty(): return {}
	if holds_office(game): return town_office(game, str(state.get("town_id", "")))
	var row: Dictionary = ruler(game)
	row["law"] = leadership_law(game); row["office_uid"] = ""; row["office_town_id"] = ""
	row["holds_office"] = false; row["vacant"] = not bool(row.get("alive", false))
	row["regency"] = bool(row.get("alive", false)) and int(row.get("age", 999)) < int(People.ages(str(row.get("race", "human")))["adult"])
	row["regent_uid"] = ""; row["heir_uid"] = str(selected_heir(game).get("person_uid", ""))
	return row

static func person(game, person_uid: String) -> Dictionary:
	return _row(_person(game, person_uid, true), float(game.day))

static func town_office(game, town_id: String) -> Dictionary:
	var h: Dictionary = game.world.get("towns", {}).get(town_id, {}).get("econ", {}).get("head", {})
	if h.is_empty(): return {}
	var loc := _person(game, str(h.get("person_uid", "")), true)
	var row := _row(loc, float(game.day), str(h.get("title", "Ruler"))) if not loc.is_empty() else {"person_uid": str(h.get("person_uid", "")), "name": str(h.get("name", "")), "alive": false}
	row["office_uid"] = "office:%d:%s" % [int(game.world.get("seed", 0)), town_id]; row["office_town_id"] = town_id
	row["law"] = law(game, town_id); row["vacant"] = not row.get("alive", false)
	row["regency"] = row.get("alive", false) and int(row.get("age", 999)) < int(People.ages(str(row.get("race", "human")))["adult"])
	row["regent_uid"] = str(h.get("regent_uid", "")); row["economic_household_uid"] = str(h.get("household_uid", ""))
	row["heir_uid"] = str(heir(game, town_id).get("person_uid", ""))
	return row

## Political appointment does not seize household property or change loan owners.
static func appoint(game, town_id: String, person_uid: String, title: String = "") -> bool:
	var town: Dictionary = game.world.get("towns", {}).get(town_id, {})
	var h: Dictionary = town.get("econ", {}).get("head", {})
	var loc := _person(game, person_uid)
	if h.is_empty() or loc.is_empty(): return false
	var p: Array = loc["person"]; var f: Dictionary = loc["family"]
	h["person_uid"] = person_uid; h["house_uid"] = str(p[Persons.HOUSE_UID])
	h["pid"] = int(p[0]); h["home_town"] = str(loc["town"]["id"])
	h["political_household_uid"] = str(f.get("household_uid", ""))
	h["name"] = Persons.name_of(f, p, Persons.race_of(loc["econ"]))
	if title != "": h["title"] = title
	f["named"] = true; h["regent_uid"] = ""
	if Persons.age_of(p, float(game.day)) < int(People.ages(Persons.race_of(loc["econ"]))["adult"]):
		var candidates := []
		for home in game.world.get("towns", {}).values():
			for family in home.get("econ", {}).get("fams", []):
				for q in family.get("pp", []):
					if str(Persons.g(q, Persons.HOUSE_UID, "")) == str(h["house_uid"]) and _living(game, str(home["id"]), family, q) and Persons.age_of(q, float(game.day)) >= int(People.ages(Persons.race_of(home["econ"]))["adult"]): candidates.append(q)
		candidates.sort_custom(func(a, b): return float(a[3]) < float(b[3]) if float(a[3]) != float(b[3]) else str(a[Persons.PERSON_UID]) < str(b[Persons.PERSON_UID]))
		if not candidates.is_empty(): h["regent_uid"] = str(candidates[0][Persons.PERSON_UID])
	var state: Dictionary = game.world.get("player_house", {})
	var following_office: bool = str(state.get("leadership_mode", "office")) == "office" and str(state.get("house_uid", "")) == str(h["house_uid"])
	if str(state.get("town_id", "")) == town_id and (following_office or str(state.get("ruler_uid", "")) == person_uid):
		if not state.has("estate_household_uid"): state["estate_household_uid"] = str(state.get("household_uid", ""))
		state["household_uid"] = str(f.get("household_uid", ""))
		state["ruler_uid"] = person_uid; state["ruler_name"] = str(h["name"])
		state["ruler_sex"] = int(p[2]); state["ruler_race"] = Persons.race_of(loc["econ"]); state["title"] = str(h.get("title", "Ruler"))
		state["leader_uid"] = person_uid; state["leadership_mode"] = "office"; state["selection_kind"] = "office"; state["holds_office"] = true
	_index_world(game)
	return true

## Existing army contest winner is the orc sovereign, even when his household
## is in another town. No civilian names or capital wallets are substituted.
static func appoint_unit(game, town_id: String, u: Unit, title: String = "") -> bool:
	var h: Dictionary = game.world.get("towns", {}).get(town_id, {}).get("econ", {}).get("head", {})
	if h.is_empty() or u == null or u.dead: return false
	if Population.promote_ruler(game, u).is_empty(): return false
	var town: Dictionary = game.world.get("towns", {}).get(u.home_town, {})
	var f: Dictionary = People.fam_of(town, u.family)
	var p: Array = Persons.by_uid(f, u.uid)
	return not p.is_empty() and appoint(game, town_id, str(Persons.g(p, Persons.PERSON_UID, "")), title)

static func bind_war_leader(game, faction_id: String, u: Unit, title: String) -> void:
	var fac: Dictionary = game.world.get("factions", {}).get(faction_id, {})
	var cap := str(fac.get("capital", ""))
	if not appoint_unit(game, cap, u, title): return
	var uid := str(game.world["towns"][cap]["econ"]["head"]["person_uid"])
	fac["war_leader"]["person_uid"] = uid

static func succession_day(game) -> void:
	var index_started := Time.get_ticks_usec()
	_index_world(game)
	Perf.record_us("Native genealogy indexing", Time.get_ticks_usec() - index_started)
	var office_started := Time.get_ticks_usec()
	for tid in game.world.get("towns", {}):
		var town: Dictionary = game.world["towns"][tid]
		var h: Dictionary = town.get("econ", {}).get("head", {})
		if h.is_empty() or not _person(game, str(h.get("person_uid", ""))).is_empty(): continue
		var policy := law(game, str(tid))
		if policy in ["male_preference", "absolute"]:
			var next := heir(game, str(tid))
			if not next.is_empty() and appoint(game, str(tid), str(next["person_uid"])):
				CampaignWorld.log_event(game, "%s inherited the rule of %s." % [next["name"], town["name"]])
		elif policy == "strength":
			# Capital is filled solely by Army's existing real combat contests.
			var fac: Dictionary = game.world.get("factions", {}).get(str(town.get("faction", "")), {})
			if str(fac.get("capital", "")) == str(tid): continue
			var best: Unit = null; var power := -INF
			for u in Militia.units_of(game, str(tid)):
				var score := CampaignWorld.unit_power(u)
				if score > power and not Persons.by_uid(People.fam_of(town, u.family), u.uid).is_empty(): best = u; power = score
			if best != null:
				appoint_unit(game, str(tid), best)
	_house_succession(game)
	Perf.record_us("Office succession", Time.get_ticks_usec() - office_started)

static func _house_succession(game) -> void:
	var state: Dictionary = game.world.get("player_house", {})
	if state.is_empty(): return
	var current: Dictionary = _person(game, str(state.get("ruler_uid", "")))
	if current.is_empty():
		var head: Dictionary = game.world.get("towns", {}).get(str(state.get("town_id", "")), {}).get("econ", {}).get("head", {})
		# A dead selected office holder still follows the native office procedure,
		# including a pending orc contest. Do not replace that with civilian heads.
		if str(state.get("leadership_mode", "office")) == "office" and str(head.get("house_uid", "")) == str(state.get("house_uid", "")): return
		var next: Dictionary = selected_heir(game)
		if next.is_empty(): return
		state["ruler_uid"] = next["person_uid"]; state["leader_uid"] = next["person_uid"]
		state["ruler_name"] = next["name"]; state["ruler_sex"] = next["sex"]; state["ruler_race"] = next["race"]
		state["household_uid"] = next["household_uid"]; state["title"] = "House leader"
		state["leadership_mode"] = "household"; state["selection_kind"] = "household"; state["holds_office"] = false
		CampaignWorld.log_event(game, "%s became the selected house's leader." % next["name"])
		current = _person(game, str(next["person_uid"]))
	if not current.is_empty():
		state["household_uid"] = str(current["family"].get("household_uid", ""))
		state["native_house_name"] = str(current["family"].get("name", state.get("native_house_name", "House")))
		state["house_name"] = str(state.get("customization", {}).get("display_name", state["native_house_name"]))
		state["holds_office"] = holds_office(game, current)

