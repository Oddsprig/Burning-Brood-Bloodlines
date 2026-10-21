extends RefCounted
## Town land market (v0.044): SELL pass queues payroll sellers during the day and settles
## once in batch to town stock paid from e.land_fund; BUY pass sells town stock in batch to
## eligible and interested buyers (skipping rich households with no land need); coins, acres,
## plot ownership and save/load of e.land_fund balance exactly.

var fails := 0
var checks := 0

func check(ok: bool, msg: String) -> void:
	checks += 1
	if not ok:
		fails += 1
		printerr("FAIL: ", msg)

func run(_tree: SceneTree) -> int:
	Game.SAVE_PATH = "user://test_save_land_mkt_%d.json" % OS.get_process_id()
	Game.new_game(713)
	var w: Dictionary = Game.world
	var town: Dictionary = {}
	for tid in w["towns"]:
		var t: Dictionary = w["towns"][tid]
		if TownEcon.has_econ(t) and int(t["econ"]["land"].get("grain", 0)) >= 16:
			town = t
			break
	check(not town.is_empty(), "found a town with grain land")
	if town.is_empty():
		return fails
	var e: Dictionary = town["econ"]
	var est: Dictionary = e["fams"][0]
	var seller: Dictionary = {}
	var buyer: Dictionary = {}
	var rich_no_need: Dictionary = {}
	for f in e["fams"]:
		if f.get("gone", false) or f.get("estate", false) or Population.is_cohort(f):
			continue
		if seller.is_empty() and int(f["land"].get("grain", 0)) >= 8 and not Businesses.farm_of(e, f).is_empty():
			seller = f
		elif buyer.is_empty() and Families.adults(f) - (f.get("keeps", []) as Array).size() >= 2:
			buyer = f
		elif rich_no_need.is_empty() and Families.adults(f) >= 1 and f != seller and f != buyer:
			rich_no_need = f
	if buyer.is_empty():
		for f in e["fams"]:
			if f.get("gone", false) or f.get("estate", false) or Population.is_cohort(f) or f == seller:
				continue
			if Families.adults(f) >= 2:
				buyer = f
				break
	if rich_no_need.is_empty():
		for f in e["fams"]:
			if f.get("gone", false) or f.get("estate", false) or Population.is_cohort(f) or f == seller or f == buyer:
				continue
			rich_no_need = f
			break
	check(not seller.is_empty() and not buyer.is_empty() and not rich_no_need.is_empty(), "selected seller, buyer and rich family")
	if seller.is_empty() or buyer.is_empty() or rich_no_need.is_empty():
		return fails

	# Prepare buyer: free adults, no land/herds/jobs/debt -> needs land.
	for crop in buyer["land"].keys():
		Families.move_land(e, buyer, seller, String(crop), int(buyer["land"][crop]))
	for anim in buyer["herd"].keys():
		Families.move_herd(e, buyer, seller, String(anim), int(buyer["herd"][anim]))
	for h in Herds.of_family(e, int(buyer["id"])):
		for age in ["y", "g", "o"]:
			var cnt := int(h.get(age, 0))
			if cnt > 0:
				var dst := Herds.herd_for(e, int(seller["id"]), String(h["k"]), float(e["day"]))
				Herds._transfer(e, h, dst, age, cnt, "test", "test", "", "", float(e["day"]))
	buyer["ox"] = 0
	buyer["serve"] = {}
	buyer["debt"] = 0.0
	Families.reassign(e, buyer)
	for k in buyer["jobs"].keys():
		Families.set_job(e, buyer, int(k), 0)
	Shelter.release_casual(e, buyer)
	buyer["hands"] = 0
	buyer["idle"] = Families.adults(buyer) - (buyer.get("keeps", []) as Array).size()

	# Prepare rich_no_need: 500+ coins, but all adults away/occupied so _property_hands == 0 (no land need).
	for crop in rich_no_need["land"].keys():
		Families.move_land(e, rich_no_need, seller, String(crop), int(rich_no_need["land"][crop]))
	for anim in rich_no_need["herd"].keys():
		Families.move_herd(e, rich_no_need, seller, String(anim), int(rich_no_need["herd"][anim]))
	rich_no_need["serve"] = {"militia": Families.adults(rich_no_need)}
	rich_no_need["kids"] = 0
	rich_no_need["old"] = 0
	rich_no_need["debt"] = 0.0

	# Move existing coins from other families to treasury, then fund rich_no_need and buyer.
	for f in e["fams"]:
		if f.get("estate", false): continue
		e["treasury"] = float(e["treasury"]) + float(f["purse"])
		f["purse"] = 0.0
	var unit := Loans.crop_acre_price(e, "grain")
	var keep := 40.0 * TownEcon.COIN
	var rich_coin := 500.0 * TownEcon.COIN
	var buyer_coin := keep + unit * 6.0
	e["treasury"] = float(e["treasury"]) - (rich_coin + buyer_coin)
	rich_no_need["purse"] = rich_coin
	buyer["purse"] = buyer_coin

	# Ensure estate starts with 0 grain land so any estate grain comes from seller.
	if int(est["land"].get("grain", 0)) > 0:
		Families.move_land(e, est, seller, "grain", int(est["land"]["grain"]))
	e["land_market"] = {}
	e["land_sell_q"] = []

	# Seller's farm needs wage money for 2 acres beyond any kind value.
	var farm: Dictionary = Businesses.farm_of(e, seller)
	farm["till"] = 0.0
	farm["workers"] = 0
	farm["cap"] = 0
	farm["owed"] = Businesses.farm_kind_value(e, farm) + unit * 1.5
	farm["payroll_sale_day"] = int(e["day"]) - 7

	var gold0 := TownEcon.town_gold(e)
	var holdings0 := Barge.holdings(Game)
	var land0 := TownEcon.land_total(e)
	var seller_ac0 := int(seller["land"]["grain"])
	var seller_plot0 := Plots.acres_of(e, int(seller["id"]))
	var buyer_ac0 := int(buyer["land"].get("grain", 0))
	var buyer_plot0 := Plots.acres_of(e, int(buyer["id"]))
	var est_plot0 := Plots.acres_of(e, 0)

	# 1. Queue seller during the day; verify it is queued and not yet settled.
	Loans.sell_for_payroll(e, seller, farm)
	check((e["land_sell_q"] as Array).has(int(seller["id"])), "seller queued in land_sell_q")
	check(int(seller["land"]["grain"]) == seller_ac0, "no acres moved before SELL pass settles")

	# 2. SELL pass: seller sells to the town; town pays from land_fund and holds land as town stock.
	var sold_n := Loans.settle_land_sales(e)
	check(sold_n == 2, "seller sold 2 acres to the town in SELL pass (got %d)" % sold_n)
	check((e["land_sell_q"] as Array).is_empty(), "land_sell_q cleared after SELL pass")
	check(int(seller["land"].get("grain", 0)) == seller_ac0 - sold_n, "seller grain acres decreased by sold_n")
	check(int(est["land"].get("grain", 0)) == sold_n and int(e["land_market"].get("grain", 0)) == sold_n, "town holds sold acres in town stock")
	check(Plots.acres_of(e, int(seller["id"])) == seller_plot0 - sold_n and Plots.acres_of(e, 0) == est_plot0 + sold_n, "plot ownership moved from seller to town")
	check(float(farm["till"]) > 0.0, "seller farm payroll reserve funded from town land sale")
	check(absf(TownEcon.town_gold(e) - gold0) < 0.01 and absf(Barge.holdings(Game) - holdings0) < 0.01, "coins conserved after SELL pass")
	check(TownEcon.land_total(e) == land0, "acres conserved after SELL pass")

	# 3. BUY pass (same day): rich family with no need skips checking; eligible buyer buys from town stock.
	var fund_before_buy := float(e["land_fund"])
	check(not Loans.is_interested_buyer(e, rich_no_need, unit), "rich family with 500 coins but no need is not interested")
	check(Loans.is_interested_buyer(e, buyer, unit), "eligible land-poor family with spare hands is interested")
	var bought_n := Loans.settle_land_buys(e)
	check(bought_n == sold_n, "eligible buyer bought the town stock on the same day (got %d)" % bought_n)
	check(not Loans.last_buyers_checked.has(int(rich_no_need["id"])), "rich family with no need did not check town stock")
	check(Loans.last_buyers_checked.has(int(buyer["id"])), "eligible buyer checked town stock")
	check(int(buyer["land"].get("grain", 0)) == buyer_ac0 + bought_n, "buyer acres increased by bought_n")
	check(int(est["land"].get("grain", 0)) == 0 and not (e["land_market"] as Dictionary).has("grain"), "town stock cleared after BUY pass")
	check(Plots.acres_of(e, int(buyer["id"])) == buyer_plot0 + bought_n and Plots.acres_of(e, 0) == est_plot0, "plot ownership moved from town to buyer")
	check(absf(float(e["land_fund"]) - (fund_before_buy + float(bought_n) * unit)) < 0.01, "buyer payment replenished town land_fund")
	check(absf(TownEcon.town_gold(e) - gold0) < 0.01 and absf(Barge.holdings(Game) - holdings0) < 0.01, "coins conserved after BUY pass")
	var split := TownEcon.land_split(e)
	check(TownEcon.land_total(e) == land0 and int(split["families"]) + int(split["estate"]) + int(split["common"]) == int(split["territory"]), "land split and totals balance after BUY pass")

	# 4. Save and load preserves e.land_fund.
	var saved_fund := float(e["land_fund"])
	var tid_s := String(town["id"])
	Game.save_game()
	Game.load_game()
	var loaded_e: Dictionary = Game.world["towns"][tid_s]["econ"]
	check(loaded_e.has("land_fund") and absf(float(loaded_e["land_fund"]) - saved_fund) < 0.01, "town land_fund saved and loaded with the game")
	if FileAccess.file_exists(Game.SAVE_PATH):
		Game.wait_save()

	print("Land market v0.044: %d checks, %d failures" % [checks, fails])
	return fails
