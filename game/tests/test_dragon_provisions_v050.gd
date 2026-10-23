extends RefCounted
## v0.050: one daily dragon feeding, packed meat on campaign, household priority.
## Uses the cached DevTools world. Does not write user://save.json.

var fails := 0
var checks := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		fails += 1
		printerr("FAIL dragon provisions: " + message)

func near(a: float, b: float) -> bool:
	return absf(a - b) < 0.000001

## The wage step then the meal clock, in the same order as Game.advance_time, without the world midnight.
func rest_slice(days: float) -> void:
	var before := int(floor(Game.day))
	Game.day += days
	var whole := int(floor(Game.day)) - before
	if whole > 0:
		Game.pay_wages(whole)
	Food.on_time(Game, days, true)

func apply_tree(data: Dictionary) -> void:
	Game.company = data.get("company", []).map(func(x): return Unit.from_dict(x))
	Game.day = float(data.get("day", 0.0))
	Game.gold = int(data.get("gold", 0))
	Game.location = str(data.get("location", ""))
	Game.world = Game._deserialize(data.get("world", {}))
	Game.provisions = Food.stock_from_save(data.get("provisions", {}))
	var saved: Dictionary = data.get("rations", {})
	Game.rations = {"food": str(saved.get("food", "normal")), "drink": str(saved.get("drink", "ration"))}
	Game.food_clock = {}
	var clock: Dictionary = data.get("food_clock", {})
	for key in clock.keys():
		Game.food_clock[key] = int(clock[key]) if key == "rot" else float(clock[key])
	CampaignWorld.after_load(Game)

func care_view(uid: String) -> Dictionary:
	var row: Dictionary = live(uid)
	var last: Dictionary = row.get("care", {}).get("last", {})
	return {"meat": Food.meat_units(Game), "grain": Food.food_stock(Game, "grain"),
		"health": float(row.get("care", {}).get("health", -1.0)), "fed": int(last.get("food_units", -1)),
		"day": int(row.get("care", {}).get("last_day", -1))}

func live(uid: String) -> Dictionary:
	return Game.world["dragons"]["records"][uid]

func groups() -> Array:
	var grouped := {}
	for uid in Game.world.get("dragons", {}).get("records", {}):
		var row: Dictionary = Game.world["dragons"]["records"][uid]
		if str(row.get("stage", "")) != "adult" or not bool(row.get("alive", false)): continue
		var owner: Dictionary = Dynasty._person(Game, str(row.get("owner_person_uid", "")))
		if owner.is_empty(): continue
		var tid := str(row.get("location_town_id", ""))
		var key := str(row.get("owner_household_uid", "")) + "|" + tid
		if not grouped.has(key):
			grouped[key] = {"household": str(row.get("owner_household_uid", "")), "tid": tid, "uids": []}
		(grouped[key]["uids"] as Array).append(str(uid))
	var out: Array = grouped.values()
	out.sort_custom(func(a, b): return str(a["household"]) < str(b["household"]))
	return out

func keeper_for(tid: String, household: String) -> String:
	var town: Dictionary = Game.world["towns"].get(tid, {})
	var fallback := ""
	for family in town.get("econ", {}).get("fams", []):
		var home := str(family.get("household_uid", "")) == household
		for person in family.get("pp", []) + family.get("kp", []):
			var uid := str(Persons.g(person, Persons.PERSON_UID, ""))
			var who: Dictionary = Dragons._person(Game, uid)
			if who.is_empty() or not Dragons._present(who, tid): continue
			if home: return uid
			if fallback == "": fallback = uid
	return fallback

func run(tree: SceneTree) -> int:
	if not await DevTools.start_world(tree, "user://test_dragon_provisions_v050.json"):
		check(false, "start world")
		return fails
	Game.world["work"] = []
	var chosen := {}
	for group in groups():
		if (group["uids"] as Array).size() < 1: continue
		if not bool(HouseOnboarding.preview(Game, str(group["tid"]), str(group["household"])).get("ok", false)): continue
		if chosen.is_empty() or (group["uids"] as Array).size() > (chosen["uids"] as Array).size():
			chosen = group
	check(not chosen.is_empty(), "a living adult belongs to a household the player can lead")
	if chosen.is_empty(): return fails
	var ids: Array = chosen["uids"]
	ids.sort()
	var uid_a := str(ids[0])
	var uid_b := str(ids[1] if ids.size() > 1 else ids[0])
	var row_a: Dictionary = live(uid_a)
	var tid := str(chosen["tid"])
	var began: Dictionary = HouseOnboarding.begin(Game, tid, str(chosen["household"]))
	check(bool(began.get("ok", false)), "owning household can be selected: " + str(began.get("reason", "")))
	if not bool(began.get("ok", false)): return fails
	check(bool(Dragons.authority(Game, row_a).get("ok", false)), "selected household may order this dragon")
	var keeper := keeper_for(tid, str(chosen["household"]))
	check(keeper != "", "the household has a keeper at the roost")
	if keeper == "": return fails
	for uid in [uid_a, uid_b]:
		var row: Dictionary = live(uid)
		if str(row.get("custodian_person_uid", "")) == "" or not Dragons._present(Dragons._person(Game, str(row.get("custodian_person_uid", ""))), tid):
			row["custodian_person_uid"] = keeper
	var raised := DevTools.raise_army(Game, tid, 8)
	check(raised > 0 and not Game.company.is_empty(), "field army is raised before the meat snapshot")
	if Game.company.is_empty(): return fails
	var day := int(floor(Game.day))
	for uid in [uid_a, uid_b]:
		live(uid)["care"]["last_day"] = day - 1
		live(uid)["care"]["health"] = 1.0
	var town: Dictionary = Game.world["towns"][tid]
	var e: Dictionary = town["econ"]
	e["stock"]["grain"] = 100000
	e["stock"]["fruit"] = 100000
	e["stock"]["fresh_meat"] = 0
	e["stock"]["meat"] = 0
	e["stock"]["wood"] = 5000
	e["price"]["meat"] = 12.0
	e["price"]["wood"] = 5.0
	e["price"]["fresh_meat"] = 0.0
	var owner: Dictionary = Dynasty._person(Game, str(row_a.get("owner_person_uid", "")))
	var fam: Dictionary = owner["family"]
	fam["purse"] = 100000.0
	fam["store"]["food"] = 30.0
	fam["last"] = float(day)
	Caravans.unload(town, {"goods": {"meat": 17}})
	check(int(e["stock"]["meat"]) == 17 and int(e["stock"].get("fresh_meat", 0)) == 0, "supply order unloads meat into the town stock")
	var meat0 := int(e["stock"]["meat"])
	var fresh0 := int(e["stock"].get("fresh_meat", 0))
	var wood0 := int(e["stock"]["wood"])
	var purse0 := float(fam["purse"])
	var till0 := float(e["biz"][int(e["mkt"])]["till"])
	var sales0 := float(e["stats"]["sales"])
	var gold0 := int(Game.gold)
	check(DragonCare.settle(Game, live(uid_a), day), "home care settles once")
	var receipt: Dictionary = live(uid_a)["care"]["last"]
	var bought := int(receipt.get("food_units", 0))
	var upkeep := int(receipt.get("upkeep_units", 0))
	check(bought > 0 and float(receipt.get("food_cost", 0.0)) > 0.0, "home care buys meat (%s)" % str(receipt.get("reason", "")))
	check(str(receipt.get("source", "")) == "market", "home receipt is a market purchase")
	check(int(e["stock"]["meat"]) - (meat0 - bought) == 0 or int(e["stock"]["meat"]) + int(e["stock"].get("fresh_meat", 0)) == meat0 + fresh0 - bought, "town meat drops by the receipt")
	check(meat0 + fresh0 - int(e["stock"]["meat"]) - int(e["stock"].get("fresh_meat", 0)) == bought, "meat and fresh meat drops equal food units")
	check(wood0 - int(e["stock"]["wood"]) == upkeep, "wood drops by the shelter receipt")
	var spent := float(receipt.get("food_cost", 0.0)) + float(receipt.get("upkeep_cost", 0.0))
	check(near(purse0 - float(fam["purse"]), spent), "household purse pays the receipt")
	check(near(float(e["biz"][int(e["mkt"])]["till"]) - till0, spent), "market till receives the receipt")
	check(near(float(e["stats"]["sales"]) - sales0, spent), "market sales record the receipt")
	check(int(Game.gold) == gold0, "home care does not spend the army purse")
	var snap_meat := int(e["stock"]["meat"])
	var snap_purse := float(fam["purse"])
	var snap_units := int(receipt.get("food_units", 0))
	check(not DragonCare.settle(Game, live(uid_a), day), "second home settlement the same day does nothing")
	check(int(e["stock"]["meat"]) == snap_meat and near(float(fam["purse"]), snap_purse), "second settlement moves no meat or coin")
	check(int(live(uid_a)["care"]["last"].get("food_units", -1)) == snap_units, "receipt stays the first purchase")
	live(uid_a)["campaign_march"] = {"enabled": true, "day": float(Game.day)}
	var meat_before_march := Food.meat_units(Game)
	check(not DragonCare.settle(Game, live(uid_a), day), "marching the same day does not feed again")
	check(int(e["stock"]["meat"]) == snap_meat and near(float(fam["purse"]), snap_purse), "same-day march moves no town meat or household coin")
	check(Food.meat_units(Game) == meat_before_march, "same-day march draws no packed meat")
	var same := uid_a == uid_b
	var feed_day := day
	if same:
		var early_units := int(live(uid_a)["care"]["last"].get("food_units", -1))
		DragonCare.daily(Game, day)
		check(int(live(uid_a)["care"]["last"].get("food_units", -2)) == early_units and int(live(uid_a)["care"]["last_day"]) == day, "the day's home receipt survives the care pass")
		feed_day = day + 1
	Game.provisions["meal"] = []
	Food.add_stock(Game, "meal", 4, 2, "grain", "Barley")
	Food.add_stock(Game, "meal", 20, 11, "meat", "Salted")
	Food.add_stock(Game, "meal", 500, 16, "fresh_meat", "Fresh")
	var packed_before := Food.meat_units(Game)
	var grain_before := Food.food_stock(Game, "grain")
	var gold_b := int(Game.gold)
	var purse_b := float(fam["purse"])
	live(uid_b)["campaign_march"] = {"enabled": true, "day": float(Game.day)}
	check(DragonCare.settle(Game, live(uid_b), feed_day), "campaign care settles from packed meat")
	var march: Dictionary = live(uid_b)["care"]["last"]
	var taken := int(march.get("food_units", 0))
	check(str(march.get("source", "")) == "army" and float(march.get("food_cost", 1.0)) == 0.0 and float(march.get("upkeep_cost", 1.0)) == 0.0, "campaign receipt spends no coin")
	check(int(march.get("spoiled", 1)) == 0, "the draw itself does not spoil")
	check(taken > 0 and Food.meat_units(Game) == packed_before - taken, "packed meat falls by the amount drawn")
	check(packed_before == Food.meat_units(Game) + taken, "meat before equals meat after plus drawn")
	check(int(Game.gold) == gold_b and near(float(fam["purse"]), purse_b), "campaign settle leaves gold and the household purse")
	check(Food.food_stock(Game, "grain") == grain_before, "grain lots are not dragon meat")
	var lots: Array = march.get("lots", [])
	check(not lots.is_empty() and str(lots[0].get("good", "")) == "fresh_meat" and int(lots[0].get("age", -1)) == 16, "oldest named meat is drawn first")
	check(Food.food_stock(Game, "fresh_meat") == 500 - mini(taken, 500), "fresh meat remainder keeps its count")
	check(Food.food_stock(Game, "meat") == 20 - maxi(0, taken - 500), "younger meat is touched only after fresh meat")
	var fresh_age_ok := true
	for lot in Game.provisions.get("meal", []):
		var good := String(lot[2]) if lot.size() > 2 else ""
		if good == "fresh_meat" and int(lot[1]) != 16: fresh_age_ok = false
		if good == "meat" and int(lot[1]) != 11: fresh_age_ok = false
		if good == "grain" and int(lot[1]) != 2: fresh_age_ok = false
	check(fresh_age_ok, "lots that remain keep their age")
	var packed_after := Food.meat_units(Game)
	check(not DragonCare.settle(Game, live(uid_b), feed_day) and Food.meat_units(Game) == packed_after, "second campaign settlement draws nothing")
	if not same:
		var home_units := int(live(uid_a)["care"]["last"].get("food_units", -1))
		DragonCare.daily(Game, day)
		check(int(live(uid_a)["care"]["last"].get("food_units", -2)) == home_units and int(live(uid_a)["care"]["last_day"]) == day, "the day's home receipt survives the care pass")
		check(Food.meat_units(Game) == packed_after, "the care pass does not draw packed meat again")
	var plan: Dictionary = Supplies.dragon_meat_plan(Game)
	var need := int(plan.get("need_per_day", 0))
	check(int(plan.get("dragons", 0)) >= 1 and need > 0, "the plan counts marching dragons")
	check(near(float(plan.get("days_needed", -1.0)), 6.0), "pre-war horizon is the army store of 6 days")
	check(near(float(plan.get("days_packed", -1.0)), float(plan.get("packed", 0)) / float(need)), "days packed are packed meat divided by the daily need")
	check(bool(plan.get("short", false)) == (int(plan.get("packed", 0)) < need * 6), "shortfall follows packed meat against the horizon")
	Game.provisions["meal"] = []
	Food.add_stock(Game, "meal", 1, 1, "meat", "Salted")
	Food.add_stock(Game, "meal", 4, 2, "grain", "Barley")
	var lean: Dictionary = Supplies.dragon_meat_plan(Game)
	check(bool(lean.get("short", false)) and "Shortfall" in str(lean.get("line", "")), "a thin store warns of the shortfall")
	Food.add_stock(Game, "meal", int(lean.get("units_needed", 0)) + Food.eaters(Game).size() * 3 + 5, 0, "meat", "Extra")
	var covered: Dictionary = Supplies.dragon_meat_plan(Game)
	check(not bool(covered.get("short", true)) and not ("Shortfall" in str(covered.get("line", ""))), "enough packed meat clears the warning")
	var keep := []
	for lot in Game.provisions.get("meal", []):
		var good := String(lot[2]) if lot.size() > 2 else ""
		if good != "meat" and good != "fresh_meat": keep.append(lot)
	Game.provisions["meal"] = keep
	check(Food.meat_units(Game) == 0 and Food.food_stock(Game, "grain") == 4, "hunger setup keeps grain and no named meat")
	var growth := float(live(uid_b).get("growth_points", 0.0))
	live(uid_b)["care"]["health"] = 1.0
	check(DragonCare.settle(Game, live(uid_b), feed_day + 1), "the next day still settles")
	check(near(float(live(uid_b)["care"]["health"]), 1.0 - 0.018), "missed packed meat lowers health by the care rule")
	check(not near(float(live(uid_b)["care"]["health"]), 1.0 - 0.08), "missed meat is not the old purse penalty")
	check(near(float(live(uid_b).get("growth_points", 0.0)), growth), "a missed feed does not grow the dragon")
	fam["store"]["food"] = 0.0
	fam["last"] = float(day)
	check(bool(DragonCare.set_priority(Game, live(uid_a), "last").get("ok", false)), "priority can be set to last")
	var reserve_last := float(DragonCare.status(Game, live(uid_a)).get("reserve", 0.0))
	check(bool(DragonCare.set_priority(Game, live(uid_a), "normal").get("ok", false)), "priority can be set to normal")
	var reserve_normal := float(DragonCare.status(Game, live(uid_a)).get("reserve", 0.0))
	check(bool(DragonCare.set_priority(Game, live(uid_a), "first").get("ok", false)), "priority can be set to feed first")
	var reserve_first := float(DragonCare.status(Game, live(uid_a)).get("reserve", 0.0))
	check(reserve_last > reserve_normal and reserve_normal > reserve_first, "food-fund reserve is last, then normal, then feed first (%.2f %.2f %.2f)" % [reserve_last, reserve_normal, reserve_first])
	fam["purse"] = reserve_first + 1.0
	var purse_probe := float(fam["purse"])
	var stock_probe := int(e["stock"]["meat"])
	var quoted: Dictionary = DragonCare.status(Game, live(uid_a))
	check(float(quoted.get("spendable", 0.0)) > 0.0, "feed first can spend the coin above its floor")
	check(near(float(fam["purse"]), purse_probe) and int(e["stock"]["meat"]) == stock_probe, "a quote does not spend or move meat")
	var words := DragonsView.care_quote_text(live(uid_a), quoted)
	check(DragonCare.priority_line("first") in words, "the dragon screen explains the priority")
	check(bool(DragonCare.set_priority(Game, live(uid_a), "last").get("ok", false)), "priority returns to last")
	check(str(fam.get("dragon_feed", "")) == "last", "priority is stored on the live household")
	var held_back: Dictionary = DragonCare.status(Game, live(uid_a))
	check(float(held_back.get("spendable", 1.0)) == 0.0, "last holds the purse when it sits on the feed-first floor")
	Food.add_stock(Game, "meal", 3, 4, "fresh_meat", "Fresh")
	var saved_feed := str(fam.get("dragon_feed", ""))
	var saved_day := int(live(uid_a)["care"]["last_day"])
	var saved_fresh := Food.food_stock(Game, "fresh_meat")
	var saved_gold := int(Game.gold)
	var raw := JSON.stringify(Game._save_tree())
	var data = JSON.parse_string(raw)
	check(data is Dictionary, "save tree round-trips as JSON")
	if not data is Dictionary: return fails
	Game.day = -5.0
	Game.gold = -5
	Game.world = {}
	Game.provisions = Food.new_stock()
	Game.company = data.get("company", []).map(func(x): return Unit.from_dict(x))
	Game.day = data.get("day", 0.0)
	Game.gold = int(data.get("gold", 0))
	Game.location = str(data.get("location", ""))
	Game.world = Game._deserialize(data.get("world", {}))
	Game.provisions = Food.stock_from_save(data.get("provisions", {}))
	CampaignWorld.after_load(Game)
	check(int(Game.gold) == saved_gold, "gold survives the round trip")
	var restored: Dictionary = live(uid_a)
	check(int(restored["care"]["last_day"]) == saved_day, "care day survives the round trip")
	var owner_again: Dictionary = Dynasty._person(Game, str(restored.get("owner_person_uid", "")))
	check(str(owner_again.get("family", {}).get("dragon_feed", "")) == saved_feed, "household priority survives the round trip")
	check(Food.food_stock(Game, "fresh_meat") == saved_fresh, "fresh meat lots survive the round trip")
	var packed_loaded := Food.meat_units(Game)
	check(not DragonCare.settle(Game, restored, saved_day), "the restored day does not feed again")
	check(Food.meat_units(Game) == packed_loaded, "the restored day draws no meat")
	Game.provisions["meal"] = []
	Food.add_stock(Game, "meal", 10, 20, "meat", "Salted")
	Food.add_stock(Game, "meal", 7, 3, "grain", "Barley")
	var drawn: Dictionary = Food.take_named(Game, Food.MEAT_GOODS, 4)
	check(int(drawn.get("taken", 0)) == 4 and int(drawn.get("spoiled", 1)) == 0, "four meat units are drawn and none spoil in the draw")
	check(Food.meat_units(Game) == 6 and Food.food_stock(Game, "grain") == 7, "the rest of the meat and all the grain stay")
	var spoiled: Dictionary = Food.age_stock(Game)
	check(int(spoiled.get("meal", 0)) == 6 and Food.meat_units(Game) == 0, "the next day spoils the six meat units left at the limit")
	check(Food.food_stock(Game, "grain") == 7, "grain is not spoiled by the meat lot")
	check(4 + 6 == 10, "drawn meat plus spoiled meat is the whole lot")
	var dawn := float(int(floor(Game.day)))
	Game.day = dawn
	Game.rations["food"] = "normal"
	Game.food_clock = {"next": Food.next_tick_after(Game.day), "last": Game.day, "march": 0.0, "rot": 0}
	for u in Food.eaters(Game):
		u.belly = 100.0
	for uid in Game.world["dragons"]["records"].keys():
		(Game.world["dragons"]["records"][uid] as Dictionary).erase("campaign_march")
	Game.provisions["meal"] = []
	Food.add_stock(Game, "meal", 7, 1, "grain", "Barley")
	Food.add_stock(Game, "meal", 5, 20, "meat", "Salted")
	live(uid_b)["campaign_march"] = {"enabled": true, "day": Game.day}
	live(uid_b)["care"]["last_day"] = int(dawn)
	live(uid_b)["care"]["health"] = 1.0
	check(DragonCare.food_need_units(Game, live(uid_b)) > 0, "the marching dragon needs packed meat")
	var snap = JSON.parse_string(JSON.stringify(Game._save_tree()))
	check(snap is Dictionary, "the rest snapshot round-trips")
	if snap is Dictionary:
		rest_slice(1.0)
		var one := care_view(uid_b)
		apply_tree(snap)
		var origin := float(Game.day)
		for step in 24:
			var dest := origin + float(step + 1) / 24.0
			rest_slice(dest - float(Game.day))
		var many := care_view(uid_b)
		check(int(one["meat"]) == int(many["meat"]) and int(one["grain"]) == int(many["grain"]) and int(one["fed"]) == int(many["fed"]) and int(one["day"]) == int(many["day"]) and near(float(one["health"]), float(many["health"])), "one-day rest and 24 small steps leave the same meat and spoilage")
		check(int(one["meat"]) == 0 and int(one["grain"]) == 7 and int(one["fed"]) == 0 and float(one["health"]) < 1.0, "age-20 meat spoils before the march draw")
	for u2 in Food.eaters(Game):
		u2.belly = 0.0
	Game.rations["food"] = "normal"
	Game.provisions["meal"] = []
	Food.add_stock(Game, "meal", 4000, 3, "meat", "Salted")
	var reserve := Food.ration_meat_reserve(Game)
	check(reserve > 0, "the company has a meat ration for the day")
	Game.provisions["meal"] = []
	Food.add_stock(Game, "meal", reserve, 3, "meat", "Salted")
	check(Food.meat_units(Game) == reserve and Food.ration_meat_reserve(Game) == reserve, "meat equal to the day's meals is all reserved")
	for uid3 in Game.world["dragons"]["records"].keys():
		(Game.world["dragons"]["records"][uid3] as Dictionary).erase("campaign_march")
	live(uid_b)["campaign_march"] = {"enabled": true, "day": float(Game.day)}
	var held_plan: Dictionary = Supplies.dragon_meat_plan(Game)
	check(int(held_plan.get("packed", -1)) == 0 and bool(held_plan.get("short", false)), "attack review counts only meat above the soldiers' ration")
	live(uid_b)["care"]["last_day"] = int(floor(Game.day)) - 1
	live(uid_b)["care"]["health"] = 1.0
	var held := Food.meat_units(Game)
	check(DragonCare.settle(Game, live(uid_b), int(floor(Game.day))), "a short march day still settles")
	check(Food.meat_units(Game) == held, "dragons cannot eat the soldiers' day ration")
	check(int(live(uid_b)["care"]["last"].get("food_units", -1)) == 0, "the shortage draws none of the reserved meat")
	check(near(float(live(uid_b)["care"]["health"]), 1.0 - 0.018), "the shortage uses the hunger path")
	print("Dragon provisions v0.050: %d checks, %d fails" % [checks, fails])
	return fails
