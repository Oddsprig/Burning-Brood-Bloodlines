extends RefCounted
## Full native people/plots/stock remain present. Only real holdings, rights and coins change holders.
const Native = preload("res://tests/class_d_native_economy.gd")
const Physical = preload("res://tests/farm_fixture_tools.gd")

static func mint_site(town: Dictionary) -> bool:
	var e: Dictionary = town["econ"]
	return bool(town.get("capital", false)) or str(town.get("specialty", "")) == "mining" or ((e["deposits"] as Dictionary).has("copper_ore") and (e["deposits"] as Dictionary).has("tin_ore"))

## Prefer generated eligible towns. Missing cultures use a real non-capital mining
## site's unchanged terrain/specialty as generation inputs, before any economy exists.
## EconGen owns all people, holdings, shops and mint admission; no mint is appended.
static func towns(game: Node) -> Dictionary:
	var registry: Dictionary = TownEcon.data()["cultures"]
	var found: Dictionary = {}
	var source: Dictionary = {}
	var ids: Array = game.world["towns"].keys()
	ids.sort()
	for tid: String in ids:
		var town: Dictionary = game.world["towns"][tid]
		if not TownEcon.has_econ(town) or not town["econ"].has("mint_biz"): continue
		if not mint_site(town): return {"ok": false, "reason": "generated mint violates native capital/mining admission"}
		var culture: String = str(town["econ"]["culture"])
		if not registry.has(culture): return {"ok": false, "reason": "unregistered generated culture: " + culture}
		if not found.has(culture): found[culture] = town
		if not town.get("capital", false) and str(town.get("specialty", "")) == "mining" and (source.is_empty() or town["econ"]["fams"].size() > source["econ"]["fams"].size()): source = town
	if registry.is_empty(): return {"ok": false, "reason": "native culture registry is empty"}
	if found.size() < registry.size() and source.is_empty(): return {"ok": false, "reason": "missing cultures need an existing native non-capital mining site"}
	var cultures: Array = registry.keys()
	cultures.sort()
	for culture: String in cultures:
		if found.has(culture): continue
		var town: Dictionary = source.duplicate(true)
		town.erase("econ")
		town["id"] = "weekly225_" + culture
		town["culture"] = culture
		town["race"] = str(registry[culture]["race"])
		for key: String in ["shop", "recruits", "contracts", "roads", "neighbours"]: town[key] = []
		for key: String in ["crafters", "healer", "prices", "material_prices"]: town[key] = {}
		if game.world["towns"].has(town["id"]): return {"ok": false, "reason": "weekly native fixture ID already exists"}
		var rng: RandomNumberGenerator = RandomNumberGenerator.new()
		rng.seed = hash([game.world["seed"], culture, "weekly225-native-mint-site"])
		Economy.make_crafters(town, rng)
		Economy.roll_prices(town, rng)
		EconGen.generate(game.world, town, rng)
		if not TownEcon.has_econ(town) or str(town["econ"].get("culture", "")) != culture or not town["econ"].has("mint_biz") or not mint_site(town):
			return {"ok": false, "reason": "native generation did not admit an eligible mint for " + culture}
		Plots.layout(game.world, town)
		if Plots.needs_layout(town["econ"]): return {"ok": false, "reason": "weekly native fixture needs complete physical plots"}
		found[culture] = town
	return {"ok": true, "towns": found}

## Independent native review from the funded setup, before the actual town turn.
## Keep the pre-review order in sync with TownEcon.town_turn; never read its result.
static func reviewed_weekly_wage(town: Dictionary, e: Dictionary, bid: int, day: int) -> float:
	var quote: Dictionary = e.duplicate(true)
	var quote_town: Dictionary = town.duplicate()
	quote_town["econ"] = quote
	TownSanitation.weekly(quote, float(day))
	TownHousing.weekly(quote, float(day))
	Shelter.weekly(Game, quote_town, quote)
	var tx: Dictionary = quote["tax"]
	var stamp: int = TownEcon.season_stamp(float(day))
	if stamp != int(tx["season"]):
		tx["season"] = stamp
		tx["last_paid"] = float(tx.get("paid", 0.0))
		tx["paid"] = 0.0
		tx["owed"] = 0.0
		var ph: Array = quote["stats"]["pop_hist"]
		ph.append(int(quote["pop"]))
		while ph.size() > 8:
			ph.pop_front()
		var st: Dictionary = quote["stats"]
		st["bd_last"] = [int(st.get("births", 0)) - int(st.get("births_at", 0)), int(st.get("deaths", 0)) - int(st.get("deaths_at", 0))]
		st["births_at"] = int(st.get("births", 0))
		st["deaths_at"] = int(st.get("deaths", 0))
	var T: Dictionary = TownEcon.data()["tax"]
	var live: int = int(Population.household_stats(quote)["households"])
	for business: Dictionary in quote["biz"]:
		if business["type"] == "collector":
			business["cap"] = maxi(1, int(ceil(float(live) / float(T["collector_per"]))))
			tx["leak"] = float(T["leak_max"]) * (1.0 - minf(1.0, float(business["workers"]) / float(business["cap"])))
	Barge.pay_week(quote)
	return float(quote["biz"][bid]["wage"])

static func exercise(test: RefCounted, town: Dictionary, original: Dictionary, funded: bool, reverse_order: bool) -> void:
	var e: Dictionary = original.duplicate(true)
	town["econ"] = e
	test.check(e.has("mint_biz") and mint_site(town), "existing mint was admitted by native capital/mining generation")
	if not e.has("mint_biz") or not mint_site(town): return
	var initial_coin: float = Native.money(e)
	var initial_people: int = 0
	var initial_acres: int = 0
	for family: Dictionary in e["fams"]:
		initial_people += Families.people(family); initial_acres += Families.acres(family)
	var selected: Array = []
	for family: Dictionary in e["fams"]:
		if not family.get("gone", false) and not family.get("estate", false) and Families.adults(family) >= 3 and Families.serving(family) == 0:
			selected.append(int(family["id"]))
	test.check(selected.size() >= 6, "six real civilian households exist")
	if selected.size() < 6: return
	if reverse_order: selected.reverse()
	selected = selected.slice(0, 6)
	var owner: Dictionary = e["fams"][int(selected[0])]
	var custodian: Dictionary = {}
	for family: Dictionary in e["fams"]:
		if not family.get("gone", false) and not family.get("estate", false) and not selected.has(int(family["id"])) and Families.serving(family) == 0:
			custodian = family
	test.check(not custodian.is_empty(), "existing separate household can hold the other physical property")
	if custodian.is_empty(): return
	# Remove private payroll collateral by transferring rights, never deleting grain or its books.
	for family: Dictionary in e["fams"]:
		if not family.get("estate", false): HarvestClaims.transfer(e, "f:%d" % int(family["id"]), "f:0")
	var pooled: Dictionary = Native.pool(e)
	test.check(bool(pooled["ok"]), str(pooled.get("reason", "")))
	if not bool(pooled["ok"]): return
	for family: Dictionary in e["fams"]:
		if not family.get("estate", false) and not family.get("gone", false):
			Native.vacate(e, family)
			Native.transfer_holding(e, family)
	var est: Dictionary = e["fams"][0]
	for crop: String in est["land"].keys(): Families.move_land(e, est, custodian, crop, int(est["land"][crop]))
	for kind: String in est["herd"].keys(): Families.move_herd(e, est, custodian, kind, int(est["herd"][kind]))
	# Rebuild the original small public holding from counted native fields, without reducing the town.
	var physical: RefCounted = Physical.new()
	test.check(physical.grain(e, est, 16), "public estate receives sixteen existing productive cereal acres")
	# Exactly two vacancies must emerge from real work, helpers, keepers and draught animals.
	var farm: Dictionary = {}
	for acre: int in int(e["territory"]) + 1:
		# Draw only from the other holder, never the estate's reserved fields.
		if not physical.grain(e, owner, 1, int(custodian["id"])): break
		Families.reassign(e, owner)
		farm = Businesses.farm_of(e, owner)
		if not farm.is_empty() and int(farm["cap"]) >= 2: break
	test.check(not farm.is_empty() and int(farm["cap"]) == 2 and int(farm["owner"]) == int(owner["id"]) and int(owner["farm"]) == int(farm["id"]),
		"real productive private holding naturally advertises exactly two linked native vacancies")
	if farm.is_empty() or int(farm["cap"]) != 2: return
	test.check(int(est["land"].get("grain", 0)) == 16, "private holding preserves the estate's sixteen productive cereal acres")
	Families.reassign(e, custodian)
	pooled = Native.pool(e)
	test.check(bool(pooled["ok"]), str(pooled.get("reason", "")))
	if not bool(pooled["ok"]): return
	# Keep the original isolated anonymous debt, separate from actual newly earned staff claims.
	test.check(float(farm.get("owed", 0.0)) == 0.0 and farm.get("wage_claims", {}).is_empty(), "new native holding has no fabricated former-worker debt")
	farm["owed"] = 14.0; farm["owed_unattributed"] = 14.0; farm["wage_claims"] = {}
	e["day"] = 7; Game.day = 7.0
	WageClaims.accrue_day(e, 7)
	# Holding transfers must conserve the complete town before ordinary life events.
	var people_before_turns: int = 0
	var acres_before_turns: int = 0
	for family: Dictionary in e["fams"]:
		people_before_turns += Families.people(family); acres_before_turns += Families.acres(family)
	test.check(people_before_turns == initial_people and acres_before_turns == initial_acres,
		"holding transfers preserve every native person and acre before civilian turns")
	var census_before: Dictionary = Census.balance(e)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 17263
	for fid: int in selected: Families.turn(Game, town, e, e["fams"][fid], 7.0, rng)
	var census_after: Dictionary = Census.balance(e)
	var births_during_turns: int = int(census_after["births"]) - int(census_before["births"])
	# Native pooled households can have whole births during their real weekly turn.
	# Do not let births mask a death, departure or replacement resident.
	test.check(births_during_turns >= 0 and int(census_after["deaths"]) == int(census_before["deaths"])
		and int(census_after["left"]) == int(census_before["left"]) and int(census_after["arrived"]) == int(census_before["arrived"]),
		"ordinary civilian turns add only registered births; no original resident dies or leaves")
	# All actual participants remain; the six original civilian paydays have happened before funding.
	for family: Dictionary in e["fams"]:
		if not family.get("estate", false): HarvestClaims.transfer(e, "f:%d" % int(family["id"]), "f:0")
	pooled = Native.pool(e)
	test.check(bool(pooled["ok"]), str(pooled.get("reason", "")))
	if not bool(pooled["ok"]): return
	var mint: Dictionary = e["biz"][int(e["mint_biz"])]
	var estate: Dictionary = e["biz"][int(e["estate_biz"])]
	# This early vacancy quote budgets payroll only; staffing can change before review.
	var budget_quote: Dictionary = e.duplicate(true)
	Barge.pay_week(budget_quote)
	var budget_wage: float = float(budget_quote["biz"][int(farm["id"])]["wage"])
	var floor_reserve: float = maxf(5.0 * TownEcon.COIN, EconomyRules.essential_food_cost(e,
		maxf(0.0, 14.0 - float(owner["store"]["food"])) * float(Families.daily_rates(e, owner)["food"])))
	var payroll: float = 14.0 + (float(farm["cap"]) * budget_wage * 8.0 if funded else 0.0)
	test.check(Native.move(pooled["vault"], "purse", owner, "purse", floor_reserve + payroll), "existing holder funds only the native protected reserve and actual farm payroll")
	Businesses.fund_farm(owner, farm, e)
	if funded:
		test.check(Native.move(pooled["vault"], "purse", e, "treasury", float(Barge.treasury_lines(e)["full"]) * 0.9), "public jobs use conserved native treasury funding")
	else:
		test.check(Businesses.farm_kind_value(e, farm) == 0.0 and Businesses.takeable(farm, e) == 0, "unfunded farm has no private surplus grain or free payroll cash")
	test.check(absf(Native.money(e) - initial_coin) < 0.00001, "native holding and funding setup conserves all existing coins")
	var people_after: int = 0
	var acres_after: int = 0
	for family: Dictionary in e["fams"]:
		people_after += Families.people(family); acres_after += Families.acres(family)
	test.check(people_after == initial_people + births_during_turns and acres_after == initial_acres,
		"full native population and acreage survive fixture setup (people %d -> %d, registered births %d; acres %d -> %d)"
		% [initial_people, people_after, births_during_turns, initial_acres, acres_after])
	var last: Array = []
	for fid: int in selected: last.append(float(e["fams"][fid]["last"]))
	var before: float = Native.money(e)
	var reviewed_wage: float = reviewed_weekly_wage(town, e, int(farm["id"]), 7)
	TownEcon.town_turn(Game, town, 7)
	test.check(absf(Native.money(e) - before) < 0.00001, "weekly event moves existing coins only")
	test.check(float(farm["wage"]) == reviewed_wage, "actual weekly wage equals independent detached native review")
	test.check(int(farm["cap"]) == 2 and int(farm["owner"]) == int(owner["id"]) and int(owner["farm"]) == int(farm["id"]), "native reassignment preserves the real holding's two vacancies")
	test.check(int(estate["cap"]) > 0 and int(mint["cap"]) > 0, "ordinary weekly capacities open estate and mint")
	if funded:
		test.check(int(estate["workers"]) == int(estate["cap"]), "new funded estate jobs fill after civilian turns")
		test.check(int(mint["workers"]) == int(mint["cap"]), "new funded mint jobs fill after civilian turns")
		test.check(int(farm["workers"]) == 2, "funded family farm joins the same matching event")
	else:
		test.check(int(estate["workers"]) == 0 and int(mint["workers"]) == 0 and int(farm["workers"]) == 0, "unfinanced capacities do not become jobs")
	test.check(float(farm["owed"]) == 14.0, "hiring preserves committed anonymous obligations")
	var public_bill: float = 0.0
	var idle: int = 0
	for business: Dictionary in e["biz"]:
		var funding: String = str(business.get("public_funding", ""))
		if (funding == "town" or (funding.is_empty() and int(business["owner"]) < 0)) and not business.get("closed", false):
			public_bill += int(business["workers"]) * float(business["wage"])
	for family: Dictionary in e["fams"]:
		if not family.get("estate", false) and not family.get("gone", false): idle += int(family["idle"])
	for fid: int in selected:
		var family: Dictionary = e["fams"][fid]
		test.check(not Families.assignments_stale(family), "weekly matching balances civilian adults")
		test.check(float(family.get("wage_receipts", 0)) == 0.0, "new hires receive no preceding wages")
	test.check(absf(float(e["stats"]["town_wages"]) - public_bill) < 0.00001, "reserve bill includes newly matched public hands")
	test.check(int(e["idle_n"]) == idle, "weekly idle recount sees the completed matching")
	var after_last: Array = []
	for fid: int in selected: after_last.append(float(e["fams"][fid]["last"]))
	test.check(last == after_last, "weekly matching leaves ordinary paydays unchanged")
	var snapshot: String = JSON.stringify(e)
	Families.match_idle(e)
	test.check(JSON.stringify(e) == snapshot, "no genuine remaining offer leaves coins and assignments identical")
	var expected: float = 0.0
	for business: Dictionary in e["biz"]:
		if not business.get("closed", false): expected += int(business["workers"]) * float(business["wage"])
	WageClaims.accrue_day(e, 8)
	var paid: float = 0.0
	for family: Dictionary in e["fams"]:
		if not family.get("gone", false): paid += float(WageClaims.pay_family(e, family)[0])
	test.check(absf(paid - expected) < 0.00001, "following day pays actual new staff wages from funded tills")
	test.check(absf(Native.money(e) - before) < 0.00001, "settling worked wages preserves existing coins")
	test.check(float(farm["owed"]) == 14.0, "paying today's workers preserves older unattributed wages")
