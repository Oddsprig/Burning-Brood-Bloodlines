class_name WorldWarbands
extends RefCounted
## Warband strength/scouting, spawning, multi-frame muster, movement, AI clashes,
## and road-link/town helpers split from CampaignWorld (game/campaign/world.gd)
## to keep each file focused and under the size threshold.
## Structure only; all CampaignWorld.* entry points delegate here with identical behavior.

const PARTY_SPEED := CampaignWorld.PARTY_SPEED
const WARBAND_SPEED := CampaignWorld.WARBAND_SPEED
const CONTACT := CampaignWorld.CONTACT
const WARBAND_SIGHT := CampaignWorld.WARBAND_SIGHT
const BAND_SIZE := CampaignWorld.BAND_SIZE
const FIELD_LIMIT := CampaignWorld.FIELD_LIMIT
const FIELD_WEEKLY_GROWTH := CampaignWorld.FIELD_WEEKLY_GROWTH
const MUSTER_STEP := CampaignWorld.MUSTER_STEP

# ================================================================== strength / scouting
## Rough fighting value of one unit; gear counts heavily because gear IS difficulty.
static func unit_power(u: Unit) -> float:
	if u.dead or (u.sick_bed and u.bedridden(float(Game.day))):   # sickness: a bed-ridden man is off duty
		return 0.0
	if u.race_def().get("creature", false):   # monsters wave 1: creatures carry no gear
		return Creatures.power(u)
	var a := (u.attr("STR") + u.attr("AGI") + u.attr("TOU") + u.attr("END")) / 4000.0
	var best := 0
	for s in DB.WEAPON_SKILLS:
		best = maxi(best, u.skill(s))
	var sk := best * 0.06 + u.skill("fighter") * 0.03 + u.skill("dodger") * 0.02 + u.skill("shield_user") * 0.02 + u.skill("armor_user") * 0.02
	var gear := 0.0
	for slot in u.equip:
		var it: Item = u.equip[slot]
		if it.mat().get("kind", "") != "metal":
			continue
		var m := 1.0 if it.material == "copper" else 0.6
		gear += (0.35 if slot == "main_hand" else 0.15) * m * DB.quality_mult(it.quality)
	return a * (1.0 + sk) * (1.0 + gear)

static func band_power(units: Array) -> float:
	var p := 0.0
	for u in units:
		p += unit_power(u)
	return p

static func party_power(game) -> float:
	return band_power(game.deployed_units())

static func approx_count(n: int) -> String:
	if n <= 2: return "one or two"
	if n <= 5: return "a handful (3-5)"
	if n <= 9: return "under a dozen (6-9)"
	if n <= 14: return "about a dozen"
	if n <= 20: return "a score or so"
	return "a horde"

## "lightly armoured, mostly tin, crude work"
static func gear_impression(units: Array) -> String:
	var n := 0; var armour := 0; var metal := 0; var tin := 0; var q := 0
	for u in units:
		if u.dead:
			continue
		n += 1
		for slot in u.equip:
			var it: Item = u.equip[slot]
			if it.mat().get("kind", "") != "metal":
				continue
			metal += 1
			q += it.quality
			if it.material == "tin":
				tin += 1
			if slot != "main_hand":
				armour += 1
	if n == 0:
		return "nothing left"
	var parts := []
	var apu := float(armour) / n
	parts.append("heavily armoured" if apu >= 2.5 else ("lightly armoured" if apu >= 0.8 else "barely armoured"))
	if metal > 0:
		var tf := float(tin) / metal
		parts.append("mostly dull tin" if tf > 0.65 else ("mixed tin and copper" if tf > 0.3 else "bright copper"))
		var aq := float(q) / metal
		parts.append("masterwork" if aq >= 3.0 else ("fine work" if aq >= 2.0 else ("decent work" if aq >= 1.0 else "crude work")))
	else:
		parts.append("no metal to speak of")
	return ", ".join(parts)

static func relative_strength(game, units: Array) -> String:
	var r := band_power(units) / maxf(0.01, party_power(game))
	if r < 0.5: return "much weaker than us"
	if r < 0.85: return "weaker than us"
	if r < 1.2: return "an even match"
	if r < 1.8: return "stronger than us"
	return "far stronger than us"

## What the player sees when tapping a warband.
static func scout_report(game, wid: String) -> Dictionary:
	var wb: Dictionary = game.world["warbands"].get(wid, {})
	if wb.is_empty():
		return {}
	var units: Array = wb["units"]
	var alive := units.filter(func(u): return not u.dead)
	var fid: String = wb["faction"]
	var disp := Diplomacy.disposition(game, fid)   # hostile | neutral | friendly
	if wb.get("deserter", false):   # monsters wave 1: deserters are hostile whatever their old faction thinks
		disp = "hostile"
	var kind_txt: String = {"patrol": "patrol", "raider": "raiding party", "contract": "contract target",
		"assault": "assault force", "caravan": "merchant caravan"}.get(wb["kind"], "warband")
	var mk := Monsters.kind_text(wb)   # monsters wave 1: packs, dens, camps, gangs, deserters, militia
	if mk != "":
		kind_txt = mk
	var race: String = alive[0].race if not alive.is_empty() and Monsters.is_monster_band(wb) else DB.factions[fid]["race"]
	var fname := CampaignWorld.faction_name(fid) if not Monsters.is_monster_band(wb) else ""
	return {"id": wid, "faction": fid, "faction_name": fname, "kind": wb["kind"], "kind_text": kind_txt,
		"title": (kind_txt.substr(0, 1).to_upper() + kind_txt.substr(1) + "!") if fname == "" else "%s %s!" % [fname, kind_txt],
		"count_text": approx_count(alive.size()), "gear_text": gear_impression(alive) if not Monsters.is_monster_band(wb) else "teeth and claws",
		"disposition": disp, "strength_text": relative_strength(game, alive), "race": race,
		"is_contract_target": game.contract.get("target_id", "") == wid,
		"home": wb.get("home", ""), "home_text": home_text(game.world, wb),
		"cargo_text": Caravans.cargo_text(wb.get("cargo", {}), float(wb.get("gold", 0.0))) if wb["kind"] == "caravan" else "",
		"supply": TownEcon.supply_word(TownEcon.force_supply(game.world, wb))}

## "from Fengate, the Kingdom of the Middle March"
static func home_text(w: Dictionary, wb: Dictionary) -> String:
	var mh := Monsters.home_text(w, wb)   # monsters wave 1: lair / camp homes
	if mh != "":
		return mh
	var t: Dictionary = w["towns"].get(str(wb.get("home", "")), {})
	return "from %s, %s" % [t.get("name", "the wilds"), CampaignWorld.faction_the(wb["faction"])]

# ================================================================== warbands
static func spawn_warband(game, fid: String, pos: Vector2, count: int, kind: String, rng: RandomNumberGenerator, extra: Dictionary = {}) -> String:
	if Monsters.suspended_band({"faction": fid, "kind": kind, "units": extra.get("units", [])}): return ""
	var w: Dictionary = game.world
	var id := CampaignWorld.new_id(w, "wb")
	# monsters wave 1: extra["units"] = ready-made units (creatures, militia, armed outlaws)
	var _t0 := Time.get_ticks_usec()
	var units: Array = extra.get("units", [])
	if not extra.has("units"):
		var native_home := String(extra.get("home", ""))
		if not w["towns"].has(native_home): native_home = nearest_faction_town(w, fid, pos)
		for i in maxi(1, count):
			units.append(make_resident_troop(rng, fid, w["towns"].get(native_home, {})))
	if TownEcon.prof_on: _t0 = TownEcon._prof("sw_make_" + kind, _t0)
	var p := CampaignWorld.nearest_passable(w, pos)
	var wb := {"id": id, "faction": fid, "pos": p, "units": units, "kind": kind, "home": "", "anchor": p,
		"path": [], "rest_until": 0.0, "idle_until": 0.0, "repath_at": 0.0, "mode": "wander",
		"march_day": 0.0, "target_town": "", "contract_id": ""}
	wb.merge(extra, true)
	WarAI.sync_objective(wb, float(game.day))
	# every force belongs to a home town of its faction (Douglas), and so do its people
	# (monsters wave 1: bandits' home is their camp; monsters belong to a lair or to none)
	if not w["towns"].has(wb["home"]) and not w.get("lairs", {}).has(wb["home"]) and not Monsters.is_monster_faction(fid):
		wb["home"] = nearest_faction_town(w, fid, p)
	for u in units:
		u.home_town = wb["home"]
	w["warbands"][id] = wb
	if w.has("army"):
		_t0 = Time.get_ticks_usec()
		Army.enlist(game, wb)   # economy spec 2: every person in the force is a real family member (not monsters)
		if TownEcon.prof_on: TownEcon._prof("sw_enlist_" + kind, _t0)
		if (wb["units"] as Array).is_empty():
			w["warbands"].erase(id)   # war pick 4: the town could spare nobody: not raised
			return ""
	return id

## Nearest town of a faction to pos (any town when the faction has none).
static func nearest_faction_town(w: Dictionary, fid: String, pos: Vector2) -> String:
	var best := ""; var bd := INF
	for tid in w["towns"]:
		var t: Dictionary = w["towns"][tid]
		if t["faction"] != fid:
			continue
		var d: float = (t["pos"] as Vector2).distance_to(pos)
		if d < bd:
			bd = d; best = tid
	return best if best != "" else nearest_town(w, pos)

## from_stock (economy spec 11): a band raised during the campaign takes its gear out of its home town's arms
## stock (the treasury pays the market); the bands of world generation keep their rolled gear (pre-history).
## staged: tests' perf scenes only (Army.enlist: the band is put on the map whole, not drafted).
## muster_head (world size): the band is raised over several work jobs (see muster_start); returns "" (the band goes
## on the map when its last job runs).
static func field_target(w: Dictionary, day: float = 0.0) -> int:
	return mini(FIELD_LIMIT, int(BAND_SIZE.get(String(w.get("size", "normal")), 100)) +
		maxi(0, int(day / 7.0)) * FIELD_WEEKLY_GROWTH)

## Residence determines the body/template; allegiance does not change a person's race.
static func make_resident_troop(rng: RandomNumberGenerator, fid: String, town: Dictionary, wealth: int = -1) -> Unit:
	var race := Persons.race_of(town["econ"]) if TownEcon.has_econ(town) else String(DB.factions[fid]["race"])
	var source := fid
	if String(DB.factions[fid].get("race", "")) != race:
		for candidate in DB.factions:
			if String(DB.factions[candidate].get("race", "")) == race and not Monsters.is_monster_faction(candidate):
				source = candidate; break
	var u := Factory.make_troop(rng, source, Factory.pick_troop(rng, source), wealth)
	u.faction = fid
	return u

## Replacements reserve household food at home and must be able to buy a three-day mess plus wages.
static func supported_field_count(game, fid: String, town: Dictionary, target: int) -> int:
	if not TownEcon.has_econ(town): return 0
	var n := mini(target, Population.available(town))
	var e: Dictionary = town["econ"]
	var stock: Dictionary = e.get("stock", {})
	var meals := 0
	var cheapest := INF
	for good in Supplies.FOOD:
		var q := maxi(0, int(stock.get(good, 0)))
		meals += q
		if q > 0: cheapest = minf(cheapest, float(e.get("price", {}).get(good, 1.0)))
	n = mini(n, meals / 12)   # half stays in the home market; six meals per departing soldier
	var cash := float(game.world.get("factions", {}).get(fid, {}).get("treasury", 0.0))
	var reserve := Army.bill(game, fid) * 3.0
	var cost := Army.wage("army", 0) * float(Army.A()["desert_days"]) + 6.0 * maxf(0.01, cheapest)
	if n > 0: n = mini(n, maxi(0, int((cash - reserve) / cost)))
	return n if n > 0 and Army.can_raise(game, fid, n) else 0

static func spawn_faction_band(game, fid: String, rng: RandomNumberGenerator, from_stock: bool = false, staged: bool = false,
		muster_head: Array = []) -> String:
	var w: Dictionary = game.world
	var towns: Array = w["factions"].get(fid, {}).get("towns", [])
	if towns.is_empty():
		return ""
	var home: String = towns[rng.randi() % towns.size()]
	var pools := {}   # the pool looked at here is the one the draft takes from (built once per raising)
	if not staged and TownEcon.has_econ(w["towns"][home]):
		var pl := People.draft_pool(w["towns"][home])
		if not pl.is_empty():
			pools[home] = pl
		else:
			for tid2 in towns:   # war pick 4: that town has no one to spare; the realm raises the band where men can go
				if tid2 == home or not TownEcon.has_econ(w["towns"][tid2]):
					continue
				var pl2 := People.draft_pool(w["towns"][tid2])
				if not pl2.is_empty():
					home = tid2
					pools[home] = pl2
					break
	var n := field_target(w, float(game.day) if from_stock else 0.0)
	if not staged:
		if pools.is_empty(): return ""
		n = mini(n, (pools[home] as Array).size())
		if from_stock: n = supported_field_count(game, fid, w["towns"][home], n)
		else: n = mini(n, Population.available(w["towns"][home]))
		if n <= 0: return ""
	var kind := "raider" if DB.factions[fid].get("player_hostile", false) else "patrol"
	var pos: Vector2 = w["towns"][home]["pos"] + Vector2(rng.randf_range(-60, 60), rng.randf_range(-60, 60))
	var extra := {"home": home, "staged": true} if staged else {"home": home}
	if not muster_head.is_empty():
		muster_start(game, muster_head, fid, pos, n, kind, extra, rng, false,
			{"then": "band", "outfit": from_stock and TownEcon.has_econ(w["towns"][home]), "pools": pools})
		return ""
	var wid := spawn_warband(game, fid, pos, n, kind, rng, extra)
	if wid != "" and from_stock and TownEcon.has_econ(w["towns"][home]):   # ("": nobody to spare, war pick 4)
		TownEcon.outfit_units(w["towns"][home], w["warbands"][wid]["units"])
	return wid

# ================================================================== the muster (world size)
static func muster_start(game, head: Array, fid: String, pos: Vector2, count: int, kind: String, extra: Dictionary,
		rng: RandomNumberGenerator, own_rng: bool, then: Dictionary) -> void:
	if Monsters.suspended_band({"faction": fid, "kind": kind, "units": extra.get("units", [])}): return
	var w: Dictionary = game.world
	var m := {"id": CampaignWorld.new_id(w, "wb"), "fid": fid, "pos": pos, "n": maxi(1, count), "kind": kind, "extra": extra, "units": [],
		"stage": "make"}
	m.merge(then, true)
	if own_rng:
		m["rs"] = str(rng.state)
	muster_step(game, head + [m], rng)

## The forces being raised: their men (Army.sweep must not count them dead; Caravans.count counts the caravans).
static func mustering(w: Dictionary) -> Array:
	var out := []
	for j in w.get("work", []):
		if (j as Array).size() > 2 and j[-1] is Dictionary and (j[-1] as Dictionary).has("stage"):
			out.append(j[-1])
	return out

static func mustering_units(w: Dictionary) -> Array:
	var out := []
	for m in mustering(w):
		if m.has("wb"):
			out.append_array(m["wb"]["units"])
		else:
			out.append_array(m["units"])
	return out

## One muster job: a step of the force's raising. Queues the next at the front of the queue unless it is done.
static func muster_step(game, job: Array, frame_rng: RandomNumberGenerator) -> void:
	var w: Dictionary = game.world
	var m: Dictionary = job[-1]
	var rng := frame_rng
	if m.has("rs"):
		rng = RandomNumberGenerator.new()
		rng.state = String(m["rs"]).to_int()
	var more := _muster_part(game, m, rng)
	if m.has("rs"):
		m["rs"] = str(rng.state)
	if more:
		(w["work"] as Array).push_front(job)

## Returns true while there is more to do.
static func _muster_part(game, m: Dictionary, rng: RandomNumberGenerator) -> bool:
	var w: Dictionary = game.world
	var fid := String(m["fid"])
	if Monsters.suspended_band({"faction": fid, "kind": m.get("kind", ""), "units": m.get("units", [])}): return false
	match String(m["stage"]):
		"make":   # Factory.make_warband, MUSTER_STEP men a job
			var units: Array = m["units"]
			for _k in MUSTER_STEP:
				if units.size() >= int(m["n"]):
					break
				var town: Dictionary = w["towns"].get(String(m["extra"].get("home", "")), {})
				units.append(make_resident_troop(rng, fid, town))
			if units.size() < int(m["n"]):
				return true
			# the rest of spawn_warband up to the draft
			var p := CampaignWorld.nearest_passable(w, m["pos"])
			var wb := {"id": m["id"], "faction": fid, "pos": p, "units": units, "kind": m["kind"], "home": "", "anchor": p,
				"path": [], "rest_until": 0.0, "idle_until": 0.0, "repath_at": 0.0, "mode": "wander",
				"march_day": 0.0, "target_town": "", "contract_id": ""}
			wb.merge(m["extra"], true)
			WarAI.sync_objective(wb, float(game.day))
			if not w["towns"].has(wb["home"]) and not w.get("lairs", {}).has(wb["home"]) and not Monsters.is_monster_faction(fid):
				wb["home"] = nearest_faction_town(w, fid, p)
			for u in units:
				u.home_town = wb["home"]
			m.erase("units"); m.erase("extra")
			m["wb"] = wb
			var ctx := Army.enlist_begin(game, wb, m.get("pools", {})) if w.has("army") else {}
			m.erase("pools")
			if ctx.is_empty():
				m["stage"] = "drafted"
				return _muster_part(game, m, rng)
			m["ctx"] = ctx
			m["stage"] = "draft"
			return true
		"draft":   # Army.enlist, MUSTER_STEP men a job
			var wb: Dictionary = m["wb"]
			if not Army.enlist_some(game, wb, m["ctx"], MUSTER_STEP):
				return true
			Army.enlist_end(game, wb, m["ctx"])
			m.erase("ctx")
			m["stage"] = "drafted"
			return _muster_part(game, m, rng)
		"drafted":
			var wb: Dictionary = m["wb"]
			if (wb["units"] as Array).is_empty():   # war pick 4: the town could spare nobody: not raised
				return _muster_done(game, m, "", rng)
			if String(m.get("then", "")) == "band" and m.get("outfit", false):
				m["stage"] = "outfit"
				m["oi"] = 0
				m["ob"] = int(floor(float((w["towns"][wb["home"]].get("shop", []) as Array).size()) * 0.5))
				return true
			w["warbands"][m["id"]] = wb
			return _muster_done(game, m, String(m["id"]), rng)
		"outfit":   # TownEcon.outfit_units from the home town's stock, MUSTER_STEP men a job (one share for the band)
			var wb: Dictionary = m["wb"]
			var town: Dictionary = w["towns"][wb["home"]]
			var units: Array = wb["units"]
			var i0 := int(m["oi"])
			var i1 := mini(units.size(), i0 + MUSTER_STEP)
			m["ob"] = int(m["ob"]) - TownEcon.outfit_units(town, units.slice(i0, i1), 0.5, true, int(m["ob"]), false)
			m["oi"] = i1
			if i1 < units.size():
				return true
			BowsEcon.fill_quivers(town, units)   # bows: quivers from the town's arrows (the whole band at once, as before)
			w["warbands"][m["id"]] = wb
			return _muster_done(game, m, String(m["id"]), rng)
	return false

## The force is on the map (wid; "" when nobody could be raised): what its raiser does next.
static func _muster_done(game, m: Dictionary, wid: String, rng: RandomNumberGenerator) -> bool:
	match String(m.get("then", "")):
		"caravan":
			if wid != "":
				wid = Caravans.sail(game, wid, rng)
	m["stage"] = "done"
	return false

static func remove_warband(game, wid: String) -> void:
	game.world["warbands"].erase(wid)
	if game.world.get("encounter", "") == wid:
		game.world["encounter"] = ""

static func _wander_target(game, wb: Dictionary, rng: RandomNumberGenerator) -> Vector2:
	var w: Dictionary = game.world
	var base: Vector2 = wb["anchor"]
	var radius := 260.0
	match wb["kind"]:
		"patrol":
			if w["towns"].has(wb["home"]):
				base = w["towns"][wb["home"]]["pos"]
			# diplomacy: at WAR, patrols sometimes go after enemy caravans and prowl enemy towns
			if rng.randf() < 0.35 and not Diplomacy.enemies_at_war(w, wb["faction"]).is_empty():
				var prey := _war_prey(w, wb, rng)
				if prey != Vector2.INF:
					return prey
		"raider":
			# prowl near enemy towns (or the home region)
			var targets := []
			for tid in w["towns"]:
				var t: Dictionary = w["towns"][tid]
				if CampaignWorld.at_war(w, wb["faction"], t["faction"]) and t["pos"].distance_to(wb["pos"]) < 900:
					targets.append(t["pos"])
			# caravans in reach are the best prey
			for cid in w["warbands"]:
				var car: Dictionary = w["warbands"][cid]
				if car["kind"] == "caravan" and (car["pos"] as Vector2).distance_to(wb["pos"]) < 450.0 and Caravans.is_prey(w, wb, car):
					var ahead: Array = car["path"]
					return ahead[mini(2, ahead.size() - 1)] if not ahead.is_empty() else car["pos"]
			if not targets.is_empty() and rng.randf() < 0.6:
				base = targets[rng.randi() % targets.size()]
				radius = 180.0
			elif w["towns"].has(wb["home"]):
				base = w["towns"][wb["home"]]["pos"]
				radius = 380.0
		"contract":
			radius = 110.0
		"bandit":   # monsters wave 1
			return Bandits.wander_target(game, wb, rng)
		"deserter":
			return Bandits.deserter_target(game, wb, rng)
	return base + Vector2(rng.randf_range(-radius, radius), rng.randf_range(-radius, radius))

## Diplomacy: an enemy town nearby to prowl; Vector2.INF when none. (Enemy forces, caravans included, are hunted
## by campaign/war_ai.gd: sight, tracks, word, lead interception.)
static func _war_prey(w: Dictionary, wb: Dictionary, rng: RandomNumberGenerator) -> Vector2:
	for tid in w["towns"]:
		var t: Dictionary = w["towns"][tid]
		if (t["pos"] as Vector2).distance_to(wb["pos"]) < 700.0 and CampaignWorld.at_war(w, wb["faction"], t["faction"]):
			return t["pos"] + Vector2(rng.randf_range(-120, 120), rng.randf_range(-120, 120))
	return Vector2.INF

## Size is O(1): field rosters remove casualties; never scan individual soldiers during movement.
static func travel_speed(base: float, men: int) -> float:
	return base * clampf(1.0 - 0.35 * log(maxf(1.0, float(men) / 100.0)) / log(10.0), 0.45, 1.0)

static func _step_along(w: Dictionary, obj: Dictionary, dist: float) -> bool:
	## All band walkers pass their base distance here; apply army size exactly once, including militia/convoys.
	## The party has no units array, so _move_party supplies its size-adjusted distance.
	if obj.has("units"):
		dist = travel_speed(dist, (obj["units"] as Array).size())
	var path: Array = obj["path"]
	while dist > 0.0 and not path.is_empty():
		var p: Vector2 = obj["pos"]
		var q: Vector2 = path[0]
		var d := p.distance_to(q)
		if d <= dist:
			obj["pos"] = q
			dist -= d
			path.pop_front()
		else:
			obj["pos"] = p + (q - p) / d * dist
			dist = 0.0
	return path.is_empty()

static func _move_warbands(game, dt: float, t: float, rng: RandomNumberGenerator) -> void:
	var w: Dictionary = game.world
	var party: Dictionary = w["party"]
	var ppow := -1.0
	for wid in w["warbands"].keys():
		var wb: Dictionary = w["warbands"].get(wid, {})
		if wb.is_empty() or Monsters.suspended_band(wb) or wid == w.get("encounter", ""):
			continue
		WarAI.sync_objective(wb, t)
		if float(wb["rest_until"]) > t:
			continue
		if wb["kind"] == "caravan":
			Caravans.step(game, wid, wb, dt)
			continue
		if Monsters.step_band(game, wid, wb, dt, t, rng, true):   # identical suspension check already completed above
			continue
		if wb["kind"] == "assault":
			if t < float(wb["march_day"]):
				continue
			var wm := WarAI.control(game, wid, wb, t)   # war: a war band falls on enemy forces it sees on the march
			if wm >= 0.0:
				_step_along(w, wb, WARBAND_SPEED * wm * CampaignWorld.smooth_speed(w, wb, dt) * dt)
				continue
			var town: Dictionary = w["towns"].get(wb["target_town"], {})
			if town.is_empty():
				wb["kind"] = "raider"
				continue
			if (wb["path"] as Array).is_empty():
				wb["path"] = CampaignWorld.find_path(w, wb["pos"], town["pos"])
			_step_along(w, wb, WARBAND_SPEED * CampaignWorld.smooth_speed(w, wb, dt) * dt)
			if (wb["pos"] as Vector2).distance_to(town["pos"]) < 20.0:
				_assault_arrives(game, wid)
			continue
		var mode := "wander"
		# The geometry is unused while the company is protected or in town.
		if float(party["safe_until"]) <= t and game.location == "" \
				and (wb["pos"] as Vector2).distance_to(party["pos"]) < WARBAND_SIGHT and Monsters.band_hostile(game, wb):
			if ppow < 0.0:
				ppow = party_power(game)
			var bp := band_power(wb["units"])
			if bp >= ppow * 1.0:
				mode = "chase"
			elif bp < ppow * 0.6 and wb["kind"] != "contract":
				mode = "flee"
		if mode != wb["mode"]:
			wb["mode"] = mode
			wb["path"] = []
			wb["repath_at"] = 0.0
			WarAI.sync_objective(wb, t)
		var speed := WARBAND_SPEED * CampaignWorld.smooth_speed(w, wb, dt)
		match mode:
			"chase":
				if t >= float(wb["repath_at"]):
					# war interception: head for where the company will be along its route, not where it is
					var aim := WarAI.lead_point(wb["pos"], travel_speed(WARBAND_SPEED, (wb["units"] as Array).size()) * maxf(0.5, float(wb.get("spd", 1.0))), party["pos"],
						party["path"], travel_speed(PARTY_SPEED, game.company.size()) * float(party.get("spd", 1.0)) if game.location == "" else 0.0)
					wb["path"] = CampaignWorld.find_path(w, wb["pos"], aim)
					wb["repath_at"] = t + 0.15
				_step_along(w, wb, speed * dt)
			"flee":
				if t >= float(wb["repath_at"]) or (wb["path"] as Array).is_empty():
					var away: Vector2 = ((wb["pos"] as Vector2) - party["pos"]).normalized()
					wb["path"] = CampaignWorld.find_path(w, wb["pos"], wb["pos"] + away * 250.0)
					wb["repath_at"] = t + 0.3
				_step_along(w, wb, speed * 0.95 * dt)
			_:
				var wm := WarAI.control(game, wid, wb, t)   # war: hunt, shadow, avoid, fall back home (decisions amortised)
				if wm >= 0.0:
					if wm > 0.0:
						_step_along(w, wb, speed * wm * dt)
					continue
				if (wb["path"] as Array).is_empty():
					if float(wb["idle_until"]) > t:
						continue
					wb["path"] = CampaignWorld.find_path(w, wb["pos"], _wander_target(game, wb, rng))
					if (wb["path"] as Array).is_empty():
						wb["idle_until"] = t + 0.5
						continue
				if _step_along(w, wb, speed * 0.8 * dt):
					wb["idle_until"] = t + rng.randf_range(0.2, 0.9)

## Warbands of factions at war fight when they meet (auto-resolved).
static func _warband_clashes(game, t: float, rng: RandomNumberGenerator) -> void:
	var w: Dictionary = game.world
	var ids: Array = []
	for k in w["warbands"]:   # monsters wave 1: militia/packs/dens/camps fight through Militia.tick instead
		# These native kinds never enter this resolver. Reject them before an
		# otherwise unused full-roster creature scan; both predicates are pure.
		if not w["warbands"][k]["kind"] in Monsters.NO_CLASH and not Monsters.suspended_band(w["warbands"][k]):
			ids.append(k)
	var enc: String = w.get("encounter", "")
	var pairs := _clash_pairs(w, ids)
	for pr in pairs:
		var i: int = pr.x; var j: int = pr.y
		var a: Dictionary = w["warbands"].get(ids[i], {})
		var b: Dictionary = w["warbands"].get(ids[j], {})
		if a.is_empty() or b.is_empty():
			continue
		if ids[i] == enc or ids[j] == enc:
			continue
		var car: Dictionary = a if a["kind"] == "caravan" else (b if b["kind"] == "caravan" else {})
		if not car.is_empty():
			var att: Dictionary = b if car["id"] == a["id"] else a
			if not Caravans.is_prey(w, att, car) or float(att["rest_until"]) > t:
				continue
			if Caravans.escort_near(game, car):
				# the company stands with the caravan it escorts: battle, guards as allies
				if enc == "":
					att["escort_fight"] = car["id"]
					w["encounter"] = att["id"]
					enc = att["id"]
					w["party"]["path"] = []
					w["party"]["dest_town"] = ""
				continue
		elif not Diplomacy.fights(w, a["faction"], b["faction"]) and not Monsters.extra_fight(a, b):
			continue   # diplomacy: WAR or HOSTILE fight on contact; monsters wave 1: outlaws vs all, deserters vs their old faction
		var pa := band_power(a["units"]); var pb := band_power(b["units"])
		if car.is_empty():   # diplomacy: allied bands close by join the fight (only computed on contact)
			pa += Diplomacy.ally_power(w, a["faction"], b["faction"], a["pos"], [ids[i], ids[j]])
			pb += Diplomacy.ally_power(w, b["faction"], a["faction"], b["pos"], [ids[i], ids[j]])
		pa += WarAI.pack_power(w, a, b["id"], [ids[i], ids[j]])   # war: own bands closing on the same target join in
		pb += WarAI.pack_power(w, b, a["id"], [ids[i], ids[j]])
		# Rounds (campaign/clash_rounds.gd): 100 v 100 until one army's morale or numbers break.
		var na := (a["units"] as Array).size(); var nb := (b["units"] as Array).size()
		var cr := ClashRounds.resolve(na, nb, pa / maxf(1.0, float(na)), pb / maxf(1.0, float(nb)), _officer_count(a), _officer_count(b), rng,
			70.0, 70.0, CampaignWorld.terrain_at(w, a["pos"]), BattleTactics.commander_tactician(game, a["units"], 0), BattleTactics.commander_tactician(game, b["units"], 1))
		var win := a if str(cr["winner"]) == "a" else b
		var lose := b if win == a else a
		var wrep: Dictionary = cr["a"] if win == a else cr["b"]
		var lrep: Dictionary = cr["b"] if win == a else cr["a"]
		var fought_n := mini(na, nb) * int(cr["rounds"])
		ArmsPool.after_clash(game, str(win["faction"]), fought_n, true, int(wrep["dead"]))
		ArmsPool.after_clash(game, str(lose["faction"]), fought_n, false, int(lrep["dead"]))
		# the census: the men who die in this clash (now, or later when the army sweep finds them gone) died here
		var cwhere := nearest_town_name(w, lose["pos"])
		var cdetail := ("%s raided a caravan of %s near %s" if lose["kind"] == "caravan" else "%s beat %s near %s") % [
			CampaignWorld.faction_the(win["faction"]), CampaignWorld.faction_the(lose["faction"]), cwhere]
		Census.ctx("battle", cdetail)
		var told := WarAI.on_clash(game, a, b, win)   # war: news line when one side ran the other down
		var losses := int(wrep["dead"])
		if lose["kind"] != "caravan":   # diplomacy: grievance -4 and the men lost count toward war weariness
			Diplomacy.on_army_destroyed(w, lose["faction"], win["faction"], losses + int(lrep["dead"]) + int(lrep["captured"]))
		var fallen := []   # arms trade: the winners' dead (their kit stays with whoever holds the field)
		for k in losses:
			if (win["units"] as Array).size() > 1:
				fallen.append((win["units"] as Array).pop_at(rng.randi() % (win["units"] as Array).size()))
		win["rest_until"] = t + 0.5
		Army.survived(win)   # economy spec 2: a battle survived (veteran / blooded at the faction's day)
		var holder := {} if Monsters.is_monster_band(win) else {"band": win}
		Census.note_fates(w, fallen, "battle", cdetail)
		if lose["kind"] == "caravan":
			ArmsTrade.field(game, fallen, holder, lose["pos"])
			if not holder.is_empty():
				ArmsTrade.plunder_cargo(game, win, lose)   # arms trade: the guards' kit and a share of the arms cargo
			Bandits.on_plunder(game, win, lose)   # monsters wave 1: a gang carries the cargo to its camp
			Army.on_plunder(w, win, lose)   # economy spec 2: food and drink into the winner's stores, the purse to its chest
			Caravans.lost(game, lose["id"], win["faction"])
			Census.ctx_end()
			continue
		Supplies.take(win, lose)   # the winner takes the beaten force's stores, up to what it can carry
		Army.fight_pay(game, lose, 1.0)
		var ldead := []
		for k in int(lrep["dead"]):
			if (lose["units"] as Array).is_empty(): break
			ldead.append((lose["units"] as Array).pop_at(rng.randi() % (lose["units"] as Array).size()))
		for k in int(lrep["captured"]):   # taken, then ransomed home by their families
			if (lose["units"] as Array).is_empty(): break
			Army.release(game, (lose["units"] as Array).pop_at(rng.randi() % (lose["units"] as Array).size()), "fled")
		Census.note_fates(w, ldead, "battle", cdetail)
		ArmsTrade.field(game, fallen + ldead, holder, lose["pos"])   # arms trade: the dead's kit to the victors (Loot.spoils)
		if win["kind"] == "caravan":
			win["rest_until"] = t   # merchants keep moving
		weaken_faction(w, lose["faction"], ldead.size() + int(lrep["captured"]))
		var where := nearest_town_name(w, lose["pos"])
		if BattleRounds.retreat_band(game, lose):
			if not told:
				CampaignWorld.log_event(game, "A band of %s beat a band of %s near %s in %d rounds; the beaten fell back home to regroup." % [CampaignWorld.faction_the(win["faction"]), CampaignWorld.faction_the(lose["faction"]), where, int(cr["rounds"])])
		else:
			if not told:
				CampaignWorld.log_event(game, "A band of %s destroyed a band of %s near %s." % [CampaignWorld.faction_the(win["faction"]), CampaignWorld.faction_the(lose["faction"]), where])
			remove_warband(game, lose["id"])
		Census.ctx_end()

static func _officer_count(wb: Dictionary) -> int:
	var n := 0
	for u in wb["units"]:
		if u is Unit and u.role in ["captain", "officer"]: n += 1
	return n

static func _clash_pairs(w: Dictionary, ids: Array) -> Array:
	# The pairs in contact, found by a sweep along x (bands are sorted by x once; a pair further apart in x than
	# CONTACT is never in contact), then resolved in the same (i, j) order the plain double loop used: same fights,
	# same rolls, a fraction of the distance tests on the 1.5x map with its many bands (war pick 5)
	var xs := []
	var positions := []   # these positions cannot change until all pairs have been collected
	for i in ids.size():
		var pos: Vector2 = w["warbands"][ids[i]]["pos"]
		positions.append(pos)
		xs.append(Vector2(pos.x, i))
	xs.sort()   # native Vector2 order: x, then band index (pair resolution is sorted below)
	var pairs := []
	for m in xs.size():
		var mi := int(xs[m].y)
		var pm: Vector2 = positions[mi]
		for q in range(m + 1, xs.size()):
			if float(xs[q].x) - pm.x > CONTACT:
				break
			var qi := int(xs[q].y)
			if pm.distance_squared_to(positions[qi]) <= CONTACT * CONTACT:
				pairs.append(Vector2i(mini(mi, qi), maxi(mi, qi)))
	pairs.sort()
	return pairs

static func weaken_faction(w: Dictionary, fid: String, size: int) -> void:
	var f: Dictionary = w["factions"].get(fid, {})
	if f.is_empty():
		return
	f["strength"] = clampf(float(f["strength"]) - 0.06 - 0.015 * size, 0.2, 1.5)

## town.road_links = [{id, faction, dist}] for every town joined to it by a road (caravans, escort offers).
static func compute_road_links(w: Dictionary) -> void:
	for tid in w["towns"]:
		w["towns"][tid]["road_links"] = []
	for r in w.get("roads", []):
		var a: Dictionary = w["towns"].get(r["a"], {})
		var b: Dictionary = w["towns"].get(r["b"], {})
		if a.is_empty() or b.is_empty():
			continue
		var pts: Array = r["pts"]
		var d := CampaignWorld.path_length(pts[0], pts) if not pts.is_empty() else (a["pos"] as Vector2).distance_to(b["pos"])
		(a["road_links"] as Array).append({"id": b["id"], "faction": b["faction"], "dist": d})
		(b["road_links"] as Array).append({"id": a["id"], "faction": a["faction"], "dist": d})

static func nearest_town(w: Dictionary, pos: Vector2) -> String:
	var best := ""; var bd := INF
	for tid in w["towns"]:
		var d: float = w["towns"][tid]["pos"].distance_to(pos)
		if d < bd:
			bd = d; best = tid
	return best

static func nearest_town_name(w: Dictionary, pos: Vector2) -> String:
	var t := nearest_town(w, pos)
	return w["towns"][t]["name"] if t != "" else "the wilds"

static func _assault_arrives(game, wid: String) -> void:
	var w: Dictionary = game.world
	var wb: Dictionary = w["warbands"][wid]
	var town: Dictionary = w["towns"][wb["target_town"]]
	var party: Dictionary = w["party"]
	if wb.get("war_assault", false):   # diplomacy: a faction's own war band, no contract: militia vs raiders
		Diplomacy.war_assault_arrives(game, wid)
		return
	if (party["pos"] as Vector2).distance_to(town["pos"]) < 70.0 or game.location == town["id"]:
		w["encounter"] = wid     # the company stands with the town: battle
		party["path"] = []
		return
	# the town falls to the raid
	town["wealth"] = maxi(1, int(town["wealth"]) - 1)
	Diplomacy.on_town_attacked(w, town["faction"], wb["faction"], true)   # diplomacy: sacked -25
	Migration.note_attack(w, String(town["id"]), float(game.day))   # v0.034: its people fear for their lives
	CampaignWorld.log_event(game, "%s was sacked by %s." % [town["name"], CampaignWorld.faction_the(wb["faction"])])
	var c: Dictionary = game.contract
	if c.get("target_id", "") == wid:
		Contracts.fail(game, "%s was sacked before you arrived." % town["name"])
	wb["kind"] = "raider"
	wb["path"] = []
	wb["rest_until"] = game.day + 1.0
