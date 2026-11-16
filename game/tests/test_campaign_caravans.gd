extends RefCounted
## Caravans: spawn with real cargo (Items out of the origin shop, goods out of its supply), travel by road,
## unload into the destination; destroyed by a hostile band; escort contract success and failure; player
## raid loots the actual cargo; every force has a home town; save/load; per-frame cost of on_time.

## Test brief: one selected part; 150 s cooperative budget plus an external cutoff below 180 s.
## "run only one Godot game test at a time on the user's PC (several at once crashed it), headless. Before starting any game test, check for other running Godot or Unity processes (from any project or helper); if any are running, queue the test and wait until they have finished before starting it. Every test must finish in under 3 minutes. These rules must be pasted word for word into every helper task and test brief."
## A test failure stops all further tests. No other test runs until that one failing test is fixed and passes.

var fails: int = 0
var _part: String = "delivery"
var _part_deadline_msec: int = 0
const PART_BUDGET_MSEC: int = 150000
# Exactly one part per invocation; the no-argument default is the funded delivery.
const PARTS: Array[String] = ["delivery", "unfunded", "loss", "escort-success",
	"escort-failure", "raid", "persistence", "perf"]

func check(ok: bool, msg: String) -> void:
	if not ok:
		print("FAIL: caravans ", _part, ": ", msg)
		fails += 1

func _within_part_budget() -> bool:
	var within_budget: bool = Time.get_ticks_msec() < _part_deadline_msec
	check(within_budget, "whole part exceeded its 150 s budget; incomplete work is a failure")
	return within_budget

## Goods dict as sorted "k:v" (saves sort keys).
func _gs(d: Dictionary) -> String:
	var ks: Array = d.keys()
	ks.sort()
	return ",".join(PackedStringArray(ks.map(func(k: String) -> String: return "%s:%d" % [k, int(d[k])])))

func _clear_bands(w: Dictionary) -> void:
	for wid: String in w["warbands"].keys():
		CampaignWorld.remove_warband(Game, wid)
	w["work"] = []

## Cohort residents become named people by consuming one same-race/sex/birth-year bin.
## Rule: campaign/population.gd:3-4,96-125; sol_fix_group_K_worldgen.md:13,25.
## Compare the original bandit-proven immutable columns; job titles/history may change with service.
static func cohort_snapshot(world: Dictionary, faction: String = "") -> Dictionary:
	var towns: Dictionary = {}
	var errors: Array = []
	var person_uids: Dictionary = {}
	if not (world.get("towns") is Dictionary):
		return {"towns": towns, "errors": ["missing world towns dictionary"]}
	for town: Dictionary in world["towns"].values():
		if not town.has("id"): errors.append("town has no persistent id"); continue
		if not TownEcon.has_econ(town) or (faction != "" and str(town.get("faction", "")) != faction): continue
		var economy: Dictionary = town["econ"]
		if not economy.has_all(["fams", "pop", "adults"]) or not (economy["fams"] is Array):
			errors.append("missing population/families in " + str(town["id"])); continue
		var families: Dictionary = {}
		var town_pids: Dictionary = {}
		for family: Dictionary in economy["fams"]:
			if not family.has_all(["id", "m", "f", "old", "kids"]):
				errors.append("missing family identity/counts in " + str(town["id"])); continue
			if families.has(int(family["id"])): errors.append("duplicate family id in " + str(town["id"]))
			if Population.is_cohort(family) and not (family.get("age_bins") is Dictionary):
				errors.append("missing cohort age bins in " + str(town["id"])); continue
			var people: Dictionary = {}
			for person: Array in Persons.pp_read(family):
				if person.size() < 11: errors.append("short resident row in " + str(town["id"])); continue
				var pid: int = int(person[0])
				var uid: String = str(Persons.g(person, Persons.PERSON_UID, ""))
				if town_pids.has(pid) or uid == "" or person_uids.has(uid): errors.append("duplicate/missing resident identity in " + str(town["id"]))
				town_pids[pid] = true; person_uids[uid] = true
				var facts: Array = [person[0], person[1], person[2], person[3], person[6], person[7], person[8], person[9], person[10]]
				people[pid] = {"facts": facts, "person_uid": uid, "service": person[4], "unit_uid": person[5]}
			families[int(family["id"])] = {"cohort": Population.is_cohort(family), "race": Persons.family_race(economy, family),
				"counts": [family["m"], family["f"], family["old"], family["kids"]], "people": people,
				"bins": (family.get("age_bins", {}) as Dictionary).duplicate(true)}
		towns[str(town["id"])] = {"pop": economy["pop"], "adults": economy["adults"], "families": families}
	return {"towns": towns, "errors": errors}

static func materialization_errors(before: Dictionary, after: Dictionary) -> Array:
	var errors: Array = before["errors"].duplicate()
	errors.append_array(after["errors"])
	var old_towns: Dictionary = before["towns"]
	var new_towns: Dictionary = after["towns"]
	if old_towns.size() != new_towns.size(): errors.append("town identity set changed")
	for tid: String in old_towns:
		if not new_towns.has(tid): errors.append("missing original town " + tid); continue
		var old_town: Dictionary = old_towns[tid]
		var new_town: Dictionary = new_towns[tid]
		if old_town["pop"] != new_town["pop"] or old_town["adults"] != new_town["adults"]: errors.append(tid + " population/adult count changed")
		var old_families: Dictionary = old_town["families"]
		var new_families: Dictionary = new_town["families"]
		if old_families.size() != new_families.size(): errors.append(tid + " family identity set changed")
		for fid: int in old_families:
			if not new_families.has(fid): errors.append(tid + " missing family %d" % fid); continue
			var old_family: Dictionary = old_families[fid]
			var new_family: Dictionary = new_families[fid]
			if old_family["counts"] != new_family["counts"] or old_family["race"] != new_family["race"] or old_family["cohort"] != new_family["cohort"]:
				errors.append(tid + " family %d changed race/counts/type" % fid)
			var expected_bins: Dictionary = old_family["bins"].duplicate(true)
			var old_people: Dictionary = old_family["people"]
			var new_people: Dictionary = new_family["people"]
			for pid: int in old_people:
				if not new_people.has(pid) or new_people[pid]["facts"] != old_people[pid]["facts"] or new_people[pid]["person_uid"] != old_people[pid]["person_uid"]:
					errors.append(tid + " existing person %d changed identity/life facts" % pid)
			for pid: int in new_people:
				if old_people.has(pid): continue
				var person: Dictionary = new_people[pid]
				var facts: Array = person["facts"]
				var bin_key: String = "%d:%d" % [int(facts[2]), int(round(float(facts[3]) / People.year_days()))]
				if not bool(old_family["cohort"]) or int(expected_bins.get(bin_key, 0)) <= 0:
					errors.append(tid + " new person %d has no matching original race/sex/birth bin" % pid)
					continue
				if int(expected_bins[bin_key]) == 1: expected_bins.erase(bin_key)
				else: expected_bins[bin_key] = int(expected_bins[bin_key]) - 1
			if expected_bins != new_family["bins"]: errors.append(tid + " family %d did not debit exactly its new named residents" % fid)
	return errors

## Select, without editing prices, needs, stock or purses, a genuinely profitable
## native linen-and-Items trip whose destination can pay for the entire outward load.
## Preview copies own their mutable ledgers; neither probe consumes the real RNG.
func _native_pair(w: Dictionary, rng: RandomNumberGenerator) -> Array:
	var ids: Array = w["towns"].keys()
	ids.sort()
	for tid: String in ids:
		if not _within_part_budget(): return []
		var town: Dictionary = w["towns"][tid]
		if town["faction"] != "middle_kingdom": continue
		for link: Dictionary in Caravans.trade_partners(w, town):
			if not _within_part_budget(): return []
			var partner: Dictionary = w["towns"].get(str(link.get("id", "")), {})
			if not TownEcon.has_econ(town) or not TownEcon.has_econ(partner): continue
			var quote_rng: RandomNumberGenerator = RandomNumberGenerator.new()
			quote_rng.state = rng.state
			var quote: Dictionary = Caravans.quote_trip(w, town, partner, quote_rng)
			if not bool(quote.get("ready", false)) or float(quote.get("expected", {}).get("net", 0.0)) <= 0.0: continue
			var preview_rng: RandomNumberGenerator = RandomNumberGenerator.new()
			preview_rng.state = rng.state
			var preview: Dictionary = Caravans.load_cargo(town.duplicate(true), partner.duplicate(true),
				preview_rng, false, Caravans.trade_purse(town))
			if int(preview["goods"].get("linen", 0)) <= 0 or preview["items"].is_empty(): continue
			var gross: float = 0.0
			for good: String in preview["goods"]:
				gross += int(preview["goods"][good]) * Goods.price_f(partner, good) * float(TownEcon.data()["market"]["buy_share"])
			for it: Item in preview["items"]:
				gross += Economy.base_value(partner, it) * float(TownEcon.data()["market"]["arms_buy_share"])
			if Goods.market_gold(partner) >= gross:
				return [tid, str(partner["id"])]
	return []

func _homes(w: Dictionary) -> void:
	check(not w["warbands"].is_empty(), "native world has a force for home/scouting coverage")
	if w["warbands"].is_empty(): return
	for wid: String in w["warbands"]:
		var wb: Dictionary = w["warbands"][wid]
		if Monsters.is_monster_band(wb) or w.get("lairs", {}).has(wb["home"]): continue
		check(w["towns"].has(wb["home"]) and w["towns"][wb["home"]]["faction"] == wb["faction"],
			"band %s has no home town of its faction" % wid)
		check(not wb["units"].is_empty(), "band %s has actual units" % wid)
		if not wb["units"].is_empty():
			check(wb["units"][0].home_town == wb["home"], "band units lack home_town")
	var any: String = w["warbands"].keys()[0]
	print("scouting: ", CampaignWorld.scout_report(Game, any)["home_text"])

func _sale_snapshot(town: Dictionary, car: Dictionary) -> Dictionary:
	var prices: Dictionary = {}
	var bids: Dictionary = {}
	var shop_values: Dictionary = {}
	for good: String in Goods.ids():
		prices[good] = Goods.price_f(town, good)
	for it: Item in car["cargo"]["items"]:
		bids[it.uid] = Economy.base_value(town, it) * float(TownEcon.data()["market"]["arms_buy_share"])
	for it: Item in town["shop"]:
		shop_values[it.uid] = Economy.base_value(town, it) * 0.8
	return {"goods": car["cargo"]["goods"].duplicate(true), "bids": bids,
		"prices": prices, "shop_values": shop_values, "stock": town["econ"]["stock"].duplicate(true),
		"shop_uids": town["shop"].map(func(it: Item): return it.uid),
		"stats": town["econ"]["stats"].duplicate(true), "till": Goods.market_gold(town),
		"treasury": float(town["econ"]["treasury"]), "gold": float(car["gold"]),
		"receipt": car["receipt"]["realized"].duplicate(true)}

## arrive() also buys the return load. Derive that expense independently from
## physical stock changes and exact Item UIDs, rather than calling sale income a net purse delta.
func _check_sale(town: Dictionary, car: Dictionary, before: Dictionary, funded: bool) -> void:
	var economy: Dictionary = town["econ"]
	var stats: Dictionary = economy["stats"]
	var cargo: Dictionary = car["cargo"]
	var receipt: Dictionary = car["receipt"]["realized"]
	var gross: float = 0.0
	var return_cost: float = 0.0
	for good: String in Goods.ids():
		var loaded: int = int(before["goods"].get(good, 0))
		var delivered: int = loaded if funded else 0
		var recorded: int = int(stats.get("cargo_in", {}).get(good, 0)) - int(before["stats"].get("cargo_in", {}).get(good, 0))
		check(recorded == delivered, "%s cargo_in increment is exactly %d, got %d" % [good, delivered, recorded])
		var bought: int = int(before["stock"].get(good, 0)) + delivered - int(economy["stock"].get(good, 0))
		check(bought >= 0, good + " inventory increment equals imports less actual return purchases")
		check(int(cargo["goods"].get(good, 0)) == loaded - delivered + bought,
			good + " delivered plus retained cargo, accounting for return purchases, equals the loaded quantity")
		if good == "linen":
			check(bought == 0, "profitable outward linen is not repurchased on the return leg")
			check(delivered + int(cargo["goods"].get("linen", 0)) == loaded,
				"linen delivered plus unsold linen retained on the wagons equals linen loaded")
			check(int(economy["stock"].get("linen", 0)) - int(before["stock"].get("linen", 0)) == delivered,
				"destination linen inventory increments by exactly the paid delivery")
		gross += delivered * float(before["prices"][good]) * float(TownEcon.data()["market"]["buy_share"])
		return_cost += bought * float(before["prices"][good])
	var dest_uids: Array = town["shop"].map(func(it: Item): return it.uid)
	var wagon_uids: Array = cargo["items"].map(func(it: Item): return it.uid)
	var expected_shop: Array = before["shop_uids"].duplicate()
	for uid: int in before["bids"]:
		if funded:
			check(dest_uids.count(uid) == 1 and not wagon_uids.has(uid),
				"cargo item %d not unloaded exactly once at the destination" % uid)
			expected_shop.append(uid)
			gross += float(before["bids"][uid])
		else:
			check(wagon_uids.count(uid) == 1 and not dest_uids.has(uid),
				"unfunded buyer must leave original item %d on the wagon" % uid)
	for it: Item in cargo["items"]:
		if before["bids"].has(it.uid): continue
		check(before["shop_values"].has(it.uid) and wagon_uids.count(it.uid) == 1,
			"return Item %d came from the destination's existing shop" % it.uid)
		if before["shop_values"].has(it.uid): return_cost += float(before["shop_values"][it.uid])
		expected_shop.erase(it.uid)
	expected_shop.sort()
	dest_uids.sort()
	check(dest_uids == expected_shop, "destination retains exactly the delivered Items less paid return Items")
	var duty: float = gross * 0.03
	check(gross > 0.0 if funded else gross == 0.0, "funded sale has positive income; unfunded sale has none")
	check(absf(Goods.market_gold(town) - float(before["till"]) + gross - return_cost) < 0.01,
		"real buyer till is debited by the sale and credited only for return purchases")
	check(absf(float(car["gold"]) - float(before["gold"]) - gross + duty + return_cost) < 0.01,
		"actual seller purse receives the sale less 3% duty and actual return purchases")
	check(absf(float(economy["treasury"]) - float(before["treasury"]) - duty) < 0.01,
		"destination treasury receives exactly the 3% duty")
	check(absf(float(stats.get("duties", 0.0)) - float(before["stats"].get("duties", 0.0)) - duty) < 0.01,
		"destination duties ledger records exactly the paid duty")
	check(absf(float(stats.get("trade_in", 0.0)) - float(before["stats"].get("trade_in", 0.0)) - gross) < 0.01,
		"destination trade_in records exactly the gross paid sale")
	for key: String in ["sale_value", "duties", "buy_cost", "net", "crew", "lost_coin"]:
		var expected: float = 0.0
		match key:
			"sale_value": expected = gross
			"duties": expected = duty
			"buy_cost": expected = return_cost
			"net": expected = gross - duty - return_cost
		check(absf(float(receipt[key]) - float(before["receipt"][key]) - expected) < 0.01,
			"realized receipt " + key + " matches independently counted cargo and coin")
	check(absf(Goods.market_gold(town) + float(economy["treasury"]) + float(car["gold"])
		- float(before["till"]) - float(before["treasury"]) - float(before["gold"])) < 0.01,
		"buyer, seller and duty recipient conserve their existing coin")
	print("linen receipt: loaded %d, sold %d, retained %d; gross %.2f, duty %.2f, return purchases %.2f" %
		[int(before["goods"].get("linen", 0)), int(stats.get("cargo_in", {}).get("linen", 0)) - int(before["stats"].get("cargo_in", {}).get("linen", 0)),
		int(cargo["goods"].get("linen", 0)), gross, duty, return_cost])

func _delivery(w: Dictionary, rng: RandomNumberGenerator, funded: bool) -> void:
	var pair: Array = _native_pair(w, rng)
	check(not pair.is_empty(), "no native profitable linen-and-Items trade pair with a fully funded buyer; do not force prices or mint stock/coin")
	if pair.is_empty(): return
	var origin: Dictionary = w["towns"][pair[0]]
	var dest: Dictionary = w["towns"][pair[1]]
	var shop0: int = origin["shop"].size() + ArmsTrade.armory(origin).size()
	var linen0: int = int(origin["econ"]["stock"].get("linen", 0))
	var cid: String = Caravans.spawn(Game, pair[0], rng, pair[1])
	check(cid != "" and w["warbands"].has(cid), "caravan did not spawn")
	if cid == "" or not w["warbands"].has(cid): return
	var car: Dictionary = w["warbands"][cid]
	var cargo: Dictionary = car["cargo"]
	var uids: Array = cargo["items"].map(func(it: Item): return it.uid)
	var loaded: int = int(cargo["goods"].get("linen", 0))
	var guard_gear: int = 0
	for gu: Unit in car["units"]: guard_gear += gu.equip.size()
	check(not uids.is_empty() and origin["shop"].size() + ArmsTrade.armory(origin).size() == shop0 - uids.size() - guard_gear,
		"items not taken out of the origin shop and armory")
	check(loaded > 0, "surplus linen not loaded")
	check(int(origin["econ"]["stock"].get("linen", 0)) == linen0 - loaded, "loaded linen leaves the real origin stock")
	for it: Item in origin["shop"]:
		check(not uids.has(it.uid), "cargo item still in origin shop")
	check(not (car["path"] as Array).is_empty() and not Caravans.road_path(w, pair[0], pair[1]).is_empty(),
		"native caravan has an actual road route")
	if fails > 0: return
	if not funded:
		# Move the native market's entire till to its existing treasury. No coin is created or destroyed.
		var market: Dictionary = dest["econ"]["biz"][int(dest["econ"]["mkt"])]
		var existing_till: float = float(market["till"])
		var native_sum: float = existing_till + float(dest["econ"]["treasury"])
		market["till"] = float(market["till"]) - existing_till
		dest["econ"]["treasury"] = float(dest["econ"]["treasury"]) + existing_till
		check(Goods.market_gold(dest) == 0.0 and absf(float(dest["econ"]["treasury"]) - native_sum) < 0.01,
			"unfunded control parks only the buyer's existing money outside its till")
	var before: Dictionary = _sale_snapshot(dest, car)
	var trade0: int = int(origin.get("trade", 0))
	var wealth0: int = int(origin["wealth"])
	var t_start: float = Game.day
	var start_pos: Vector2 = car["pos"]
	var arrived: bool = false
	# Isolate movement + the real arrive/sell/buy-return path. Full-world daily production,
	# consumption and other traders cannot contaminate these transaction snapshots.
	for i: int in 400:
		if not _within_part_budget(): return
		Game.day += 0.05
		CampaignWorld._move_warbands(Game, 0.05, Game.day, rng)
		w["encounter"] = ""
		if not w["warbands"].has(cid) or car.get("leg", "out") == "home":
			arrived = true
			break
	check(arrived, "caravan never arrived")
	check(w["warbands"].has(cid) and car.get("leg", "out") == "home", "arrival keeps unsold/return cargo on the real homebound wagons")
	check((car["pos"] as Vector2).distance_to(start_pos) > 0.0, "caravan actually traverses the road")
	if not arrived or not w["warbands"].has(cid): return
	_check_sale(dest, car, before, funded)
	var enriched: bool = trade0 + 1 >= 4 + 2 * wealth0 and wealth0 < 5
	check(int(origin.get("trade", 0)) == (0 if enriched else trade0 + 1)
		and int(origin["wealth"]) == wealth0 + (1 if enriched else 0), "origin records exactly one completed trade")
	print("caravan %s -> %s arrived after %.1f days; dest goods: %s; linen price %d" %
		[origin["name"], dest["name"], Game.day - t_start, Goods.summary(dest), Goods.price(dest, "linen")])

## All cargo prerequisites come from the native economy. Missing fixtures fail, never skip.
func _spawn_native(w: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var pair: Array = _native_pair(w, rng)
	check(not pair.is_empty(), "no native profitable linen-and-Items trade pair with a fully funded buyer")
	if pair.is_empty(): return {}
	if not _within_part_budget(): return {}
	var cid: String = Caravans.spawn(Game, pair[0], rng, pair[1])
	check(cid != "" and w["warbands"].has(cid), "caravan did not spawn")
	if cid == "" or not w["warbands"].has(cid): return {}
	return {"id": cid, "pair": pair}

func _loss(w: Dictionary, rng: RandomNumberGenerator) -> void:
	var fixture: Dictionary = _spawn_native(w, rng)
	if fixture.is_empty(): return
	var pair: Array = fixture["pair"]
	var c2: String = fixture["id"]
	var dest: Dictionary = w["towns"][pair[1]]
	var dest_shop0: int = dest["shop"].size()
	var dest_linen: float = Goods.supply(dest, "linen")
	var linen_load: int = int(w["warbands"][c2]["cargo"]["goods"].get("linen", 0))
	var linen_lost: int = int(TownEcon.goods_lost.get("linen", 0))
	check(linen_load > 0, "loss fixture carries real linen from the origin")
	if fails > 0: return
	var cpos: Vector2 = w["warbands"][c2]["pos"]
	# Requested 30 is a cap, not a promised force. Preserve the r2 identity/bin oracle.
	var source_people: Dictionary = cohort_snapshot(w, "orc_horde")
	if not _within_part_budget(): return
	var orcs: String = CampaignWorld.spawn_warband(Game, "orc_horde", cpos, 30, "raider", rng, {"staged": true})
	check(orcs != "" and w["warbands"].has(orcs), "loss fixture raises a real accepted attacking force")
	if orcs == "" or not w["warbands"].has(orcs): return
	var home_id: String = str(w["warbands"][orcs]["home"])
	check(home_id != "" and w["towns"].has(home_id) and w["towns"][home_id]["faction"] == "orc_horde",
		"orc raiders without an orc home town")
	var recruited_people: Dictionary = cohort_snapshot(w, "orc_horde")
	var cohort_errors: Array = materialization_errors(source_people, recruited_people)
	check(cohort_errors.is_empty(), "attacker materialization debits exactly matching cohorts: " + str(cohort_errors))
	var attackers: Array = w["warbands"][orcs]["units"]
	check(not attackers.is_empty(), "loss fixture has accepted real attackers")
	var seen_people: Dictionary = {}
	var roll_book: Dictionary = Army.state(w)["roll"]
	for u: Unit in attackers:
		if not _within_part_budget(): return
		var home: Dictionary = w["towns"].get(u.home_town, {})
		var family: Dictionary = People.fam_of(home, u.family)
		var person: Array = Persons.by_uid(family, u.uid) if not family.is_empty() else []
		var identity: String = "%s:%d:%d" % [u.home_town, u.family, int(person[0]) if not person.is_empty() else -1]
		var named_people: Dictionary = recruited_people["towns"].get(u.home_town, {}).get("families", {}).get(u.family, {}).get("people", {})
		var known: bool = cohort_errors.is_empty() and not person.is_empty() and named_people.has(int(person[0])) and str(named_people[int(person[0])]["person_uid"]) == str(Persons.g(person, Persons.PERSON_UID, ""))
		check(known and not seen_people.has(identity), "attacker %d is one unique pre-existing registered person" % u.uid)
		seen_people[identity] = true
		var entry: Array = roll_book.get(str(u.uid), [])
		check(u.faction == "orc_horde" and home.get("faction", "") == "orc_horde" and entry.size() >= 3
			and entry[0] == u.home_town and int(entry[1]) == u.family and entry[2] == "army", "attacker %d retains actual home/family/army roll" % u.uid)
	print("loss fixture requested 30, accepted %d real registered attackers" % attackers.size())
	check(Caravans.is_prey(w, w["warbands"][orcs], w["warbands"][c2]), "staged attacker is hostile to the caravan")
	var cp: float = CampaignWorld.band_power(w["warbands"][c2]["units"])
	var ap: float = CampaignWorld.band_power(w["warbands"][orcs]["units"])
	var caravan_win: float = cp * cp / maxf(0.001, cp * cp + ap * ap)
	var clash_rng: RandomNumberGenerator = RandomNumberGenerator.new()
	clash_rng.seed = 42
	var clash_state: int = clash_rng.state
	var roll: float = clash_rng.randf()
	check(roll >= caravan_win, "controlled clash roll selects the attacker: %.6f >= %.6f" % [roll, caravan_win])
	if fails > 0 or not _within_part_budget(): return
	clash_rng.state = clash_state
	w["encounter"] = ""
	CampaignWorld._warband_clashes(Game, Game.day, clash_rng)
	check(not w["warbands"].has(c2), "controlled hostile clash destroys the caravan")
	check(dest["shop"].size() == dest_shop0, "a lost caravan still delivered")
	check(Goods.supply(dest, "linen") == dest_linen, "destroyed cargo adds no linen at the destination")
	check(int(TownEcon.goods_lost.get("linen", 0)) - linen_lost == linen_load, "destroyed linen is recorded once in the actual goods-loss ledger")
	print("loss log: ", w["log"].slice(-1))

## Try native offers in sorted towns, without changing needs, prices, cargo or pay.
func _start_escort(w: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	Game.contract = {}
	var ids: Array = w["towns"].keys()
	ids.sort()
	var offer: Dictionary = {}
	var town: Dictionary = {}
	for tid: String in ids:
		if not _within_part_budget(): return {}
		town = w["towns"][tid]
		if town["faction"] != "middle_kingdom": continue
		for i: int in 60:
			if not _within_part_budget(): return {}
			offer = Contracts.escort_offer(town, Game.day, rng)
			if not offer.is_empty(): break
		if not offer.is_empty(): break
	check(not offer.is_empty(), "no escort offer")
	if offer.is_empty(): return {}
	town["contracts"].append(offer)
	print("escort offer: ", offer["desc"], " pay ", offer["pay"])
	w["party"]["pos"] = town["pos"] + Vector2(0, 30)
	w["party"]["path"] = []
	check(Contracts.accept(Game, offer), "escort accept")
	if fails > 0: return {}
	var cid: String = str(Game.contract.get("target_id", ""))
	check(cid != "" and w["warbands"].has(cid), "accepted escort has a real target caravan")
	if cid == "" or not w["warbands"].has(cid): return {}
	return {"id": cid, "offer": offer}

func _escort_success(w: Dictionary, rng: RandomNumberGenerator) -> void:
	var fixture: Dictionary = _start_escort(w, rng)
	if fixture.is_empty(): return
	var offer: Dictionary = fixture["offer"]
	var ecar: String = fixture["id"]
	check(w["warbands"][ecar]["state"] == "waiting", "escort caravan should wait for the company")
	if fails > 0: return
	var gold0: int = Game.gold
	var done: bool = false
	for i: int in 600:
		if not _within_part_budget(): return
		Game.advance_time(0.02, false)
		w["encounter"] = ""
		if w["warbands"].has(ecar):
			w["party"]["pos"] = w["warbands"][ecar]["pos"] + Vector2(10, 0)
		if Game.contract.is_empty():
			done = true
			break
	check(done and (not w["warbands"].has(ecar) or w["warbands"][ecar].get("leg", "") == "home"), "escort never finished (economy: the caravan then heads home)")
	check(Game.gold > gold0 - Game.daily_wages() * 20 + int(offer["pay"]) - 1, "escort pay missing (gold %d -> %d)" % [gold0, Game.gold])
	print("escort result: ", w["log"].slice(-2))

func _escort_failure(w: Dictionary, rng: RandomNumberGenerator) -> void:
	var fixture: Dictionary = _start_escort(w, rng)
	if fixture.is_empty(): return
	var fcar: String = fixture["id"]
	for i: int in 10:
		if not _within_part_budget(): return
		Game.advance_time(0.02, false)
	check(w["warbands"].has(fcar), "escort failure target survives its initial departure")
	if not w["warbands"].has(fcar): return
	check(w["warbands"][fcar]["state"] == "travel", "escort caravan did not set out")
	if fails > 0: return
	w["party"]["pos"] = CampaignWorld.nearest_passable(w, w["warbands"][fcar]["pos"] + Vector2(600, 0))
	var rep0: int = Game.rep["middle_kingdom"]
	for i: int in 60:
		if not _within_part_budget(): return
		Game.advance_time(0.02, false)
		w["encounter"] = ""
		if Game.contract.is_empty(): break
	check(Game.contract.is_empty() and int(Game.rep["middle_kingdom"]) < rep0, "straying did not fail the escort")
	check(w["warbands"].has(fcar) and w["warbands"][fcar]["escort"] == "", "abandoned caravan should go on alone")
	print("escort failure: ", w["log"].slice(-1))

func _raid(w: Dictionary, rng: RandomNumberGenerator) -> void:
	var fixture: Dictionary = _spawn_native(w, rng)
	if fixture.is_empty(): return
	var pair: Array = fixture["pair"]
	var origin: Dictionary = w["towns"][pair[0]]
	var dest: Dictionary = w["towns"][pair[1]]
	var rc: String = fixture["id"]
	var rcargo: Dictionary = w["warbands"][rc]["cargo"]
	var r_uids: Array = rcargo["items"].map(func(it: Item) -> int: return it.uid)
	var food_q: float = float(rcargo["goods"].get("linen", 0.0))
	check(not r_uids.is_empty() and food_q > 0.0, "raid fixture has real native Items and linen")
	var cg0: float = float(Goods.company_goods(Game).get("linen", 0.0))
	var rep1: int = Game.rep[origin["faction"]]
	check(Caravans.can_raid(Game, rc), "raid hook refuses an unescorted caravan")
	if fails > 0 or not _within_part_budget(): return
	# Preserve the original victorious battle-result fixture; exercise the real loot handler.
	var guards: Array = w["warbands"][rc]["units"]
	for u: Unit in guards:
		u.dead = true
	Game.pending_battle = {"warband_id": rc, "enemy": guards}
	Game.finish_battle({"winner": 0, "player_units": Game.company, "enemy_units": guards, "enemy_fallen": guards, "events": []})
	var stash_uids: Array = Game.stash.map(func(it: Item) -> int: return it.uid)
	var in_stash: int = r_uids.filter(func(u: int) -> bool: return stash_uids.has(u)).size()
	check(in_stash == int(ceil(r_uids.size() * Caravans.PLUNDER_SHARE)), "raided items: %d of %d in the stash (economy: the company takes its share, the rest is lost)" % [in_stash, r_uids.size()])
	check(absf(float(Goods.company_goods(Game).get("linen", 0.0)) - cg0 - round(food_q * Caravans.PLUNDER_SHARE)) < 0.01, "raided linen (the company's share) not in the company goods store")
	check(int(Game.rep[origin["faction"]]) <= rep1 + Caravans.RAID_REP, "raid did not cost reputation")
	check(not w["warbands"].has(rc), "raided caravan still on the map")
	if fails > 0 or not _within_part_budget(): return
	var sold: int = Goods.sell(Game, dest, "linen", int(round(food_q * Caravans.PLUNDER_SHARE)))
	print("raid: %d items, %.0f food; sold the food in %s for %d gold; log %s" % [r_uids.size(), food_q, dest["name"], sold, w["log"].slice(-1)])
	check(food_q < 1.0 or sold > 0, "could not sell looted food")

func _persistence(w: Dictionary, rng: RandomNumberGenerator) -> void:
	var ids: Array = w["towns"].keys()
	ids.sort()
	for tid: String in ids:
		if not _within_part_budget(): return
		if Caravans.count(w) >= 4: break
		Caravans.spawn(Game, tid, rng)
	var before: Dictionary = {}
	for wid: String in w["warbands"]:
		if not _within_part_budget(): return
		var wb: Dictionary = w["warbands"][wid]
		before[wid] = "%s>%s %s %s" % [wb["origin"], wb["dest"], str(wb["cargo"]["items"].map(func(it: Item) -> int: return it.uid)), _gs(wb["cargo"]["goods"])]
	check(not before.is_empty(), "persistence has actual native caravans in flight")
	if fails > 0 or not _within_part_budget(): return
	# The existing runner supplies a private per-process SAVE_PATH. Do not touch it.
	var written: bool = Game.save_game()
	Game.wait_save()
	check(written, "caravan persistence fixture saves")
	if not written or not _within_part_budget(): return
	Game.world = {}
	var loaded: bool = Game.load_game()
	check(loaded, "caravan persistence fixture loads")
	if not loaded or not _within_part_budget(): return
	w = Game.world
	for wid: String in before:
		if not _within_part_budget(): return
		var wb: Dictionary = w["warbands"].get(wid, {})
		check(not wb.is_empty(), "caravan %s lost in save/load" % wid)
		if not wb.is_empty():
			var after: String = "%s>%s %s %s" % [wb["origin"], wb["dest"], str(wb["cargo"]["items"].map(func(it: Item) -> int: return it.uid)), _gs(wb["cargo"]["goods"])]
			check(after == before[wid], "caravan %s changed: %s vs %s" % [wid, before[wid], after])
			check(wb["cargo"]["items"].is_empty() or wb["cargo"]["items"][0] is Item, "cargo items not Items after load")

func _perf(w: Dictionary, rng: RandomNumberGenerator) -> void:
	# This part alone keeps the native generated bands, then the original full warm-up.
	for i: int in 40:
		if not _within_part_budget(): return
		Game.advance_time(0.25, false)
		w["encounter"] = ""
	for tid: String in w["towns"]:
		if not _within_part_budget(): return
		if Caravans.count(w) < Caravans.MAX_CARAVANS:
			Caravans.spawn(Game, tid, rng)
	w["party"]["safe_until"] = Game.day + 100.0
	var frame_days: float = (1.0 / 60.0) / 5.0
	var total: int = 0
	var worst: int = 0
	var n: int = 600
	for i: int in n:
		if not _within_part_budget(): return
		var t0: int = Time.get_ticks_usec()
		Game.day += frame_days
		CampaignWorld.on_time(Game, frame_days, false)
		var dtu: int = Time.get_ticks_usec() - t0
		total += dtu
		worst = maxi(worst, dtu)
		w["encounter"] = ""
	var mean: float = total / float(n) / 1000.0
	print("on_time per map frame: mean %.3f ms, worst %.2f ms, %d warbands (%d caravans)" % [mean, worst / 1000.0, w["warbands"].size(), Caravans.count(w)])
	check(mean < 0.5, "on_time too slow per frame: %.3f ms" % mean)

func run(_tree: SceneTree) -> int:
	fails = 0
	_part = "delivery"
	var selected: bool = false
	for arg: String in OS.get_cmdline_user_args():
		if arg == "--caravans-part":
			check(false, "use --caravans-part=<name>")
			continue
		if not arg.begins_with("--caravans-part="): continue
		check(not selected, "select exactly one caravan part per invocation")
		selected = true
		_part = arg.trim_prefix("--caravans-part=")
		check(_part in PARTS, "unknown caravan part; choose one of " + ", ".join(PARTS))
	if fails > 0: return fails
	var started: int = Time.get_ticks_msec()
	_part_deadline_msec = started + PART_BUDGET_MSEC
	Game.new_game(321)
	if _within_part_budget():
		var w: Dictionary = Game.world
		var rng: RandomNumberGenerator = RandomNumberGenerator.new()
		rng.seed = 11
		_homes(w)
		if fails == 0 and _within_part_budget():
			if _part != "perf": _clear_bands(w)
			match _part:
				"delivery": _delivery(w, rng, true)
				"unfunded": _delivery(w, rng, false)
				"loss": _loss(w, rng)
				"escort-success": _escort_success(w, rng)
				"escort-failure": _escort_failure(w, rng)
				"raid": _raid(w, rng)
				"persistence": _persistence(w, rng)
				"perf": _perf(w, rng)
	if fails == 0: _within_part_budget()
	print("caravans %s: %d failures; %.3f s" % [_part, fails, (Time.get_ticks_msec() - started) / 1000.0])
	return fails
