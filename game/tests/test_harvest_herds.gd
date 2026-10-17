extends RefCounted

var fails := 0
var checks := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		fails += 1
		printerr("FAIL: ", message)

func fixture() -> Dictionary:
	var fams := []
	for id in 4:
		var f := Families._blank(id)
		f["m"] = 1; f["homes"] = 1; f["worked"] = 1.0; f["purse"] = 0.0
		if id == 0: f["estate"] = true
		fams.append(f)
	var e := {"day": 190, "culture": "middle", "climate": "temperate", "fams": fams, "barn": {}, "stock": {}, "hh": {}, "carry": {}, "req": {}, "price": {"fodder": 2.0, "hides": 2.0, "grain": 3.6, "wool": 2.0, "feathers": 2.0}, "need": {}, "land": {}, "herd": {}, "cum": {}, "treasury": 0.0, "farm_till": 0.0, "stats": {"sales": 0.0}, "biz": [{"till": 0.0, "spend": 0.0}], "mkt": 0, "led": {"made": {}, "used": {}, "spoil": {}}}
	HarvestClaims.ensure(e)
	return e

func herd(fid: int) -> Dictionary:
	return {"ow": "f", "oi": fid, "k": "cattle", "g": 10, "y": 0, "o": 0, "fod": 0.0}

func leftovers() -> void:
	var e := fixture()
	Herds._sell(e, herd(2), {"hides": 5}, 0.75)
	check(int(e["barn"].get("hides", 0)) == 5 and HarvestClaims.owned(e, "f:2", "hides") == 5.0, "unsold carcass goods retain the actual producer")
	check(float(e["farm_till"]) == 0.0 and float(e["fams"][2]["purse"]) == 0.0, "unsold goods have no fabricated receipts")
	e["need"]["hides"] = 10; e["biz"][0]["till"] = 6.0
	Herds._sell(e, herd(1), {"hides": 7}, 0.75)
	check(int(e["stock"].get("hides", 0)) == 4 and int(e["barn"]["hides"]) == 8, "immediate herd sale preserves whole output and market cash limit")
	check(float(e["fams"][1]["purse"]) == 6.0 and float(e["biz"][0]["till"]) == 0.0 and HarvestClaims.owned(e, "f:1", "hides") == 3.0, "prepaid sold goods and unsold ownership cannot be paid twice")

func fodder_ownership() -> void:
	var e := fixture()
	HarvestClaims.add(e, "fodder", 8, {"f:2": 1.0}, 188, "straw")
	e["fams"][1]["land"] = {"grain": 999}
	check(Herds.straw_left(e, herd(1)) == 0.0 and Herds.straw_left(e, herd(2)) == 8.0, "current acreage cannot claim another producer's dated straw")
	check(Herds._buy_fodder(e, herd(2), 3, false) == 3.0 and int(e["barn"]["fodder"]) == 5 and HarvestClaims.owned(e, "f:2", "fodder") == 5.0, "landless prior producer consumes its real fodder without payment")
	e["fams"][1]["purse"] = 100.0
	var before := float(e["fams"][1]["purse"])
	check(Herds._buy_fodder(e, herd(1), 2, false) == 2.0, "paid fodder consumption removes actual barn units")
	var paid := before - float(e["fams"][1]["purse"])
	check(HarvestClaims.owned(e, "f:2", "fodder") == 3.0 and absf(float(e["farm_till"]) - paid) < 0.000001, "paid feed credits only consumed goods and conserves coins")

func loans() -> void:
	var e := fixture()
	HarvestClaims.add(e, "fodder", 10, {"f:2": 4.0, "f:3": 6.0}, 187, "straw")
	check(Herds._buy_fodder(e, herd(1), 3, true) == 3.0, "unfunded herd borrows physical lender goods")
	var hd := Herds.H(e)
	var claims: Dictionary = hd["floan_claims"]["1"]
	var repayment := float(Herds.A()["fodder_loan"]["repay"])
	check(absf(float(hd["floan"]["1"]) - 3.0 * repayment) < 0.000001 and absf(Herds._fodder_claim_total(claims) - 3.0 * repayment) < 0.000001, "forward loan retains actual lenders at the unchanged repayment rate")
	check(claims.has("f:2") and claims.has("f:3") and not claims.has("f:1"), "borrowing retains the consumed producer shares")
	check(int(e["barn"]["fodder"]) == 7 and float(e["farm_till"]) == 0.0, "loan consumption cannot produce a sale receipt")
	HarvestClaims.add(e, "fodder", 5, {"f:1": 1.0}, 191, "straw")
	e["fams"][1]["purse"] = float(Herds.A()["buy_reserve"]) + 100.0
	var goods_before := int(e["barn"]["fodder"])
	var coin_before := float(e["fams"][1]["purse"])
	Herds._repay_loans(e)
	check(not hd["floan"].has("1") and not hd["floan_claims"].has("1"), "known loan clears through real owned straw then real cash")
	check(int(e["barn"]["fodder"]) == goods_before and HarvestClaims.owned(e, "f:1", "fodder") == 1.0, "in-kind repayment reassigns existing goods without consuming or creating them")
	check(absf(float(e["farm_till"]) - (coin_before - float(e["fams"][1]["purse"]))) < 0.000001, "cash loan repayment stays backed by the debtor's actual purse")

func legacy_loan() -> void:
	var e := fixture()
	HarvestClaims.add(e, "fodder", 6, {"f:1": 1.0}, 190, "straw")
	Herds.H(e)["floan"] = {"1": 4.0}
	Herds._repay_loans(e)
	check(int(e["barn"]["fodder"]) == 6 and HarvestClaims.owned(e, "f:1", "fodder") == 2.0 and HarvestClaims.owned(e, "?", "fodder") == 4.0, "old unknown lenders get no invented identities during in-kind repayment")
	check(Herds.H(e)["floan_claims"].is_empty() and float(e["farm_till"]) == 0.0, "legacy in-kind settlement fabricates neither creditors nor coins")
	var cash_e := fixture()
	cash_e["fams"][1]["purse"] = float(Herds.A()["buy_reserve"]) + 8.0
	cash_e["land"] = {"grain": 1000}
	Herds.H(cash_e)["floan"] = {"1": 4.0}
	Herds._repay_loans(cash_e)
	check(float(cash_e["farm_till"]) == 8.0 and float(cash_e["harvest_book"]["unattributed_cash"]) == 8.0, "old cash repayments preserve real money for unknowable lenders")
	check(cash_e["cum"].is_empty() and cash_e["harvest_book"]["cash"].is_empty() and cash_e["barn"].is_empty(), "old cash repayment cannot invent current-acre creditors or consume another physical batch")

func fractional_self_loan() -> void:
	var e := fixture()
	HarvestClaims.add(e, "fodder", 10, {"f:1": 0.5, "f:2": 9.5}, 187, "straw")
	check(Herds._buy_fodder(e, herd(1), 3, true) == 3.0, "joint ownership can supply a whole feed batch")
	var claims: Dictionary = Herds.H(e)["floan_claims"]["1"]
	check(not claims.has("f:1") and absf(Herds._fodder_claim_total(claims) - snappedf(2.85 * 1.5, 0.01)) < 0.000001, "borrower's own fractional feed never earns an external loan or interest")
	check(absf(float(Herds.H(e)["floan"]["1"]) - snappedf(2.85 * 1.5, 0.01)) < 0.000001 and int(e["barn"]["fodder"]) == 7, "self-owned fraction exemption preserves real feed and existing debt rounding")

func legacy_fowl() -> void:
	var e := fixture()
	e["wacres"] = {"grain": 250.0}
	e["fams"][2]["land"] = {"grain": 250}
	BowsEcon._fowl(e)
	check(int(e["barn"].get("feathers", 0)) == 1 and HarvestClaims.owned(e, "f:2", "feathers") == 1.0, "legacy barnyard feathers retain their producing worked acres")
	Herds.H(e)
	BowsEcon._fowl(e)
	check(int(e["barn"]["feathers"]) == 1, "recorded live poultry cannot duplicate legacy fowl production")

func straw_production() -> void:
	var e := fixture()
	e["fams"][1]["worked"] = 0.5
	e["fams"][3]["worked"] = 0.25
	# Use complete physical plots so every derived rotation/work index can be
	# rebuilt. The original fixture supplied only a cached yield dictionary.
	var year := Calendar.year(float(e["day"]))
	e["crops"] = {"grain": "mixed crops"}
	e["plots"] = {"x": PackedInt32Array([0, 1, 2]), "y": PackedInt32Array([0, 0, 0]),
		"ac": PackedInt32Array([10, 20, 6]), "use": PackedInt32Array([Plots.FIELD, Plots.FIELD, Plots.FIELD]),
		"own": PackedInt32Array([1, 2, 3]), "sub": PackedInt32Array([0, 0, 0]), "crops": ["grain"],
		"variety": ["", "", ""], "soil": ["loam", "loam", "light"],
		"rotation_phase": [posmod(-year, 4), posmod(1 - year, 4), posmod(-year, 4)], "h": [[], [], []]}
	for id in [1, 2, 3]: e["fams"][id]["land"] = {"grain": [10, 20, 6][id - 1]}
	var per := float(Herds.A()["straw_acre"])
	Herds.straw(e, 13.0 / per)
	check(int(e["barn"].get("fodder", 0)) == 13 and int(e["led"]["made"].get("fodder", 0)) == 13, "dated straw preserves exact existing pooled production")
	check(absf(HarvestClaims.owned(e, "f:1", "fodder") - 10.0) < 0.000001 and absf(HarvestClaims.owned(e, "f:3", "fodder") - 3.0) < 0.000001, "straw contribution follows cereal acreage and actual worked share")
	check(HarvestClaims.owned(e, "f:2", "fodder") == 0.0, "legume acreage cannot earn cereal straw")

func weekly_products() -> void:
	var e := fixture()
	var sheep := herd(3)
	sheep["k"] = "sheep"; sheep["g"] = 90; sheep["lac"] = 0.0
	Herds.H(e)["h"] = {"1": sheep}
	Herds._products(e, 1, 190.0)
	var wool := int(floor(90.0 * float(Herds.kind("sheep")["wool"]) * 7.0 / Calendar.DAYS_PER_SEASON))
	check(int(e["barn"].get("wool", 0)) == wool and HarvestClaims.owned(e, "f:3", "wool") == float(wool), "unsold weekly herd products retain their owner's physical output")
	check(Herds.H(e)["dd"].is_empty() and float(e["farm_till"]) == 0.0, "unsold weekly products receive no prepaid market delivery or cash")

func run(_tree: SceneTree) -> int:
	leftovers()
	fodder_ownership()
	loans()
	legacy_loan()
	fractional_self_loan()
	legacy_fowl()
	straw_production()
	weekly_products()
	print("Harvest herd checks: ", checks)
	return fails
