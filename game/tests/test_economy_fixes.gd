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
			for b in e["biz"]:
				if b["type"] in ["farm", "estate"]:
					var wage := EconomyRules.wage_limit(e, b, 10000)
					check(wage <= float(b["revenue_hand"]) + 0.01, "farm wage cannot exceed revenue per hand")
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
