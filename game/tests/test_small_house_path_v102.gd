extends RefCounted
## v0.102: three independently seeded native economy fixtures, no world/history simulation.
## Required route: empty House purse -> charter loan -> House purse -> Army purse ->
## hire and muster commoners at home -> move an unled household army on the native map.
## v0.102: Controller-only execution: --block=small_house_v102 --watchdog=60; whole test <55 s.
##
## run only one Godot game test at a time on the user's PC (several at once crashed it), headless. Before starting any game test, check for other running Godot or Unity processes (from any project or helper); if any are running, queue the test and wait until they have finished before starting it. Every test must finish in under 3 minutes. These rules must be pasted word for word into every helper task and test brief.
## A test failure stops all further tests. No other test runs until that one failing test is fixed and passes.

const SEEDS := [101, 202, 303]
const HOME := "home"
const AWAY := "away"
const REALM := "middle_kingdom"
const CHARTER := 1200.0
const BUDGET_MS: int = 55000 # v0.102: Reserve 5 seconds within the 60-second watchdog.

var checks: int = 0
var fails: int = 0
var case_seed: int = 0
var refusals: Dictionary = {}

func check(ok: bool, what: String) -> void:
	checks += 1
	if not ok:
		fails += 1
		printerr("FAIL seed %d: %s" % [case_seed, what])

## Assert the actual returned reason and its specific recovery action. A different
## earlier gate cannot silently satisfy a later branch's test.
func _text(text: String, branch: String, blocker: String, next_step: String) -> void:
	var low: String = text.to_lower()
	check(not low.strip_edges().is_empty() and low.contains(blocker.to_lower()) and low.contains(next_step.to_lower()),
		"%s names blocker '%s' and next step '%s': %s" % [branch, blocker, next_step, text])
	refusals[branch] = true

func _no(result: Dictionary, branch: String, blocker: String, next_step: String) -> void:
	check(not bool(result.get("ok", true)), branch + " refuses")
	_text(str(result.get("reason", "")), branch, blocker, next_step)

func _family(e: Dictionary, name_text: String, adults: int) -> Dictionary:
	var f: Dictionary = Families._blank(e["fams"].size())
	f["name"] = name_text
	f["pp"] = []
	f["kp"] = []
	f["race"] = "human"
	f["cul"] = "middle"
	f["seed"] = Game.rng.randi()
	f["idle"] = adults
	e["fams"].append(f)
	Families.identity(e, f)
	for i in adults:
		_person(e, f, 20 + Game.rng.randi_range(0, 8), i % 2)
	return f

func _person(e: Dictionary, f: Dictionary, age: int, sex: int) -> Array:
	var pid: int = int(e["next_pid"])
	e["next_pid"] = pid + 1
	var p: Array = [pid, 0, sex, 1 - int(age * People.year_days()), "", -1,
		2 if age < int(People.ages("human")["adult"]) else 0, "Fixture%d" % pid, -1, -1, -1, "", []]
	Persons.identity(e, f, p)
	if int(p[6]) == 2:
		f["kp"].append(p)
		f["kids"] = int(f["kids"]) + 1
	else:
		f["pp"].append(p)
		var category: String = "m" if sex == 0 else "f"
		f[category] = int(f[category]) + 1
	return p

func _weapon_ids() -> Array:
	var ids: Array = DB.weapons.keys()
	ids.sort()
	var out: Array = []
	for tid in ids:
		if not DB.is_bow(str(tid)):
			out.append(str(tid))
		if out.size() == 2:
			break
	return out

## Native economy generation only: two hamlets at 10% household scale, Normal
## map dimensions, day 1 set directly. No start-world cache, save or campaign day.
func _fixture(seed_value: int) -> Dictionary:
	Game.seed_value = seed_value
	Game.rng.seed = seed_value
	Game.day = 1.0
	Game.gold = 0
	Game.company = []
	Game.stash = []
	Game.squads = {}
	Game.rep = {REALM: 0}
	Game.contract = {}
	Game.pending_battle = {}
	Game.provisions = {"meal": [], "beer": [], "wine": []}
	Game.food_clock = {}
	Game.location = ""
	Game.screen_params = {"town_id": HOME}
	Game.main = null
	var cells: int = WorldGen.W * WorldGen.H
	Game.world = {"seed": seed_value, "w": WorldGen.W, "h": WorldGen.H, "tf": 1.0,
		"terrain": "g".repeat(cells), "road": "0".repeat(cells), "region": "0".repeat(cells),
		"tin_belts": [], "towns": {}, "warbands": {}, "wars": [], "work": [], "log": [], "next_id": 0,
		"factions": {REALM: {"towns": [HOME, AWAY], "capital": HOME, "treasury": 3000.0}},
		"party": {"pos": Vector2(240, 240), "target": Vector2(240, 240), "path": [],
			"dest_town": "", "arrived": "", "waiting": false, "objective": "hold_capital"}, "encounter": ""}
	var scale: Variant = EconGen.town_scale_override
	EconGen.town_scale_override = 0.1
	for i in 2:
		var tid: String = HOME if i == 0 else AWAY
		var t: Dictionary = {"id": tid, "name": tid.capitalize(), "faction": REALM, "culture": "middle",
			"size": 0, "wealth": 1, "specialty": "farming", "capital": i == 0,
			"pos": Vector2(240 + i * 240, 240), "shop": [], "armory_items": [], "recruits": [], "contracts": []}
		Game.world["towns"][tid] = t
		# Match native pre-economy setup without changing the household RNG stream.
		var town_rng := RandomNumberGenerator.new()
		town_rng.seed = hash([seed_value, tid, "fixture-town"])
		Economy.make_crafters(t, town_rng)
		Economy.roll_prices(t, town_rng)
		EconGen.generate(Game.world, t, Game.rng)
		t["econ"]["day"] = Game.day
	EconGen.town_scale_override = scale
	var town: Dictionary = Game.world["towns"][HOME]
	var e: Dictionary = town["econ"]
	# Keep generated households working; only the explicit idle commoners are
	# draftable. The ruler/account/market are still the native generated records.
	for f in e["fams"]:
		f["hands"] = Families.adults(f)
	var house: Dictionary = _family(e, "Penniless house %d" % seed_value, 2)
	var child: Array = _person(e, house, 10, 0)
	var common: Dictionary = _family(e, "Commoners %d" % seed_value, 8)
	# Native commoners belong to population pools; tracked noble households
	# would legitimately be promoted by Army.house_born during command_plan.
	common["cohort"] = true
	common["homes"] = 2
	common["named"] = true
	TownEcon.recount(e)
	house["purse"] = 0.0
	e["treasury"] = CHARTER
	var held_food: int = 0
	for good in Goods.FOODS:
		e["stock"][good] = 0
		held_food += maxi(0, int(e["hh"].get(good, 0)))
	e["price"]["grain"] = 1.0
	e["stock"]["grain"] = ceili(Barge.household_eaters(e, Game.day, false) * 6.0) + held_food + 100
	var ids: Array = _weapon_ids()
	check(ids.size() == 2, "fixture has two native melee weapon templates")
	if ids.size() != 2:
		return {}
	var expensive: Item = Item.make(str(ids[0]), "", DB.LEGEND)
	var cheap: Item = Item.make(str(ids[1]))
	town["prices"] = {expensive.tid: 10000.0, cheap.tid: 0.001}
	town["shop"] = [expensive, cheap]
	town["armory_items"] = []
	var recruit: Unit = Mobilization._new_unit(Game, town)
	recruit.home_town = HOME
	recruit.hire_cost = 100
	recruit.wage = 20
	recruit.equip["main_hand"] = Item.make(str(ids[1]))
	Persons.bind(e, common, common["pp"][0], recruit, "hire", Game.day)
	town["recruits"] = [recruit]
	var adults: Array = []
	for p in house["pp"]:
		var u: Unit = Mobilization._new_unit(Game, town)
		u.home_town = HOME
		Persons.bind(e, house, p, u, "army", Game.day)
		adults.append(u)
		Army.state(Game.world)["roll"][str(u.uid)] = [HOME, int(house["id"]), "army", u.name]
	house["serve"]["army"] = adults.size()
	Game.world["warbands"]["realm_service"] = {"id": "realm_service", "faction": REALM,
		"home": HOME, "kind": "patrol", "pos": Game.world["towns"][AWAY]["pos"], "units": adults,
		"path": [], "regroup_until": 99, "gold": 100.0, "stores": {}}
	Dynasty.prepare_world(Game)
	Feudal.prepare_world(Game)
	Game.invalidate_deploy()
	return {"town": town, "econ": e, "house": house, "common": common, "child": child,
		"adults": adults, "recruit": recruit, "cheap": cheap, "expensive": expensive}

func _money(fx: Dictionary) -> Array:
	return [Game.gold, float(fx["house"]["purse"]), float(fx["house"]["debt"]),
		float(fx["econ"]["treasury"]), float(fx["econ"].get("loans", 0.0)),
		float(fx["econ"]["stats"].get("lent", 0.0))]

func _begin(fx: Dictionary) -> bool:
	var house: Dictionary = fx["house"]
	var uid: String = str(house["household_uid"])
	var p: Array = house["pp"][0]
	var preview: Dictionary = HouseOnboarding.preview(Game, HOME, uid)
	check(bool(preview.get("ok", false)) and not bool(preview.get("holds_office", true)), "away leader's non-ruling house can be reviewed")
	var result: Dictionary = HouseOnboarding.begin(Game, HOME, uid, {}, str(p[Persons.PERSON_UID]))
	check(bool(result.get("ok", false)), "non-ruling campaign begins with its real away adult")
	if not bool(result.get("ok", false)):
		return false
	check(Game.world["seed"] == case_seed and Game.rng.seed == case_seed, "fixed seed drives native economy and body generation")
	check(not Dynasty.holds_office(Game) and not Feudal.can_act(Game, HOME) and Feudal.can_act_household(Game, HOME),
		"private home-army authority grants no town office")
	check(Game.gold == 0 and float(house["purse"]) == 0.0 and Game.company.is_empty() and Game.stash.is_empty() and Food.stock(Game, "meal") == 0,
		"starts with no House coin, Army coin, troops, baggage or rations")
	check(Mobilization.household_candidates(Game).is_empty(), "no adult family rider is free")
	# v0.102: An empty adult roster must not satisfy the service checks vacuously.
	var adult_count: int = 0
	for row in Dynasty.living_members(Game):
		if int(row["age"]) >= int(People.ages(str(row["race"]))["adult"]):
			adult_count += 1
			check(row["state"] == "army" and int(row["unit_uid"]) >= 0, "each house adult remains bound in realm service")
			check(MusterView._return_day_text(row) == -1, "regroup timer is not a discharge date")
	check(adult_count == 2 and fx["adults"].size() == 2, "fixture house has exactly its two away adults")
	_text(MusterView.no_riders_text(Dynasty.living_members(Game)), "riders/realm service", "realm's field army", "raise settlement troops")
	_text(MusterView.no_riders_text([]), "riders/no adults", "no adult family members", "hire men in town recruits")
	check(MusterView.no_riders_text(Dynasty.living_members(Game)).contains("no set return date"), "no invented homecoming promise")
	return true

func _chooser_refusals(fx: Dictionary) -> void:
	var uid: String = str(fx["house"]["household_uid"])
	var before: Array = _money(fx)
	_no(Loans.borrow_quote(Game, 1.0), "loan/no house", "choose an existing house", "choose")
	_no(Mobilization.quote(Game, HOME, 1), "muster/no house", "no campaign house", "choose a settlement")
	_no(Feudal.action_preview(Game, HOME, "fund_army", "", 1.0), "fund/no house", "outside your authority", "travel to your home")
	var bad_custom: Array = [
		["unsupported detail", {"purse": 1}, "cannot be changed", "customize house"],
		["brackets", {"display_name": "[House]"}, "forbidden characters", "enter plain text"],
		["control character", {"display_name": "House\n"}, "forbidden characters", "enter plain text"],
		["empty name", {"display_name": " "}, "1-40 characters", "enter a name"],
		["long name", {"display_name": "H".repeat(41)}, "1-40 characters", "enter a name"],
		["emblem", {"emblem": "missing"}, "emblem is unavailable", "choose one"],
		["colour length", {"primary_color": "#12345"}, "colour is invalid", "pick a colour"],
		["colour prefix", {"primary_color": "1234567"}, "colour is invalid", "pick a colour"],
		["colour digits", {"secondary_color": "#12345Z"}, "colour is invalid", "pick a colour"]]
	for row in bad_custom:
		_no(HouseOnboarding.customization(row[1], "Fixture"), "chooser/" + str(row[0]), str(row[2]), str(row[3]))
	_no(HouseOnboarding.preview(Game, HOME, "missing"), "chooser/missing leader", "no eligible living leader", "choose another")
	_no(HouseOnboarding.preview(Game, HOME, uid, {"design": 1}), "chooser/design type", "design is invalid", "reopen customize house")
	_no(HouseOnboarding.preview(Game, HOME, uid, {"design": {"purse": 1}}), "chooser/design forwarded", "unknown character design", "reopen customize house")
	_no(HouseOnboarding.begin(Game, HOME, uid, {"emblem": "missing"}), "chooser/begin forwards preview", "emblem is unavailable", "choose one")
	_no(HouseOnboarding.begin(Game, HOME, uid, {}, "stale-person"), "chooser/stale leader", "leader changed", "review the house")
	var party: Dictionary = Game.world["party"]
	Game.world["party"] = {}
	_no(HouseOnboarding.begin(Game, HOME, uid), "chooser/missing party", "party is missing", "start a new campaign")
	Game.world["party"] = party
	Game.world["work"] = [{"kind": "fixture"}]
	_no(HouseOnboarding.begin(Game, HOME, uid), "chooser/work pending", "still updating", "wait for it to finish")
	Game.world["work"] = []
	Game._save_capture = SaveSnapshot.new()
	_no(HouseOnboarding.begin(Game, HOME, uid), "chooser/save pending", "still updating", "wait for it to finish")
	Game._save_capture = null
	check(Game.world.get("player_house", {}).is_empty() and _money(fx) == before,
		"chooser refusals do not choose a house or change its accounts")

func _away_refusals(fx: Dictionary) -> void:
	var before: Array = _money(fx)
	var company: Array = Game.company.duplicate()
	var home_pos: Vector2 = fx["town"]["pos"]
	var leader_uid: String = str(fx["house"]["pp"][0][Persons.PERSON_UID])
	for mode in ["another town", "on the map", "remote home records"]:
		Game.location = AWAY if mode == "another town" else (HOME if mode == "remote home records" else "")
		Game.world["party"]["pos"] = Game.world["towns"][AWAY]["pos"]
		_no(Loans.borrow_quote(Game, 1.0), mode + "/borrow quote", "before borrowing", "travel to your home")
		_no(Loans.borrow(Game, 1.0), mode + "/borrow", "before borrowing", "travel to your home")
		_no(Feudal.fund_army(Game, 1.0), mode + "/fund army", "before funding", "travel to your home")
		_no(Feudal.action_preview(Game, HOME, "fund_army", "", 1.0), mode + "/fund preview", "before funding", "travel to your home")
		_no(Mobilization.fund(Game, 1.0), mode + "/transfer", "before funding", "travel to your home")
		_no(Mobilization.quote(Game, HOME, 1), mode + "/raise quote", "away from this settlement", "travel here")
		_no(Mobilization.muster(Game, HOME, 1), mode + "/muster", "away from this settlement", "travel here")
		_no(Mobilization.enlist_household(Game, leader_uid), mode + "/family enlist", "away from this settlement", "travel here")
		_no(Mobilization.stand_down(Game, HOME), mode + "/stand down", "away from this settlement", "travel here")
		_no(Mobilization.refit(Game, HOME, {}), mode + "/refit", "away from this settlement", "travel here")
		_text(MusterView.fund_refusal(Mobilization.status(Game), 1.0), mode + "/UI forwarded funding reason",
			"outside your authority" if mode == "another town" else "away from this settlement", "travel")
	check(_money(fx) == before and Game.company == company, "all away refusals preserve coin, debt and roster")
	Game.world["party"]["pos"] = home_pos
	DevTools.stand_at(Game, HOME)

func _loan_refusals(fx: Dictionary) -> void:
	var e: Dictionary = fx["econ"]
	var f: Dictionary = fx["house"]
	check(is_equal_approx(Loans.credit_left(e, f), CHARTER), "propertyless two-adult house has exactly the 1,200-coin charter floor")
	var ordinary: Dictionary = f.duplicate(true)
	ordinary["household_uid"] = "unselected fixture"
	check(Loans.credit_left(e, ordinary) < CHARTER, "native ordinary credit is below the charter floor")
	_text(Loans.refusal(e, {}, 1.0), "loan/empty family", "has left", "choose another")
	var bad: Dictionary = f.duplicate(true)
	bad["gone"] = true
	_text(Loans.refusal(e, bad, 1.0), "loan/gone", "has left", "choose another")
	bad = f.duplicate(true)
	bad["estate"] = true
	_text(Loans.refusal(e, bad, 1.0), "loan/estate", "ruling estate", "fund the army")
	for amount in [0.0, -1.0, 0.5, INF, NAN]:
		_text(Loans.refusal(e, f, float(amount)), "loan/invalid amount " + str(amount), "positive whole amount", "choose")
	f["destitute"] = true
	_text(Loans.refusal(e, f, 1.0), "loan/destitute text", "destitute", "earn coin")
	_no(Loans.borrow(Game, 1.0), "loan/destitute order", "destitute", "earn coin")
	f.erase("destitute")
	f["ln"] = {"miss": 1}
	_text(Loans.refusal(e, f, 1.0), "loan/arrears text", "behind on", "wait for weekly wages")
	_no(Loans.borrow(Game, 1.0), "loan/arrears order", "behind on", "wait for weekly wages")
	f.erase("ln")
	f["debt"] = CHARTER
	_text(Loans.refusal(e, f, 1.0), "loan/credit text", "credit limit", "wait for weekly repayments")
	_no(Loans.borrow(Game, 1.0), "loan/credit order", "credit limit", "wait for weekly repayments")
	f["debt"] = 0.0
	e["treasury"] = 0.0
	_text(Loans.refusal(e, f, 1.0), "loan/treasury text", "no lendable coin", "wait for town taxes")
	_no(Loans.borrow(Game, 1.0), "loan/treasury order", "no lendable coin", "wait for town taxes")
	e["treasury"] = CHARTER
	check(Loans.quote(e, f, CHARTER) == 0.0, "ordinary/AI quote keeps the treasury reserve")
	check(Loans.quote(e, f, CHARTER, true) == CHARTER, "explicit player quote can use treasury reserve")
	check(Loans.refusal(e, f, 1.0, true) == "", "valid player loan has no refusal")
	_text(Loans.refusal(e, f, 1.0, false), "loan/ordinary reserve", "no lendable coin", "wait for town taxes")
	var q: Dictionary = Loans.borrow_quote(Game, CHARTER + 1.0)
	check(bool(q.get("ok", false)) and float(q.get("amount", 0.0)) == CHARTER, "oversized request is capped at the charter and available real treasury")

func _gate_and_fund_refusals(fx: Dictionary) -> void:
	var uid: String = str(fx["house"]["household_uid"])
	_no(HouseOnboarding.begin(Game, HOME, uid), "chooser/already chosen", "already chosen", "open house")
	Game._save_capture = SaveSnapshot.new()
	_no(Loans.borrow_quote(Game, 1.0), "loan/save pending", "save snapshot", "wait for")
	_no(Mobilization.fund(Game, 1.0), "fund/save pending", "save is being prepared", "wait for")
	_no(Mobilization.quote(Game, HOME, 1), "muster/save pending", "save is being prepared", "wait for")
	Game._save_capture = null
	Game.world["work"] = [{"kind": "fixture"}]
	_no(Mobilization.quote(Game, HOME, 1), "muster/work pending", "work is still updating", "wait for")
	Game.world["work"] = []
	_no(Mobilization.quote(Game, AWAY, 1), "muster/foreign authority", "outside your authority", "travel to your home")
	_no(Feudal.action_preview(Game, AWAY, "fund_army", "", 1.0), "fund/foreign authority", "outside your authority", "travel to your home")
	var leader: String = str(Game.world["player_house"]["ruler_uid"])
	Game.world["player_house"]["ruler_uid"] = "missing"
	_no(Loans.borrow_quote(Game, 1.0), "loan/no living authority", "outside your authority", "travel to your home")
	Game.world["player_house"]["ruler_uid"] = leader
	var e: Dictionary = fx["econ"]
	var market: int = int(e["mkt"])
	for index in [-1, e["biz"].size()]:
		e["mkt"] = index
		_no(Mobilization.quote(Game, HOME, 1), "muster/market index " + str(index), "no working market", "hire men at another")
	e["mkt"] = market
	for key in ["price", "stock"]:
		var value: Variant = e[key]
		e.erase(key)
		_no(Mobilization.quote(Game, HOME, 1), "muster/missing " + key, "no working market", "hire men at another")
		e[key] = value
	for amount in [0.0, -1.0, 0.5, INF, NAN]:
		_no(Mobilization.fund(Game, float(amount)), "fund/invalid amount " + str(amount), "whole coins", "enter an amount")
	for amount in [0.0, -1.0, INF, NAN]:
		_no(Feudal.action_preview(Game, HOME, "fund_army", "", float(amount)), "fund/preview amount " + str(amount), "positive amount", "choose")
	_no(Feudal.action_preview(Game, HOME, "fund_army", "", 0.5), "fund/fractional preview", "whole coins", "choose a whole")
	_no(Mobilization.fund(Game, 1.0), "fund/empty private purse", "house purse cannot afford", "borrow coin")
	_text(MusterView.fund_refusal(Mobilization.status(Game), 1.0), "fund/UI empty purse", "no coin to transfer", "borrow coin")
	_text(MusterView.fund_refusal({"can_act": false}, 1.0), "fund/UI authority fallback", "unavailable here", "travel to your home")
	_text(MusterView.fund_refusal({"can_act": true, "payer_purse": 5.0}, 0.0), "fund/UI no amount", "no transfer amount", "enter at least one")
	_text(MusterView.fund_refusal({"can_act": true, "payer_purse": 5.0}, 6.0), "fund/UI too much", "only", "choose a smaller")
	check(MusterView.fund_refusal({"can_act": true, "payer_purse": 5.0}, 5.0) == "", "UI accepts an affordable transfer")
	_away_refusals(fx)

func _manpower_refusals(fx: Dictionary) -> void:
	var town: Dictionary = fx["town"]
	var e: Dictionary = fx["econ"]
	var recruit: Unit = fx["recruit"]
	var before: Array = _money(fx)
	_no(Mobilization.quote(Game, HOME, 1), "muster/unfunded", "no funded", "fund the army purse")
	_no(Mobilization.muster(Game, HOME, 1), "muster/unfunded order", "no funded", "fund the army purse")
	_text(Recruits.hire_refusal(Game, town, recruit), "hire/unfunded", "army purse needs", "return home to transfer house coin")
	_text(Roster.hire(Game, town, recruit, -1), "hire/roster forwards funding", "army purse needs", "borrow into the house purse first")
	_text(Recruits.hire_refusal(Game, town, null), "hire/missing recruit", "no longer available", "town recruits")
	_text(Roster.hire(Game, town, null, -1), "hire/roster forwards missing recruit", "no longer available", "town recruits")
	Game.rep[REALM] = -100
	_text(Recruits.hire_refusal(Game, town, recruit), "hire/standing", "standing here is too low", "earn standing")
	Game.rep[REALM] = 0
	var recruits: Array = town["recruits"]
	town["recruits"] = []
	var hands: Array = []
	for f in e["fams"]:
		hands.append(f["hands"])
		f["hands"] = Families.adults(f)
	_no(Mobilization.quote(Game, HOME, 1), "muster/no manpower", "no free, fit people", "hire men at another")
	for i in e["fams"].size():
		e["fams"][i]["hands"] = hands[i]
	var shop: Array = town["shop"]
	town["shop"] = []
	_no(Mobilization.quote(Game, HOME, 1), "muster/no weapons", "no serviceable weapons", "wait for smiths")
	town["shop"] = shop
	var stock: Dictionary = e["stock"]
	e["stock"] = stock.duplicate(true)
	for good in Goods.FOODS:
		e["stock"][good] = 0
	_no(Mobilization.quote(Game, HOME, 1), "muster/no deployment food", "market lacks food", "wait for food deliveries")
	e["stock"] = stock
	town["recruits"] = recruits
	_no(Mobilization.refit_quote(Game, HOME), "refit/no soldiers", "no living soldier", "fund the army purse")
	_no(Mobilization.stand_down_quote(Game, HOME), "stand down/no enlisted", "no living enlisted", "raise men here")
	_no(Mobilization.enlist_household(Game, "missing"), "rider/missing person", "not a living member", "choose a living adult")
	fx["child"][4] = "dead"
	_no(Mobilization.enlist_household(Game, str(fx["child"][Persons.PERSON_UID])), "rider/dead person", "not a living member", "choose a living adult")
	fx["child"][4] = ""
	var p: Array = fx["house"]["pp"][0]
	var person_uid: String = str(p[Persons.PERSON_UID])
	var family_id: int = int(fx["house"]["id"])
	fx["house"]["id"] = e["fams"].size() + 1
	_no(Mobilization.enlist_household(Game, person_uid), "rider/missing local family", "family record is missing", "choose another household member")
	fx["house"]["id"] = family_id
	var pid: int = int(p[0])
	p[0] = -1
	_no(Mobilization.enlist_household(Game, person_uid), "rider/missing local person", "person's record is missing", "raise settlement troops")
	p[0] = pid
	for row in [
		["army", "realm's field army", "raise settlement troops"],
		["militia", "town guard", "choose another adult"],
		["caravan", "away with a caravan", "wait for the caravan"],
		["captive", "held captive", "open court"],
		["reserve", "home reserves", "review raising"],
		["company", "already serving", "review the army roster"],
		["guard", "already serving", "choose another adult"]]:
		p[4] = row[0]
		_no(Mobilization.enlist_household(Game, person_uid), "rider/duty " + str(row[0]), str(row[1]), str(row[2]))
	p[4] = "army"
	_no(Mobilization.enlist_household(Game, str(fx["child"][Persons.PERSON_UID])), "rider/too young", "too young", "wait for them to come of age")
	# Count-only boundary fixtures reuse one sentinel. No duplicate soldier is
	# ever hired, mustered, saved or marched from this capacity probe.
	var slots: Array = []
	slots.resize(Mobilization.LIMIT)
	slots.fill(recruit)
	Game.company = slots
	Game.gold = int(CHARTER)
	_text(Recruits.hire_refusal(Game, town, recruit), "hire/full company", "full size", "stand down")
	_no(Mobilization.enlist_household(Game, person_uid), "rider/full army", "full size", "stand down")
	_no(Mobilization.quote(Game, HOME, 1), "muster/full army fallback", "no funded", "review local weapons and food")
	Game.company = []
	slots = []
	slots.resize(Roster.MAX_TROOPS)
	slots.fill(recruit)
	recruit.squad = 123
	Game.company = slots
	_text(Roster.hire(Game, town, recruit, 123), "hire/full squad", "squad is full", "choose another squad")
	recruit.squad = -1
	Game.company = []
	Game.gold = 0
	check(_money(fx) == before and town["recruits"].has(recruit), "forced refusal probes leave the required route unfunded and unhired")

func _contract_refusals() -> void:
	var offer: Dictionary = {"id": "fixture", "employer": REALM, "tier": 0, "kind": "battle", "town_id": HOME}
	Game.rep[REALM] = -100
	_text(Contracts.refusal(Game, offer), "contracts/standing", "will not hire you", "raise your standing")
	Game.rep[REALM] = 0
	offer["tier"] = 1
	_text(Contracts.refusal(Game, offer), "contracts/trusted tier", "only to companies they trust", "choose a plain contract")
	offer["tier"] = 0
	offer["kind"] = "war"
	offer["target_faction"] = "moon_court"
	_text(Contracts.refusal(Game, offer), "contracts/war ended", "war is over", "choose another contract")
	offer["kind"] = "battle"
	Game.contract = {"state": "active", "title": "Fixture"}
	check(not Contracts.accept(Game, offer), "contracts/active contract refuses")
	_text(str(Game.world["log"].back()), "contracts/already active", "already have an active contract", "finish or abandon")
	Game.contract = {}

func _coin() -> float:
	var total: float = float(Game.gold)
	for town in Game.world["towns"].values():
		var e: Dictionary = town["econ"]
		total += float(e["treasury"])
		for f in e["fams"]:
			total += float(f["purse"])
		for b in e["biz"]:
			total += float(b["till"])
	for faction in Game.world["factions"].values():
		total += float(faction["treasury"])
	for band in Game.world["warbands"].values():
		total += float(band.get("gold", 0.0))
	return total

## These are headless control/label checks, not rendered layout or screenshot QA.
## Only refused UI handlers run; successful actions below use campaign APIs and
## never request autosaves or touch the user's save/settings files.
func _army_ui(tree: SceneTree, funded_house: bool) -> void:
	var view: MusterView = MusterView.new()
	# The runner may still be in _ready; attach and settle before reading controls.
	tree.root.add_child.call_deferred(view)
	await tree.process_frame
	if funded_house:
		check(view.fund_input.value >= 1.0 and not view.fund_button.disabled, "Army defaults to an affordable positive transfer after a loan")
		_no(view.apply_funding(1.0, {}), "fund/UI stale household", "household changed", "review the transfer")
	else:
		check(view.fund_button.disabled and not view.borrow_button.disabled and view.raise_button.disabled,
			"empty Army screen disables transfer/raising and offers borrowing")
		_text(view.funding_label.text, "Army visible funding reason", "no coin to transfer", "borrow coin")
		_text(view.reason_label.text, "Army visible raising reason", "no funded", "fund the army purse")
		_text(view.down_reason_label.text, "Army visible stand-down reason", "no living enlisted", "raise men here")
		_text(view.refit_reason_label.text, "Army visible refit reason", "no living soldier", "fund the army purse")
		view.request_funding()
		_text(view.notice_label.text, "Army transfer refusal notice", "no coin to transfer", "borrow coin")
		view.request_raise()
		_text(view.notice_label.text, "Army raising refusal notice", "no funded", "fund the army purse")
		view.request_stand_down()
		_text(view.notice_label.text, "Army stand-down refusal notice", "no living enlisted", "raise men here")
		view.request_refit()
		_text(view.notice_label.text, "Army refit refusal notice", "no living soldier", "fund the army purse")
	view.free()

func _stale_reviews(fx: Dictionary) -> void:
	var before: Array = _money(fx)
	var company: Array = Game.company.duplicate()
	_no(Mobilization.stand_down(Game, HOME, {"stale": true}), "stand down/stale review", "roster changed", "review it again")
	# A stale household that cannot be restored can pass the roster preview,
	# yet return zero soldiers. That native refusal must remain actionable.
	fx["common"]["gone"] = true
	_no(Mobilization.stand_down(Game, HOME), "stand down/no accepted returns", "no reviewed soldiers could return", "review the roster")
	fx["common"]["gone"] = false
	var helm_id: String = ""
	var ids: Array = DB.armor.keys()
	ids.sort()
	for tid in ids:
		if str(DB.armor[tid].get("slot", "")) == Mobilization.HELM_SLOT:
			helm_id = str(tid)
			break
	check(helm_id != "", "native refit fixture has a helmet template")
	if helm_id != "":
		var town: Dictionary = fx["town"]
		var armory: Array = town["armory_items"]
		town["armory_items"] = [Item.make(helm_id)]
		check(bool(Mobilization.refit_quote(Game, HOME).get("ok", false)), "stale-refit probe reaches a feasible refit")
		_no(Mobilization.refit(Game, HOME, {"stale": true}), "refit/stale review", "refit changed", "review the current roster")
		town["armory_items"] = armory
	check(_money(fx) == before and Game.company == company, "stale reviews spend nothing and stand down nobody")

func _path(tree: SceneTree, fx: Dictionary) -> void:
	var town: Dictionary = fx["town"]
	var e: Dictionary = fx["econ"]
	var house: Dictionary = fx["house"]
	var common: Dictionary = fx["common"]
	var recruit: Unit = fx["recruit"]
	var cheap: Item = fx["cheap"]
	var purse0: float = float(common["purse"])
	var treasury0: float = float(e["treasury"])
	var coin0: float = _coin()
	var day0: float = Game.day
	var initial: Dictionary = Mobilization.quote(Game, HOME, 1)
	check(not bool(initial.get("ok", true)) and int(initial.get("eligible", 0)) > 0 and int(initial.get("required_funding", 0)) > 0,
		"unfunded quote counts real manpower and reports a coin shortfall")
	await _army_ui(tree, false)
	var quoted: Dictionary = Mobilization.borrow_quote(Game, CHARTER)
	check(bool(quoted.get("ok", false)) and float(quoted.get("amount", 0.0)) == CHARTER, "Army loan preview uses the 1,200-coin charter")
	var loan: Dictionary = Mobilization.borrow(Game, CHARTER)
	check(bool(loan.get("ok", false)) and float(loan.get("amount", 0.0)) == CHARTER, "explicit player loan succeeds within the charter")
	if not bool(loan.get("ok", false)):
		return
	check(float(e["treasury"]) == treasury0 - CHARTER and float(house["purse"]) == CHARTER and Game.gold == 0,
		"loan goes from settlement treasury to House purse; Army remains empty")
	check(float(house["debt"]) == CHARTER and float(house["ln"]["lent"]) == CHARTER and float(e["stats"]["lent"]) == CHARTER
		and Loans.credit_left(e, house) == 0.0, "native debt, loan receipts and remaining charter credit agree")
	check(is_equal_approx(_coin(), coin0), "loan conserves all-account coin")
	var borrowed_state: Array = _money(fx)
	_no(Mobilization.muster(Game, HOME, 1), "route/loan alone cannot muster", "no funded", "fund the army purse")
	_text(Roster.hire(Game, town, recruit, -1), "route/loan alone cannot hire", "army purse needs", "return home to transfer house coin")
	check(_money(fx) == borrowed_state and Game.company.is_empty() and town["recruits"].has(recruit), "House credit does not bypass the Army transfer")
	await _army_ui(tree, true)
	_no(Mobilization.fund(Game, CHARTER + 1.0), "route/oversized transfer", "house purse cannot afford", "borrow coin")
	var transfer: Dictionary = Mobilization.fund(Game, CHARTER)
	check(bool(transfer.get("ok", false)), "private house funds its Army while physically home")
	if not bool(transfer.get("ok", false)):
		return
	check(float(house["purse"]) == 0.0 and Game.gold == int(CHARTER) and float(e["treasury"]) == treasury0 - CHARTER,
		"funding debits House purse and credits only Army purse")
	check(is_equal_approx(_coin(), coin0), "House-to-Army transfer conserves coin")
	var offer: Dictionary = Recruits.offer(Game, recruit)
	var hire_gold: int = Game.gold
	check(Roster.hire(Game, town, recruit, -1) == "", "Town Recruits hires a real commoner after funding")
	check(Game.company.size() == 1 and Game.company.has(recruit) and not town["recruits"].has(recruit),
		"hire transfers the exact native recruit once")
	check(Game.gold == hire_gold - int(offer["hire_cost"]) and float(common["purse"]) == purse0 + float(offer["hire_cost"]),
		"hiring pays the actual commoner family from the Army purse")
	var hired_person: Array = Persons.by_uid(common, recruit.uid)
	check(not hired_person.is_empty() and str(hired_person[4]) == "company" and is_equal_approx(_coin(), coin0),
		"hired recruit keeps its person identity and coin is conserved")
	if fails > 0:
		return
	var rng_before: int = Game.rng.state
	var units_before: int = Unit._next_uid
	var items_before: int = Item._next_uid
	var partial: Dictionary = Mobilization.quote(Game, HOME, 100)
	check(bool(partial.get("ok", false)) and int(partial.get("planned", 0)) > 0 and int(partial.get("planned", 100)) < 100
		and int(partial.get("required_funding", -1)) == 0, "affordable partial raising clears the misleading remaining-funds warning")
	var quote: Dictionary = Mobilization.quote(Game, HOME, 1)
	check(bool(quote.get("ok", false)) and int(quote.get("planned", 0)) == 1, "home muster can raise one more commoner within charter funding")
	if not bool(quote.get("ok", false)):
		return
	check(quote["review"]["rows"][0][0] == "draft" and int(quote["review"]["rows"][0][4]) == cheap.uid,
		"empty armory falls back from expensive shop weapon to affordable native weapon")
	check(Game.rng.state == rng_before and Unit._next_uid == units_before and Item._next_uid == items_before,
		"raising previews consume no RNG or Unit/Item identities")
	var before_muster: Array = _money(fx)
	_no(Mobilization.muster(Game, HOME, 1, {"stale": true}), "muster/stale review", "muster changed", "review the current people")
	check(_money(fx) == before_muster and Game.company.size() == 1, "stale muster spends nothing and raises nobody")
	var army0: int = Game.gold
	var meals0: int = Food.stock(Game, "meal")
	var raised: Dictionary = Mobilization.muster(Game, HOME, 1, quote["review"])
	check(bool(raised.get("ok", false)) and int(raised.get("raised", 0)) == 1 and Game.company.size() == 2, "native muster raises one household soldier beside the hired commoner")
	if not bool(raised.get("ok", false)) or Game.company.size() != 2:
		return
	var soldier: Unit = Game.company.back()
	var address: Dictionary = Mobilization._address(Game, soldier)
	check(not address.is_empty() and str(address.get("person", [0, 0, 0, 0, ""])[4]) == "company"
		and soldier.home_town == HOME and soldier.weapon() == cheap and not town["shop"].has(cheap),
		"muster binds the real resident and transfers the reviewed market weapon")
	check(Game.gold == army0 - int(raised["cost"]) and Game.gold >= Game.daily_wages() * 3,
		"muster debits actual costs and retains at least three days of payroll")
	check(Food.stock(Game, "meal") == meals0 + Mobilization.MEALS and int(raised["food_units"]) == Mobilization.MEALS,
		"muster buys exactly the departing soldier's deployment meals")
	check(is_equal_approx(_coin(), coin0), "hiring, equipment, levy fee and rations conserve all-account coin")
	_stale_reviews(fx)
	_away_refusals(fx)
	Mobilization.command_plan(Game)
	check(Mobilization.household_candidates(Game).is_empty() and Game.squads.is_empty(), "household army has no available family rider or invented officer")
	for u in Game.company:
		check(not Mobilization.is_house_rider(Game, u) and u.role == "troop" and u.squad == -1, "actual commoner is deployable without a leader")
	Game.invalidate_deploy()
	check(Game.deployed_units().size() == 2, "both unled commoners are fit to deploy")
	var company: Array = Game.company.duplicate()
	var origin: Vector2 = Game.world["party"]["pos"]
	var destination: Vector2 = Game.world["towns"][AWAY]["pos"]
	Game.location = ""
	var ordered: bool = CampaignWorld.set_travel(Game, destination, AWAY)
	check(ordered and CampaignWorld.is_travelling(Game) and Game.world["party"]["dest_town"] == AWAY,
		"unled household army receives a real native march path")
	if ordered:
		CampaignWorld._move_party(Game, 0.01)
		check((Game.world["party"]["pos"] as Vector2).distance_to(origin) > 0.0
			and (Game.world["party"]["pos"] as Vector2).distance_to(destination) < origin.distance_to(destination),
			"army actually moves toward its destination in one bounded movement slice")
	check(Game.company == company and Game.day == day0, "march retains the same soldiers and simulates no campaign days")
	for u in fx["adults"]:
		var person: Array = Persons.by_uid(house, u.uid)
		check(not Game.company.has(u) and not person.is_empty() and str(person[4]) == "army", "family adult stays in the realm army throughout the successful route")
	if fails == 0:
		print("seed %d: House 0 -> borrow %.0f -> Army transfer -> hire 1 -> muster 1 -> unled march; day unchanged" % [case_seed, CHARTER])

func run(tree: SceneTree) -> int:
	var started: int = Time.get_ticks_msec()
	Game.wait_save()
	var completed: int = 0
	var fields: Array = ["world", "company", "stash", "squads", "rep", "contract", "pending_battle", "provisions",
		"food_clock", "location", "screen_params", "main", "day", "gold", "seed_value", "_save_capture"]
	var saved: Dictionary = {}
	for key in fields:
		saved[key] = Game.get(key)
	var rng_seed: int = Game.rng.seed
	var rng_state: int = Game.rng.state
	var dimensions: Array = [WorldGen.W, WorldGen.H, WorldGen.K, WorldGen.KD, WorldGen.TF]
	var gone: float = TownEcon.gold_gone
	WorldGen.set_size(float(WorldGen.SIZES["normal"]["stretch"]))
	for seed_value in SEEDS:
		case_seed = int(seed_value)
		var fx: Dictionary = _fixture(case_seed)
		if fx.is_empty() or fails > 0:
			break
		_chooser_refusals(fx)
		if fails > 0 or not _begin(fx):
			break
		_loan_refusals(fx)
		_gate_and_fund_refusals(fx)
		_manpower_refusals(fx)
		_contract_refusals()
		if fails > 0:
			break
		await _path(tree, fx)
		if fails > 0:
			break
		completed += 1
		check(Time.get_ticks_msec() - started < BUDGET_MS, "three-seed path stays below its 55-second internal budget")
		if fails > 0:
			break
	if fails == 0:
		check(completed == SEEDS.size(), "all three fixed seeds completed the required route")
	for key in fields:
		Game.set(key, saved[key])
	Game.rng.seed = rng_seed
	Game.rng.state = rng_state
	WorldGen.W = int(dimensions[0])
	WorldGen.H = int(dimensions[1])
	WorldGen.K = float(dimensions[2])
	WorldGen.KD = float(dimensions[3])
	WorldGen.TF = float(dimensions[4])
	TownEcon.gold_gone = gone
	Game.invalidate_deploy()
	Dynasty.note_households_changed()
	var elapsed_ms: int = Time.get_ticks_msec() - started
	check(elapsed_ms < BUDGET_MS, "whole test including restoration finishes below its 55-second internal budget")
	print("v102 small house: %d completed seeds, %d checks, %d refusal cases, %d failures, %d ms" %
		[completed, checks, refusals.size(), fails, elapsed_ms])
	return fails
