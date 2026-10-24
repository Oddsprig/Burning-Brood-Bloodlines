extends RefCounted
## --test=res://tests/test_horses_v056.gd --watchdog=60
## One DevTools Normal/one-day fixture, direct due dates, two bodies; no long presim.
var checks := 0
var fails := 0
var fixture: Dictionary

func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		fails += 1
		printerr("FAIL horses v056: " + text)

func coins() -> float:
	var n := float(Game.gold)
	for town: Dictionary in Game.world["towns"].values():
		var e: Dictionary = town["econ"]
		n += float(e.get("treasury", 0)) + float(e.get("farm_till", 0))
		for f: Dictionary in e.get("fams", []): n += float(f.get("purse", 0))
		for b: Dictionary in e.get("biz", []): n += float(b.get("till", 0))
	for fac: Dictionary in Game.world["factions"].values(): n += float(fac.get("treasury", 0))
	for wb: Dictionary in Game.world["warbands"].values(): n += float(wb.get("gold", 0))
	return n

func grain(town: Dictionary) -> int:
	var n := int(town["econ"]["stock"].get("grain", 0)) + int(TownEcon.goods_lost.get("grain", 0))
	for lot: Array in Game.provisions.get("meal", []):
		if lot.size() > 2 and str(lot[2]) == "grain": n += int(lot[0])
	return n

func stock(town: Dictionary) -> int:
	var n := Horses.count(Game.company)
	for h: Dictionary in Herds.herds(town["econ"]).values():
		if str(h["k"]) == "horses": n += Herds.head(h)
	return n

func biology(seed_value: int) -> String:
	var data: Dictionary = fixture.duplicate(true)
	var e: Dictionary = data["econ"]
	var h: Dictionary = e["hd"]["h"][data["herd_id"]]
	var P := Plots._p(e)
	# One real pasture expanded by the tool fixture, not years of world simulation.
	P["ac"][int(data["pasture"])] = 120
	for age: String in Herds.AGES:
		Herds.change(e, h, age, -int(h[age]), "died", "fixture reset", 0)
	Herds.change(e, h, "g", 12, "bought", "fixture opening", 0)
	h["foals"] = []
	h["horse_due"] = []
	h["hun"] = 0
	Herds._males(e)
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	LivestockCare.horse_life(e, h, P, 1, r)
	var due: Array = h.get("horse_due", [])
	check(not due.is_empty() and int(h["y"]) == 0, "conception creates a pregnancy, not a foal")
	if due.is_empty(): return ""
	var birth := int(due[0][0])
	var expected := int(due[0][1])
	check(birth - 1 == ceili(float(Herds.kind("horses")["gestation"]) * Herds.year_days()), "roughly eleven game months of gestation")
	LivestockCare.horse_life(e, h, P, birth - 1, r)
	check(int(h["y"]) == 0, "no birth before the due date")
	LivestockCare.horse_life(e, h, P, birth, r)
	check(int(h["y"]) == expected, "native birth ledger receives the due foals")
	var grown := int(h["g"])
	var adult_day := birth + int(float(Herds.kind("horses")["grow"]) * Herds.year_days())
	h["horse_bred_year"] = Calendar.year(adult_day) # Isolate this cohort from later conceptions.
	LivestockCare.horse_life(e, h, P, adult_day - 1, r)
	check(int(h["g"]) == grown, "foals cannot mature early")
	LivestockCare.horse_life(e, h, P, adult_day, r)
	check(int(h["g"]) == grown + expected and int(h["y"]) == 0, "foals mature after three full game years")
	P["ac"][int(data["pasture"])] = 5
	e["hd"].erase("_pg")
	var cap := LivestockCare.horse_capacity(e, h, P)
	LivestockCare.horse_life(e, h, P, adult_day + 1, r)
	check(Herds.head(h) <= cap, "pasture capacity caps the herd")
	P["use"][int(data["pasture"])] = Plots.FIELD
	LivestockCare.horse_life(e, h, P, adult_day + 2, r)
	check(Herds.head(h) == 0, "no pasture leaves no permanent horse herd")
	return JSON.stringify([h, e["hd"]["log"]], "", true, true)

func hungry_herd() -> void:
	var data: Dictionary = fixture.duplicate(true)
	var e: Dictionary = data["econ"]
	var h: Dictionary = e["hd"]["h"][data["herd_id"]]
	var P := Plots._p(e)
	Herds.change(e, h, "g", 100, "bought", "fixture opening", 0)
	h["fod"] = 0
	h["hun"] = int(Herds.A()["starve_after"]) + 7
	e["treasury"] = 0
	var account := Herds._acct(e, h)
	account[0][account[1]] = 0
	P["use"][int(data["pasture"])] = Plots.FIELD
	e["barn"]["fodder"] = 0
	e["stock"]["fodder"] = 0
	var before := Herds.head(h)
	var r := RandomNumberGenerator.new()
	r.seed = 56
	Herds._feed_all(e, P, 3, 7, r)
	check(Herds.head(h) < before and int(h["led"]["d"].get("starved", 0)) > 0, "native fodder shortage shrinks the herd and records starvation")

func fight(snapshot: Dictionary, enemy: Dictionary) -> String:
	var s := BattleSim.new()
	s.setup([Unit.from_dict(snapshot.duplicate(true))], [Unit.from_dict(enemy.duplicate(true))], 560,
		{"combat_journal": false, "max_ticks": 80, "verbose": false})
	for _i in 40:
		if not s.is_over(): s.step()
	var state: Array = []
	for f: Fighter in s.fighters: state.append([f.cell, f.state, f.unit.to_dict()])
	return JSON.stringify(state, "", true, true)

func run(tree: SceneTree) -> int:
	var started := Time.get_ticks_msec()
	if not await DevTools.start_world(tree, Game.SAVE_PATH):
		check(false, "DevTools fixture loads")
		return fails
	var tid := DevTools.choose_house(Game, func(choice: Dictionary):
		var t: Dictionary = Game.world["towns"][str(choice["town_id"])]
		return str(Dynasty.person(Game, str(choice["ruler_uid"])).get("race", "")) == "human" \
			and not DevTools.horse_fixture(t).is_empty())
	check(tid != "", "native human settlement has horses and pasture")
	if tid == "": return fails
	var town: Dictionary = Game.world["towns"][tid]
	fixture = DevTools.horse_fixture(town)
	var a := biology(56)
	check(a == biology(56), "the same seed reproduces births, ages and capacity losses")
	hungry_herd()
	check(DevTools.raise_army(Game, tid, 2) == 2, "two real residents muster")
	if Game.company.size() < 2: return fails
	var u: Unit = Game.company[0]
	var enemy: Dictionary = Game.company[1].to_dict().duplicate(true)
	check(not Horses.can_field(u), "a soldier without a horse cannot field cavalry")
	var foot := BattleSim.new()
	foot.setup([u], [Unit.from_dict(enemy.duplicate(true))], 56, {"combat_journal": false})
	check(foot.fighters.size() == 2 and foot.fighters[0].mount_idx == -1, "native setup fields unmounted soldiers on foot")
	check(DevTools.offer_horses(town) > 0, "real grown stock is offered")
	var before := coins()
	var heads := stock(town)
	var wallet := Game.gold
	var bought := Horses.buy(Game, town, u)
	check(bool(bought.get("ok", false)), "army buys one actual grown mount")
	if not bool(bought.get("ok", false)): return fails
	check(Game.gold == wallet - int(bought["cost"]) and absf(coins() - before) < 0.0001, "buying moves coin exactly to the native seller")
	check(stock(town) == heads and Horses.can_field(u), "purchase transfers one head from herd to cavalry")
	town["econ"]["hd"]["pr"]["horses"] = float(Herds.kind("horses")["price"]) * Barge.pl(town["econ"])
	var old_price := Herds.price(town["econ"], "horses")
	town["econ"]["hd"]["wak"]["horses"] = 0
	town["econ"]["hd"]["ofk"]["horses"] = 0
	Herds._prices(town["econ"])
	check(Herds.price(town["econ"], "horses") > old_price, "native market price responds to scarce supply and mount demand")
	before = coins()
	heads = stock(town)
	wallet = Game.gold
	var solvent := float(town["econ"]["treasury"]) >= Horses.price(town)
	var sold := Horses.sell(Game, town, u)
	check(bool(sold.get("ok", false)) == solvent and Game.gold == wallet + int(sold.get("paid", 0)) \
		and absf(coins() - before) < 0.0001 and stock(town) == heads, "sale or unfunded rejection conserves horse stock and exact coins")
	if solvent:
		DevTools.offer_horses(town)
		check(bool(Horses.buy(Game, town, u).get("ok", false)), "sold stock remains available through the native market")
	if u.horse == null: return fails
	var saved := u.to_dict().duplicate(true)
	var restored := Unit.from_dict(saved.duplicate(true))
	check(restored.horse.uid == u.horse.uid and restored.horse.body.to_dict() == u.horse.body.to_dict(), "save retains the exact purchased body")
	before = coins()
	var grain_before := grain(town)
	var market_grain := int(town["econ"]["stock"].get("grain", 0))
	var used := int(town["econ"]["led"]["used"].get("grain", 0))
	var packed := Supplies.pack_horse_grain(Game, town)
	check(bool(packed.get("ok", false)), "existing provision lots receive horse grain")
	check(grain(town) == grain_before and absf(coins() - before) < 0.0001, "packing balances physical grain and coins")
	check(int(town["econ"]["stock"]["grain"]) == market_grain - int(packed.get("grain", 0)) \
		and int(town["econ"]["led"]["used"].get("grain", 0)) == used + int(packed.get("grain", 0)), "town grain ledger books the exact export")
	wallet = Game.gold
	Warfare.feed_march_day(Game, int(Game.day) + 1)
	var receipt: Dictionary = u.horse_care.get("receipt", {})
	check(int(receipt.get("grain", 0)) == Horses.GRAIN_DAY and int(receipt.get("coin", 0)) == Horses.COIN_DAY, "daily upkeep draws counted feed plus coin")
	check(Game.gold == wallet - Horses.COIN_DAY and grain(town) == grain_before - int(receipt.get("grain", 0)) and absf(coins() - before) < 0.0001, "daily feed consumes packed grain once and all coin holders balance")
	wallet = Game.gold
	var lost := int(TownEcon.goods_lost.get("grain", 0))
	Warfare.feed_march_day(Game, int(Game.day) + 1)
	check(Game.gold == wallet and int(TownEcon.goods_lost.get("grain", 0)) == lost, "same morning cannot charge twice")
	var dry := Unit.from_dict(saved.duplicate(true))
	dry.horse_care["fed"] = false
	check(not Horses.can_field(dry), "unfed cavalry is unavailable")
	var s := BattleSim.new()
	s.setup([u], [Unit.from_dict(enemy.duplicate(true))], 560, {"combat_journal": false})
	check(s.fighters.size() == 3 and s.fighters[0].mount_idx == 2, "native horse body is a target under the actual rider")
	var rng_before := Game.rng.state
	check(fight(saved, enemy) == fight(saved, enemy) and Game.rng.state == rng_before, "same seeded native battle is deterministic without campaign RNG")
	heads = stock(town)
	var horse: Unit = u.horse
	s._kill(s.fighters[2], 1, "native fixture casualty")
	MountedCombat.sync(s)
	check(horse.dead and u.horse == null and stock(town) == heads - 1, "native horse casualty removes exactly one owned horse")
	check(not Horses.casualty(u, horse) and stock(town) == heads - 1, "casualty replay cannot remove another horse")
	for coat: String in HorseArt.COATS:
		for animation: String in HorseArt.ANIMATIONS:
			for i in int(HorseArt.ANIMATIONS[animation]):
				var tex := HorseArt.frame(coat, animation, i)
				check(is_same(tex, HorseArt.frame(coat, animation, i)) and tex.get_image().get_used_rect().has_area(), "cached visible " + coat + "/" + animation + "/" + str(i))
	check(Time.get_ticks_msec() - started < 60000, "whole DevTools test finishes under 60 seconds")
	print("Horses v056: %d checks, %d failures." % [checks, fails])
	return fails
