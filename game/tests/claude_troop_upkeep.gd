extends RefCounted
## Troop wages and armour upkeep. Setup matches tests/claude_campaign.gd (shared start world,
## a real ruling house). Calls TroopUpkeep directly. Headless:
##   -- --test=res://tests/claude_troop_upkeep.gd --watchdog=180
var checks: int = 0
var fails: int = 0
var previous_save_path: String = ""

func check(ok: bool, what: String) -> void:
	checks += 1
	if not ok:
		fails += 1
		printerr("FAIL troops: ", what)

func _finish() -> int:
	Game.wait_save()
	if previous_save_path != "":
		Game.SAVE_PATH = previous_save_path
	print("troops: %d checks, %d failures" % [checks, fails])
	return fails

func _near(a: float, b: float) -> bool:
	return absf(a - b) < 0.05

func _seed_income(f: Dictionary, day_now: float, yearly_income: float, final_purse: float = -1.0) -> void:
	var end_purse: float = final_purse if final_purse >= 0.0 else float(f.get("purse", 0.0))
	var yr_days: float = float(EconGen.YEAR_DAYS)
	f.erase("house_budget")
	f["debt"] = float(f.get("debt", 0.0))
	var start_day: float = day_now - yr_days
	f["purse"] = end_purse - yearly_income
	HouseUpkeep.observe_income(f, start_day)
	var steps: int = 12
	for i in range(1, steps + 1):
		var d: float = start_day + yr_days * float(i) / float(steps)
		f["purse"] = end_purse - yearly_income + yearly_income * float(i) / float(steps)
		HouseUpkeep.observe_income(f, d)
	f["purse"] = end_purse

func _smith_tills(e: Dictionary) -> float:
	var n: float = 0.0
	for b in e.get("biz", []):
		if not (b is Dictionary):
			continue
		var typ: String = str((b as Dictionary).get("type", ""))
		if typ == "weaponsmith" or typ == "armorsmith":
			n += float((b as Dictionary).get("till", 0.0))
	return n

func _other_purses(e: Dictionary, head: int) -> float:
	var n: float = 0.0
	var fams: Array = e.get("fams", [])
	for i in fams.size():
		if i == head:
			continue
		n += float((fams[i] as Dictionary).get("purse", 0.0))
	return n

func _market_till(e: Dictionary) -> float:
	var biz: Array = e.get("biz", [])
	var idx: int = int(e.get("mkt", -1))
	if idx < 0 or idx >= biz.size():
		return 0.0
	return float((biz[idx] as Dictionary).get("till", 0.0))

func _faction_treasury(town: Dictionary) -> float:
	var fid: String = str(town.get("faction", ""))
	return float(Game.world.get("factions", {}).get(fid, {}).get("treasury", 0.0))

func _bind(seat: String) -> Dictionary:
	var town: Dictionary = Game.world["towns"][seat]
	var e: Dictionary = town["econ"]
	var head: int = int(e["head"]["fam"])
	var f: Dictionary = e["fams"][head]
	return {"town": town, "e": e, "f": f, "head": head, "uid": str(f.get("household_uid", ""))}

func _drain() -> void:
	var guard: int = 0
	while not Game.world.get("work", []).is_empty() and guard < 40:
		CampaignWorld.work_slice(Game, 20000)
		guard += 1

func run(tree: SceneTree) -> int:
	await tree.process_frame
	Game.wait_save()
	previous_save_path = Game.SAVE_PATH
	if not await DevTools.start_world(tree, "user://claude_troop_upkeep-test.json"):
		check(false, "the shared test world loads")
		return _finish()
	var seat: String = DevTools.choose_house(Game)
	check(seat != "", "selected a ruling house")
	if seat == "":
		return _finish()
	_drain()
	Game.location = seat
	var home: Dictionary = _bind(seat)
	var town: Dictionary = home["town"]
	var e: Dictionary = home["e"]
	var f: Dictionary = home["f"]
	var head: int = int(home["head"])
	var uid: String = str(home["uid"])
	check(uid != "" and TroopUpkeep._rules(e, f), "the seat head is the ruling household")
	if uid == "":
		return _finish()

	var start_purse: float = maxf(180000.0, float(f.get("purse", 0.0)))
	var per_man: float = TroopUpkeep.wage_week(e) + TroopUpkeep.keep_week(e)
	var target_men: int = maxi(10, int(floor(1000000.0 * HouseUpkeep.TROOP_SHARE / TroopUpkeep.WEEKS_YEAR / maxf(1.0, per_man))))
	var rich_income: float = (float(target_men) + 0.75) * per_man * TroopUpkeep.WEEKS_YEAR / HouseUpkeep.TROOP_SHARE

	_seed_income(f, float(Game.day), 250000.0, start_purse)
	var poor_year: float = TroopUpkeep.expected_yearly_cost(Game, uid)
	_seed_income(f, float(Game.day), rich_income, start_purse)
	var year: float = TroopUpkeep.expected_yearly_cost(Game, uid)
	var purse_now: float = float(f.get("purse", 0.0))
	print("troops yearly %.0f at purse %.0f" % [year, purse_now])
	check(year > poor_year and poor_year > 0.0 and year > 50000.0 and year <= rich_income * HouseUpkeep.TROOP_SHARE + 1.0, "expected yearly cost scales with income and is a real sink within TROOP_SHARE (%.0f -> %.0f)" % [poor_year, year])

	var gold0: int = int(Game.gold)
	var daily0: int = int(Game.daily_wages())
	var treas0: float = float(e.get("treasury", 0.0))
	var fac0: float = _faction_treasury(town)
	var holds0: float = Barge.holdings(Game)
	var purse0: float = float(f["purse"])
	var others0: float = _other_purses(e, head)
	var smith0: float = _smith_tills(e)
	var market0: float = _market_till(e)
	Game.pay_wages(1)
	var pay_drop0: int = gold0 - int(Game.gold)
	var rep: Dictionary = TroopUpkeep.weekly(Game, town, e, f)
	var spent: float = float(rep.get("wages_paid", 0.0)) + float(rep.get("maintenance_paid", 0.0)) + float(rep.get("repair_paid", 0.0))
	check(bool(rep.get("ok", false)) and int(rep.get("retinue", 0)) > 0, "retinue stands (%s men, target %s)" % [rep.get("retinue", 0), rep.get("target", 0)])
	check(float(rep.get("wages_paid", 0.0)) > 0.0 and int(rep.get("recipients", 0)) > 0, "wages paid to %s real households" % int(rep.get("recipients", 0)))
	check(float(rep.get("maintenance_paid", 0.0)) > 0.0, "peacetime kit maintenance was bought")
	check(_near(holds0, Barge.holdings(Game)), "wages and maintenance conserve coin")
	check(_near(others0 + float(rep.get("wages_paid", 0.0)), _other_purses(e, head)), "soldier households received the wages")
	check(_near(purse0 - float(f["purse"]), spent), "house purse paid wages, upkeep and nothing else")
	check(_near(smith0 + float(rep.get("maintenance_paid", 0.0)) + float(rep.get("repair_paid", 0.0)), _smith_tills(e)), "maintenance bought from the smith")
	check(_near(market0, _market_till(e)), "the market till is only the pass-through")
	check(int(Game.gold) == gold0 - pay_drop0 and _near(treas0, float(e.get("treasury", 0.0))) and _near(fac0, _faction_treasury(town)), "house retinue did not spend the army purse, garrison treasury or faction treasury")
	check(int(Game.daily_wages()) == daily0 and pay_drop0 == daily0, "company payroll amount unchanged by the retinue week (%d)" % daily0)

	var bystander: Dictionary = {}
	var fams: Array = e["fams"]
	for i in fams.size():
		if i != head and not (fams[i] as Dictionary).get("gone", false):
			bystander = fams[i]
			break
	var by_purse: float = float(bystander.get("purse", 0.0))
	var skipped: Dictionary = TroopUpkeep.weekly(Game, town, e, bystander)
	check(not bool(skipped.get("ok", false)) and _near(by_purse, float(bystander.get("purse", 0.0))), "a household that does not rule is not charged retinue wages")

	var book: Dictionary = Game.world["troop_upkeep"]["houses"][uid]
	var n_save: int = int(book["n"])
	book["kit"] = 77.0
	Game.save_game()
	Game.wait_save()
	check(Game.load_game(), "save reloads")
	TroopUpkeep.after_load(Game)
	home = _bind(seat)
	town = home["town"]
	e = home["e"]
	f = home["f"]
	head = int(home["head"])
	uid = str(home["uid"])
	var loaded: Dictionary = Game.world.get("troop_upkeep", {}).get("houses", {}).get(uid, {})
	check(not loaded.is_empty() and int(loaded.get("n", -1)) == n_save, "retinue size survived save/load (%s)" % str(loaded.get("n", -1)))
	check(_near(float(loaded.get("kit", -1.0)), 77.0), "kit condition survived save/load")
	check(typeof(loaded.get("n", 0.5)) == TYPE_INT, "after_load restored retinue count as an int")
	check(TroopUpkeep.expected_yearly_cost(Game, uid) > 50000.0, "yearly cost still reads after load")

	var before_cut: int = int(loaded.get("n", 0))
	f["purse"] = 0.0
	var broke: Dictionary = TroopUpkeep.weekly(Game, town, e, f)
	var left: int = int(broke.get("retinue", -1))
	check(left >= 0 and left < before_cut, "unpaid retinue shrinks (%d -> %d)" % [before_cut, left])
	var spins: int = 0
	while left > 0 and spins < 40:
		var again: Dictionary = TroopUpkeep.weekly(Game, town, e, f)
		var next_n: int = int(again.get("retinue", -1))
		check(next_n >= 0 and next_n <= left, "retinue stays non-negative while unpaid (%d)" % next_n)
		left = next_n
		spins += 1
	check(left == 0, "an unpaid house is left with no retinue")
	Game.day = float(Game.day) + 8.0
	_seed_income(f, float(Game.day), rich_income, 180000.0)
	_drain()
	Game.location = seat

	var raised: int = DevTools.raise_army(Game, seat, 4)
	check(raised > 0, "mobilization still raises a field company (%d)" % raised)
	if raised > 0:
		var sum: int = 0
		var wage_sig: Array = []
		for u in Game.company:
			if u is Unit and not (u as Unit).dead:
				sum += int((u as Unit).wage)
				wage_sig.append(int((u as Unit).wage))
		var g0: int = int(Game.gold)
		Game.pay_wages(1)
		var drop1: int = g0 - int(Game.gold)
		check(drop1 == sum and sum > 0, "company payroll still pays each man's own wage from the army purse (%d vs %d)" % [drop1, sum])
		var g1: int = int(Game.gold)
		var treas1: float = float(e.get("treasury", 0.0))
		var fac1: float = _faction_treasury(town)
		TroopUpkeep.weekly(Game, town, e, f)
		var same: bool = true
		var i2: int = 0
		for u2 in Game.company:
			if u2 is Unit and not (u2 as Unit).dead:
				if i2 >= wage_sig.size() or int((u2 as Unit).wage) != int(wage_sig[i2]):
					same = false
				i2 += 1
		check(int(Game.gold) == g1 and _near(treas1, float(e.get("treasury", 0.0))) and _near(fac1, _faction_treasury(town)) and same, "retinue week does not change mobilization payroll wallets or wages")
		var g2: int = int(Game.gold)
		Game.pay_wages(1)
		check(g2 - int(Game.gold) == sum, "a second payday still matches the mobilization wage bill")

	var fighter: Unit = Unit.create("human", "player")
	fighter.equip["body"] = Item.make("mail_shirt", "copper", 1)
	fighter.equip["main_hand"] = Item.make("arming_sword", "copper", 1)
	var dead_man: Unit = Unit.create("human", "player")
	dead_man.dead = true
	dead_man.equip["helm"] = Item.make("nasal_helm", "copper", 1)
	var home_pos: Vector2 = Game.world["party"]["pos"]
	Game.location = ""
	Game.world["party"]["pos"] = Vector2(-100000.0, -100000.0)
	var damage: Dictionary = {}
	damage[str(fighter.uid)] = 0.5
	damage[str(dead_man.uid)] = 0.9
	var battle: Dictionary = {"winner": 0, "player_units": [fighter, dead_man], "enemy_units": [], "gear_damage": damage}
	var holds_b: float = Barge.holdings(Game)
	var worn: Dictionary = TroopUpkeep.on_battle_end(Game, battle)
	var body_item: Item = fighter.equip["body"]
	var hand_item: Item = fighter.equip["main_hand"]
	var helm_item: Item = dead_man.equip["helm"]
	check(int(worn.get("wear_steps", 0)) > 0 and body_item.wear == 2 and hand_item.wear == 2, "a battle wears surviving weapons and armour (%s steps)" % str(worn.get("wear_steps", 0)))
	check(helm_item.wear == 0, "the dead man's gear is not worn again here")
	check(float(worn.get("repair_paid", 0.0)) == 0.0 and _near(holds_b, Barge.holdings(Game)), "repair waits until the army is home")
	Game.location = seat
	Game.world["party"]["pos"] = home_pos
	Game.day = float(Game.day) + 8.0
	var ph_loc: Dictionary = Dynasty._household(Game, str(Game.world.get("player_house", {}).get("household_uid", "")))
	var ph_fam: Dictionary = ph_loc["family"]
	_seed_income(ph_fam, float(Game.day), rich_income, maxf(180000.0, float(ph_fam.get("purse", 0.0))))
	var smith_b: float = _smith_tills(e)
	var holds_r: float = Barge.holdings(Game)
	var fixed: Dictionary = TroopUpkeep.weekly(Game, ph_loc["town"], ph_loc["town"]["econ"], ph_fam)
	check(float(fixed.get("repair_paid", 0.0)) > 0.0 and body_item.wear == 0 and hand_item.wear == 0, "home repair pays the smith and restores the kit (%.0f)" % float(fixed.get("repair_paid", 0.0)))
	check(_near(smith_b + float(fixed.get("repair_paid", 0.0)) + float(fixed.get("maintenance_paid", 0.0)), _smith_tills(e)), "repair coins landed in the smith's till")
	check(_near(holds_r, Barge.holdings(Game)), "repair conserves coin")
	return _finish()
