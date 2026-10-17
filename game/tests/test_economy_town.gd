extends RefCounted
var fails := 0
var checks := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: fails += 1; printerr("FAIL ", message)
func run(_tree: SceneTree) -> int:
	WorldGen.gen_size = "normal"
	for seed_v in [713, 2026, 8801]:
		Game.new_game(seed_v)
		for town in Game.world["towns"].values():
			if not TownEcon.has_econ(town): continue
			var e: Dictionary = town["econ"]
			var s := TownSanitation.book(e)
			s["filth_kg"] = 100.0; s["urine_litres"] = 0.0
			s["paid_days"] = {}; s["rotting_kg"] = 0.0; s["trade_kg"] = 0.0
			var grain := TownSanitation.reachable_meals(e)
			var coins := Barge.holdings(Game)
			TownSanitation.weekly(e, 14)
			check(absf(float(s["filth_kg"]) - (100 + float(s["incoming_kg"]) - float(s["swept_kg"]) - float(s["decayed_kg"]))) < 0.01, "weekly solid waste mass balances")
			check(absf(Barge.holdings(Game) - coins) < 0.01, "dung sale conserves coins")
			check(int(s["rats"]) <= int(s["food_capacity"]), "rats cannot exceed their reachable weekly food")
			check(absf(float(grain - TownSanitation.reachable_meals(e)) * float(Herds.A()["kg_per_meal"]) - float(s["grain_eaten_kg"])) < 0.01, "rats consume the recorded quantity from real grain")
			var unpaid_filth := float(s["filth_kg"])
			s["paid_days"] = {"street_sweeper": 7.0, "night_soil_man": 7.0, "rat_catcher": 7.0}
			TownSanitation.weekly(e, 21)
			check(float(s["swept_kg"]) > 0 and int(s["caught"]) >= 0, "paid cleaners remove physical waste and catch rats")
			check(absf(float(s["filth_kg"]) - (unpaid_filth + float(s["incoming_kg"]) - float(s["swept_kg"]) - float(s["decayed_kg"]))) < 0.01, "paid cleanup preserves mass balance")
			var f: Dictionary = e["fams"][1]
			for bid in f["jobs"].keys(): Families.set_job(e, f, int(bid), 0)
			f["hands"] = 0; f["keeps"] = []
			f["cj"] = {"night_soil_man": 1}
			for d in 7: Shelter.accrue_sanitation(e, d)
			coins = Barge.holdings(Game)
			Shelter.pay_casual(e, f, 7)
			check(absf(Barge.holdings(Game) - coins) < 0.01, "customer-funded night-soil wages conserve coins")
			check(TownSanitation.paid_days(e, "night_soil_man") > 0, "registered night-soil worker earns pay for actual attendance")
			f.erase("cj")
			var candidates: Array = e["fams"].filter(func(h): return not h.get("gone", false) and not h.get("estate", false))
			if candidates.size() < 2: continue
			var tenant: Dictionary = candidates[0]
			var lord: Dictionary = candidates[1]
			tenant["homes"] = 0; tenant["purse"] = 5000.0
			lord["purse"] = 1000000.0
			e["stock"]["home"] = 2
			coins = Barge.holdings(Game)
			TownHousing.weekly(e, 28)
			check(not TownHousing.rows(e).is_empty(), "funded real building order creates lodging houses")
			check(absf(Barge.holdings(Game) - coins) < 0.01, "lodging construction and land purchase conserve coins")
			check(tenant.has("lodging"), "homeless household can rent available rooms")
			if not tenant.has("lodging"): continue
			var h: Dictionary = TownHousing.rows(e)[int(tenant["lodging"])]
			check(int(e["plots"]["ac"][int(h["plot"])]) == 5 and int(h["rooms"]) == 30 and int(h["buildings"]) == 2, "two houses and thirty rooms occupy five acres")
			check(TownHousing.free_rooms(e, h) >= 0, "tenants never overfill a lodging house")
			coins = Barge.holdings(Game)
			Families._pay_rent(e, tenant, 7, 35)
			check(absf(Barge.holdings(Game) - coins) < 0.01, "rent transfers to the landlord without minting money")
			var free_before := TownHousing.free_rooms(e, h)
			TownHousing.leave(e, tenant, 42)
			check(TownHousing.free_rooms(e, h) > free_before and int(tenant["homes"]) == 0, "departure frees the rented rooms")
	print("Town economy: %d checks, %d failures" % [checks, fails])
	return fails
