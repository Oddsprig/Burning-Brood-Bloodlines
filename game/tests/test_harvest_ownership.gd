extends RefCounted
## Physical harvest ownership, independent sale/food/conservation assertions.
## Synthetic households and plots never depend on names or particular generated IDs.

var checks := 0
var fails := 0
var claims = null

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: fails += 1; printerr("FAIL: ", message)

func near(a: float, b: float, message: String) -> void:
	check(absf(a - b) < 0.00001, "%s (got %.8f expected %.8f)" % [message, a, b])

func fixture(culture: String = "middle", spec: Array = [[8, 1.0], [8, 0.0]]) -> Dictionary:
	var estate := Families._blank(0); estate["estate"] = true
	var fams: Array = [estate]
	var land := 0; var worked := 0.0
	for s in spec:
		var f := Families._blank(fams.size())
		f["m"] = 1; f["homes"] = 1; f["land"] = {"grain": int(s[0])}
		f["worked"] = float(s[1]); f["store"]["food"] = float(EconGen.YEAR_DAYS) * 2.0
		f["cum"] = {"grain": 0.0, "fruit": 0.0, "flax": 0.0, "herd": 0.0}
		land += int(s[0]); worked += float(s[0]) * float(s[1]); fams.append(f)
	return {"culture": culture, "climate": "temperate", "day": 60.0, "fams": fams,
		"land": {"grain": land}, "herd": {}, "wacres": {"grain": worked}, "wherd": {},
		"barn": {}, "stock": {}, "hh": {}, "carry": {}, "cum": {"grain": 0.0, "fruit": 0.0, "flax": 0.0, "herd": 0.0},
		"farm_till": 0.0, "treasury": 0.0, "granary": 0, "hf_now": 1.0,
		"adults": spec.size(), "pop": spec.size(), "hands": 0, "kids_n": 0,
		"price": {"grain": 4.0, "fruit": 9.0, "flax": 13.0, "fodder": 1.0}, "need": {},
		"biz": [{"id": 0, "type": "market", "till": 100000.0, "spend": 0.0}], "mkt": 0,
		"led": {"made": {}, "used": {}, "spoil": {}}, "stats": {"sales": 0.0}, "req": {}}

func cash(e: Dictionary) -> float:
	var n := float(e["farm_till"]) + float(e["treasury"]) + float(e["biz"][0]["till"])
	for f in e["fams"]: n += float(f["purse"])
	return n

func sell(e: Dictionary, good: String, n: int) -> float:
	e["need"] = {good: float(n + int(e["stock"].get(good, 0))) / 1.2 + 0.01}
	var before := float(e["biz"][0]["till"])
	TownEcon._barn_sales(e, TownEcon.data())
	return before - float(e["biz"][0]["till"])

func settle(e: Dictionary) -> Array:
	var paid := []
	for f in e["fams"]: paid.append(Families.settle(e, f))
	return paid

func produce(e: Dictionary) -> int:
	var before := int(e["barn"].get("grain", 0))
	TownEcon._farms(e, TownEcon.data(), Calendar.season_index(float(e["day"])), TownEcon.data()["climates"]["temperate"])
	return int(e["barn"].get("grain", 0)) - before

func production_sale(culture: String, spec: Array) -> void:
	var e := fixture(culture, spec)
	var total_cash := cash(e)
	var made := produce(e)
	check(made > 0, "ordinary crop production creates a positive physical harvest")
	check(int(e["led"]["made"]["grain"]) == made + int(e["granary"]), "crop output conserves physical barn and grain tax")
	var payment := sell(e, "grain", made)
	var paid := settle(e)
	var weight := 0.0
	for s in spec: weight += float(s[0]) * float(s[1])
	for i in spec.size():
		near(float(paid[i + 1]), payment * float(spec[i][0]) * float(spec[i][1]) / weight, "fresh sale follows actual worked contribution %s family%d" % [culture, i + 1])
	near(cash(e), total_cash, "production and sale conserve coins")
	check(int(e["barn"].get("grain", 0)) == 0 and int(e["stock"].get("grain", 0)) == made, "sale transfers exactly the produced harvest")
	for p in settle(e): near(float(p), 0.0, "repeat settlement cannot pay again")

func rotation_sale() -> void:
	var e := fixture("middle", [[5, 1.0], [5, 1.0], [5, 1.0]])
	# Physical plots exercise ordinary rotation selection: cereal loam, cereal
	# heavy soil, and fallow. Expected yields are explicit source-data values.
	var year := Calendar.year(float(e["day"]))
	e["plots"] = {"x": PackedInt32Array([0, 1, 2]), "y": PackedInt32Array([0, 0, 0]),
		"ac": PackedInt32Array([5, 5, 5]), "own": PackedInt32Array([1, 2, 3]),
		"use": PackedInt32Array([Plots.FIELD, Plots.FIELD, Plots.FIELD]), "sub": PackedInt32Array([0, 0, 0]),
		"crops": ["grain"], "variety": ["", "", ""], "soil": ["loam", "heavy", "loam"],
		"rotation_phase": [posmod(-year, 4), posmod(-year, 4), posmod(3 - year, 4)], "h": [[], [], []]}
	e["crops"] = {"grain": "grain"}
	var made := produce(e)
	check(e["plots"]["variety"] == ["wheat", "oats", "fallow"], "physical soils and rotation create independent 200:180:0 contributions")
	var payment := sell(e, "grain", made)
	var paid := settle(e)
	near(float(paid[1]), payment * 200.0 / 380.0, "rotation-adjusted first owner receives its actual output share")
	near(float(paid[2]), payment * 180.0 / 380.0, "rotation-adjusted second owner receives its actual output share")
	near(float(paid[3]), 0.0, "fallow acres cannot earn a neighbour's crop proceeds")

func dated_staffing() -> void:
	var e := fixture()
	var old := produce(e)
	e["day"] = 61.0
	e["fams"][1]["worked"] = 0.0; e["fams"][2]["worked"] = 1.0
	var fresh := produce(e)
	# A staffing change does not rewrite a stored older contribution.
	var old_payment := sell(e, "grain", old)
	var first := settle(e)
	near(float(first[1]), old_payment, "FIFO stored harvest retains its original producer after staffing changes")
	near(float(first[2]), 0.0, "today's new producer cannot collect yesterday's crop")
	e["price"]["grain"] = 7.0
	var next_payment := sell(e, "grain", fresh)
	var second := settle(e)
	near(float(second[1]), 0.0, "old contributor receives no new producer's later sale")
	near(float(second[2]), next_payment, "later contribution receives its actual later sale quote")

func dated_transfer() -> void:
	var e := fixture()
	var n := produce(e)
	Families.move_land(e, e["fams"][1], e["fams"][2], "grain", 8)
	check(Families.acres(e["fams"][1]) == 0, "transfer fixture makes original producer genuinely landless")
	var payment := sell(e, "grain", n)
	var paid := settle(e)
	near(float(paid[1]), payment, "landless former producer retains actual stored harvest proceeds")
	near(float(paid[2]), 0.0, "land buyer cannot acquire the seller's already harvested goods")

func produced_food_before_broker(culture: String) -> void:
	var e := fixture(culture)
	var f: Dictionary = e["fams"][1]
	f["store"]["food"] = 0.0; f["purse"] = 0.0
	var made := produce(e)
	check(made >= 14, "actual harvest provides enough physical meals for the food-priority fixture")
	var before := cash(e)
	var payment := sell(e, "grain", made)
	EconomyRules.cover_food(e, f, 7.0, 60.0)
	check(float(f["store"]["food"]) >= 7.0, "own produced meals survive funded broker sale before household food check %s" % culture)
	check(int(e["hh"].get("grain", 0)) == 14, "ordinary food path moves fourteen actually owned meals")
	near(payment, 0.0, "subannual-budget crop is retained before broker surplus sale")
	near(cash(e), before, "production food priority conserves coins")

func add(e: Dictionary, good: String, n: int, owners: Dictionary, day: float) -> void:
	claims.add(e, good, n, owners, day, "harvest")

func api_fifo_and_fairness() -> void:
	for reverse in [false, true]:
		var e := fixture()
		claims.ensure(e)
		var owners := {"f:1": 1.0, "f:2": 3.0} if not reverse else {"f:2": 3.0, "f:1": 1.0}
		add(e, "grain", 8, owners, 60.0)
		add(e, "grain", 4, {"f:1": 1.0}, 61.0)
		var total := {"f:1": 0.0, "f:2": 0.0}
		for n in [1, 2, 3, 2]:
			var got: Dictionary = claims.take(e, "grain", n, false)
			check(int(got["n"]) == n, "partial sale takes precisely requested whole units")
			near(float(got["shares"].get("f:1", 0)), float(n) / 4.0, "same-day first contribution receives proportional partial sale")
			near(float(got["shares"].get("f:2", 0)), float(n) * 3.0 / 4.0, "same-day later contribution receives proportional partial sale")
			for owner in total: total[owner] += float(got["shares"].get(owner, 0))
		near(total["f:1"], 2.0, "repeated tiny sales retain first fractional contribution")
		near(total["f:2"], 6.0, "repeated tiny sales retain second fractional contribution")
		var last: Dictionary = claims.take(e, "grain", 4, false)
		near(float(last["shares"].get("f:1", 0)), 4.0, "newer batch enters only after oldest batch is exhausted")
		near(float(last["shares"].get("f:2", 0)), 0.0, "FIFO excludes earlier contributor from later batch")
		check(int(e["barn"]["grain"]) == 0, "partial takes conserve complete physical batch")
	# Separate deliveries during the same day also form one proportional batch.
	for order in [[1, 2], [2, 1]]:
		var e := fixture(); claims.ensure(e)
		for fid in order: add(e, "grain", 2 if fid == 1 else 6, {"f:%d" % fid: 1.0}, 60.0)
		var got: Dictionary = claims.take(e, "grain", 4, false)
		near(float(got["shares"].get("f:1", 0)), 1.0, "same-day separate delivery order cannot favour first producer")
		near(float(got["shares"].get("f:2", 0)), 3.0, "same-day separate delivery order preserves proportional second producer")

func api_fractional_carry() -> void:
	var e := fixture()
	claims.ensure(e)
	# Aggregate 0.6 old-owner + 0.6 new-owner becomes one physical unit.
	claims.harvest(e, "grain", "h_grain", {"f:1": 1.0}, 0.6, 0, 0, 0.0, 60.0)
	check(int(e["barn"].get("grain", 0)) == 0, "subunit harvest cannot mint a whole good")
	claims.harvest(e, "grain", "h_grain", {"f:2": 1.0}, 0.6, 1, 0, 0.6, 61.0)
	check(int(e["barn"].get("grain", 0)) == 1, "combined production floors once across households and dates")
	var got: Dictionary = claims.take(e, "grain", 1, false)
	near(float(got["shares"].get("f:1", 0)), 0.6, "carried fraction retains its original dated contributor")
	near(float(got["shares"].get("f:2", 0)), 0.4, "new producer owns only its portion of the whole good")
	claims.harvest(e, "grain", "h_grain", {"f:2": 1.0}, 0.8, 1, 0, 0.2, 62.0)
	got = claims.take(e, "grain", 1, false)
	near(float(got["shares"].get("f:2", 0)), 1.0, "remaining carry is neither duplicated nor lost")
	check(int(e["barn"]["grain"]) == 0, "fractional ownership consumption conserves two whole units")

func api_multioutput_and_retention(culture: String) -> void:
	var e := fixture(culture)
	claims.ensure(e)
	var f: Dictionary = e["fams"][1]
	f["store"]["food"] = 0.0; f["purse"] = 0.0; f["kids"] = 2; f["frate"] = 2.2
	f["land"] = {"grain": 8, "fruit": 2}
	f["herd"] = {"sheep": 3}
	add(e, "grain", 40, {"f:1": 1.0}, 60.0)
	add(e, "fruit", 30, {"f:2": 1.0}, 60.0)
	add(e, "flax", 10, {"f:1": 1.0}, 60.0)
	var before_cash := cash(e)
	claims.reserve_food(e, f)
	check(claims.available(e, "grain") == 0, "broker cannot sell household's annual-budget owned food")
	check(claims.available(e, "flax") == 10, "nonfood output never enters household food reserve")
	var payment := sell(e, "grain", 40)
	near(payment, 0.0, "funded broker leaves reserved own food physical")
	EconomyRules.cover_food(e, f, 7.0, 60.0)
	check(float(f["store"]["food"]) >= 7.0, "child-adjusted own harvest covers real household meals")
	check(int(e["hh"].get("grain", 0)) == 31 and int(e["barn"]["grain"]) == 9, "retention takes exactly31 owned whole meals")
	check(int(e["barn"]["fruit"]) == 30 and int(e["barn"]["flax"]) == 10, "retention cannot take another family's fruit or consume flax")
	near(cash(e), before_cash, "own retention moves no coins")
	check(f["herd"] == {"sheep": 3}, "sufficient own food prevents avoidable livestock slaughter")
	var own_before := float(claims.owned(e, "f:1", "grain"))
	EconomyRules.cover_food(e, f, 7.0, 60.0)
	near(float(claims.owned(e, "f:1", "grain")), own_before, "repeated covered-food check cannot consume again")
	var flax_payment := sell(e, "flax", 10)
	var paid := settle(e)
	near(float(paid[1]), flax_payment, "nonfood sale pays its true crop owner once")
	near(float(paid[2]), 0.0, "other crop owner receives no unrelated nonfood proceeds")
	near(cash(e), before_cash, "mixed goods sales and retention conserve coins")

func api_loss_and_limits() -> void:
	var e := fixture()
	claims.ensure(e)
	add(e, "fruit", 5, {"f:1": 2.0, "f:2": 3.0}, 60.0)
	var lost: Dictionary = claims.take(e, "fruit", 2, false)
	TownEcon.led(e, "spoil", "fruit", int(lost["n"]))
	var receipt: Dictionary = claims.take(e, "fruit", 10, false)
	check(int(receipt["n"]) == 3 and int(e["barn"]["fruit"]) == 0, "physical loss and overlarge request cannot consume absent goods")
	near(float(receipt["shares"].get("f:1", 0)), 1.2, "loss debits proportional first physical ownership")
	near(float(receipt["shares"].get("f:2", 0)), 1.8, "loss debits proportional second physical ownership")
	var empty: Dictionary = claims.take(e, "fruit", 1, false)
	check(int(empty["n"]) == 0 and empty["shares"].is_empty(), "empty barn yields no invented owner shares")
	near(cash(e), 100000.0, "goods lost or taken without a sale cannot create owner cash")
	e = fixture(); claims.ensure(e)
	add(e, "grain", 20, {"f:1": 1.0}, 60.0)
	e["biz"][0]["till"] = 0.0
	near(sell(e, "grain", 20), 0.0, "insolvent broker cannot purchase or credit output")
	check(int(e["barn"]["grain"]) == 20, "no-cash sale keeps physical harvest")
	e["biz"][0]["till"] = 1000.0; e["need"] = {}
	TownEcon._barn_sales(e, TownEcon.data())
	check(int(e["barn"]["grain"]) == 20, "absent broker demand keeps actual goods")
	for p in settle(e): near(float(p), 0.0, "unsold goods are not imaginary proceeds")
	e = fixture(); claims.ensure(e)
	add(e, "fruit", 100, {"f:1": 1.0, "f:2": 3.0}, 60.0)
	TownEcon._spoil(e, TownEcon.data(), 2, TownEcon.data()["climates"]["temperate"], 3.0)
	var lost_n := int(e["led"]["spoil"].get("fruit", 0))
	var left := int(e["barn"]["fruit"])
	check(lost_n > 0 and left + lost_n == 100, "ordinary spoilage preserves exact physical loss ledger")
	near(float(claims.owned(e, "f:1", "fruit")), float(left) / 4.0, "ordinary barn spoilage debits first physical owner")
	near(float(claims.owned(e, "f:2", "fruit")), float(left) * 3.0 / 4.0, "ordinary barn spoilage debits second physical owner")
	var payment := sell(e, "fruit", left)
	var paid := settle(e)
	near(float(paid[1]), payment / 4.0, "spoiled fruit cannot earn a later sale receipt")
	near(float(paid[2]), payment * 3.0 / 4.0, "remaining actual fruit pays proportionally after loss")
	near(cash(e), 100000.0, "ordinary spoilage and remaining fruit sale conserve coins")

func api_food_budget() -> void:
	var e := fixture(); claims.ensure(e)
	var f: Dictionary = e["fams"][1]
	f["kids"] = 2; f["frate"] = 2.2; f["store"]["food"] = 20.0
	add(e, "grain", 800, {"f:1": 1.0}, 60.0)
	add(e, "fruit", 200, {"f:1": 1.0}, 60.0)
	claims.reserve_food(e, f)
	var budget := (float(EconGen.YEAR_DAYS) - 20.0) * 4.4
	near(float(f["hv"]), budget, "child-adjusted annual reserve subtracts food already in the household larder")
	near(float(claims.owned(e, "f:1", "grain", true)), budget, "annual food budget protects actual grain ownership once")
	near(float(claims.owned(e, "f:1", "fruit", true)), 0.0, "food budget cannot reserve the same meals again in another crop")
	check(claims.available(e, "grain") == 360 and claims.available(e, "fruit") == 200, "only real output above annual food budget becomes surplus")
	f["store"]["food"] = float(EconGen.YEAR_DAYS)
	claims.reserve_food(e, f)
	near(float(f["hv"]), 0.0, "already full-year larder releases the remaining real crop surplus")
	check(claims.available(e, "grain") == 800 and claims.available(e, "fruit") == 200, "release of food reserve preserves physical goods and all ownership")
	e = fixture(); claims.ensure(e); f = e["fams"][1]
	f["store"]["food"] = 0.0; f["purse"] = 0.0
	add(e, "grain", 3, {"f:1": 1.0}, 60.0)
	add(e, "fruit", 50, {"f:2": 1.0}, 60.0)
	EconomyRules.cover_food(e, f, 7.0, 60.0)
	near(float(f["store"]["food"]), 1.5, "short own harvest covers only the actual three owned meals")
	check(int(e["barn"]["grain"]) == 0 and int(e["barn"]["fruit"]) == 50, "hungry family's short harvest cannot authorize taking another owner's crop")
	near(cash(e), 100000.0, "short ownership grants neither free neighbour food nor invented coins")

func generated_food() -> void:
	WorldGen.gen_size = "normal"; Game.new_game(2026)
	var town: Dictionary = {}; var f: Dictionary = {}
	for t in Game.world["towns"].values():
		if not TownEcon.has_econ(t): continue
		for candidate in t["econ"]["fams"]:
			if not candidate.get("estate", false) and not candidate.get("gone", false) and Families.acres(candidate) > 0 and int(candidate["kids"]) > 0 and Families.heads(candidate) > 0:
				town = t; f = candidate; break
		if not town.is_empty(): break
	check(not town.is_empty(), "generated world supplies a generic actual farmer with children and animals")
	if town.is_empty(): return
	var e: Dictionary = town["econ"]
	Game.day = 60.0; e["day"] = 60.0; f["last"] = 53.0
	f["frate"] = float(Barge.eaters(e, f, 60.0)[0])
	var rate := float(Families.daily_rates(e, f)["food"])
	f["store"] = {"food": 0.0, "drink": 1000.0, "wood": 1000.0}
	f["purse"] = 0.0; f["hungry"] = 0; f["cond"] = 1.0; f["tax_season"] = e["tax"]["season"]
	# Add real fixture goods with explicit ownership, never seed a paper hv claim.
	add(e, "grain", int(ceil(rate * 21.0)), {"f:%d" % int(f["id"]): 1.0}, 60.0)
	claims.reserve_food(e, f)
	var own := float(claims.owned(e, "f:%d" % int(f["id"]), "grain", true))
	e["need"]["grain"] = float(e["stock"].get("grain", 0)) + float(e["barn"].get("grain", 0)) * 2.0
	TownEcon._barn_sales(e, TownEcon.data())
	near(float(claims.owned(e, "f:%d" % int(f["id"]), "grain", true)), own, "broker before ordinary household turn preserves actual reserved food ownership")
	check(float(claims.owned(e, "f:%d" % int(f["id"]), "grain")) >= own, "actual unreserved opening surplus may sell while household's food remains backed")
	var herd_before: Dictionary = f["herd"].duplicate(true)
	var rng := RandomNumberGenerator.new(); rng.seed = 95471
	Families.turn(Game, town, e, f, 60.0, rng)
	check(float(f.get("food_at_hunger_check", 0)) >= 7.0 and float(f.get("fshort", -1)) == 0.0, "ordinary generated household has its own meals before hunger check")
	check(int(f["hungry"]) == 0 and not f.get("gone", false), "penniless real producer stays fed and alive")
	check(f["herd"] == herd_before, "ordinary household keeps its animals when sufficient own harvest exists")

func run(_tree: SceneTree) -> int:
	if FileAccess.file_exists("res://campaign/harvest_claims.gd"):
		claims = load("res://campaign/harvest_claims.gd")
	check(claims != null, "dated physical harvest ownership API exists (expected baseline regression)")
	for culture in ["middle", "northern", "orc", "goblin", "moon_elf", "dwarf", "steppe"]:
		for spec in [[[8, 1.0], [8, 0.0]], [[8, 1.0], [8, 0.5]], [[4, 1.0], [12, 0.5]]]:
			production_sale(culture, spec)
		produced_food_before_broker(culture)
	rotation_sale(); dated_staffing(); dated_transfer()
	if claims != null:
		api_fifo_and_fairness(); api_fractional_carry(); api_loss_and_limits(); api_food_budget()
		for culture in ["middle", "northern", "orc", "goblin", "moon_elf", "dwarf", "steppe"]:
			api_multioutput_and_retention(culture)
		generated_food()
	print("HARVEST OWNERSHIP checks=", checks, " failures=", fails)
	return fails
