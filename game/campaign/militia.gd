class_name Militia
extends RefCounted
## Monsters wave 1, section C [ours, BB-like]: every town has a militia (a warband of kind "militia").
## - Sized by town size and wealth; belongs to that town (home) and its faction.
## - Equips from its own town: the faction's troop loadouts, quality and copper share from the town's smiths
##   (until the economy design lands).
## - Campaign map: a small static sprite that patrols near its town (short walks, long idles).
## - Off-screen auto-resolve against bandits, deserters, raiders at war with the town and animals near the town;
##   losses shrink it; it rebuilds one recruit every REBUILD_DAYS.
## - On a "defend the town" contract it deploys on the company's side as AI allies (Monsters.battle_extras);
##   the pay grows with the share of militia that survive (PAY_BONUS).
## world.militia[town id] = warband id.

const CHECK_DAYS := 0.1        # [ours] how often militia look for threats near town
const RADIUS := 110.0          # [ours] px around the town that the militia defends
const PATROL := 70.0           # [ours] px: patrol walk radius around the town
const REBUILD_DAYS := 2        # [ours] one new militiaman every N days while below strength
## War pick 3 (Douglas): the militia holds the walls unless it clearly outnumbers the enemy. It sallies out only
## when its power is at least 1.25 x theirs (was 0.6 x); otherwise it stays in town (war bands do not hunt it in the
## field, war_ai.gd) and the town is defended at the walls (a war band's assault, Diplomacy.war_assault_arrives).
const SALLY_RATIO := 1.25
const PAY_BONUS := 0.3        # [ours] defend pay x (1 + 0.3 x survivors share)
const NO_THREAT := ["militia", "caravan", "camp", "den"]

## [ours] hamlet 2-3 ... city 10-12: 2 + 2 x size + (wealth - 1) / 2
static func target_size(town: Dictionary) -> int:
	return TownDefence.militia_target(town)

static func band_of(game, tid: String) -> Dictionary:
	return game.world["warbands"].get(String(game.world.get("militia", {}).get(tid, "")), {})

static func units_of(game, tid: String) -> Array:
	var wb := band_of(game, tid)
	if wb.is_empty():
		return []
	return (wb["units"] as Array).filter(func(u): return not u.dead)

## One militiaman of the town: faction troop template, gear quality and copper share from the town's smiths.
## from_stock (economy spec 1): a militiaman raised during the campaign takes his gear out of the town's own
## arms stock (TownEcon.outfit_units: his rolled template when the stalls have one, else any piece for that
## slot, else nothing; the treasury pays the market) and comes from a family of the town. The militia of
## world generation keeps its rolled gear (pre-history).
static func make_unit(town: Dictionary, rng: RandomNumberGenerator, from_stock: bool = false) -> Unit:
	var fid: String = town["faction"]
	var u := CampaignWorld.make_resident_troop(rng, fid, town, int(town["wealth"]))
	u.title = "militia " + u.title
	u.home_town = town["id"]
	_from_family(town, u)
	if from_stock and TownEcon.has_econ(town):
		TownEcon.outfit_units(town, [u], 0.25)
		return u
	var copper := clampf(0.3 + 0.1 * int(town["wealth"]) + (0.25 if town.get("specialty", "") == "mining" else 0.0), 0.0, 0.95)
	var crafters: Dictionary = town.get("crafters", {})
	for slot in u.equip:
		var it: Item = u.equip[slot]
		if it.mat().get("kind", "") != "metal":
			continue
		var smith: Dictionary = crafters.get("weaponsmith" if it.is_weapon() else "armorsmith", {})
		it.quality = Factory.roll_quality(rng, float(smith.get("skill", 2)))
		var mats: Array = ["copper", "tin"] if it.is_weapon() else it.tmpl().get("materials", ["copper", "tin"])
		if mats.has("copper") and mats.has("tin"):
			it.material = "copper" if rng.randf() < copper else "tin"
	u.home_town = town["id"]
	return u

## Economy: a militiaman is a person of a town family (People.draw, role "militia"), named after it; the
## town treasury pays him into that family's purse (People.pay_militia). Own RNG: the band's rolls stay the same.
static func _from_family(town: Dictionary, u: Unit) -> void:
	if not TownEcon.has_econ(town):
		return
	var r := RandomNumberGenerator.new()
	r.seed = hash([town["id"], u.name, u.title, "militia"])   # not the uid: uids run on across new games
	var fid := People.draw(town, r, "militia")
	if fid >= 0:
		People.bind(town, fid, u, "militia")   # the militiaman IS the register person drawn
		Families.event(People.fam_of(town, fid), "joined", [u.name, "militia", "the militia of %s" % town["name"]], float(Game.day))

## Older saves: militiamen without a family record get one from their town.
static func adopt_families(game) -> void:
	for tid in game.world.get("militia", {}):
		var town: Dictionary = game.world["towns"].get(tid, {})
		var wb := band_of(game, tid)
		if wb.is_empty() or town.is_empty():
			continue
		for u in wb["units"]:
			if u.family < 0:
				u.home_town = tid
				_from_family(town, u)

## Every town has its militia band (created if missing, e.g. after the company beat it).
static func ensure_all(game, rng: RandomNumberGenerator) -> void:
	var w: Dictionary = game.world
	if not w.has("militia"):
		w["militia"] = {}
	var ids: Array = w["towns"].keys()
	ids.sort()
	for tid in ids:
		ensure(game, tid, rng)

static func ensure(game, tid: String, rng: RandomNumberGenerator, from_stock: bool = false) -> String:
	var w: Dictionary = game.world
	var town: Dictionary = w["towns"][tid]
	var have := String(w["militia"].get(tid, ""))
	if w["warbands"].has(have):
		return have
	var units := []
	for i in target_size(town):
		var u := make_unit(town, rng, from_stock)
		if u.family >= 0: units.append(u)
	var pos: Vector2 = town["pos"] + Vector2(rng.randf_range(-26, 26), rng.randf_range(16, 30))
	var wid := CampaignWorld.spawn_warband(game, town["faction"], pos, units.size(), "militia", rng,
		{"units": units, "home": tid, "anchor": town["pos"], "last_recruit": float(game.day)})
	w["militia"][tid] = wid
	TownDefence.set_muster(game, town, false)
	return wid

static func wants_recruit(game, tid: String, day: int) -> bool:
	var wb := band_of(game, tid)
	if wb.is_empty():
		return true
	return (wb["units"] as Array).size() < target_size(game.world["towns"][tid]) and float(day) - float(wb.get("last_recruit", 0.0)) > REBUILD_DAYS - 1.0   # daily check vs a fractional recruit day

## Daily work job: rebuild by one man (or recreate a destroyed militia).
static func recruit(game, tid: String, rng: RandomNumberGenerator) -> void:
	var w: Dictionary = game.world
	if not w["towns"].has(tid):
		return
	var wb := band_of(game, tid)
	if wb.is_empty():
		ensure(game, tid, rng, true)
		return
	var town: Dictionary = w["towns"][tid]
	if (wb["units"] as Array).size() < target_size(town):
		var u := make_unit(town, rng, true)
		if u.family >= 0:
			(wb["units"] as Array).append(u)
			TownDefence.set_muster(game, town, bool(wb.get("mustered", false)))
		wb["last_recruit"] = float(game.day)

## The fallen militia of a town after a battle; returns how many died.
static func bury_dead(game, tid: String) -> int:
	var wb := band_of(game, tid)
	if wb.is_empty():
		return 0
	var before := (wb["units"] as Array).size()
	var fallen := []
	for u in wb["units"]:
		if u.dead:
			People.casualty(game, u, "dead", "militia")   # economy: the family loses him
			fallen.append(u)
	ArmsTrade.field(game, fallen, {"band": wb}, wb["pos"])   # arms trade: the town gathers its own dead's kit
	wb["units"] = (wb["units"] as Array).filter(func(u): return not u.dead)
	return before - (wb["units"] as Array).size()

# ---------------------------------------------------------------- map
## Patrol: a short walk around the town now and then; mostly standing at the gate.
static func step(game, wb: Dictionary, dt: float, t: float, rng: RandomNumberGenerator) -> void:
	var w: Dictionary = game.world
	if wb.get("pasture_defence", false): return
	if wb.get("professional", false):
		TownDefence.guard_step(game, wb, dt)
		return
	if not wb.get("mustered", false): return
	if (wb["path"] as Array).is_empty():
		if float(wb["idle_until"]) > t:
			return
		if bool(wb.get("walls", false)):
			return   # holding the walls: no patrol walk until the threat is gone (tick)
		var goal: Vector2 = wb["anchor"] + Vector2(rng.randf_range(-PATROL, PATROL), rng.randf_range(-PATROL, PATROL))
		wb["path"] = CampaignWorld.find_path(w, wb["pos"], goal)
		if (wb["path"] as Array).is_empty():
			wb["idle_until"] = t + 1.0
			return
	if CampaignWorld._step_along(w, wb, CampaignWorld.WARBAND_SPEED * 0.5 * CampaignWorld.smooth_speed(w, wb, dt) * dt):
		wb["idle_until"] = t + rng.randf_range(0.6, 1.6)

## Is warband x a threat this militia fights?
static func is_threat(game, mil: Dictionary, x: Dictionary) -> bool:
	if Monsters.suspended_band(x): return false
	var w: Dictionary = game.world
	var k := String(x.get("kind", ""))
	if k in NO_THREAT or x["id"] == w.get("encounter", "") or x["id"] == game.contract.get("target_id", ""):
		return false
	if float(x.get("rest_until", 0.0)) > float(game.day):
		return false
	if k in ["beasts", "bandit"]:
		return true
	if k == "deserter" or Monsters.is_wild_faction(x["faction"]):
		return true
	return Diplomacy.fights(w, mil["faction"], x["faction"])   # the town's enemies per diplomacy (WAR or HOSTILE)

## Off-screen auto-resolve near towns (every CHECK_DAYS). Same power rule as CampaignWorld._warband_clashes.
static func tick(game, rng: RandomNumberGenerator) -> void:
	var w: Dictionary = game.world
	var r2 := RADIUS * RADIUS
	var powers := {}   # exact within this check; every fight clears it before another force is evaluated
	var threats := {}   # militia faction -> force id -> native verdict, invalidated with every fight
	var raid_towns := _raid_towns(w)
	# world size: the forces bucketed once by RADIUS cells, each town looks at the 3 x 3 cells round it (was every
	# force for every town), in the same order as before (the map's order of forces)
	var cells := {}
	var ids: Array = w["warbands"].keys()
	for order in ids.size():
		var x: Dictionary = w["warbands"][ids[order]]
		if String(x.get("kind", "")) in NO_THREAT:
			continue   # is_threat always rejects these kinds, including after another town's fight
		# Rejected native kinds do not need a creature scan of their entire
		# roster. Both original predicates are pure and keep the same candidates.
		if Monsters.suspended_band(x): continue
		var xp: Vector2 = x["pos"]
		var ck := Vector2i(floori(xp.x / RADIUS), floori(xp.y / RADIUS))
		if not cells.has(ck):
			cells[ck] = []
		(cells[ck] as Array).append(order)
	for tid in w.get("militia", {}):
		var mil: Dictionary = w["warbands"].get(String(w["militia"][tid]), {})
		if mil.is_empty() or (mil["units"] as Array).is_empty():
			continue
		# This policy has already been read for the stand-down decision. Reuse
		# it only until a native fight can change the political/service state.
		var known_policy := TownDefence.defence_policy(game, w["towns"][tid])
		if known_policy == "stand_down":
			TownDefence.set_muster(game, w["towns"][tid], false, false, known_policy)
			mil["walls"] = false
			continue # An explicit order declines militia callups and field combat.
		var tpos: Vector2 = w["towns"][tid]["pos"]
		var held := false
		var nearby: bool = raid_towns.has(tid)
		# Repeating an identical true muster only re-reads the same people and
		# writes the same service flags. Keep the first native transition, and
		# require another after any fight that may change those people/jobs.
		var mustered_here := false
		if nearby:
			TownDefence.set_muster(game, w["towns"][tid], true, false, known_policy)
			mustered_here = true
		var cand := PackedInt32Array()
		var tc := Vector2i(floori(tpos.x / RADIUS), floori(tpos.y / RADIUS))
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				cand.append_array(PackedInt32Array(cells.get(tc + Vector2i(dx, dy), [])))
		cand.sort()   # native ordinal sort retains the original force order without callback comparisons
		for ce in cand:
			var xid: String = ids[ce]
			var x: Dictionary = w["warbands"].get(xid, {})
			if x.is_empty() or (x["pos"] as Vector2).distance_squared_to(tpos) > r2 or not _tick_threat(game, mil, x, threats):
				continue
			nearby = true
			if not mustered_here:
				TownDefence.set_muster(game, w["towns"][tid], true, false, known_policy)
				mustered_here = true
			if x.has("raid"): continue
			var pa := _tick_power(mil, powers)
			var pb := _tick_power(x, powers)
			if not sallies(pa, pb):
				held = true   # too strong to meet outside: the militia stays in town
				continue
			_fight(game, tid, mil, x, rng, pa, pb)
			powers.clear()   # casualties, supplies and captured gear can change either side's power
			threats.clear()   # rest, removed forces, contract state and diplomacy may also have changed
			mustered_here = false
			known_policy = ""
			raid_towns = _raid_towns(w)   # the next town observes the forces remaining after this fight
			if (mil["units"] as Array).is_empty():
				break
		if not nearby: TownDefence.set_muster(game, w["towns"][tid], false, bool(mil.get("drill_today", false)), known_policy)
		if held != bool(mil.get("walls", false)):
			mil["walls"] = held
			if held:
				mil["path"] = [mil["anchor"]]   # back inside the gate (map), no patrol walks meanwhile

## Does a militia of power pa come out against a force of power pb? (war pick 3: only at 1.25 x or better)
static func sallies(pa: float, pb: float) -> bool:
	return pa >= SALLY_RATIO * pb

static func _tick_power(wb: Dictionary, powers: Dictionary) -> float:
	var wid: String = wb["id"]
	if not powers.has(wid):
		powers[wid] = CampaignWorld.band_power(wb["units"])
	return float(powers[wid])

## A verdict depends on the militia's faction and this force, not the town.
## The caller owns this dictionary for one synchronous tick and clears it
## after every fight; no roster, diplomacy or contract mutation survives it.
static func _tick_threat(game, mil: Dictionary, x: Dictionary, threats: Dictionary) -> bool:
	var faction: String = mil["faction"]
	if not threats.has(faction): threats[faction] = {}
	var row: Dictionary = threats[faction]
	var xid: String = x["id"]
	if not row.has(xid): row[xid] = is_threat(game, mil, x)
	return bool(row[xid])

static func _raid_towns(w: Dictionary) -> Dictionary:
	var towns := {}
	for wb in w["warbands"].values():
		towns[wb.get("raid", {}).get("town", "")] = true
	return towns

static func _fight(game, tid: String, mil: Dictionary, x: Dictionary, rng: RandomNumberGenerator, pa: float = -1.0, pb: float = -1.0) -> void:
	var w: Dictionary = game.world
	if pa < 0.0: pa = CampaignWorld.band_power(mil["units"])
	if pb < 0.0: pb = CampaignWorld.band_power(x["units"])
	if not sallies(pa, pb):
		return   # it holds the walls

	var pwin := pa * pa / maxf(0.001, pa * pa + pb * pb)
	var town: Dictionary = w["towns"][tid]
	var what := Monsters.kind_text(x)
	if what == "":
		what = "band of %s" % CampaignWorld.faction_the(x["faction"]).trim_prefix("the ")
	if rng.randf() < pwin:
		var losses := int(round((mil["units"] as Array).size() * clampf(pb / maxf(0.01, pa) * 0.5, 0.0, 0.6)))
		var fallen := _lose(game, mil, losses, rng)
		CampaignWorld.log_event(game, "The militia of %s fought off a %s." % [town["name"], what])
		Army.survived(mil)
		Supplies.take(mil, x)   # economy spec 2: the beaten force's stores, as far as the militia can carry them
		var bb := Army.band_beaten(game, x, null, 0.5)
		ArmsTrade.field(game, fallen + bb["dead"], {"band": mil}, x["pos"])   # arms trade: the town holds the field
		Monsters.band_destroyed(game, x)
		if not Monsters.is_monster_band(x):
			CampaignWorld.weaken_faction(w, x["faction"], (x["units"] as Array).size())
			if not x.get("deserter", false):   # diplomacy: grievance and war losses, as for any destroyed army
				Diplomacy.on_army_destroyed(w, x["faction"], mil["faction"], (x["units"] as Array).size() + losses)
		CampaignWorld.remove_warband(game, x["id"])
	else:
		var losses2 := int(round((x["units"] as Array).size() * clampf(pa / maxf(0.01, pb) * 0.5, 0.1, 0.8)))
		var fallen2 := []
		for i in losses2:
			if (x["units"] as Array).size() > 1:
				fallen2.append((x["units"] as Array).pop_at(rng.randi() % (x["units"] as Array).size()))
		fallen2.append_array(_lose(game, mil, maxi(1, int(ceil((mil["units"] as Array).size() * 0.75))), rng))
		ArmsTrade.field(game, fallen2, {} if Monsters.is_monster_band(x) else {"band": x}, x["pos"])   # arms trade: the raiders hold the field
		x["rest_until"] = float(game.day) + 0.5
		Army.survived(x)
		CampaignWorld.log_event(game, "A %s cut down the militia of %s." % [what, town["name"]])

## Returns the fallen (arms trade: their kit goes to whoever holds the field).
static func _lose(game, mil: Dictionary, n: int, rng: RandomNumberGenerator) -> Array:
	var out := []
	for i in n:
		if (mil["units"] as Array).is_empty():
			return out
		var gone: Unit = (mil["units"] as Array).pop_at(rng.randi() % (mil["units"] as Array).size())
		People.casualty(game, gone, "dead", "militia")   # economy: the family loses him
		out.append(gone)
	return out


## Claude Edition: release reservists above the town's cap back to civilian life (same people, same households);
## their town-issued kit returns to the town's own stock. Returns how many were released.
static func trim(game, tid: String) -> int:
	var w: Dictionary = game.world
	var wb := band_of(game, tid)
	if wb.is_empty(): return 0
	var town: Dictionary = w["towns"].get(tid, {})
	if not TownEcon.has_econ(town): return 0
	var cap := TownDefence.militia_cap(town)
	var units: Array = wb["units"]
	if units.size() <= cap: return 0
	var e: Dictionary = town["econ"]
	var families: Array = e.get("fams", [])
	var keep: Array = units.slice(0, cap)
	var release: Array = units.slice(cap)
	var touched := {}
	for u in release:
		if not (u is Unit) or u.dead: continue
		if u.family >= 0 and u.family < families.size():
			var f: Dictionary = families[u.family]
			var p: Array = Persons.by_uid(f, u.uid)
			if not p.is_empty():
				if String(p[4]) == "militia": f["serve"]["militia"] = maxi(0, int(f.get("serve", {}).get("militia", 0)) - 1)
				p[4] = ""; p[5] = -1
				touched[u.family] = true
		for s in u.equip.keys():
			ArmsTrade.to_holder(game, {"town": town}, u.equip[s])
		u.equip.clear(); u.quiver.clear()
	wb["units"] = keep
	wb["n0"] = keep.size()
	for fid in touched: Families.reassign(e, families[int(fid)])
	if not touched.is_empty(): Families.match_idle(e)
	return release.size()

static func trim_all(game) -> int:
	var n := 0
	for tid in game.world.get("militia", {}):
		n += trim(game, str(tid))
	for tid in game.world.get("towns", {}):
		trim_armory(game, str(tid))
	return n

## Claude Edition: a town armory keeps what its reserve could ever carry (its arms target, at least 4 pieces per
## reservist); surplus pieces are melted into the town's scrap metal stock by their real mass (legendary pieces are
## always kept). The uncapped armories of a large world held 178,000 Item objects.
static func trim_armory(game, tid: String) -> int:
	var town: Dictionary = game.world["towns"].get(tid, {})
	if not TownEcon.has_econ(town) or not town.has("armory_items"): return 0
	ArmsTrade.refresh_reserve(game, town)
	var items: Array = town["armory_items"]
	var tgt := 0
	for c in town["econ"].get("arms_tgt", {}): tgt += int(town["econ"]["arms_tgt"][c])
	var cap := TownDefence.militia_cap(town)
	var keep_n := maxi(tgt, cap * 4)
	if items.size() <= keep_n: return 0
	# Melt the most worn first; keep legends and the best pieces (value computed once per piece).
	var ranked: Array = []
	for i in items.size():
		var it: Item = items[i]
		ranked.append([(1000000 if it.is_legend() else 0) + it.value(), i])
	ranked.sort_custom(func(a, b): return a[0] > b[0])
	var keep: Array = []
	var stock: Dictionary = town["econ"].get("stock", {})
	var melted := 0
	for k in ranked.size():
		var it: Item = items[int(ranked[k][1])]
		if k < keep_n or it.is_legend(): keep.append(it); continue
		var key := "scrap_" + str(it.material)
		if stock.has(key): stock[key] = int(stock[key]) + maxi(0, int(round(it.mass())))
		melted += 1
	town["armory_items"] = keep
	return melted
