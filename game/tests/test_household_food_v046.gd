extends RefCounted
## Existing household entry points only: usable unchanged on v0.045 and v0.046.
## Controlled opening endowments have matching physical, household and person counts.
const EDIBLE := ["grain", "fruit", "meat", "fresh_meat"]
var checks := 0
var fails := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		fails += 1
		printerr("FAIL: ", message)

func near(actual: float, expected: float, message: String) -> void:
	check(absf(actual - expected) < 0.00001, "%s got %.9f expected %.9f" % [message, actual, expected])

func fixture(culture: String) -> Dictionary:
	var estate := Families._blank(0)
	estate["estate"] = true
	var e := {"culture": culture, "climate": "temperate", "day": 1000.0, "fams": [estate],
		"stock": {}, "barn": {}, "hh": {}, "price": {}, "carry": {}, "need": {},
		"land": {}, "herd": {}, "wacres": {}, "wherd": {}, "hands": 0,
		"pop": 0, "adults": 0, "homes": 0, "kids_n": 0, "broth_n": 0, "away_n": 0,
		"shel_n": 0, "rich": 0, "granary": 0, "treasury": 10000.0, "farm_till": 0.0,
		"cum": {}, "next_pid": 1, "stats": {"sales": 0.0}, "req": {},
		"led": {"made": {}, "used": {}, "spoil": {}},
		"biz": [{"id": 0, "type": "market", "till": 10000.0, "spend": 0.0}], "mkt": 0}
	for good in TownEcon.data()["goods"]:
		e["stock"][good] = 0
		e["barn"][good] = 0
		e["hh"][good] = 0
		e["price"][good] = float(TownEcon.data()["goods"][good]["price"])
	return e

func child_threshold(e: Dictionary) -> float:
	return float(Barge.B()["labour"]["kid_from"]) * float(People.ages(Persons.race_of(e))["adult"]) / 16.0 * People.year_days()

func person(e: Dictionary, f: Dictionary, sex: int, born: float, kind: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(e["next_pid"]) + 46000
	return Persons._new(e, f, Persons.race_of(e), sex, born, kind, rng)

func household(e: Dictionary, young: int = 0, older: int = 0, elders: int = 0, grown: int = 2) -> Dictionary:
	var f := Families._blank((e["fams"] as Array).size())
	f["homes"] = 1
	f["purse"] = 10000.0
	f["pp"] = []
	f["kp"] = []
	(e["fams"] as Array).append(f)
	var ab := People.ages(Persons.race_of(e))
	var day := float(e["day"])
	for i in grown:
		var sex := i % 2
		f[["m", "f"][sex]] = int(f[["m", "f"][sex]]) + 1
		f["pp"].append(person(e, f, sex, day - (float(ab["adult"]) + 2.0) * People.year_days(), 0))
	for i in elders:
		f["old"] = int(f["old"]) + 1
		f["pp"].append(person(e, f, i % 2, day - (float(ab["elder"]) + 1.0) * People.year_days(), 1))
	for i in young + older:
		var born := day - child_threshold(e) + (10.0 if i < young else -10.0)
		f["kp"].append(person(e, f, i % 2, born, 2))
		f["kids"] = int(f["kids"]) + 1
	f["frate"] = float(grown + elders) + 0.6 * young + 0.8 * older
	TownEcon.recount(e)
	Barge.recount_week(e)
	check((f["pp"] as Array).size() == grown + elders and (f["kp"] as Array).size() == young + older, "fixture register matches household counts")
	return f

func food_sum(holder: Dictionary) -> int:
	var n := 0
	for good in EDIBLE: n += int(holder.get(good, 0))
	return n

func used(e: Dictionary) -> int:
	return food_sum(e["led"]["used"])

func eat_carry(e: Dictionary) -> float:
	var n := 0.0
	for good in EDIBLE: n += float(e["carry"].get("eat" + good, 0.0))
	return n

func eat(e: Dictionary, days: int = 1) -> void:
	for i in days:
		TownEcon._households(e, TownEcon.data(), 1, TownEcon.data()["climates"][e["climate"]])
		e["day"] = float(e["day"]) + 1.0

func cash(e: Dictionary) -> float:
	var n := float(e["treasury"]) + float(e["farm_till"])
	for b in e["biz"]: n += float(b["till"])
	for f in e["fams"]: n += float(f["purse"])
	return n

func shares(culture: String) -> void:
	for spec in [[2, 0, 0, 6.4], [0, 2, 0, 7.2], [1, 1, 1, 8.8]]:
		var e := fixture(culture)
		var f := household(e, int(spec[0]), int(spec[1]), int(spec[2]))
		near(float(Barge.eaters(e, f, float(e["day"]))[0]) * 2.0, float(spec[3]), culture + ": exact child and elder shares")
		e["hh"]["grain"] = 1000
		eat(e, 5)
		near(float(used(e)) + eat_carry(e), float(spec[3]) * 5.0, culture + ": five actual daily meals retain fractional carry")
		check(int(e["hh"]["grain"]) + used(e) == 1000, culture + ": daily meals close physical used ledger")
		near(float(e["food_short"]), 0.0, culture + ": sufficient physical grain feeds exact shares")
	var e := fixture(culture)
	household(e, 1, 1, 1)
	var demand := TownEcon.household_use(e, 1)
	var diet := Barge.diet(e)
	for good in ["grain", "fruit", "meat"]:
		near(float(demand[good]), 4.4 * float(diet[good]), culture + ": opening food demand uses actual shares " + good)

func age_cache(culture: String) -> void:
	var e := fixture(culture)
	var f := household(e, 1)
	var threshold := float(f["kp"][0][3]) + child_threshold(e)
	var before := threshold - 0.25
	near(float(Barge.eaters(e, f, before)[0]), 2.6, culture + ": younger share warms age cache")
	near(float(Barge.eaters(e, f, threshold)[0]), 2.8, culture + ": birthday refreshes warm same-count cache")
	near(float(Barge.eaters(e, f, threshold + 8.0)[0]), 2.8, culture + ": older share warms a future-dated cache")
	near(float(Barge.eaters(e, f, before)[0]), 2.6, culture + ": future-dated age cache cannot serve an earlier day")
	e = fixture(culture)
	f = household(e, 1)
	near(float(Barge.eaters(e, f, float(e["day"]))[0]), 2.6, culture + ": replacement setup has one younger child")
	# Replace the record, preserving the child count and valid native person shape.
	f["kp"][0] = person(e, f, 0, float(e["day"]) - child_threshold(e) - 10.0, 2)
	near(float(Barge.eaters(e, f, float(e["day"]))[0]), 2.8, culture + ": same-count older record invalidates age cache")

func service_and_broth(culture: String) -> void:
	for role in ["army", "bandit", "deserter", "militia", "guard", "caravan"]:
		var e := fixture(culture)
		var f := household(e, 1, 1, 1, 4)
		f["serve"] = {role: 1}
		f["pp"][0][4] = role
		# Cached town counters deliberately predate this real service change.
		e["hh"]["grain"] = 1000
		eat(e)
		var expected := 10.8 if role in ["army", "bandit", "deserter"] else 12.8
		near(float(used(e)) + eat_carry(e), expected, culture + ": existing home/away role " + role)
		f["serve"] = {}
		f["pp"][0][4] = ""
		var before := float(used(e)) + eat_carry(e)
		eat(e)
		near(float(used(e)) + eat_carry(e) - before, 12.8, culture + ": service return changes demand immediately")
	var e := fixture(culture)
	var f := household(e, 1)
	household(e, 0, 0, 0, 1)
	f["homes"] = 0
	e["fams"][0]["homes"] = 1 # Its existing roof passes to the estate.
	f["shel"] = true
	f["serve"] = {"army": 1}
	f["pp"][0][4] = "army"
	e["shel_n"] = Families.people(f)
	e["shelter_short"] = 0.0
	f["store"]["food"] = 0.0
	Shelter.eat({}, e, f, 7.0)
	check(f.get("broth", false), culture + ": native shelter enters broth mode")
	e["hh"]["grain"] = 1000
	eat(e)
	near(float(used(e)) + eat_carry(e), 2.0, culture + ": broth and away shares excluded exactly once")
	f["store"]["food"] = 7.0
	Shelter.eat({}, e, f, 7.0)
	check(not f.get("broth", false), culture + ": native real-food switch leaves broth mode")
	var before := float(used(e)) + eat_carry(e)
	eat(e)
	near(float(used(e)) + eat_carry(e) - before, 5.2, culture + ": switch restores exact home shares")
	f["broth"] = true
	e["broth_n"] = Families.people(f)
	e["fams"][0]["homes"] = 0
	f["homes"] = 1 # The estate returns the same existing roof.
	Shelter._housed(e, f, float(e["day"]))
	before = float(used(e)) + eat_carry(e)
	eat(e)
	near(float(used(e)) + eat_carry(e) - before, 5.2, culture + ": rehousing refreshes broth exclusion immediately")

func fresh_food(culture: String) -> void:
	var e := fixture(culture)
	household(e)
	e["hh"]["fresh_meat"] = 3
	var before_supply := JSON.stringify(e)
	near(TownEcon.days_food({"econ": e}), 0.75, culture + ": town supply includes actual household fresh food")
	check(JSON.stringify(e) == before_supply, culture + ": fresh-food supply read preserves live physical books")
	eat(e)
	check(int(e["hh"]["fresh_meat"]) == 0 and int(e["led"]["used"].get("fresh_meat", 0)) == 3, culture + ": fresh-only short stock is physically eaten")
	near(float(e["food_short"]), 0.25, culture + ": three fresh meals cover three of four needed meals")
	e = fixture(culture)
	household(e)
	for good in EDIBLE: e["hh"][good] = 100
	eat(e)
	for good in EDIBLE:
		check(int(e["hh"][good]) == 99 and int(e["led"]["used"].get(good, 0)) == 1, culture + ": mixed physical meals retain identity " + good)
	e = fixture(culture)
	var f := household(e)
	e["stock"]["fresh_meat"] = 1000
	var before_cash := cash(e)
	EconomyRules.cover_food(e, f, 7.0, float(e["day"]))
	check(int(e["stock"]["fresh_meat"]) == 972 and int(e["hh"]["fresh_meat"]) == 28, culture + ": emergency purchase transfers 28 existing fresh meals")
	near(float(f["store"]["food"]), 7.0, culture + ": purchased fresh meals credit seven food days")
	near(cash(e), before_cash, culture + ": fresh purchase conserves actual payer/payee coins")
	check(int(e["hh"]["meat"]) == 0 and int(e["led"]["made"].get("meat", 0)) == 0, culture + ": bought fresh food is not silently salted")
	eat(e)
	check(int(e["hh"]["fresh_meat"]) == 24 and int(e["led"]["used"].get("fresh_meat", 0)) == 4, culture + ": purchased food enters actual daily used ledger")
	# Separate fixture isolates household spoilage from market spoilage.
	e = fixture(culture)
	household(e)
	e["climate"] = "hot"
	e["hh"]["fresh_meat"] = 1000
	eat(e)
	TownEcon._spoil(e, TownEcon.data(), 1, TownEcon.data()["climates"]["hot"], 3.0)
	var lost := int(e["led"]["spoil"].get("fresh_meat", 0))
	check(lost > 0 and int(e["hh"]["fresh_meat"]) + lost + int(e["led"]["used"].get("fresh_meat", 0)) == 1000, culture + ": eaten plus spoiled fresh stock closes physical ledger")
	check(int(e["hh"]["meat"]) == 0, culture + ": fresh spoilage preserves original food identity")

func bounded_transfers(culture: String) -> void:
	for mixed in [false, true]:
		var e := fixture(culture)
		var f := household(e)
		var dest := fixture(culture)
		f["store"]["food"] = 0.5
		if mixed:
			for good in EDIBLE: e["hh"][good] = 100
		else:
			e["hh"]["fresh_meat"] = 100
		var opening: Dictionary = e["hh"].duplicate(true)
		var opening_total := food_sum(e["hh"])
		var carried := Barge._carry_stores(e, dest, f)
		check(food_sum(dest["hh"]) == 2 and food_sum(e["hh"]) == opening_total - 2, culture + ": migration moves exactly two requested meals")
		near(float(carried["food"]), 0.5, culture + ": carried days equal actual bounded meals")
		for good in EDIBLE:
			check(int(e["hh"][good]) + int(dest["hh"][good]) == int(opening[good]), culture + ": migration conserves each physical food identity " + good)
		check(used(e) == 0 and used(dest) == 0, culture + ": migration is a transfer rather than eating")
		e = fixture(culture)
		f = household(e)
		f["store"]["food"] = 0.5
		if mixed:
			for good in EDIBLE: e["hh"][good] = 100
		else:
			e["hh"]["fresh_meat"] = 100
		opening = e["hh"].duplicate(true)
		opening_total = food_sum(e["hh"])
		Families._take_stores(e, f)
		check(food_sum(e["hh"]) == opening_total - 2 and used(e) == 2, culture + ": departure removes exactly two requested meals")
		near(float(f["store"]["food"]), 0.0, culture + ": departure clears the departing store-days")
		for good in EDIBLE:
			check(int(e["hh"][good]) + int(e["led"]["used"].get(good, 0)) == int(opening[good]), culture + ": departure closes each food ledger " + good)
	var short := fixture(culture)
	var family := household(short)
	var destination := fixture(culture)
	family["store"]["food"] = 0.5
	short["hh"]["fresh_meat"] = 1
	var remainder := Barge._carry_stores(short, destination, family)
	check(food_sum(short["hh"]) == 0 and int(destination["hh"]["fresh_meat"]) == 1, culture + ": short migration moves only the one existing fresh meal")
	near(float(remainder["food"]), 0.25, culture + ": short migration reports only actual carried days")
	short = fixture(culture)
	family = household(short)
	family["store"]["food"] = 0.5
	short["hh"]["fresh_meat"] = 1
	Families._take_stores(short, family)
	check(food_sum(short["hh"]) == 0 and used(short) == 1, culture + ": short departure debits only existing physical food")

func keeping_recipes(culture: String) -> void:
	var e := fixture(culture)
	var f := household(e)
	var kept := Herds._to_larder(e, f, 10)
	check(kept == 10 and int(e["hh"]["meat"]) == 10 and int(e["hh"]["fresh_meat"]) == 0, culture + ": established own-slaughter larder keeps salted meat")
	check(int(e["led"]["made"].get("meat", 0)) == 10, culture + ": own-larder keeping recipe records physical output")
	e = fixture(culture)
	f = household(e)
	f["purse"] = 0.0
	var animal := ""
	for kind in Herds.GRAZE:
		if float(Herds.yields(String(kind), "g").get("fresh_meat", 0)) >= 28.0:
			animal = String(kind)
			break
	check(animal != "", culture + ": property-selected grazer can feed the household")
	if animal == "": return
	var h := Herds.new_herd(e, animal, "f", int(f["id"]), float(e["day"]))
	# One explicit opening animal endowment, with matching ledger and mirrors.
	h["g"] = 1
	h["h0"] = 1
	f["herd"][animal] = 1
	e["herd"][animal] = 1
	e["wherd"][animal] = 0.0
	var output := int(floor(float(Herds.yields(animal, "g")["fresh_meat"])))
	var before_cash := cash(e)
	EconomyRules.cover_food(e, f, 7.0, float(e["day"]))
	check(Herds.head(h) == 0 and int(h["led"]["sl"]) == 1 and Families.heads(f) == 0, culture + ": emergency slaughter removes one actual owned animal")
	check(int(e["hh"]["meat"]) >= 28 and int(e["hh"]["fresh_meat"]) == 0, culture + ": established emergency home slaughter retains keeping meat")
	check(int(e["hh"]["meat"]) + int(e["barn"]["fresh_meat"]) + int(e["stock"]["fresh_meat"]) == output, culture + ": emergency slaughter preserves all actual meat output")
	near(cash(e), before_cash, culture + ": emergency home-slaughter endowment creates no coins")

func legacy_age_lookup() -> void:
	var e := {"day": 1000.0, "wf": 0.75}
	var f := Families._blank(1)
	f["m"] = 1
	f["f"] = 1
	f["old"] = 1
	f["homes"] = 2
	f["frate"] = 3.0
	var before_e := JSON.stringify(e)
	var before_f := JSON.stringify(f)
	var counted := Barge.eaters(e, f, float(e["day"]))
	near(float(counted[0]), 3.0, "culture-free adults and elder need no child age lookup")
	check(int(counted[1]) == 0 and int(counted[2]) == 0 and int(counted[3]) == 1,
		"culture-free adult fixture preserves age-class counts")
	var rates := Families.daily_rates(e, f)
	near(float(rates["food"]), 3.0 * float(TownEcon.data()["needs"]["food"]),
		"culture-free adult and elder daily food rate")
	check(JSON.stringify(e) == before_e and JSON.stringify(f) == before_f,
		"culture-free adult reads preserve econ and family")

	for empty_register in [false, true]:
		for complete_cache in [false, true]:
			f = Families._blank(1)
			f["m"] = 1
			f["f"] = 1
			f["old"] = 1
			f["kids"] = 2
			f["homes"] = 2
			f["frate"] = 4.2
			if empty_register:
				f["kp"] = []
			f["k1014"] = 2
			f["k1014_d"] = float(e["day"])
			f["k1014_n"] = 2
			if complete_cache:
				f["k1014_next"] = float(e["day"]) + 7.0
				f["k1014_race"] = "human"
				f["k1014_sig"] = hash(f.get("kp", []))
			var label := "%s register, %s cache" % [
				"empty" if empty_register else "missing",
				"current-looking" if complete_cache else "legacy"]
			before_e = JSON.stringify(e)
			before_f = JSON.stringify(f)
			counted = Barge.eaters(e, f, float(e["day"]))
			near(float(counted[0]), 4.2, label + ": unrecorded children eat 0.6 each")
			check(int(counted[1]) == 0 and int(counted[2]) == 2 and int(counted[3]) == 1,
				label + ": stale cache cannot supply older-child counts")
			rates = Families.daily_rates(e, f)
			near(float(rates["food"]), 4.2 * float(TownEcon.data()["needs"]["food"]),
				label + ": pure daily rate uses actual fallback shares")
			check(JSON.stringify(e) == before_e and JSON.stringify(f) == before_f,
				label + ": reads preserve econ, family and legacy cache")

func run(_tree: SceneTree) -> int:
	legacy_age_lookup()
	for culture in TownEcon.data()["cultures"].keys():
		shares(culture)
		age_cache(culture)
		service_and_broth(culture)
		fresh_food(culture)
		bounded_transfers(culture)
		keeping_recipes(culture)
	print("HOUSEHOLD FOOD v046 checks=", checks, " failures=", fails)
	return fails
