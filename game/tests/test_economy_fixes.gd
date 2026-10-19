extends RefCounted

var fails := 0
var checks := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		fails += 1
		printerr("FAIL ", message)

func run(_tree: SceneTree) -> int:
	WorldGen.gen_size = "normal"
	for seed_v in [713, 2026, 8801]:
		Game.new_game(seed_v)
		for town in Game.world["towns"].values():
			if not TownEcon.has_econ(town): continue
			var e: Dictionary = town["econ"]
			for f in e["fams"]:
				if f.get("gone", false) or f.get("estate", false) or Families.adults(f) < 2: continue
				var copy: Dictionary = f.duplicate(true)
				copy["purse"] = 100000.0
				copy["store"]["food"] = 30.0
				copy["homes"] = maxi(1, int(copy["homes"]))
				var old_short: Variant = e.get("food_short", 0)
				e["food_short"] = 1.0
				copy["last"] = float(Game.day) - 7
				copy["jobs"] = {}; copy["owns"] = []; copy["keeps"] = []
				# The actual family turn must not import a town-wide shortage into this full larder.
				Families.turn(Game, town, e, copy, float(Game.day), Game.rng)
				check(float(copy.get("fshort", -1)) == 0, "full household larder cannot starve in a hungry town")
				e["food_short"] = old_short
				var p: Array = Persons.pp(f)[0]
				var rich: Dictionary = f.duplicate(true)
				rich["purse"] = 100000.0; rich["store"]["food"] = 30.0
				var offer := {"pay_day": 100, "food_days": 7}
				check(People.outlaw_value(e, rich, p, {}, "bandit", offer) == -INF, "wealthy fed person rejects outlaw service")
				var poor: Dictionary = f.duplicate(true)
				poor["purse"] = 0.0; poor["store"]["food"] = 0.0
				var person: Array = p.duplicate(true); person[4] = ""; person[5] = -1; person[6] = 0
				var gain := People.outlaw_value(e, poor, person, {}, "bandit", offer)
				Persons.remember_unpaid(person, "bandit", 7, float(Game.day))
				check(People.outlaw_value(e, poor, person, {}, "bandit", offer) < gain, "unpaid service changes later personal choice")
				check(People.outlaw_value(e, poor, person, {"keeper": true}, "bandit", offer) == -INF, "working keeper remains at the shop")
				var remembered: Dictionary = {"dp": [p.duplicate(true)]}
				check(RecPages.remembered(e, remembered).is_empty(), "living person is excluded from remembered list")
				break
			var before := Barge.holdings(Game)
			var household: Dictionary = e["fams"][1]
			var save_purse := float(household["purse"])
			household["purse"] += 1000
			before += 1000
			var n := EconomyRules.buy_essential(e, household, "grain", 1, "food", 2)
			check(absf(Barge.holdings(Game) - before) < 0.01, "food purchase conserves coins")
			check(n >= 0 and n <= 1, "food purchase cannot exceed requested amount")
			household["purse"] -= 1000
			var day_w: float = Barge.day_wage(e)
			for b in e["biz"]:
				if b["type"] in ["farm", "estate"]:
					var lo: float = EconomyRules.wage_limit(e, b, 0.0)
					var hi: float = EconomyRules.wage_limit(e, b, 10000.0)
					var cur: float = EconomyRules.wage_limit(e, b, float(b["wage"]))
					check(absf(lo - day_w * 0.6) < 0.01 and absf(hi - day_w * 1.8) < 0.01 and cur >= lo - 0.01 and cur <= hi + 0.01, "farm wage stays within the adult labour band")
				elif EconomyRules.skilled_work(b):
					var table: Dictionary = TownEcon.data()["businesses"][b["type"]]
					var premium: float = maxf(1.15, float(table["wage"]) / float(Barge.B()["labour"]["base"]))
					var slo: float = EconomyRules.wage_limit(e, b, 0.0)
					var shi: float = EconomyRules.wage_limit(e, b, 10000.0)
					var scur: float = EconomyRules.wage_limit(e, b, float(b["wage"]))
					check(absf(slo - day_w * premium) < 0.01 and absf(shi - day_w * premium * 1.8) < 0.01 and scur >= slo - 0.01 and scur <= shi + 0.01, "skilled wage stays within its premium band")
			var probe_fam: Dictionary = Families._blank(0)
			probe_fam["land"] = {"grain": 16}
			var probe_farm: Dictionary = {"id": 0, "type": "farm", "owner": 0, "closed": false, "cap": 4, "workers": 1,
				"wage": day_w, "till": 0.0, "owed": 0.0, "wage_review_day": -7}
			probe_fam["farm"] = 0
			var probe_e: Dictionary = {"culture": e["culture"], "climate": e["climate"], "day": 0, "dwage": day_w,
				"price": e["price"].duplicate(), "fams": [probe_fam], "biz": [probe_farm], "barn": {}}
			Businesses.bid_day(probe_e)
			var raised_w: float = float(probe_farm["wage"])
			check(raised_w > day_w and raised_w <= day_w * 1.8 + 0.01 and absf(float(probe_farm.get("revenue_hand", -1.0)) - EconomyRules.farm_hand_value(probe_e, probe_fam)) < 0.01, "short-staffed farm raises its offer within the band and records hand value")
			check(Businesses.takeable(probe_farm, probe_e) == 0, "affordability limits farm hiring rather than capping wage")
			probe_farm["workers"] = 5; probe_farm["cap"] = 4; probe_e["day"] = 7
			Businesses.bid_day(probe_e)
			check(float(probe_farm["wage"]) < raised_w and float(probe_farm["wage"]) >= day_w * 0.6 - 0.01, "overstaffed ordinary business lowers its wage offer within the band")
			var grain_before := int(e["stock"].get("grain", 0))
			var price_before := float(e["price"]["grain"])
			e["stock"]["grain"] = int(float(e["need"].get("grain", 1)) * 10) + 100
			EconomyRules.clear_surplus(e, "grain")
			check(float(e["price"]["grain"]) <= price_before, "surplus lowers price")
			e["stock"]["grain"] = grain_before; e["price"]["grain"] = price_before
			var P: Dictionary = e.get("plots", {})
			var stands: Variant = P.get("st", []).duplicate()
			for i in Plots.count(P):
				if int(P["use"][i]) == Plots.WOOD: P["st"][i] = 0
			check(EconomyRules.wood_available(e) == 0, "exhausted woods produce no timber")
			P["st"] = stands
	print("Economy fixes: %d checks across all generated towns and three seeds" % checks)
	return fails
