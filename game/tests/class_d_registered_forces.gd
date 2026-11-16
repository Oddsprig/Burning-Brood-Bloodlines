extends RefCounted
## Presentation fixtures use actual generated forces and native drafting from real households.
## Supplied registered Units retain their person residence; exact drafts avoid donor surgery.
static func registered(game: Node, band: Dictionary) -> Dictionary:
	if band.is_empty() or (band.get("units", []) as Array).is_empty():
		return {"ok": false, "reason": "native force has no actual roster"}
	var seen: Dictionary = {}
	for unit: Unit in band["units"]:
		var town: Dictionary = game.world["towns"].get(unit.home_town, {})
		if unit.dead or town.is_empty() or unit.family < 0:
			return {"ok": false, "reason": "force %s Unit %d needs a living registered hometown/family" % [band.get("id", "?"), unit.uid]}
		var family: Dictionary = People.fam_of(town, unit.family)
		if family.is_empty():
			return {"ok": false, "reason": "native Unit %d has no actual hometown family" % unit.uid}
		var person: Array = Persons.by_uid(family, unit.uid)
		if person.is_empty() or int(person[5]) != unit.uid or unit.faction != band["faction"] or seen.has(unit.uid):
			return {"ok": false, "reason": "invalid/duplicate native person binding for Unit %d" % unit.uid}
		seen[unit.uid] = true
	return {"ok": true}

static func population(game: Node) -> int:
	var count: int = 0
	for town: Dictionary in game.world["towns"].values():
		if TownEcon.has_econ(town): count += Census.people(town["econ"])
	return count

## A field force drafted by the game; donors and their service ledgers are never edited.
static func spawn_exact(game: Node, faction: String, count: int, kind: String, pos: Vector2, rng: RandomNumberGenerator) -> Dictionary:
	if kind not in ["patrol", "raider"] or count <= 0:
		return {"ok": false, "reason": "native exact draft supports only positive patrol/raider requests"}
	var home: String = ""
	var available: int = -1
	var town_ids: Array = game.world["towns"].keys()
	town_ids.sort()
	for tid: String in town_ids:
		var town: Dictionary = game.world["towns"][tid]
		if str(town["faction"]) != faction or not TownEcon.has_econ(town): continue
		var pool: Array = People.draft_pool(town)
		if pool.size() > available:
			available = pool.size()
			home = tid
	if home == "" or available < count:
		return {"ok": false, "reason": "%s needs %d real draftable residents; best native pool has %d" % [faction, count, available]}
	var before_people: int = population(game)
	var before_coin: float = Barge.holdings(game)
	var id: String = CampaignWorld.spawn_warband(game, faction, pos, count, kind, rng, {"home": home})
	if id == "" or not game.world["warbands"].has(id):
		return {"ok": false, "reason": "native draft refused %s/%s; no fabricated roster fallback" % [faction, kind]}
	var band: Dictionary = game.world["warbands"][id]
	var valid: Dictionary = registered(game, band)
	var reason: String = str(valid.get("reason", ""))
	if str(band["faction"]) != faction or str(band["kind"]) != kind or (band["units"] as Array).size() != count:
		reason = "native draft did not accept the exact requested faction/kind/count"
	if population(game) != before_people or absf(Barge.holdings(game) - before_coin) >= 0.01:
		reason = "needs game fix: campaign/world_warbands.gd native draft changed population or total coin"
	if reason != "":
		for unit: Unit in band["units"]:
			if not unit.dead: Army.release(game, unit, "fled")
		CampaignWorld.remove_warband(game, id)
		return {"ok": false, "reason": reason}
	return {"ok": true, "id": id}

## Select a whole existing record. No patrol-shaped caravan/militia, donor extraction or rollback debt.
static func existing(game: Node, faction: String, kind: String, excluded: Array) -> Dictionary:
	var ids: Array = game.world["warbands"].keys()
	ids.sort()
	var rejected: Array[String] = []
	for id: String in ids:
		if excluded.has(id): continue
		var band: Dictionary = game.world["warbands"][id]
		if str(band["faction"]) != faction or str(band["kind"]) != kind: continue
		var valid: Dictionary = record(game, band)
		if not bool(valid["ok"]):
			rejected.append(id + ": " + str(valid.get("reason", "")))
			continue
		return {"ok": true, "id": id}
	return {"ok": false, "reason": "native token scene needs an actual %s/%s force; rejected=%s" % [faction, kind, rejected]}

static func record(game: Node, band: Dictionary) -> Dictionary:
	var valid: Dictionary = registered(game, band)
	if not bool(valid["ok"]): return valid
	var home: String = str(band.get("home", ""))
	var kind: String = str(band.get("kind", ""))
	if kind == "caravan":
		for key: String in ["origin", "dest", "leg", "cargo", "gold", "escort", "away", "state", "depart_day", "path", "crew"]:
			if not band.has(key): return {"ok": false, "reason": "native caravan is missing " + key}
		var origin: String = str(band["origin"])
		var dest: String = str(band["dest"])
		if not game.world["towns"].has(origin) or not game.world["towns"].has(dest) or origin != home:
			return {"ok": false, "reason": "native caravan needs actual origin/destination towns and its real origin home"}
		var leg: String = str(band["leg"])
		if leg == "out":
			if origin == dest:
				return {"ok": false, "reason": "outbound native caravan needs a distinct destination"}
		elif leg == "home":
			var last_dest: String = str(band.get("last_dest", ""))
			if dest != origin or not game.world["towns"].has(last_dest) or last_dest == origin:
				return {"ok": false, "reason": "returning native caravan needs its actual previous destination and home route"}
		else:
			return {"ok": false, "reason": "unknown native caravan leg: " + leg}
		if (band["crew"] as Array).size() != (band["units"] as Array).size() + People.DRIVERS:
			return {"ok": false, "reason": "native caravan must contain its complete actual guards/drivers"}
	elif kind == "militia":
		if str(game.world.get("militia", {}).get(home, "")) != str(band["id"]):
			return {"ok": false, "reason": "native militia must be the town's registered band"}
	elif str(band["faction"]) == "outlaws":
		if str(game.world.get("lairs", {}).get(home, {}).get("kind", "")) != "bandit_camp":
			return {"ok": false, "reason": "native outlaw force needs its actual bandit camp"}
	return {"ok": true}
