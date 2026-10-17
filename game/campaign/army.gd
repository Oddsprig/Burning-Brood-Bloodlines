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

# ================================================================== tree math
static func ranks(cul: Dictionary, tier: String) -> Array:
	return cul.get("ranks", {}).get(tier, ["soldier"])

## First officer rank index: army lists keep two status ranks, militia/guard one.
static func first_officer(tier: String) -> int:
	return 2 if tier == "army" else 1

static func levels_for(n: int, span: int, n_off: int) -> int:
	var l := 0
	var p := 1
	while l < n_off:
		p *= span
		if p > n:
			break
		l += 1
	return l

static func offset(k: int, span: int) -> int:
	var o := 0
	var p := 1
	for i in k:
		o += p
		p *= span
	return o

## Posts at each level from the top (caps): [1, span, span^2 ...] for `levels` levels.
static func caps(levels: int, span: int) -> Array:
	var out := []
	var p := 1
	for i in levels:
		out.append(p)
		p *= span
	return out

static func level_of(idx: int, span: int) -> int:
	var k := 0
	while offset(k + 1, span) <= idx:
		k += 1
	return k

static func up_of(idx: int, span: int) -> int:
	var k := level_of(idx, span)
	if k == 0:
		return -1
	return offset(k - 1, span) + (idx - offset(k, span)) / span

static func children_of(idx: int, span: int, levels: int) -> Array:
	var k := level_of(idx, span)
	if k + 1 >= levels:
		return []
	var j := idx - offset(k, span)
	var s := offset(k + 1, span) + j * span
	return range(s, s + span)

## Rank index of a post at level k (top = last rank of the list).
static func rank_at(k: int, rl: Array) -> int:
	return rl.size() - 1 - k

## Rank and file report to a bottom post by uid (stable while the tree keeps its shape).
static func report_post(u: Unit, levels: int, span: int) -> int:
	if levels <= 0:
		return -1
	var b0 := offset(levels - 1, span)
	var bn := offset(levels, span) - b0
	return b0 + (u.uid % bn)

## Caller-local pure command plan from the real roster and authoritative posts.
## No ranks/officers are created here; duplicate UID/post claims fail closed.
static func command_plan(units: Array, posts: Array, levels: int, span: int, fid: String, protected_units: Array = []) -> Array:
	span = maxi(2, span)
	levels = maxi(0, levels)
	var protected_ids: Dictionary = {}
	for value: Variant in protected_units:
		if value is Unit: protected_ids[value.get_instance_id()] = true
	var by: Dictionary = {}
	var ambiguous: Dictionary = {}
	var seen: Dictionary = {}
	var roster: Array = []
	for value: Variant in units:
		if not value is Unit: continue
		var u: Unit = value
		var instance: int = u.get_instance_id()
		if seen.has(instance): continue
		seen[instance] = true
		if u.dead or u.faction != fid or u.faction == "player" or protected_ids.has(instance): continue
		roster.append(u)
		if u.uid <= 0 or ambiguous.has(u.uid): continue
		if by.has(u.uid):
			ambiguous[u.uid] = true
			by.erase(u.uid)
		else:
			by[u.uid] = u
	var count: int = mini(posts.size(), offset(levels,span))
	var holds: Dictionary = {}
	for p: int in count:
		var uid: int = int(posts[p])
		if uid <= 0 or not by.has(uid) or not (by[uid] as Unit).is_officer(): continue
		holds[uid] = -2 if holds.has(uid) else p
	# Parent posts precede children. Resolve vacant/dead/absent branches once,
	# instead of scanning officers or walking the whole tree for every man.
	var nearest: Array = []
	nearest.resize(count)
	for p: int in count:
		var uid: int = int(posts[p])
		var parent: int = up_of(p,span)
		nearest[p] = uid if int(holds.get(uid,-1)) == p else (nearest[parent] if parent >= 0 else -1)
	var plan: Array = []
	for u: Unit in roster:
		var commander: int = -1
		if by.get(u.uid) == u:
			var post: int = int(holds.get(u.uid,-1))
			var parent: int = up_of(post,span) if post >= 0 else (report_post(u,levels,span) if not u.is_officer() else -1)
			if parent >= 0 and parent < count:
				commander = int(nearest[parent])
			if commander == u.uid: commander = -1
		plan.append({"unit":u,"commander_uid":commander})
	return plan

static func _apply_commands(game, units: Array, posts: Array, levels: int, span: int, fid: String) -> void:
	for row: Dictionary in command_plan(units,posts,levels,span,fid,game.company):
		(row["unit"] as Unit).squad = int(row["commander_uid"])

static func _link_field_commands(game, fid: String) -> void:
	var r: Dictionary = rec(game.world,fid)
	var span: int = maxi(2,int(cul_of_faction(fid).get("span",5)))
	_apply_commands(game,members(game,fid),r["posts"],int(r["levels"]),span,fid)

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
			Supplies.provision(game, wb, {"kind": "faction", "fac": fac})
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
			Supplies.provision(game, wb, {"kind": "faction", "fac": fac})
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
		"faction": return float(payer["fac"].get("treasury", 0.0))
		"town": return float(payer["e"]["treasury"])
		"camp": return float(payer["l"].get("gold", 0.0))
	return 0.0

static func _spend(payer: Dictionary, v: float) -> void:
	match String(payer["kind"]):
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
	e["treasury"] = float(e["treasury"]) - take
	fac["loot"] = float(fac.get("loot", 0.0)) + take
	TownEcon.gold_out(take)   # out of the town ledgers into the raiders' chest
	Herds.on_sack(w, town, att)   # herds: the raiders drive off a share of the beasts (theft, logged)

# ================================================================== ranks: the tree
## Rebuilds the tree's shape for the army's size, validates holders, gives the status ranks, fills vacancies.
## prehistory: world gen / old saves: posts filled by the rule's score without fights or thresholds.
static func update_tree(game, fid: String, units: Array, prehistory: bool, day: int) -> void:
	var w: Dictionary = game.world
	var r := rec(w, fid)
	var cul := cul_of_faction(fid)
	var rl := ranks(cul, "army")
	var span := maxi(2, int(cul.get("span", 5)))
	var fo := first_officer("army")
	var by := {}
	for u in units:
		by[u.uid] = u
	var posts: Array = r["posts"]
	var lv := levels_for(units.size(), span, maxi(0, rl.size() - fo))
	var old_lv := int(r["levels"])
	if lv != old_lv:
		var n := offset(lv, span)
		while posts.size() > n:
			var uid := int(posts.pop_back())
			if by.has(uid):
				_demote(by[uid])
		while posts.size() < n:
			posts.append(-1)
		r["levels"] = lv
		r["fights"] = (r["fights"] as Array).filter(func(x): return int(x["p"]) < n)
		if lv < old_lv:
			_hist(game, fid, "The army shrank; the %s posts are gone." % rl[rank_at(lv, rl)])
	# holders still alive and in the army, ranks matching their posts; anyone else above the status ranks steps down
	var holds := {}
	for i in posts.size():
		var uid := int(posts[i])
		if uid < 0:
			continue
		if not by.has(uid):
			posts[i] = -1
			continue
		var u: Unit = by[uid]
		if not house_born(u):   # older saves: a commoner officer steps down
			posts[i] = -1
			_demote(u)
			continue
		holds[uid] = i
		u.rank = rank_at(level_of(i, span), rl)
		u.role = "officer"
	for u in units:
		if not holds.has(u.uid):
			if u.rank >= fo:
				_demote(u)
			elif u.rank == 0 and u.battles >= 1:
				u.rank = 1   # survived a battle: veteran / blooded
	# officers come only from houses: with too few house men in the field, the realm calls up its nobles
	if not prehistory:
		var vacant := posts.filter(func(x): return int(x) < 0).size()
		var free_nobles := 0
		for u in units:
			if not holds.has(u.uid) and house_born(u): free_nobles += 1
		if vacant > free_nobles:
			for nu in call_up_nobles(game, fid, mini(10, vacant - free_nobles)):
				by[nu.uid] = nu; units.append(nu)
	# vacancies, top-down (a contest already running keeps its post)
	var busy := {}
	for fgt in r["fights"]:
		busy[int(fgt["p"])] = true
	for i in posts.size():
		if int(posts[i]) < 0 and not busy.has(i):
			fill(game, fid, i, by, prehistory, day, false)
	if not (r["fights"] as Array).is_empty() and not prehistory:
		_queue_fight(w, fid)
	_link_field_commands(game,fid)

static func _demote(u: Unit) -> void:
	u.rank = 1
	u.role = "troop"

## Candidates for post p: the officers who reported to it; for a bottom post the rank and file reporting to it
## (blooded/veterans first). A new post nobody reports to yet: the faction's men past the promotion threshold.
static func candidates(game, fid: String, p: int, by: Dictionary, prehistory: bool) -> Array:
	var r := rec(game.world, fid)
	var cul := cul_of_faction(fid)
	var span := maxi(2, int(cul.get("span", 5)))
	var lv := int(r["levels"])
	var posts: Array = r["posts"]
	var fo := first_officer("army")
	var out := []
	var kids := children_of(p, span, lv)
	for c in kids:
		var uid := int(posts[c])
		if uid >= 0 and by.has(uid):
			out.append(by[uid])
	if kids.is_empty():
		var vets := []; var raw := []
		# One pass over the army per tree update, not one per post (a 1000-man army has hundreds of posts).
		for u in _reports(by, lv, span, fo).get(p, []):
			if u.rank >= fo:
				continue
			(vets if u.rank >= 1 else raw).append(u)
		out = vets if not vets.is_empty() else raw
	if out.is_empty():
		# a post nobody reports to yet (the tree grew): men past the threshold for that level
		var need: Array = A()["promote_battles"]
		var lvl_from_bottom := lv - 1 - level_of(p, span)
		var nb := int(need[clampi(lvl_from_bottom, 0, need.size() - 1)])
		# The most renowned men past the threshold (at most 64): a big army's whole rank and file is not a
		# candidate list for every new post.
		for u in _reports(by, lv, span, fo).get(-2, []):
			if u.rank < fo and not u.dead and (prehistory or u.battles >= nb):
				out.append(u)
				if out.size() >= 64: break
	out = out.filter(func(u): return not u.dead)
	out.sort_custom(func(a, b): return a.uid < b.uid)
	return out

## A man of a house family (named, landed or ruling, not common folk): the only men who can hold rank in an army.
static func house_born(u: Unit) -> bool:
	if u == null or u.family < 0: return false
	var town: Dictionary = Game.world.get("towns", {}).get(u.home_town, {})
	if town.is_empty(): return false
	var f: Dictionary = People.fam_of(town, u.family)
	return not f.is_empty() and not f.get("cohort", false) and not f.get("estate", false) and not f.get("gone", false) and str(f.get("household_uid", "")) != ""

## Realms call up their own nobles to lead: adults of house families in the realm's towns who are at home
## join its largest field band (a person of the register, never invented) until the officer posts can be filled.
## At most `most` a day per realm, so a big tree fills over days. Returns the men called up.
static func call_up_nobles(game, fid: String, most: int) -> Array:
	var w: Dictionary = game.world
	var out: Array = []
	if most <= 0: return out
	var band: Dictionary = {}
	for wid in w["warbands"]:
		var wb: Dictionary = w["warbands"][wid]
		if wb["faction"] == fid and is_field(wb) and is_people_band(wb) and (band.is_empty() or (wb["units"] as Array).size() > (band["units"] as Array).size()):
			band = wb
	if band.is_empty(): return out
	var roll: Dictionary = state(w)["roll"]
	for tid in w["towns"]:
		var town: Dictionary = w["towns"][tid]
		if str(town.get("faction", "")) != fid or not TownEcon.has_econ(town): continue
		var e: Dictionary = town["econ"]
		var ab := People.ages(Persons.race_of(e))
		var head_uid := str(e.get("head", {}).get("person_uid", ""))
		for f in e.get("fams", []):
			if f.get("cohort", false) or f.get("estate", false) or f.get("gone", false) or str(f.get("household_uid", "")) == "": continue
			for p in Persons.pp(f):
				if out.size() >= most: return out
				if str(p[4]) != "" or int(p[5]) >= 0 or int(p[6]) != 0: continue
				if str(Persons.g(p, Persons.PERSON_UID, "")) == head_uid: continue   # the ruler governs; his kin ride
				var age := Persons.age_of(p, float(e.get("day", game.day)))
				if age < int(ab["adult"]) or age >= int(ab["elder"]): continue
				var u: Unit = CampaignWorld.make_resident_troop(game.rng, fid, town)
				Persons.log_life(p, float(game.day), "serve", "army")
				p[4] = "army"
				var sv: Dictionary = f["serve"]; sv["army"] = int(sv.get("army", 0)) + 1
				People.last_person = p
				People.bind(town, int(f["id"]), u, "army")
				u.family = int(f["id"]); u.home_town = str(tid); u.faction = fid
				roll[str(u.uid)] = [str(tid), int(f["id"]), "army", u.name]
				(band["units"] as Array).append(u)
				Families.event(f, "joined", [u.name, "army", force_word(w, band)], float(game.day))
				out.append(u)
	return out

static var _rep_by: Dictionary = {}
static var _rep_key := []
static var _rep_map: Dictionary = {}
## Rank-and-file grouped by the post they report to (key -1: every man below officer rank), built once per roster.
static func _reports(by: Dictionary, lv: int, span: int, fo: int) -> Dictionary:
	var key := [lv, span, by.size()]
	if is_same(_rep_by, by) and _rep_key == key:
		return _rep_map
	_rep_by = by; _rep_key = key; _rep_map = {-1: []}
	for uid in by:
		var u: Unit = by[uid]
		if u.rank >= fo or not house_born(u): continue   # only house members can rise; the plebs stay plebs
		(_rep_map[-1] as Array).append(u)
		var rp := report_post(u, lv, span)
		if not _rep_map.has(rp): _rep_map[rp] = []
		(_rep_map[rp] as Array).append(u)
	var ranked: Array = (_rep_map[-1] as Array).duplicate()
	ranked.sort_custom(func(a, b): return a.renown > b.renown if a.renown != b.renown else (a.battles > b.battles if a.battles != b.battles else a.uid < b.uid))
	_rep_map[-2] = ranked
	return _rep_map

static func fill(game, fid: String, p: int, by: Dictionary, prehistory: bool, day: int, relink: bool = true) -> void:
	var w: Dictionary = game.world
	var r := rec(w, fid)
	var cul := cul_of_faction(fid)
	var span := maxi(2, int(cul.get("span", 5)))
	var cands := candidates(game, fid, p, by, prehistory)
	if cands.is_empty():
		return
	var rule := String(cul.get("rank_rule", "renown"))
	if rule == "strength":
		# orcs: high renown lets a man two levels down join the free-for-all
		var lv := int(r["levels"])
		for c in children_of(p, span, lv):
			for gc in children_of(c, span, lv):
				var uid := int(r["posts"][gc])
				if uid >= 0 and by.has(uid) and (by[uid] as Unit).renown >= float(A()["renown_join"]) and not cands.has(by[uid]):
					cands.append(by[uid])
		if cands.size() == 1 or prehistory:
			var best: Unit = cands[0]
			for c2 in cands:
				if CampaignWorld.unit_power(c2) > CampaignWorld.unit_power(best):
					best = c2
			assign(game, fid, p, best, by, prehistory, day, [], relink)
			return
		var uids := []
		for c3 in cands:
			uids.append(c3.uid)
		(r["fights"] as Array).append({"p": p, "c": uids, "beat": []})
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([int(w.get("seed", 0)), fid, p, day, "rank"])
	var pick := RankRules.pick(game, fid, rule, p, cands, by, rng, prehistory)
	if pick != null:
		assign(game, fid, p, pick, by, prehistory, day, [], relink)

## The post goes to u; the post he held opens and is filled the same way (the cascade).
static func assign(game, fid: String, p: int, u: Unit, by: Dictionary, prehistory: bool, day: int, beat: Array, relink: bool = true) -> void:
	var w: Dictionary = game.world
	var r := rec(w, fid)
	var cul := cul_of_faction(fid)
	var rl := ranks(cul, "army")
	var span := maxi(2, int(cul.get("span", 5)))
	var posts: Array = r["posts"]
	var old := posts.find(u.uid)
	if old >= 0:
		posts[old] = -1
	posts[p] = u.uid
	u.rank = rank_at(level_of(p, span), rl)
	u.role = "officer"
	var title: String = rl[u.rank]
	if not prehistory:
		var txt := ""
		var dead := beat.filter(func(b): return b[1])
		if not dead.is_empty():
			txt = "%s took the %s post over %s's corpse." % [u.name, title, String(dead[-1][0])]
		elif not beat.is_empty():
			txt = "%s took the %s post, beating %s." % [u.name, title, ", ".join(PackedStringArray(beat.map(func(b): return String(b[0]))))]
		else:
			txt = "%s was made %s." % [u.name, title]
		_hist(game, fid, txt)
		var f := People.fam_of(w["towns"].get(u.home_town, {}), u.family)
		if not f.is_empty():
			f["named"] = true
			Families.event(f, "officer", [u.name, title], float(game.day))
			Families.add_hist(f, "%s rose to %s." % [u.name, title], float(game.day))
	else:
		var f2 := People.fam_of(w["towns"].get(u.home_town, {}), u.family)
		if not f2.is_empty():
			f2["named"] = true   # named officers: full family records
	if p == 0:
		_war_leader(game, fid, u, title)
	if old >= 0:
		fill(game, fid, old, by, prehistory, day, false)
	if relink: _link_field_commands(game,fid)

## The top post is the faction's war leader; for orcs the warlord is also head of state (the capital's head).
static func _war_leader(game, fid: String, u: Unit, title: String) -> void:
	var w: Dictionary = game.world
	var fac: Dictionary = w["factions"].get(fid, {})
	fac["war_leader"] = {"name": u.name, "uid": u.uid, "title": title}
	if String(cul_of_faction(fid).get("rank_rule", "")) != "strength":
		return
	Dynasty.bind_war_leader(game, fid, u, title)

static func _hist(game, fid: String, text: String) -> void:
	var r := rec(game.world, fid)
	var h: Array = r["hist"]
	h.append("Day %d: %s" % [int(game.day) + 1, text])
	while h.size() > 20:
		h.pop_front()
	CampaignWorld.log_event(game, text)

# ================================================================== succession fights (orcs)
static func _queue_fight(w: Dictionary, fid: String) -> void:
	if not w.has("work"):
		w["work"] = []
	for j in w["work"]:
		if j[0] == "army_fight" and j[1] == fid:
			return
	# Succession duels run in the background (CampaignWorld.work_slice): they never hold the world clock.
	if not w.has("fight_work"): w["fight_work"] = []
	if not (w["fight_work"] as Array).has(fid): (w["fight_work"] as Array).append(fid)

## One duel of the first open contest (one work job, one frame): two candidates fight in the real combat sim on a
## tiny map with their own gear; real wounds and deaths. The winner meets the next; the last one standing takes
## the post, and the post he held opens (the cascade queues its own contest).
static func fight_step(game, fid: String, budget_usec: int = 4000) -> void:
	var w: Dictionary = game.world
	var r := rec(w, fid)
	var fights: Array = r["fights"]
	if fights.is_empty():
		return
	var by := {}
	for u in members(game, fid):
		by[u.uid] = u
	# Several duels per job within a small budget: a big army opens many posts at once, and one roster scan per
	# duel (with the world clock held for each job) stalled the map.
	var started := Time.get_ticks_usec()
	while not fights.is_empty():
		_fight_one(game, fid, by)
		if Time.get_ticks_usec() - started > budget_usec: break
	if not fights.is_empty():
		_queue_fight(w, fid)

static func _fight_one(game, fid: String, by: Dictionary) -> void:
	var w: Dictionary = game.world
	var r := rec(w, fid)
	var fights: Array = r["fights"]
	var fgt: Dictionary = fights[0]
	var alive: Array = (fgt["c"] as Array).filter(func(uid): return by.has(int(uid)))
	fgt["c"] = alive
	if alive.size() >= 2:
		var a: Unit = by[int(alive[0])]
		var b: Unit = by[int(alive[1])]
		var res := duel(a, b, hash([int(w.get("seed", 0)), fid, int(fgt["p"]), int(game.day), a.uid, b.uid]))
		var lose: Unit = res["lose"]
		(fgt["c"] as Array).erase(lose.uid)
		(fgt["beat"] as Array).append([lose.name, lose.dead])
		# the winner fights the next man fresh off his last fight (to the back of the line)
		(fgt["c"] as Array).erase((res["win"] as Unit).uid)
		(fgt["c"] as Array).append((res["win"] as Unit).uid)
		if lose.dead:
			Census.note_fate(w, lose.uid, "battle", "a fight for a post in the %s" % CampaignWorld.faction_name(fid))   # the census
			_bury(game, lose)
	alive = (fgt["c"] as Array).filter(func(uid): return by.has(int(uid)) and not (by[int(uid)] as Unit).dead)
	if alive.size() <= 1:
		fights.pop_front()
		if alive.size() == 1:
			var wu: Unit = by[int(alive[0])]
			var p := int(fgt["p"])
			if p < (r["posts"] as Array).size() and int(r["posts"][p]) < 0:
				assign(game, fid, p, wu, by, false, int(game.day), fgt["beat"])

## A man killed in a succession fight leaves his band now (the sweep takes him off his family row).
static func _bury(game, u: Unit) -> void:
	for wid in game.world["warbands"]:
		var wb: Dictionary = game.world["warbands"][wid]
		if (wb["units"] as Array).has(u):
			ArmsTrade.field(game, [u], {"band": wb}, wb["pos"])   # arms trade: his kit stays with his band
			(wb["units"] as Array).erase(u)
			if (wb["units"] as Array).is_empty():
				CampaignWorld.remove_warband(game, wid)
			return

## Two men fight in the real sim (tiny open map, own gear, story text off). Ends when one goes down, dies or
## yields (routs); after fight_ticks the one hurt worse (less blood) yields. Returns {win, lose, ticks, ms}.
static func duel(a: Unit, b: Unit, seed: int) -> Dictionary:
	var t0 := Time.get_ticks_usec()
	var sim := BattleSim.new()
	sim.setup([a], [b], seed, {"w": 6, "h": 3, "terrain": "plains", "log_moves": false, "verbose": false,
		"combat_journal":false, "max_ticks": int(A()["fight_ticks"])})
	while not sim.is_over():
		sim.step()
	var win: Unit = a
	if sim.winner == 1:
		win = b
	elif sim.winner == -1:
		win = a if a.body.blood >= b.body.blood else b
	if win.dead:
		win = b if win == a else a
	return {"win": win, "lose": b if win == a else a, "ticks": sim.tick, "ms": (Time.get_ticks_usec() - t0) / 1000.0}

# ================================================================== militia trees (per band)
## Militia / guard ranks: one tree per town band, the culture's rule by score (no sim fights for town posts).
static func update_band_tree(game, town: Dictionary, wb: Dictionary, tier: String) -> void:
	var cul := TownEcon.culture_of(town["econ"])
	var rl := ranks(cul, tier)
	var span := maxi(2, int(cul.get("span", 5)))
	var units: Array = (wb["units"] as Array).filter(func(u): return not u.dead)
	var lv := levels_for(units.size(), span, maxi(0, rl.size() - 1))
	var n := offset(lv, span)
	if not wb.has("posts"):
		wb["posts"] = []
	var posts: Array = wb["posts"]
	var by := {}
	for u in units:
		by[u.uid] = u
	while posts.size() > n:
		var uid := int(posts.pop_back())
		if by.has(uid):
			(by[uid] as Unit).rank = 0
			(by[uid] as Unit).role = "troop"
	while posts.size() < n:
		posts.append(-1)
	var holds := {}
	for i in posts.size():
		if int(posts[i]) >= 0 and not by.has(int(posts[i])):
			posts[i] = -1
		if int(posts[i]) >= 0:
			holds[int(posts[i])] = true
			(by[int(posts[i])] as Unit).rank = rank_at(level_of(i, span), rl)
			(by[int(posts[i])] as Unit).role = "officer"
	for u in units:
		if not holds.has(u.uid) and u.rank > 0:
			u.rank = 0
			u.role = "troop"
	var rule := String(cul.get("rank_rule", "renown"))
	for i in posts.size():
		if int(posts[i]) >= 0:
			continue
		var cands := units.filter(func(u): return not holds.has(u.uid))
		if cands.is_empty():
			break
		var best: Unit = null
		var bv := -INF
		for u in cands:
			var v := RankRules.score(game, rule, u, String(town["faction"])) if rule != "strength" else CampaignWorld.unit_power(u)
			if v > bv:
				bv = v; best = u
		posts[i] = best.uid
		holds[best.uid] = true
		best.rank = rank_at(level_of(i, span), rl)
		best.role = "officer"
	if String(wb.get("kind","militia")) in ["militia","guard"]:
		_apply_commands(game,units,posts,lv,span,String(town["faction"]))

# ================================================================== views (UI)
## Rows of the faction's rank tree, top-down: {rank, title, count, cap, officers: [Unit]}; then the status ranks
## with their counts (no cap).
static func tree_rows(game, fid: String) -> Array:
	var r := rec(game.world, fid)
	var cul := cul_of_faction(fid)
	var rl := ranks(cul, "army")
	var span := maxi(2, int(cul.get("span", 5)))
	var units := members(game, fid)
	var by := {}
	for u in units:
		by[u.uid] = u
	var out := []
	var posts: Array = r["posts"]
	var cp := caps(int(r["levels"]), span)
	for k in cp.size():
		var offs := []
		for i in range(offset(k, span), offset(k + 1, span)):
			if i < posts.size() and by.has(int(posts[i])):
				offs.append(by[int(posts[i])])
		out.append({"rank": rank_at(k, rl), "title": rl[rank_at(k, rl)], "count": offs.size(), "cap": cp[k], "officers": offs})
	for s in [1, 0]:
		var n := 0
		for u in units:
			if u.rank == s:
				n += 1
		out.append({"rank": s, "title": rl[s], "count": n, "cap": -1, "officers": []})
	return out

## A man's rank title in his own force ("blooded", "watch sergeant"), "" for the company and beasts.
static func rank_title(u: Unit) -> String:
	if u.faction == "player" or u.race_def().get("creature", false) or not DB.factions.has(u.faction):
		return ""
	var cul := cul_of_faction(u.faction)
	var tier := "army"
	if u.title.begins_with("militia"):
		tier = "militia"
		var t: Dictionary = Game.world.get("towns", {}).get(u.home_town, {})
		if not t.is_empty():
			tier = town_tier(t)
	var rl := ranks(cul, tier)
	return String(rl[clampi(u.rank, 0, rl.size() - 1)])

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
