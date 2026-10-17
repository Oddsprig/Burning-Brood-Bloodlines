class_name Migration
extends RefCounted
## v0.034: the common folk move. Tracked families already flee famine (Barge.maybe_flee) and follow wages
## (Barge.move_in) with their records. A cohort row (campaign/population.gd) stands for many households; once a week
## some of them leave, as counts: their anonymous residents (age bins), their share of the row's coin and household
## stores, never land, herds, businesses or named people. Three pushes, strongest first:
##   war    - the town was sacked, raided or taken in the last WAR_DAYS days, or lives in deep dragon fear
##   hunger - famine stage 2+, at the tracked families' own flight rate (movers.flight x (stage - 1) a day)
##   crowd  - more people than its homes hold (CROWD x room) with no empty town house or market home to be had:
##            the crowded-out households go where empty town houses wait
## Destination: a town of the same race, of the realm or a trade-pact/allied realm (Barge._refuge's rule), not under
## the same push, with a cohort row of that race. Arrivals join that row and buy empty town houses at the estate
## price (economy.json shelter.estate_home, into the treasury) from the coin they carry, else they are crowded in.
## No person or coin is made or lost; the census records the moves both ways, and your realm's big moves are logged.
const WAR_DAYS := 30
const WAR_SHARE := 0.04       # of a row's households a week while war or fear lasts
const FEAR_AT := 50.0         # DragonFear.fear at or above this drives people out
const CROWD := 1.25           # people above homes x room x this: crowded out
const CROWD_SHARE := 0.25     # of the crowded-out households a week
const LOG_AT := 20            # people: a move this big from or into your realm reaches the campaign log
const WORDS := {"war": "War", "hunger": "Hunger", "crowd": "Crowding"}

static func state(w: Dictionary) -> Dictionary:
	if not w.has("migration"): w["migration"] = {"attacked": {}, "day": -1}
	return w["migration"]

## A town was sacked, raided or taken: its people fear for their lives for WAR_DAYS days.
static func note_attack(w: Dictionary, tid: String, day: float) -> void:
	if tid == "" or not w.get("towns", {}).has(tid): return
	state(w)["attacked"][tid] = int(day)

static func after_load(game) -> void:
	var st := state(game.world)
	st["day"] = int(st.get("day", -1))
	for tid in st["attacked"]: st["attacked"][tid] = int(st["attacked"][tid])

## What drives people out of this town now ("" = nothing).
static func push(game, t: Dictionary, day: float) -> String:
	var tid := String(t["id"])
	var hit := int(state(game.world)["attacked"].get(tid, -999999))
	if float(hit) + WAR_DAYS > day or DragonFear.fear(game, tid) >= FEAR_AT: return "war"
	var e: Dictionary = t["econ"]
	if int(e.get("fstage", 0)) >= 2: return "hunger"
	if int(e["fams"][0]["homes"]) <= 0 and int(e.get("stock", {}).get("home", 0)) <= 0:
		for f in e["fams"]:
			if _crowded_households(e, f) > 0: return "crowd"
	return ""

## Households of a cohort row that its homes cannot hold (people over homes x room x CROWD).
static func _crowded_households(e: Dictionary, f: Dictionary) -> int:
	if not Population.is_cohort(f) or f.get("gone", false): return 0
	var room := float(f["homes"]) * float(TownEcon.culture_of(e)["home"]["room"]) * (0.6 + 0.4 * float(f.get("cond", 1.0)))
	var people := Families.people(f)
	if float(people) <= room * CROWD: return 0
	var per := float(people) / float(Population.households(f))
	return int(floor((float(people) - room) / maxf(1.0, per)))

static var worst_us := 0   # perf: the slowest weekly job (one map frame)

## Weekly (TownEcon queue "migrate"): every town under a push sends some of its common households away.
static func weekly(game, day: float) -> void:
	var t0 := Time.get_ticks_usec()
	_weekly(game, day)
	worst_us = maxi(worst_us, Time.get_ticks_usec() - t0)

static func _weekly(game, day: float) -> void:
	var w: Dictionary = game.world
	var st := state(w)
	if int(day) <= int(st["day"]): return
	st["day"] = int(day)
	for tid in st["attacked"].keys():
		if float(st["attacked"][tid]) + WAR_DAYS <= day: st["attacked"].erase(tid)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([int(w.get("seed", 0)), int(day), "migrate"])
	var mine := Diplomacy.player_realm(w)
	var moves := {}   # "out|town|why" / "in|town|why" -> {n, places} (for the log)
	var ids: Array = w.get("towns", {}).keys()
	ids.sort()
	var pushes := {}   # each town's push, once per run (destinations read it)
	for tid in ids:
		if TownEcon.has_econ(w["towns"][tid]): pushes[tid] = push(game, w["towns"][tid], day)
	for tid in ids:
		var t: Dictionary = w["towns"][tid]
		var why := String(pushes.get(tid, ""))
		if why == "": continue
		var e: Dictionary = t["econ"]
		for f in (e["fams"] as Array).duplicate():
			if not Population.is_cohort(f) or f.get("gone", false): continue
			var n := _leavers(e, f, why, rng)
			if n <= 0: continue
			var dest := destination(game, t, f, why, day, pushes)
			if dest.is_empty(): continue
			var moved := move_households(game, t, f, dest, n, why, day)
			if moved <= 0 or mine == "": continue
			# the log: everyone who left a town of your realm this week, and refugees from other realms into yours
			var key := ""
			if String(t["faction"]) == mine: key = "out|%s|%s" % [t["id"], why]
			elif String(dest["faction"]) == mine: key = "in|%s|%s" % [dest["id"], why]
			if key == "": continue
			if not moves.has(key): moves[key] = {"n": 0, "places": {}}
			moves[key]["n"] = int(moves[key]["n"]) + moved
			var other := String(dest["name"]) if key.begins_with("out") else String(t["name"])
			moves[key]["places"][other] = int(moves[key]["places"].get(other, 0)) + moved
	for key: String in moves:
		var parts := key.split("|")
		var n := int(moves[key]["n"])
		if n < LOG_AT: continue
		var places := ", ".join(PackedStringArray(moves[key]["places"].keys()))
		var here := String(w["towns"][parts[1]]["name"])
		if parts[0] == "out": CampaignWorld.log_event(game, "%s drove %d people from %s (to %s)." % [WORDS[parts[2]], n, here, places])
		else: CampaignWorld.log_event(game, "%d people came to %s from %s, driven out by %s." % [n, here, places, String(WORDS[parts[2]]).to_lower()])

## How many of a row's households leave this week (one always stays: the row and its named people remain).
static func _leavers(e: Dictionary, f: Dictionary, why: String, rng: RandomNumberGenerator) -> int:
	var hh := Population.households(f)
	if hh <= 1: return 0
	var lam := 0.0
	match why:
		"war": lam = float(hh) * WAR_SHARE
		"hunger":
			var p := float(Barge.B()["movers"]["flight"]) * float(int(e.get("fstage", 0)) - 1)
			lam = float(hh) * (1.0 - pow(1.0 - clampf(p, 0.0, 1.0), 7.0))
		"crowd": lam = float(_crowded_households(e, f)) * CROWD_SHARE
	return mini(hh - 1, Sickness._poisson(rng, lam))

## The best town to go to: same race, the realm or a trade-pact/allied realm, not under the same push, with a cohort
## row of that race; least hungry, best paid, nearest (Barge._refuge's score). Crowded-out people need empty houses.
static func destination(game, from: Dictionary, f: Dictionary, why: String, day: float, pushes: Dictionary = {}) -> Dictionary:
	var w: Dictionary = game.world
	var fid := String(from["faction"])
	var race := String(f.get("race", Persons.race_of(from["econ"])))
	var best: Dictionary = {}
	var bv := -INF
	for tid in w["towns"]:
		var t: Dictionary = w["towns"][tid]
		if tid == from["id"] or not TownEcon.has_econ(t): continue
		var tf := String(t["faction"])
		if tf != fid and not (Diplomacy.state(w, fid, tf) in [Diplomacy.TRADE_PACT, Diplomacy.ALLIANCE]): continue
		var e: Dictionary = t["econ"]
		if Persons.race_of(e) != race or _row_for(e, race).is_empty(): continue
		var there := String(pushes[tid]) if pushes.has(tid) else push(game, t, day)
		if there == "war" or there == "hunger" or (why == "crowd" and int(e["fams"][0]["homes"]) <= 0): continue
		var v := -10.0 * float(e.get("fstage", 0)) + Barge.day_wage(e) / 100.0 - (t["pos"] as Vector2).distance_to(from["pos"]) / 2000.0
		if why == "crowd": v += float(e["fams"][0]["homes"]) * 0.1
		if v > bv:
			bv = v; best = t
	return best

## The cohort row of a race in a town that takes newcomers (the poorest by coin per household).
static func _row_for(e: Dictionary, race: String) -> Dictionary:
	var best: Dictionary = {}
	for f in e["fams"]:
		if not Population.is_cohort(f) or f.get("gone", false) or String(f.get("race", "")) != race: continue
		if best.is_empty() or Population.household_purse(f) < Population.household_purse(best): best = f
	return best

## n households of a cohort row walk to another town: their share of each age bin, of the coin and of the household
## stores (goods out of one town's pool into the other's). Hunger and war leave their homes to the town estate; the
## crowded out had none. Returns the people moved.
static func move_households(game, from: Dictionary, f: Dictionary, to: Dictionary, n: int, why: String, day: float) -> int:
	var e: Dictionary = from["econ"]
	var e2: Dictionary = to["econ"]
	var d := _row_for(e2, String(f.get("race", "")))
	var hh := Population.households(f)
	n = clampi(n, 0, hh - 1)
	if d.is_empty() or n <= 0: return 0
	var share := float(n) / float(hh)
	var bins: Dictionary = f["age_bins"]
	var moved := {}
	var counts := [0, 0, 0, 0]   # men, women, elders, children (Population.bin_category)
	var carry := 0.0
	for key in bins.keys():
		var have := int(bins[key])
		var x := float(have) * share + carry
		var k := mini(have, int(floor(x)))
		carry = x - float(k)
		if k <= 0: continue
		counts[Population.bin_category(e, f, String(key), day)] += k
		bins[key] = have - k
		if int(bins[key]) <= 0: bins.erase(key)
		moved[key] = k
	var people: int = counts[0] + counts[1] + counts[2] + counts[3]
	if people <= 0: return 0
	var before := Families.daily_rates(e, f)
	var stores := {}
	for k in ["food", "drink", "wood"]:   # their share of the row's stores, in goods
		stores[k] = float(f["store"].get(k, 0.0)) * float(before[k]) * share
	var fields := ["m", "f", "old", "kids"]
	for c in 4:
		f[fields[c]] = int(f[fields[c]]) - int(counts[c])
	e["pop"] = int(e["pop"]) - people
	e["adults"] = int(e["adults"]) - counts[0] - counts[1]
	f["households"] = hh - n
	var coin := float(f["purse"]) * share
	f["purse"] = float(f["purse"]) - coin
	if why != "crowd":
		var left := mini(int(f["homes"]), int(floor(float(f["homes"]) * share)))
		f["homes"] = int(f["homes"]) - left
		e["homes"] = int(e["homes"]) - left
		e["fams"][0]["homes"] = int(e["fams"][0]["homes"]) + left
	var st: Dictionary = e["stats"]
	st["left"] = int(st.get("left", 0)) + people
	st["left_" + why] = int(st.get("left_" + why, 0)) + people
	if not st.has("left_to"): st["left_to"] = {}
	st["left_to"][String(to["id"])] = int(st["left_to"].get(String(to["id"]), 0)) + people
	Census.record_move(e, -1, "out", String(to.get("name", "")), day, why, people)
	Families.add_hist(f, "%d households left for %s, driven off by %s." % [n, to.get("name", "town"), why], day)
	# in the new town: the same people join a common row there
	var had := Families.daily_rates(e2, d)
	var people2 := Families.people(d)
	var dbins: Dictionary = d["age_bins"]
	for key in moved: dbins[key] = int(dbins.get(key, 0)) + int(moved[key])
	for c in 4:
		d[fields[c]] = int(d[fields[c]]) + int(counts[c])
	e2["pop"] = int(e2["pop"]) + people
	e2["adults"] = int(e2["adults"]) + counts[0] + counts[1]
	d["households"] = Population.households(d) + n
	var price := float(Shelter.D()["estate_home"])
	var estate: Dictionary = e2["fams"][0]
	var bought := mini(n, mini(int(estate["homes"]), int(floor(coin / maxf(1.0, price)))))
	if bought > 0:
		coin -= float(bought) * price
		e2["treasury"] = float(e2["treasury"]) + float(bought) * price
		estate["homes"] = int(estate["homes"]) - bought
		d["homes"] = int(d["homes"]) + bought
		e2["homes"] = int(e2["homes"]) + bought
	d["purse"] = float(d["purse"]) + coin
	var now := Families.daily_rates(e2, d)
	var after := Families.daily_rates(e, f)
	for k in ["food", "drink", "wood"]:   # goods out of the old town's household pool into the new one's
		var goods: Array = Families.HOUSEHOLD_FOOD if k == "food" else (["beer", "wine"] if k == "drink" else ["wood"])
		var got := 0
		var q := Families.store_quantities(e["hh"], goods, float(stores[k]))
		for g in q:
			if int(q[g]) <= 0: continue
			e["hh"][g] = int(e["hh"][g]) - int(q[g])
			e2["hh"][g] = int(e2["hh"].get(g, 0)) + int(q[g])
			got += int(q[g])
		var own := float(f["store"].get(k, 0.0)) * float(before[k])   # the row's store in goods, less what left
		f["store"][k] = maxf(0.0, own - float(got)) / maxf(0.01, float(after[k]))
		d["store"][k] = (float(d["store"].get(k, 0.0)) * float(had[k]) + float(got)) / maxf(0.01, float(now[k]))
	var bc: Dictionary = d.get("pool_condition", {})   # body condition: the newcomers' share of the row
	for g in f.get("pool_condition", {}):
		bc[g] = (float(bc.get(g, 1.0)) * float(people2) + float(f["pool_condition"][g]) * float(people)) / float(people2 + people)
	d["pool_condition"] = bc
	var st2: Dictionary = e2["stats"]
	st2["moved_in"] = int(st2.get("moved_in", 0)) + people
	Census.record_move(e2, -1, "in", String(from.get("name", "")), day, why, people)
	Families.add_hist(d, "%d households came from %s, driven off by %s%s." % [n, from.get("name", "town"), why,
		"; %d bought empty town houses" % bought if bought > 0 else ""], day)
	Families.reassign(e, f)
	Families.reassign(e2, d)
	return people

## One town's health, homes and movement for the Population screen (pure).
static func report(game, tid: String) -> Dictionary:
	var t: Dictionary = game.world.get("towns", {}).get(tid, {})
	if not TownEcon.has_econ(t): return {}
	var e: Dictionary = t["econ"]
	var b: Dictionary = e.get("sk", {})
	var sick := 0
	var diseases: Array = []
	for dis in b.get("act", {}):
		sick += int(b["act"][dis])
		diseases.append([Sickness.dname(String(dis)), int(b["act"][dis])])
	diseases.sort_custom(func(a, c): return int(a[1]) > int(c[1]))
	var yr: Array = b.get("yr", {}).get(str(Calendar.year(float(game.day))), [0, 0, 0])
	var households := 0; var unhoused := 0
	for f in e["fams"]:
		var n := Population.households(f)
		if n <= 0: continue
		households += n
		unhoused += maxi(0, n - int(f.get("homes", 0)))
	var cur := Census.current(e)
	return {"people": int(e["pop"]), "sick": sick, "diseases": diseases, "sick_deaths": int(yr[1]), "homes": int(e.get("homes", 0)),
		"households": households, "unhoused": unhoused, "empty_homes": int(e["fams"][0].get("homes", 0)),
		"room": int(TownEcon.culture_of(e)["home"]["room"]), "left": (cur.get("left", {}) as Dictionary).duplicate(),
		"arrived": (cur.get("arrived", {}) as Dictionary).duplicate(), "push": push(game, t, float(game.day))}

static func whys(d: Dictionary) -> String:
	if d.is_empty(): return "none"
	var parts: Array = []
	for k in d: parts.append("%s %d" % [String(k), int(d[k])])
	return "%d (%s)" % [Census.sum(d), ", ".join(PackedStringArray(parts))]
