extends RefCounted

var fails := 0
var checks := 0
var claims = null

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: fails += 1; printerr("FAIL: ", message)

func fixture(culture: String, purse: float, claim: float, grain: int, fruit: int) -> Array:
	var f := Families._blank(1)
	f["m"] = 1; f["homes"] = 1; f["land"] = {"grain": 8}; f["hv"] = claim; f["purse"] = purse
	var estate := Families._blank(0); estate["estate"] = true
	var e := {"culture": culture, "day": 190.0, "fams": [estate, f], "stock": {"grain": 100, "fruit": 100}, "barn": {"grain": grain, "fruit": fruit}, "hh": {}, "price": {"grain": 3.6, "fruit": 4.2}, "stats": {"sales": 0.0}, "req": {}, "biz": [{"till": 0.0}], "mkt": 0, "land": {"grain": 8}, "herd": {}, "farm_till": 0.0, "cum": {}, "treasury": 0.0}
	# These retained v030 cases model saved food entitlements. Migration backs
	# them only with the actual old barn; new production is tested separately.
	if claims != null: claims.ensure(e)
	return [e, f]

func retained_food(culture: String, purse: float) -> void:
	var rows := fixture(culture, purse, 30.0, 30, 0)
	var e: Dictionary = rows[0]; var f: Dictionary = rows[1]
	EconomyRules.cover_food(e, f, 7.0, 190.0)
	check(float(f["store"]["food"]) >= 7.0, culture + ": own harvest covers food even without coins")
	check(float(f["purse"]) == purse and float(e["stats"]["sales"]) == 0.0, culture + ": keeping one's own harvest costs no coins")
	check(float(f["hv"]) == 16.0 and int(e["barn"]["grain"]) == 16 and int(e["hh"].get("grain", 0)) == 14, culture + ": entitlement and physical stock transfer once")
	check(int(e["stock"]["grain"]) == 100 and float(e["biz"][0]["till"]) == 0.0 and float(e["farm_till"]) == 0.0, culture + ": retention makes no market payment or new land proceeds")
	EconomyRules.cover_food(e, f, 7.0, 190.0)
	check(float(f["hv"]) == 16.0 and int(e["barn"]["grain"]) == 16, culture + ": covered food is not claimed again")

func partial_claim(culture: String) -> void:
	var rows := fixture(culture, 100.0, 5.0, 30, 0)
	var e: Dictionary = rows[0]; var f: Dictionary = rows[1]
	EconomyRules.cover_food(e, f, 7.0, 190.0)
	var unit := 3.6 * TownEcon.markup()
	check(float(f["hv"]) == 0.0 and int(e["barn"]["grain"]) == 25, culture + ": partial entitlement is used before paid food")
	check(absf(float(f["purse"]) - (100.0 - 9.0 * unit)) < 0.00001, culture + ": only the uncovered nine meals are bought")
	check(int(e["hh"].get("grain", 0)) == 14 and int(e["stock"]["grain"]) == 91, culture + ": partial retention and purchase conserve goods")

func unavailable_claim(culture: String) -> void:
	var rows := fixture(culture, 100.0, 30.0, 0, 0)
	var e: Dictionary = rows[0]; var f: Dictionary = rows[1]
	EconomyRules.cover_food(e, f, 7.0, 190.0)
	check(float(f["hv"]) == (0.0 if claims != null else 30.0) and int(e["hh"].get("grain", 0)) == 14, culture + ": unavailable retained crop cannot become physical food; real food is bought")
	if claims != null: check(float(f.get("legacy_hv", 0)) == 30.0, culture + ": unavailable saved food metadata is preserved")
	check(int(e["stock"]["grain"]) == 86, culture + ": an entitlement cannot invent absent harvest goods")

func claim_bounds(culture: String) -> void:
	var rows := fixture(culture, 0.0, 14.75, 5, 30)
	var e: Dictionary = rows[0]; var f: Dictionary = rows[1]
	f["herd"] = {"sheep": 3}
	EconomyRules.cover_food(e, f, 7.0, 190.0)
	check(float(f["hv"]) == 0.75 and int(e["barn"]["grain"]) == 0 and int(e["barn"]["fruit"]) == 21, culture + ": both retained crops cover the gap while fractional entitlement stays")
	check(int(e["hh"].get("grain", 0)) == 5 and int(e["hh"].get("fruit", 0)) == 9 and float(f["store"]["food"]) == 7.0, culture + ": mixed retention transfers precisely fourteen real meals")
	check(f["herd"] == {"sheep": 3} and float(f["purse"]) == 0.0, culture + ": existing own food preserves herd and coin")
	rows = fixture(culture, 0.0, 30.0, 3, 2); e = rows[0]; f = rows[1]
	EconomyRules.cover_food(e, f, 7.0, 190.0)
	check(float(f["hv"]) == (0.0 if claims != null else 25.0) and float(f["store"]["food"]) == 2.5, culture + ": short barns transfer only the five meals that exist")
	if claims != null: check(float(f.get("legacy_hv", 0)) == 30.0, culture + ": short barn preserves prior entitlement as metadata without inventing goods")
	check(int(e["barn"]["grain"]) == 0 and int(e["barn"]["fruit"]) == 0 and int(e["hh"].get("grain", 0)) + int(e["hh"].get("fruit", 0)) == 5, culture + ": short barns conserve the whole food total")
	rows = fixture(culture, 0.0, 0.75, 30, 0); e = rows[0]; f = rows[1]
	EconomyRules.cover_food(e, f, 7.0, 190.0)
	check(float(f["hv"]) == 0.75 and int(e["barn"]["grain"]) == 30 and float(f["store"]["food"]) == 0.0, culture + ": submeal claim cannot become an invented whole meal")
	rows = fixture(culture, 0.0, 30.0, 30, 0); e = rows[0]; f = rows[1]
	f["land"] = {}
	EconomyRules.cover_food(e, f, 7.0, 190.0)
	if claims != null:
		check(float(f["hv"]) == 16.0 and int(e["barn"]["grain"]) == 16, culture + ": former landholder keeps its actual already-owned stored harvest")
	else:
		check(float(f["hv"]) == 30.0 and int(e["barn"]["grain"]) == 30, culture + ": legacy acres gate denies landless paper entitlement")
	rows = fixture(culture, 0.0, 30.0, 30, 0); e = rows[0]; f = rows[1]
	Families._restock(e, f, 7.0)
	check(float(f["store"]["food"]) == 7.0 and float(f["hv"]) == 16.0 and int(e["barn"]["grain"]) == 16, culture + ": penniless restocking still keeps already owed crop")
	rows = fixture(culture, 0.0, 0.0, 30, 0); e = rows[0]; f = rows[1]
	f["worked"] = 1.0; e["climate"] = "temperate"
	var cap := Families.people(f) * Families.K_FOOD * EconGen.YEAR_DAYS
	if claims != null:
		claims.add(e, "grain", int(ceil(cap + 10.0)), {"f:1": 1.0}, 70, "harvest")
		claims.reserve_food(e, f)
		check(float(f["hv"]) == cap, culture + ": annual retention ceiling protects only actual owned physical harvest")
	else:
		f["hv"] = cap - 1.0
		Families._harvest_share(e, f, 70.0, 7.0)
		check(float(f["hv"]) == cap, culture + ": existing annual harvest retention ceiling is unchanged")

func run(_tree: SceneTree) -> int:
	if FileAccess.file_exists("res://campaign/harvest_claims.gd"): claims = load("res://campaign/harvest_claims.gd")
	for culture in ["middle", "northern", "orc", "goblin", "moon_elf", "dwarf", "steppe"]:
		retained_food(culture, 0.0)
		retained_food(culture, 100.0)
		partial_claim(culture)
		unavailable_claim(culture)
		claim_bounds(culture)
	children_rate()
	ordinary_family_turn()
	print("FARM RETENTION checks=", checks, " failures=", fails)
	return fails

func children_rate() -> void:
	var rows := fixture("middle", 0.0, 100.0, 100, 0)
	var e: Dictionary = rows[0]; var f: Dictionary = rows[1]
	f["kids"] = 2; f["frate"] = 2.2
	EconomyRules.cover_food(e, f, 7.0, 190.0)
	check(int(e["hh"].get("grain", 0)) == 31 and absf(float(f["store"]["food"]) - 31.0 / 4.4) < 0.00001, "retention uses current child meal factors for store days")
	f["store"]["food"] = 0.0; f["frate"] = 3.0
	var prior := int(e["hh"].get("grain", 0))
	Families._restock(e, f, 7.0)
	check(absf(float(f["frate"]) - 2.2) < 0.00001 and int(e["hh"].get("grain", 0)) - prior == 31, "restocking refreshes child meal factors before free retention")

func ordinary_family_turn() -> void:
	WorldGen.gen_size = "normal"
	Game.new_game(2026)
	var town: Dictionary = {}; var f: Dictionary = {}
	for candidate in Game.world["towns"].values():
		if not TownEcon.has_econ(candidate): continue
		for family in candidate["econ"]["fams"]:
			if not family.get("estate", false) and Families.acres(family) > 0 and int(family["kids"]) > 0 and Families.heads(family) > 0:
				town = candidate; f = family; break
		if not town.is_empty(): break
	check(not town.is_empty(), "generated world supplies an actual farm household with children and livestock")
	if town.is_empty(): return
	var e: Dictionary = town["econ"]
	Game.day = 21.0; e["day"] = 21.0; f["last"] = 14.0
	f["frate"] = float(Barge.eaters(e, f, 21.0)[0])
	var rate := float(Families.daily_rates(e, f)["food"])
	f["store"]["food"] = 0.0; f["store"]["drink"] = 100.0; f["store"]["wood"] = 100.0
	f["purse"] = 0.0; f["hungry"] = 0; f["cond"] = 1.0
	f["tax_season"] = e["tax"]["season"]
	# Control only real goods in this scenario; production never receives these fixture stocks.
	if claims != null:
		claims.add(e, "grain", int(ceil(14.0 * rate)), {"f:%d" % int(f["id"]): 1.0}, 21, "harvest")
	else:
		f["hv"] = ceil(14.0 * rate)
		e["barn"]["grain"] = maxi(int(e["barn"].get("grain", 0)), int(f["hv"]))
	var herd_before: Dictionary = f["herd"].duplicate(true)
	var rng := RandomNumberGenerator.new(); rng.seed = 95471
	Families.turn(Game, town, e, f, 21.0, rng)
	check(float(f.get("food_at_hunger_check", 0)) >= 7.0 and float(f.get("fshort", -1)) == 0.0, "ordinary turn keeps available harvest before its hunger check")
	check(int(f["hungry"]) == 0 and not f.get("gone", false), "ordinary retained-food household stays fed and alive")
	check(f["herd"] == herd_before, "ordinary sufficient own harvest does not slaughter the household's livestock")
