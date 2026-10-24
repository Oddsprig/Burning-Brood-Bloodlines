class_name Army
extends RefCounted
## Economy spec 2 (docs/specs/economy-2-army.md): army pay, ranks, rank rules per faction, succession.
##
## Every person in every non-monster force is a real person of a real family in a real settlement of his race,
## paid real wages into that family's purse (Douglas). Militia/guard (town treasury), a faction's field bands
## (patrols, raiders, war bands, contract bands: the faction treasury, funded by town tax), bandits (their camp,
## from stolen stock), deserters (unpaid; they deserted). Pay form from the culture row (data/economy.json
## cultures.*.pay): coin, food and beer bought from the home town's market and put in the family's stores, a
## share of the realm's loot chest (sacked towns, plundered caravans). Unpaid desert_days -> the man walks home
## to his family (bandit gangs scatter). The dead leave their family (a daily sweep of the roll, so every way a
## man can vanish from the map counts).
##
## Ranks: a tree per faction field army (w.army.f[fid].posts) and per town militia (wb.posts): flat arrays of
## holder uids (-1 vacant), level k from the top has span^k posts; levels exist while span^k <= soldiers (fill
## top-down, only what the size supports, never more than the culture's officer ranks). The two lowest army ranks
## are status (survived a battle -> veteran/blooded), the lowest militia rank is the only status rank. Rank is
## hierarchy and pay only (officers get role "officer": the existing Leader morale aura in battle).
## Vacancies are filled by the culture's rank_rule from the officers who reported to the post (rank and file
## report to bottom posts by uid); new posts under a grown cap go to men past promote_battles. Orcs: the
## candidates fight it out in the real combat sim, one duel per work job (succession.gd style bracket inside
## this file), the cascade queues the winner's old post.
##
## State: w.army = {v, roll {uid: [town, family, role, name]}, f {fid: {posts, levels, hist, bill, paid,
## unpaid_n, fights [{p, c [uids], beat [[name, dead]]}]}}}. Per-unit: Unit.rank, Unit.unpaid_days, Unit.renown.
## Cost: one work job per faction per day (pay = per-man float adds, a few hundred men), one sweep job per day,
## one job per succession duel. No per-frame work.

const NO_ARMY := ["militia", "caravan", "deserter", "camp", "bandit", "beasts", "den"]

static func A() -> Dictionary:
	return TownEcon.data()["army"]

static func cul_of_faction(fid: String) -> Dictionary:
	var cs: Dictionary = TownEcon.data()["cultures"]
	var c := String(DB.factions.get(fid, {}).get("culture", "middle"))
	return cs.get(c, cs["middle"])

static func state(w: Dictionary) -> Dictionary:
	if not w.has("army"):
		w["army"] = {"v": 1, "roll": {}, "f": {}}
	return w["army"]

static func rec(w: Dictionary, fid: String) -> Dictionary:
	var f: Dictionary = state(w)["f"]
	if not f.has(fid):
		f[fid] = {"posts": [], "levels": 0, "hist": [], "bill": 0.0, "paid": 0.0, "unpaid_n": 0, "fights": []}
	return f[fid]

static func is_field(wb: Dictionary) -> bool:
	var fid := String(wb.get("faction", ""))
	return DB.factions.has(fid) and not Monsters.is_monster_faction(fid) and not Monsters.is_wild_faction(fid) \
		and not String(wb.get("kind", "")) in NO_ARMY and not wb.get("deserter", false)

static func is_people_band(wb: Dictionary) -> bool:
	return not Monsters.is_monster_band(wb) and not Monsters.is_monster_faction(String(wb.get("faction", ""))) \
		and String(wb.get("kind", "")) != "caravan"

## The living soldiers of a faction's field army (every field band on the map).
static func members(game, fid: String) -> Array:
	var out := []
	for wid in game.world.get("warbands", {}):
		var wb: Dictionary = game.world["warbands"][wid]
		if wb["faction"] == fid and is_field(wb):
			for u in wb["units"]:
				if not u.dead:
					out.append(u)
	return out

# ================================================================== tree math (campaign/army_ranks.gd)
static func ranks(cul: Dictionary, tier: String) -> Array: return ArmyRanks.ranks(cul, tier)
static func first_officer(tier: String) -> int: return ArmyRanks.first_officer(tier)
static func levels_for(n: int, span: int, n_off: int) -> int: return ArmyRanks.levels_for(n, span, n_off)
static func offset(k: int, span: int) -> int: return ArmyRanks.offset(k, span)
static func caps(levels: int, span: int) -> Array: return ArmyRanks.caps(levels, span)
static func level_of(idx: int, span: int) -> int: return ArmyRanks.level_of(idx, span)
static func up_of(idx: int, span: int) -> int: return ArmyRanks.up_of(idx, span)
static func children_of(idx: int, span: int, levels: int) -> Array: return ArmyRanks.children_of(idx, span, levels)
static func rank_at(k: int, rl: Array) -> int: return ArmyRanks.rank_at(k, rl)
static func report_post(u: Unit, levels: int, span: int) -> int: return ArmyRanks.report_post(u, levels, span)
static func command_plan(units: Array, posts: Array, levels: int, span: int, fid: String, protected_units: Array = []) -> Array: return ArmyRanks.command_plan(units, posts, levels, span, fid, protected_units)
static func _apply_commands(game, units: Array, posts: Array, levels: int, span: int, fid: String) -> void: ArmyRanks._apply_commands(game, units, posts, levels, span, fid)
static func _link_field_commands(game, fid: String) -> void: ArmyRanks._link_field_commands(game, fid)

# ================================================================== enlisting: every soldier from a family
## Gives every person of a non-monster force who has none a family, renames him after it and puts him on the roll.
## Soldiers (role "army", war pick 4): People.draft from the home town only (free, of draft age, labourers first,
## never a needed land hand); a man the town cannot spare is not raised (the band is smaller; empty = not raised,
## CampaignWorld.spawn_warband removes it). Outlaws and deserters: People.draw, a new family row when nobody fits.
## wb.staged (tests and the debug map only; the world never sets it): a scene's force put on the map whole, its
## soldiers drawn like outlaws. The draft's own test (test_econ_army _test_draft) never stages.
static func enlist(game, wb: Dictionary) -> void:
	var ctx := enlist_begin(game, wb)
	if ctx.is_empty():
		return
	enlist_some(game, wb, ctx, (wb["units"] as Array).size())
	enlist_end(game, wb, ctx)

## World size: the draft in parts (CampaignWorld's muster: a few men a work job). enlist_begin returns the draft's
## state ({} when the force enlists nobody): role, the seeded draw's state, the towns' draft pools (pools: a pool the
## caller already built this raising, e.g. spawn_faction_band's look at who the town can spare), the men not raised
## (their places in wb.units), the next man. All of it plain data: it rides in the saved work queue.
static func enlist_begin(game, wb: Dictionary, pools: Dictionary = {}) -> Dictionary:
	if not is_people_band(wb) or String(wb.get("kind", "")) == "militia" or not game.world.has("towns"):
		return {}
	var w: Dictionary = game.world
	var role := "army"
	if wb.get("deserter", false):
		role = "deserter"
	elif String(wb.get("kind", "")) in ["camp", "bandit"]:
		role = "bandit"
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([int(w.get("seed", 0)), String(wb["id"]), "enlist"])
	# pools: war pick 4: town id -> People.draft_pool (who the town can spare), built once per raising
	# unraised: war pick 4: no one to spare for him: the band goes without
	return {"role": role, "rs": str(rng.state), "pools": pools.duplicate(), "unraised": [], "i": 0}

## Enlists up to k more men of wb.units (from ctx.i). Returns true when every man has had his turn.
static func enlist_some(game, wb: Dictionary, ctx: Dictionary, k: int) -> bool:
	var w: Dictionary = game.world
	var role := String(ctx["role"])
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([int(w.get("seed", 0)), String(wb["id"]), "enlist"])
	rng.state = String(ctx["rs"]).to_int()
	var roll: Dictionary = state(w)["roll"]
	var pools: Dictionary = ctx["pools"]
	var units: Array = wb["units"]
	var i0 := int(ctx["i"])
	var i1 := mini(units.size(), i0 + k)
	for ui in range(i0, i1):
		var u = units[ui]
		if u.dead or u.race_def().get("creature", false):
			continue
		if u.family >= 0 and People.fam_of(w["towns"].get(u.home_town, {}), u.family).size() > 0:
			if not roll.has(str(u.uid)):
				roll[str(u.uid)] = [u.home_town, u.family, role, u.name]
			continue
		var tid := _source_town(w, wb, u, role)
		if tid == "":
			(ctx["unraised"] as Array).append(ui)
			continue
		var town: Dictionary = w["towns"][tid]
		var fid := -1
		if role == "army" and not wb.get("staged", false):
			if not pools.has(tid):
				var _t0 := Time.get_ticks_usec()
				pools[tid] = People.draft_pool(town)
				if TownEcon.prof_on: TownEcon._prof("en_pool", _t0)
			fid = People.draft(town, pools[tid], role)
			if fid < 0:
				(ctx["unraised"] as Array).append(ui)   # never a made-up family for a soldier
				continue
		else:
			var camp: Dictionary = w.get("lairs", {}).get(String(wb.get("lair", "")), {})
			var men := maxi(1, (wb["units"] as Array).size())
			var cash := float(camp.get("gold", wb.get("gold", 0)))
			var offer := {"pay_day": minf(float(A()["wage"].get("bandit", 0)), cash / men / 7), "food_days": Supplies.days(wb)}
			fid = People.draw(town, rng, role, offer)
			if fid < 0:
				(ctx["unraised"] as Array).append(ui)
				continue
				# Never invent a person or family to fill an outlaw band.
				# fid = _new_family(game, town, u, role)   # outlaws, deserters, staged scenes (not war pick 4's armies)
		if fid < 0:
			continue
		# he IS the register person drawn (name, birth day); a named chief keeps the name on his bounty
		People.bind(town, fid, u, role, u.name == String(wb.get("named", "")) and u.name != "")
		u.family = fid
		u.home_town = tid
		roll[str(u.uid)] = [tid, fid, role, u.name]
		var f := People.fam_of(town, fid)
		Families.event(f, "joined", [u.name, role, force_word(w, wb)], float(game.day))
	ctx["i"] = i1
	ctx["rs"] = str(rng.state)
	return i1 >= units.size()

## The draft's close: the men nobody could be spared for leave the force; a field band buys its first stores.
static func enlist_end(game, wb: Dictionary, ctx: Dictionary) -> void:
	var w: Dictionary = game.world
	var unraised := {}
	for ui in ctx["unraised"]:
		unraised[int(ui)] = true
	if not unraised.is_empty():
		var keep := []
		var units: Array = wb["units"]
		for ui in units.size():
			if not unraised.has(ui):
				keep.append(units[ui])
		wb["units"] = keep
		wb["unraised"] = int(wb.get("unraised", 0)) + unraised.size()   # (diagnostics: men the town could not spare)
	if (wb["units"] as Array).is_empty():
		return
	if is_field(wb) and Supplies.stores(wb).is_empty():   # a new band sets out with stores bought at home
		var fac: Dictionary = w["factions"].get(String(wb["faction"]), {})
		if not fac.is_empty():
			var _t1 := Time.get_ticks_usec()
			Supplies.provision(game, wb, {"kind": "faction", "fac": fac})
			if TownEcon.prof_on: TownEcon._prof("en_provision", _t1)

static func force_word(w: Dictionary, wb: Dictionary) -> String:
	match String(wb.get("kind", "")):
		"camp", "bandit":
			return "an outlaw band"
		"deserter":
			return "a band of deserters"
	return "the army of %s" % CampaignWorld.faction_the(String(wb["faction"]))   # "the army of the Kingdom of the Middle March"

## A town of his race: the band's home for faction troops and deserters; for outlaws the nearest town of their
## race to the band (ruined families of the region come first in People.draw: hardship weighs in).
static func _source_town(w: Dictionary, wb: Dictionary, u: Unit, role: String) -> String:
	var home := String(wb.get("home", ""))
	if role != "bandit" and w["towns"].has(home) and TownEcon.has_econ(w["towns"][home]):
		return home
	var best := ""; var bd := INF
	for tid in w["towns"]:
		var t: Dictionary = w["towns"][tid]
		if not TownEcon.has_econ(t) or String(TownEcon.culture_of(t["econ"]).get("race", "")) != u.race:
			continue
		if role != "bandit" and t["faction"] != wb["faction"]:
			continue
		var d: float = (t["pos"] as Vector2).distance_squared_to(wb["pos"])
		if d < bd:
			bd = d; best = tid
	if best == "" and w["towns"].has(home) and TownEcon.has_econ(w["towns"][home]):
		best = home
	return best

## Nobody in town can be spared: a family that came in from the countryside (counted from now on).
static func _new_family(game, town: Dictionary, u: Unit, role: String) -> int:
	var e: Dictionary = town["econ"]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([u.uid, town["id"], "newfam"])
	var f := Families.make_family((e["fams"] as Array).size(), u.race, TownEcon.culture_of(e), rng, {})
	f["named"] = true
	f["purse"] = 0.0   # coinage: no coin from nothing (they come with what they carry: nothing counted)
	f["store"] = {"food": 7.0, "drink": 4.0, "wood": 4.0}
	f["last"] = float(game.day)
	f["tax_season"] = int(e["tax"]["season"])
	if Families.adults(f) < 2:
		f["m"] = int(f["m"]) + 1
	f["serve"] = {role: 1}
	(e["fams"] as Array).append(f)
	e["pop"] = int(e["pop"]) + Families.people(f)
	e["adults"] = int(e["adults"]) + Families.adults(f)
	e["homes"] = int(e["homes"]) + int(f["homes"])
	Census.record_move(e, -1, "in", "", float(game.day), "from the countryside", Families.people(f))   # the census: arrivals
	Families.add_hist(f, "Came in from the countryside.", float(game.day))
	return int(f["id"])

## A man leaves his force alive (deserted, scattered, fled a lost fight): home to his family.
static func release(game, u: Unit, why: String, force: String = "") -> void:
	var w: Dictionary = game.world
	var roll: Dictionary = state(w)["roll"]
	var r: Array = roll.get(str(u.uid), [])
	roll.erase(str(u.uid))
	var role: String = r[2] if r.size() > 2 else "army"
	ArmsTrade.kit_home(game, u)   # arms trade: he walks home with his kit (the home armory takes it)
	var town: Dictionary = w["towns"].get(u.home_town, {})
	if u.family < 0 or town.is_empty():
		return
	var person := Persons.by_uid(People.fam_of(town, u.family), u.uid)
	if not person.is_empty() and u.unpaid_days > 0:
		Persons.remember_unpaid(person, role, u.unpaid_days, float(game.day), float(game.day) - Persons.served_since(person, role))
	People.release(town, u.family, role, u.uid)
	var f := People.fam_of(town, u.family)
	if f.is_empty():
		return
	if why == "deserted":
		Families.event(f, "deserted", [u.name, force], float(game.day))
		Families.add_hist(f, "%s came home from %s, unpaid." % [u.name, force], float(game.day))
	elif why in ["ransomed", "released", "exchanged"]:   # v0.033 (campaign/prisoners.gd)
		Families.add_hist(f, "%s came home, %s from captivity." % [u.name, why], float(game.day))
	else:
		Families.add_hist(f, "%s came home after a lost fight." % u.name, float(game.day))

## A band beaten in a fight (AI clash, militia, the company): the dead stay on the field (the sweep takes them
## off their family rows), the living go home. home_share: how many of the living the band loses to flight
## (1 = everyone left alive goes home: the band is gone).
## Returns {"fled": [Unit], "dead": [Unit]} (arms trade: the fled carry their kit home, the dead leave theirs on the field).
static func band_beaten(game, wb: Dictionary, rng: RandomNumberGenerator, home_share: float = 0.5) -> Dictionary:
	var out := {"fled": [], "dead": []}
	if not is_people_band(wb) or String(wb.get("kind", "")) == "militia":
		return out
	if rng == null:   # own stream: the world's rolls stay as they were
		rng = RandomNumberGenerator.new()
		rng.seed = hash([int(game.world.get("seed", 0)), String(wb.get("id", "")), int(game.day), "beaten"])
	fight_pay(game, wb, 1.0)   # barge: a day's wage for the fight, lost or not
	for u in wb["units"]:
		if u.race_def().get("creature", false):
			continue
		if u.dead:
			out["dead"].append(u)
			continue
		if home_share >= 1.0 or rng.randf() < home_share:
			release(game, u, "fled")
			out["fled"].append(u)
		else:
			out["dead"].append(u)
	return out

## Survivors of a fight count a battle (status: veteran / blooded comes at the faction's day). A field band's men
## are paid a day's wage for the fight and a day more for the win (barge part 4 section 8).
static func survived(wb: Dictionary) -> void:
	for u in wb["units"]:
		if not u.dead:
			u.battles += 1
	fight_pay(Game, wb, 2.0)

## Call-up pay: a man new to the realm's colours gets 1.5-2.5 days' wage to sign on, out of the realm's treasury
## into his family's purse (once; only when the treasury can pay it). Marks w.army.signed[uid].
static func sign_on(game, fid: String, units: Array, fac: Dictionary) -> void:
	var st: Dictionary = state(game.world)
	if not st.has("signed"):
		st["signed"] = {}
	var signed: Dictionary = st["signed"]
	var SO: Array = A().get("sign_on", [1.5, 2.5])
	for u in units:
		var k := str(u.uid)
		if signed.has(k) or u.dead:
			continue
		var town: Dictionary = game.world["towns"].get(u.home_town, {})
		var f := People.fam_of(town, u.family)
		if f.is_empty() or f["gone"]:
			signed[k] = true
			continue
		var r := float(absi(hash([u.uid, "signon"])) % 1000) / 1000.0
		var amt := wage("army", u.rank, -1, u) * lerpf(float(SO[0]), float(SO[1]), r)
		if float(fac.get("treasury", 0.0)) < amt:
			continue
		fac["treasury"] = float(fac["treasury"]) - amt
		f["purse"] = float(f["purse"]) + amt
		signed[k] = true

## A day's wage per man for a fight (two for a win), out of the realm's treasury while it lasts. Field bands only.
static func fight_pay(game, wb: Dictionary, days: float) -> void:
	if not is_field(wb) or game == null or not game.world.has("towns"):
		return
	var fac: Dictionary = game.world["factions"].get(String(wb.get("faction", "")), {})
	if fac.is_empty():
		return
	for u in wb["units"]:
		if u.dead:
			continue
		var f := People.fam_of(game.world["towns"].get(u.home_town, {}), u.family)
		if f.is_empty() or f["gone"]:
			continue
		var amt := wage("army", u.rank, -1, u) * days
		if float(fac.get("treasury", 0.0)) < amt:
			return
		fac["treasury"] = float(fac["treasury"]) - amt
		f["purse"] = float(f["purse"]) + amt

# ================================================================== the daily jobs
static func queue_day(w: Dictionary, d: int) -> void:
	var work: Array = w["work"]
	var fids := []
	for wid in w.get("warbands", {}):
		var wb: Dictionary = w["warbands"][wid]
		if is_field(wb) and not fids.has(wb["faction"]):
			fids.append(wb["faction"])
	for fid in state(w)["f"]:
		if not fids.has(fid):
			fids.append(fid)
	fids.sort()
	for fid in fids:
		work.append(["army", fid, d])
	work.append(["army_sweep", d])
	work.append(["army_misc", d])

static func do_job(game, job: Array) -> bool:
	match String(job[0]):
		"army":
			faction_day(game, String(job[1]), int(job[2]), true)
		"army_sweep":
			sweep(game)
		"army_misc":
			camps_day(game)
			company_desertion(game)
		"army_fight":
			fight_step(game, String(job[1]))
		"army_pay":   # world size: one 400-man chunk of the realm's pay (Army.faction_day, split)
			pay_chunk(game, String(job[1]), int(job[2]))
		"army_rk":   # world size: one home town's bands re-arm (the realm's day, Army.faction_day)
			var _t0 := Time.get_ticks_usec()
			ArmsTrade.rekit_town(game, String(job[1]), String(job[2]))
			if TownEcon.prof_on: TownEcon._prof("fd_rekit", _t0)
		"army_tree":
			tree_day(game, String(job[1]), int(job[2]))
		_:
			return false
	return true

## The dead leave their families: everyone on the roll who is no longer alive in a force on the map.
static func sweep(game) -> void:
	var w: Dictionary = game.world
	var here := {}
	for wid in w.get("warbands", {}):
		for u in w["warbands"][wid]["units"]:
			if not u.dead:
				here[str(u.uid)] = true
	for u in CampaignWorld.mustering_units(w):   # world size: a force still being raised (its men are not dead)
		here[str(u.uid)] = true
	for u in Prisoners.units(game):   # v0.033: a soldier held prisoner stays on his realm's roll until freed
		here[str(u.uid)] = true
	var roll: Dictionary = state(w)["roll"]
	for k in roll.keys():
		if here.has(k):
			continue
		var r: Array = roll[k]
		roll.erase(k)
		People.casualty_rec(game, String(r[0]), int(r[1]), String(r[3]), "dead", String(r[2]), [], int(k))

static func faction_day(game, fid: String, day: int, split: bool = false) -> void:
	var w: Dictionary = game.world
	var r := rec(w, fid)
	var units := members(game, fid)
	var cul := cul_of_faction(fid)
	if not units.is_empty(): ArmsPool.day(game, fid, true)   # house arms: the realm's field armies drill and march
	# pay first, then the unpaid walk home
	var order := units.duplicate()
	order.sort_custom(func(a, b): return a.rank > b.rank if a.rank != b.rank else a.uid < b.uid)
	var fac: Dictionary = w["factions"].get(fid, {})
	if not fac.has("treasury"):
		fac["treasury"] = 0.0
	var _t0 := Time.get_ticks_usec()
	# split (the work job's day): pay in 400-man army_pay jobs, first at the front of the queue, so a big
	# realm's payday spreads over frames instead of paying every man in one job. The sorted order, the
	# whole-army low officer (pay_lo), and the day's totals carry in r; pay_chunk does sign_on + pay per
	# chunk, and its last chunk runs supplies and desertion, so the order of the day is unchanged.
	if split and w.has("work"):
		r["pay_queue"] = order.map(func(u): return u.uid)
		r["bill"] = 0.0; r["paid"] = 0.0; r["unpaid_n"] = 0
		var lo := low_officer(order, "army")
		r["pay_lo"] = lo
		r["pay_day"] = day
		var pay_front := []
		if order.is_empty():
			pay_front.append(["army_pay", fid, 0])
		else:
			for start in range(0, order.size(), 400):
				pay_front.append(["army_pay", fid, start])
		for rtid in ArmsTrade.rekit_towns(game, fid):
			pay_front.append(["army_rk", fid, rtid])
		pay_front.append(["army_tree", fid, day])
		var wq: Array = w["work"]
		for i in range(pay_front.size() - 1, -1, -1):
			wq.push_front(pay_front[i])
		return
	sign_on(game, fid, order, fac)   # barge part 4 section 8: call-up pay for men new to the colours
	if TownEcon.prof_on: _t0 = TownEcon._prof("fd_sign_on", _t0)
	var res := pay_units(game, order, {"kind": "faction", "fac": fac}, "army", cul)
	r["bill"] = res["bill"]; r["paid"] = res["paid"]; r["unpaid_n"] = res["unpaid"]
	_band_unpaid(w, fid)
	if TownEcon.prof_on: _t0 = TownEcon._prof("fd_pay", _t0)
	# the bands eat out of their stores and top them up from home (the faction pays the market)
	for wid in w["warbands"]:
		var wb: Dictionary = w["warbands"][wid]
		if wb["faction"] == fid and is_field(wb):
			Supplies.eat(wb)
			Supplies.provision(game, wb, {"kind": "faction", "fac": fac}, day)
	if TownEcon.prof_on: _t0 = TownEcon._prof("fd_supplies", _t0)
	desertion(game, fid)
	if TownEcon.prof_on: _t0 = TownEcon._prof("fd_desertion", _t0)
	# world size (split: the work job's day): the rest of the realm's day as work jobs at the FRONT of the queue (a big
	# time jump runs them back to back, in this order, as the one job did): each home town's bands re-arm from its
	# armory (arms trade; a job per town, bands in map order), then the rank tree. Not split: all of it now.
	if not split or not w.has("work"):
		for tid in ArmsTrade.rekit_towns(game, fid):
			ArmsTrade.rekit_town(game, fid, tid)
		tree_day(game, fid, day)
		return
	var front := []
	for tid in ArmsTrade.rekit_towns(game, fid):
		front.append(["army_rk", fid, tid])
	front.append(["army_tree", fid, day])
	var work: Array = w["work"]
	for i in range(front.size() - 1, -1, -1):
		work.push_front(front[i])

## One 400-man chunk of the realm's payday (split days): the men of r.pay_queue[start..start+400], rebuilt
## from the map by uid (a man gone or dead since the roster was sorted is skipped), signed on and paid at
## the whole army's low officer (r.pay_lo). The chunk reaching the end of the queue closes the day as
## faction_day did after pay: band unpaid counts, supplies, then desertion; the queue is erased.
static func pay_chunk(game, fid: String, start: int) -> void:
	var w: Dictionary = game.world
	var r := rec(w, fid)
	var queue: Array = r.get("pay_queue", [])
	var cul := cul_of_faction(fid)
	var fac: Dictionary = w["factions"].get(fid, {})
	if not fac.has("treasury"):
		fac["treasury"] = 0.0
	var by := {}
	for u in members(game, fid):
		by[int(u.uid)] = u
	var chunk := []
	for i in range(start, mini(start + 400, queue.size())):
		var u = by.get(int(queue[i]), null)
		if u != null and not u.dead:
			chunk.append(u)
	var _t0 := Time.get_ticks_usec()
	sign_on(game, fid, chunk, fac)
	if TownEcon.prof_on: _t0 = TownEcon._prof("fd_sign_on", _t0)
	var res := pay_units(game, chunk, {"kind": "faction", "fac": fac}, "army", cul, int(r.get("pay_lo", -2)))
	r["bill"] = float(r.get("bill", 0.0)) + float(res["bill"])
	r["paid"] = float(r.get("paid", 0.0)) + float(res["paid"])
	r["unpaid_n"] = int(r.get("unpaid_n", 0)) + int(res["unpaid"])
	if TownEcon.prof_on: _t0 = TownEcon._prof("fd_pay", _t0)
	if start + 400 < queue.size():
		return
	_band_unpaid(w, fid)
	# the bands eat out of their stores and top them up from home (the faction pays the market)
	for wid in w["warbands"]:
		var wb: Dictionary = w["warbands"][wid]
		if wb["faction"] == fid and is_field(wb):
			Supplies.eat(wb)
			Supplies.provision(game, wb, {"kind": "faction", "fac": fac}, int(r.get("pay_day", game.day)))
	if TownEcon.prof_on: _t0 = TownEcon._prof("fd_supplies", _t0)
	desertion(game, fid)
	if TownEcon.prof_on: _t0 = TownEcon._prof("fd_desertion", _t0)
	r.erase("pay_queue")

## The realm's rank tree at the end of its day (its own work job, after the towns' re-arming).
static func tree_day(game, fid: String, day: int) -> void:
	var _t0 := Time.get_ticks_usec()
	update_tree(game, fid, members(game, fid), false, day)
	if TownEcon.prof_on: _t0 = TownEcon._prof("fd_tree", _t0)

## Per band: how many of its men went unpaid today (UI, tests).
static func _band_unpaid(w: Dictionary, fid: String) -> void:
	for wid in w["warbands"]:
		var wb: Dictionary = w["warbands"][wid]
		if wb["faction"] != fid or not is_field(wb):
			continue
		var n := 0
		for u in wb["units"]:
			if not u.dead and u.unpaid_days > 0:
				n += 1
		wb["unpaid_n"] = n

# ================================================================== pay
## Daily wage of a man of rank `r` in a force of `tier`. Officers are paid by their level counted from the lowest
## officer rank the force actually has (`lo`): a small army's lord general over a handful of men is paid as a low
## officer, a great army's as a great one (rank names fill top-down; pay follows the size of the command).
## Barge part 3 section 3 (Douglas 01:47-01:49), every race, in coins: rank base recruit 70, soldier 100, sergeant 150,
## officer 240, deputy 360, commander 500 (the status ranks, then the officer levels from the lowest the force has),
## plus 5 a day per grade (0-10) of skill with the weapon he serves with (our ladder 0-15 up to Legendary). A militia
## levyman is a recruit, a town guardsman a soldier; bandit gangs pay hired-band money (25 a man).
static func wage(tier: String, r: int, lo: int = -1, u: Unit = null) -> float:
	var a := A()
	if tier == "bandit":
		return float(a["wage"]["bandit"])
	var RB: Array = a["rank_base"]
	var fo := first_officer(tier)
	var base := 0.0
	if r < fo:
		var s := r
		if tier == "guard":
			s = 1   # a town guard is a full soldier
		elif tier == "militia":
			s = 0
		base = float(RB[clampi(s, 0, 1)])
	else:
		base = float(RB[clampi(2 + r - maxi(fo, lo), 2, RB.size() - 1)])
	return base + float(a["per_grade"]) * float(skill_grade(u))

## The grade (0-10) of a man's skill with the weapon he carries: our ladder 0..15 (Dabbling..Legendary) to 0..10.
static func skill_grade(u: Unit) -> int:
	if u == null:
		return 0
	var wpn = u.weapon() if u.has_method("weapon") else null
	var sk := ""
	if wpn != null:
		sk = String(wpn.tmpl().get("skill", ""))
	var lvl := u.skill(sk) if sk != "" else 0
	return clampi(int(round(float(mini(lvl, 15)) * 10.0 / 15.0)), 0, 10)

## The lowest officer rank among these men (-1 none).
static func low_officer(units: Array, tier: String) -> int:
	var fo := first_officer(tier)
	var lo := 999
	for u in units:
		if not u.dead and u.rank >= fo and u.rank < lo:
			lo = u.rank
	return lo if lo < 999 else -1

## Pays the men (in order, while the payer lasts) in the culture's pay form. payer: {kind: faction, fac} |
## {kind: town, e} | {kind: camp, l}. Coin goes to the family purse; food and beer are bought by the payer from
## the man's home market (payer -> market till, market stock -> the family's stores); the loot share comes out of
## the faction's loot chest (short: coin). A man the payer cannot cover counts an unpaid day.
## Returns {bill, paid, unpaid}.
static func pay_units(game, units: Array, payer: Dictionary, tier: String, cul: Dictionary, lo_override: int = -2) -> Dictionary:
	var w: Dictionary = game.world
	var mix: Dictionary = cul.get("pay", {"coin": 1.0})
	if String(payer["kind"]) == "camp":
		mix = {"coin": 1.0}
	var lo := lo_override if lo_override >= -1 else low_officer(units, tier)
	var bill := 0.0; var paid := 0.0; var unpaid := 0
	for u in units:
		if u.dead:
			continue
		var wg := wage(tier, u.rank, lo, u)
		bill += wg
		var town: Dictionary = w["towns"].get(u.home_town, {})
		var f := People.fam_of(town, u.family)
		if f.is_empty() or f["gone"]:
			u.unpaid_days = 0   # nobody at home to pay (an orphaned record): he serves for his keep
			continue
		var e: Dictionary = town["econ"]
		var coin := wg * float(mix.get("coin", 0.0))
		var loot := wg * float(mix.get("loot", 0.0))
		var took_loot := 0.0
		if loot > 0.0 and String(payer["kind"]) == "faction":
			took_loot = minf(loot, float(payer["fac"].get("loot", 0.0)))
		coin += loot - took_loot
		# kind: food (grain, then meat) and beer from the home market
		var buys := []
		var kind_cost := 0.0
		for part in [["food", ["grain", "meat"]], ["beer", ["beer"]]]:
			var val := wg * float(mix.get(part[0], 0.0))
			if val <= 0.0:
				continue
			for g in part[1]:
				if val <= 0.01:
					break
				var p := float(e["price"].get(g, 1.0))
				var q := mini(int(val / p), int(e["stock"].get(g, 0)))
				if q > 0:
					buys.append([g, q, part[0]])
					kind_cost += float(q) * p
					val -= float(q) * p
			coin += val   # what the market could not supply comes as coin
		var need := coin + kind_cost
		if _funds(payer) < need:
			u.unpaid_days += 1
			u.last_pay = 0.0
			unpaid += 1
			continue
		_spend(payer, need)
		if String(payer["kind"]) == "camp":
			TownEcon.gold_out(-need)   # stolen coin comes back into a town purse
		if took_loot > 0.0:
			payer["fac"]["loot"] = float(payer["fac"]["loot"]) - took_loot
			TownEcon.gold_out(-took_loot)   # loot comes back into a town purse
		f["purse"] = float(f["purse"]) + coin + took_loot
		if kind_cost > 0.0:
			var mkt: Dictionary = e["biz"][int(e["mkt"])]
			mkt["till"] = float(mkt["till"]) + kind_cost
			var rates := Families.daily_rates(e, f)
			for b in buys:
				e["stock"][b[0]] = int(e["stock"][b[0]]) - int(b[1])
				e["hh"][b[0]] = int(e["hh"].get(b[0], 0)) + int(b[1])
				var key := "food" if b[2] == "food" else "drink"
				f["store"][key] = float(f["store"][key]) + float(b[1]) / maxf(0.5, float(rates[key]))
		u.unpaid_days = 0
		u.last_pay = need + took_loot
		paid += need + took_loot
	return {"bill": bill, "paid": paid, "unpaid": unpaid}

static func _funds(payer: Dictionary) -> float:
	match String(payer["kind"]):
		"company": return float(payer["game"].gold)
		"faction": return float(payer["fac"].get("treasury", 0.0))
		"town": return float(payer["e"]["treasury"])
		"camp": return float(payer["l"].get("gold", 0.0))
	return 0.0

static func _spend(payer: Dictionary, v: float) -> void:
	match String(payer["kind"]):
		"company": payer["game"].gold -= int(v)
		"faction": payer["fac"]["treasury"] = float(payer["fac"]["treasury"]) - v
		"town": payer["e"]["treasury"] = float(payer["e"]["treasury"]) - v
		"camp": payer["l"]["gold"] = float(payer["l"].get("gold", 0.0)) - v

## A faction's daily wage bill (UI and the faction turn's reserve).
static func bill(game, fid: String) -> float:
	var r: Dictionary = game.world.get("army", {}).get("f", {}).get(fid, {})
	if r.has("bill") and float(r["bill"]) > 0.0:
		return float(r["bill"])
	var ms := members(game, fid)
	var lo := low_officer(ms, "army")
	var b := 0.0
	for u in ms:
		b += wage("army", u.rank, lo, u)
	return b

## A realm raises a new band only when its treasury can pay n more men for desert_days (it does not hire men it
## knows it cannot pay). Factions outside the economy (no towns) always can.
static func can_raise(game, fid: String, n: int) -> bool:
	var fac: Dictionary = game.world.get("factions", {}).get(fid, {})
	if fac.is_empty() or not game.world.has("army"):
		return true
	var need := float(n) * wage("army", 0) * float(A()["desert_days"]) + bill(game, fid) * 3.0
	return float(fac.get("treasury", 0.0)) >= need

static func days_of_pay(game, fid: String) -> float:
	var b := bill(game, fid)
	return float(game.world["factions"].get(fid, {}).get("treasury", 0.0)) / b if b > 0.0 else INF

## Militia / town guard: the town treasury pays by rank (called by the daily town pass).
static func town_tier(town: Dictionary) -> String:
	return "militia"

static func pay_town(game, town: Dictionary) -> float:
	if not TownEcon.has_econ(town):
		return 0.0
	var e: Dictionary = town["econ"]
	TownDefence.daily(game, town)
	var wb := Militia.band_of(game, town["id"])
	if wb.is_empty():
		e["stats"]["militia_wages"] = 0.0
		e["stats"]["militia_bill"] = 0.0
		return 0.0
	if not wb.get("mustered", false) and not wb.get("drill_today", false):
		e["stats"]["militia_wages"] = 0.0; e["stats"]["militia_bill"] = 0.0
		return 0.0
	var units: Array = (wb["units"] as Array).filter(func(u): return not u.dead)
	units.sort_custom(func(a, b): return a.rank > b.rank if a.rank != b.rank else a.uid < b.uid)
	var tier := town_tier(town)
	# barge part 4 section 1: the garrison is paid when the treasury holds the bill and a reserve (a quarter of its short
	# line [ours]); else the day's pay is owed, and repaid when the treasury can (the owed coin goes to the men's homes)
	var bill := town_bill(game, town)
	var reserve := float(Barge.treasury_lines(e)["short"]) * 0.25
	var res := {}
	if float(e["treasury"]) >= bill + reserve:
		res = pay_units(game, units, {"kind": "town", "e": e}, tier, TownEcon.culture_of(e))
		var owed := float(e.get("garrison_owed", 0.0))
		if owed > 0.0 and float(e["treasury"]) > owed + reserve + bill * 7.0 and not units.is_empty():
			var each := owed / float(units.size())
			for u in units:
				var f := People.fam_of(town, u.family)
				if not f.is_empty() and not f["gone"]:
					f["purse"] = float(f["purse"]) + each
					e["treasury"] = float(e["treasury"]) - each
					e["garrison_owed"] = float(e["garrison_owed"]) - each
	else:
		for u in units:
			u.unpaid_days += 1
			u.last_pay = 0.0
		e["garrison_owed"] = float(e.get("garrison_owed", 0.0)) + bill
		res = {"bill": bill, "paid": 0.0, "unpaid": units.size()}
	e["stats"]["militia_wages"] = res["paid"]
	e["stats"]["militia_bill"] = res["bill"]
	e["stats"]["militia_unpaid"] = res["unpaid"]
	wb["unpaid_n"] = res["unpaid"]
	# (militiamen live and eat at home: no field stores; what they win in a fight they hold for the town)
	# the unpaid walk home; the rest keep their ranks (the tree is per band)
	# barge part 4 section 8: unpaid militia desert 12% a day (each man his own roll, seeded)
	var gone := []
	var md := float(A().get("militia_desert", 0.12))
	for u in units:
		if u.unpaid_days > 0:
			var r := float(absi(hash([u.uid, int(game.day), "mdesert"])) % 10000) / 10000.0
			if r < md:
				gone.append(u)
	for u in gone:
		(wb["units"] as Array).erase(u)
		ArmsTrade.kit_home(game, u)   # arms trade: his kit stays in the town's armory
		People.release(town, u.family, "militia", u.uid)
		var f := People.fam_of(town, u.family)
		if not f.is_empty():
			Families.event(f, "deserted", [u.name, "the militia"], float(game.day))
	if not gone.is_empty():
		CampaignWorld.log_event(game, "%d of the militia of %s went home unpaid." % [gone.size(), town["name"]])
	update_band_tree(game, town, wb, tier)
	return float(res["paid"])

static func town_bill(game, town: Dictionary) -> float:
	var e: Dictionary = town.get("econ", {})
	var b := float(e.get("stats", {}).get("militia_bill", 0.0))
	if b <= 0.0:
		var tier := town_tier(town)
		var ms := Militia.units_of(game, town["id"])
		var lo := low_officer(ms, tier)
		for u in ms:
			b += wage(tier, u.rank, lo, u)
	return b

# ================================================================== desertion
static func desertion(game, fid: String) -> void:
	var w: Dictionary = game.world
	var dd := int(A()["desert_days"])
	var n := 0
	for wid in w["warbands"].keys():
		var wb: Dictionary = w["warbands"].get(wid, {})
		if wb.is_empty() or wb["faction"] != fid or not is_field(wb):
			continue
		var gone := []
		for u in wb["units"]:
			if not u.dead and u.unpaid_days >= dd:
				gone.append(u)
		for u in gone:
			(wb["units"] as Array).erase(u)
			release(game, u, "deserted", force_word(w, wb))
			n += 1
		if (wb["units"] as Array).is_empty():
			CampaignWorld.remove_warband(game, wid)
	if n > 0:
		_hist(game, fid, "%d unpaid soldiers walked home." % n)

## Bandit camps pay their men from the hoard: camp gold first, then a stolen piece fenced at the nearest town's
## stalls (the item goes into its arms stock, the market pays the camp). Unpaid gangs scatter home; garrison men
## walk off one by one (the chief stays).
static func camps_day(game) -> void:
	var w: Dictionary = game.world
	var cul: Dictionary = TownEcon.data()["cultures"]["middle"]
	for lid in w.get("lairs", {}).keys():
		var l: Dictionary = w["lairs"].get(lid, {})
		if l.get("kind", "") != "bandit_camp":
			continue
		var bands := []
		var g: Dictionary = w["warbands"].get(String(l.get("resident", "")), {})
		if not g.is_empty():
			bands.append(g)
		for wid in Bandits.bands_of(game, lid):
			bands.append(w["warbands"][wid])
		var men := []
		for b in bands:
			for u in b["units"]:
				if not u.dead:
					men.append(u)
		men.sort_custom(func(a, b2): return a.is_officer() and not b2.is_officer())
		var need := float(men.size()) * float(A()["wage"]["bandit"])
		var tries := 0
		while float(l.get("gold", 0.0)) < need and tries < 3 and not (l.get("stock", []) as Array).is_empty():
			if not _fence(w, l):
				break
			tries += 1
		pay_units(game, men, {"kind": "camp", "l": l}, "bandit", cul)
		for b in bands:
			Supplies.eat(b)
		for b in bands:
			var sd := int(A()["scatter_days"])
			if b["kind"] == "bandit":
				if (b["units"] as Array).any(func(u): return not u.dead and u.unpaid_days >= sd):
					for u in b["units"]:
						if not u.dead:
							release(game, u, "deserted", "an outlaw band")
					CampaignWorld.log_event(game, "An unpaid outlaw gang near %s scattered." % CampaignWorld.nearest_town_name(w, b["pos"]))
					CampaignWorld.remove_warband(game, b["id"])
			else:
				var gone := (b["units"] as Array).filter(func(u): return not u.dead and u.unpaid_days >= sd and u.name != String(b.get("named", "")))
				for u in gone:
					(b["units"] as Array).erase(u)
					release(game, u, "deserted", "an outlaw band")

static func _fence(w: Dictionary, l: Dictionary) -> bool:
	var tid := CampaignWorld.nearest_town(w, l["pos"])
	var town: Dictionary = w["towns"].get(tid, {})
	if not TownEcon.has_econ(town):
		return false
	var stock: Array = l["stock"]
	var cheapest := 0
	for i in stock.size():
		if (stock[i] as Item).value() < (stock[cheapest] as Item).value():
			cheapest = i
	var it: Item = stock[cheapest]
	var e: Dictionary = town["econ"]
	var mkt: Dictionary = e["biz"][int(e["mkt"])]
	var price := float(it.value()) * float(TownEcon.data()["market"]["arms_buy_share"])
	if float(mkt["till"]) < price or price <= 0.0:
		return false
	stock.remove_at(cheapest)
	mkt["till"] = float(mkt["till"]) - price
	l["gold"] = float(l.get("gold", 0.0)) + price
	TownEcon.gold_out(price)   # the camp sits outside the town ledgers
	(town["shop"] as Array).append(it)
	return true

## Company men unpaid company_desert_days in a row walk home to their families.
static func company_desertion(game) -> void:
	var dd := int(A()["company_desert_days"])
	var gone: Array = game.company.filter(func(u): return not u.dead and u.unpaid_days >= dd)
	for u in gone:
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
		game.company.erase(u)
		game.squads.erase(u.uid)
		ArmsTrade.kit_home(game, u)   # arms trade: he takes his kit home and hands it in for coin
		for t in game.company:
			if t.squad == u.uid:
				t.squad = -1
		var town: Dictionary = game.world["towns"].get(u.home_town, {})
		var f := People.fam_of(town, u.family)
		if not f.is_empty() and not f["gone"]:
			# back on the family row (he left it when hired): his own register record comes home with him
			var p := Persons.by_uid(f, u.uid)
			var s := "m"
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

# ================================================================== loot chest
## A faction's raiders took a caravan: its purse goes to the realm's loot chest (pays the loot share).
## Any winner also loads the cargo's food and drink into its stores, up to what it can carry (those goods leave
## the caravan here and are booked as lost to the towns; the rest is lost with the wagons in Caravans.lost).
## (The caravan purse stays on the record: Caravans.lost books it out of the towns; the chest holds it now.)
static func on_plunder(w: Dictionary, winner: Dictionary, car: Dictionary) -> void:
	var home: Dictionary = w.get("towns", {}).get(String(car.get("origin", "")), {})
	if TownEcon.has_econ(home):   # the caravan's town remembers who took it
		var by := "outlaws" if String(winner.get("kind", "")) in ["bandit", "deserter"] else CampaignWorld.faction_the(String(winner.get("faction", "")))
		TownEcon.town_event(home["econ"], "caravan_lost", [by], float(w.get("last_day", 0)))
	var cg: Dictionary = car.get("cargo", {}).get("goods", {})
	var src := {}
	for g in Supplies.FOOD + Supplies.DRINK:
		if int(cg.get(g, 0)) > 0:
			src[g] = int(cg[g])
	if not src.is_empty():
		var got := Supplies.take(winner, {"stores": src, "units": []})
		for g in got:
			cg[g] = int(cg[g]) - int(got[g])
			TownEcon.goods_lost[g] = int(TownEcon.goods_lost.get(g, 0)) + int(got[g])
	if String(winner.get("kind", "")) == "bandit":
		var l: Dictionary = w.get("lairs", {}).get(String(winner.get("home", "")), {})
		if not l.is_empty():
			l["gold"] = float(l.get("gold", 0.0)) + float(car.get("gold", 0.0))
			car["purse_taken"] = true
		return
	var fac: Dictionary = w["factions"].get(String(winner.get("faction", "")), {})
	if not fac.is_empty():
		fac["loot"] = float(fac.get("loot", 0.0)) + float(car.get("gold", 0.0))
		car["purse_taken"] = true

## A town sacked: the raiders carry sack_take of its treasury home to their realm's loot chest.
static func on_sack(w: Dictionary, town: Dictionary, att: String) -> void:
	var fac: Dictionary = w["factions"].get(att, {})
	if fac.is_empty() or not TownEcon.has_econ(town):
		return
	var e: Dictionary = town["econ"]
	TownEcon.town_event(e, "sacked", [CampaignWorld.faction_the(att)], float(w.get("last_day", 0)))   # its people remember
	var take := maxf(0.0, float(e["treasury"])) * float(A()["sack_take"])
	var lord: Dictionary = Feudal.tax_recipient(Game, str(town.get("id", "")))   # the ruling house's treasure hoard is carried off too
	if str(lord.get("household_uid", "")) != "":
		var seized: Array = CourtEvents.seize_hoard(Game, str(lord["household_uid"]), float(A()["sack_take"]))
		if not seized.is_empty():
			if not fac.has("loot_hoard"): fac["loot_hoard"] = []
			(fac["loot_hoard"] as Array).append_array(seized)
	e["treasury"] = float(e["treasury"]) - take
	fac["loot"] = float(fac.get("loot", 0.0)) + take
	TownEcon.gold_out(take)   # out of the town ledgers into the raiders' chest
	Herds.on_sack(w, town, att)   # herds: the raiders drive off a share of the beasts (theft, logged)

# ================================================================== ranks, duels, militia trees & views (campaign/army_ranks.gd)
static var _rep_by: Dictionary = {}
static var _rep_key := []
static var _rep_map: Dictionary = {}

static func update_tree(game, fid: String, units: Array, prehistory: bool, day: int) -> void: ArmyRanks.update_tree(game, fid, units, prehistory, day)
static func _demote(u: Unit) -> void: ArmyRanks._demote(u)
static func candidates(game, fid: String, p: int, by: Dictionary, prehistory: bool) -> Array: return ArmyRanks.candidates(game, fid, p, by, prehistory)
static func house_born(u: Unit) -> bool: return ArmyRanks.house_born(u)
static func call_up_nobles(game, fid: String, most: int) -> Array: return ArmyRanks.call_up_nobles(game, fid, most)
static func _reports(by: Dictionary, lv: int, span: int, fo: int) -> Dictionary: return ArmyRanks._reports(by, lv, span, fo)
static func fill(game, fid: String, p: int, by: Dictionary, prehistory: bool, day: int, relink: bool = true) -> void: ArmyRanks.fill(game, fid, p, by, prehistory, day, relink)
static func assign(game, fid: String, p: int, u: Unit, by: Dictionary, prehistory: bool, day: int, beat: Array, relink: bool = true) -> void: ArmyRanks.assign(game, fid, p, u, by, prehistory, day, beat, relink)
static func _war_leader(game, fid: String, u: Unit, title: String) -> void: ArmyRanks._war_leader(game, fid, u, title)
static func _hist(game, fid: String, text: String) -> void: ArmyRanks._hist(game, fid, text)
static func _queue_fight(w: Dictionary, fid: String) -> void: ArmyRanks._queue_fight(w, fid)
static func fight_step(game, fid: String, budget_usec: int = 4000) -> void: ArmyRanks.fight_step(game, fid, budget_usec)
static func _fight_one(game, fid: String, by: Dictionary) -> void: ArmyRanks._fight_one(game, fid, by)
static func _bury(game, u: Unit) -> void: ArmyRanks._bury(game, u)
static func duel(a: Unit, b: Unit, seed: int) -> Dictionary: return ArmyRanks.duel(a, b, seed)
static func update_band_tree(game, town: Dictionary, wb: Dictionary, tier: String) -> void: ArmyRanks.update_band_tree(game, town, wb, tier)
static func tree_rows(game, fid: String) -> Array: return ArmyRanks.tree_rows(game, fid)
static func rank_title(u: Unit) -> String: return ArmyRanks.rank_title(u)

# ================================================================== world gen / load
## World gen (and old saves): every soldier gets his family, every tree its officers (pre-history: by the
## rule's score, no fights), every faction an opening purse of start_days of its wage bill.
static func init_world(game) -> void:
	var run := init_begin(game)
	while not init_part(game, run):
		pass

## A few real drafts per part, then one faction and one militia town. The context is
## caller-local; army generation never interleaves with the next world stage.
static func init_begin(game) -> Dictionary:
	var w: Dictionary = game.world
	state(w)
	return {"phase": "bands", "i": 0, "ids": w.get("warbands", {}).keys()}

static func init_part(game, run: Dictionary) -> bool:
	var w: Dictionary = game.world
	var ids: Array = run["ids"]
	var i: int = run["i"]
	match String(run["phase"]):
		"bands":
			if i < ids.size():
				var wid := String(ids[i])
				var wb: Dictionary = w["warbands"].get(wid, {})
				if not wb.is_empty():
					if not run.has("enlist"):
						if is_people_band(wb) and String(wb.get("kind", "")) != "militia": Supplies.seed_stores(wb)
						run["enlist"] = enlist_begin(game, wb)
					var ctx: Dictionary = run["enlist"]
					if not ctx.is_empty():
						if not enlist_some(game, wb, ctx, CampaignWorld.MUSTER_STEP): return false
						enlist_end(game, wb, ctx)
					if (wb["units"] as Array).is_empty(): w["warbands"].erase(wid)
				run.erase("enlist")
				run["i"] = i + 1
			else:
				# The original faction stream starts only after all bands enlist.
				var rng := RandomNumberGenerator.new()
				rng.seed = hash([int(w.get("seed", 0)), "army-gen"])
				run["rng"] = rng
				var fids: Array = w.get("factions", {}).keys()
				fids.sort()
				run["ids"] = fids
				run["phase"] = "factions"; run["i"] = 0
		"factions":
			if i < ids.size():
				_init_faction(game, String(ids[i]), run["rng"])
				run["i"] = i + 1
			else:
				run["ids"] = w.get("militia", {}).keys()   # original insertion order
				run["phase"] = "militia"; run["i"] = 0
		"militia":
			if i < ids.size():
				_init_militia(game, String(ids[i]))
				run["i"] = i + 1
			return int(run["i"]) >= ids.size()
	return false

static func _init_band(game, wid: String) -> void:
	var w: Dictionary = game.world
	var wb: Dictionary = w["warbands"].get(wid, {})
	if not wb.is_empty():
		if is_people_band(wb) and String(wb.get("kind", "")) != "militia":
			Supplies.seed_stores(wb)   # pre-history: what the band set out with
		enlist(game, wb)
		if (wb["units"] as Array).is_empty():
			w["warbands"].erase(wid)   # war pick 4: its town could spare nobody: never raised

static func _init_faction(game, fid: String, rng: RandomNumberGenerator) -> void:
	var w: Dictionary = game.world
	if not DB.factions.has(fid) or Monsters.is_monster_faction(fid) or Monsters.is_wild_faction(fid):
		return
	var units := members(game, fid)
	for u in units:   # pre-history: about a third have seen a fight
		if u.battles == 0 and rng.randf() < 0.35:
			u.battles = 1
	update_tree(game, fid, units, true, int(game.day))
	var r := rec(w, fid)
	var fac: Dictionary = w["factions"][fid]
	if not r.get("seeded", false):
		r["seeded"] = true
		r["bill"] = 0.0
		fac["treasury"] = float(fac.get("treasury", 0.0)) + bill(game, fid) * float(A()["start_days"])

static func _init_militia(game, tid: String) -> void:
	var w: Dictionary = game.world
	var town: Dictionary = w["towns"].get(tid, {})
	var mb := Militia.band_of(game, tid)
	if not town.is_empty() and not mb.is_empty() and TownEcon.has_econ(town):
		update_band_tree(game, town, mb, town_tier(town))

static func after_load(game) -> void:
	var w: Dictionary = game.world
	if not w.has("towns"):
		return
	if not w.has("army"):
		init_world(game)   # saves from before economy spec 2
		return
	var st := state(w)
	st["v"] = int(st.get("v", 1))
	for k in st["roll"]:
		var r: Array = st["roll"][k]
		r[1] = int(r[1])
	for fid in st["f"]:
		var r2: Dictionary = st["f"][fid]
		r2["levels"] = int(r2["levels"])
		r2["unpaid_n"] = int(r2.get("unpaid_n", 0))
		var posts: Array = r2["posts"]
		for i in posts.size():
			posts[i] = int(posts[i])
		for fgt in r2.get("fights", []):
			fgt["p"] = int(fgt["p"])
			var c: Array = fgt["c"]
			for i in c.size():
				c[i] = int(c[i])
	for wid in w.get("warbands", {}):
		var wb: Dictionary = w["warbands"][wid]
		if wb.has("posts"):
			var p2: Array = wb["posts"]
			for i in p2.size():
				p2[i] = int(p2[i])
		if wb.has("unpaid_n"):
			wb["unpaid_n"] = int(wb["unpaid_n"])
