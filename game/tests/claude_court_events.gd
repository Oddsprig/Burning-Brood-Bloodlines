extends RefCounted
const Court = preload("res://campaign/court_events.gd")
var checks: int = 0
var failures: int = 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL court: ", label)

func spend(uid: String, kind: String, args: Dictionary = {}) -> Dictionary:
	var before: float = Barge.holdings(Game)
	var f: Dictionary = Dynasty._household(Game, uid)["family"]
	var purse: float = float(f["purse"])
	var prestige: float = float(f.get("prestige", 0.0))
	var quote: Dictionary = Court.preview(Game, uid, kind, args)
	check(bool(quote.get("ok", false)), kind + " quotes: " + str(quote.get("reason", "")))
	var result: Dictionary = Court.hold(Game, uid, kind, args, quote)
	check(bool(result.get("ok", false)), kind + " held")
	check(absf(before - Barge.holdings(Game)) < 0.001, kind + " conserves total native coin")
	check(is_equal_approx(purse - float(f["purse"]), float(quote.get("cost", 0))), kind + " charges exactly its quote")
	if kind in ["feast", "wedding", "parade", "display"]:
		check(float(f.get("prestige", 0.0)) > prestige, kind + " grants prestige")
	return result

func run(tree: SceneTree) -> int:
	tree.root.set_flag(Window.FLAG_NO_FOCUS, true)
	tree.root.position = Vector2i(-30000, -30000)
	if not await DevTools.start_world(tree, "user://claude_court_events-test.json"):
		check(false, "start world loads")
		print("court: %d checks, %d failures" % [checks, failures])
		return failures
	# Use an actual eligible marriage from Marriage.candidates, never fake spouses.
	var uid: String = ""
	var member: String = ""
	var spouse: String = ""
	for choice: Dictionary in Dynasty.choices(Game):
		Game.world["player_house"] = {} # fixture selection may try several real houses
		if not HouseOnboarding.begin(Game, str(choice["town_id"]), str(choice["household_uid"])).get("ok", false): continue
		for row: Dictionary in Marriage.family(Game):
			if not row.get("adult", false) or row.get("married", true): continue
			var candidates: Array = Marriage.candidates(Game, str(row["person_uid"]))
			if candidates.is_empty(): continue
			member = str(row["person_uid"]); spouse = str(candidates[0]["person_uid"])
			uid = str(choice["household_uid"]); break
		if uid != "": break
	check(uid != "", "a real adult match exists")
	if uid == "":
		print("court: %d checks, %d failures" % [checks, failures])
		return failures
	var loc: Dictionary = Dynasty._household(Game, uid)
	var town: Dictionary = loc["town"]
	var e: Dictionary = town["econ"]
	var f: Dictionary = loc["family"]
	var tid: String = str(town["id"])
	var day0: float = float(Game.day)
	# Explicit fixture balances; assertions below measure transfers after setup.
	f["purse"] = 5000000.0; f["inc"] = 1000000.0 * 7.0 / 120.0; f["debt"] = 0.0
	var market: Dictionary = e["biz"][int(e["mkt"])]
	market["till"] = 1000000.0
	var oath: Dictionary = Game.world["feudal"]["towns"][tid]
	oath["grievance"] = 60.0
	var total: float = Barge.holdings(Game)
	var snapshot: String = JSON.stringify(f)
	Court.preview(Game, uid, "feast")
	check(snapshot == JSON.stringify(f), "preview is read only")
	check(not Court.hold(Game, uid, "feast", {}).get("ok", false), "unreviewed spend rejected")
	check(not Court.preview(Game, uid, "unknown").get("ok", false), "unknown event rejected")
	check(not Court.preview(Game, uid, "wedding").get("ok", false), "no grand wedding before actual marriage")
	spend(uid, "feast")
	check(float(f.get("court_opinion", 0.0)) > 0.0 and float(oath["grievance"]) < 60.0, "feast opinion and grievance effects")
	check(not Court.preview(Game, uid, "feast").get("ok", false), "frequent feast still has a seven-day cooldown")
	var wedding: Dictionary = Marriage.wed(Game, member, spouse)
	check(wedding.get("ok", false), "Marriage.wed creates the actual marriage")
	spend(uid, "wedding")
	check(not Court.preview(Game, uid, "wedding").get("ok", false), "same marriage cannot be celebrated twice")
	var regular: Dictionary = Court.preview(Game, uid, "parade")
	# Observe an increment at the existing Warfare.after_battle counter.
	# Zero liquid cash prevents the AI from consuming the parade before the check.
	var saved_purse: float = float(f["purse"])
	f["purse"] = 0.0
	Court.weekly(Game, town, e, f)
	if not Game.world.has("warfare"): Warfare._state(Game)
	Game.world["warfare"]["battles_won"] = int(Game.world["warfare"].get("battles_won", 0)) + 1
	Court.weekly(Game, town, e, f)
	f["purse"] = saved_purse
	var triumphant: Dictionary = Court.preview(Game, uid, "parade")
	check(float(triumphant["effects"]["prestige"]) > float(regular["effects"]["prestige"]), "recent recorded victory doubles parade prestige")
	var soldier: Unit = Unit.new()
	soldier.home_town = tid; soldier.stress = 40.0
	Game.company.append(soldier)
	spend(uid, "parade")
	check(soldier.stress < 40.0 and soldier.merry_day == Game.day, "parade relieves real army stress")
	Game.company.erase(soldier)
	spend(uid, "display")
	spend(uid, "statue")
	spend(uid, "monument")
	check(not Court.preview(Game, uid, "statue").get("ok", false), "duplicate building rejected")
	var earned: float = float(f["court_prestige"])
	Game.day = day0 + 29.0
	f["purse"] = 0.0
	oath["grievance"] = 50.0
	Court.weekly(Game, town, e, f)
	check(float(f["court_prestige"]) > earned and is_equal_approx(float(oath["grievance"]), 34.0), "completed monuments grant lasting prestige and relief")
	Court.weekly(Game, town, e, f)
	check(is_equal_approx(float(oath["grievance"]), 34.0), "completion is applied once")
	f["purse"] = saved_purse
	for category: String in ["gold", "silver", "art"]:
		spend(uid, "treasure", {"category": category, "quantity": 2})
	var gem: String = str(Dragons.catalogs()["gems"][0]["id"])
	# Attach the matching test dragon to this household; restore after comparison.
	var dragon: Dictionary = {}
	var old_owner: String = ""
	var old_gem: String = ""
	for d: Dictionary in Game.world["dragons"]["records"].values():
		if d.get("alive", false):
			dragon = d; break
	check(not dragon.is_empty(), "native dragon available for matching-gem check")
	if not dragon.is_empty():
		old_owner = str(dragon.get("owner_household_uid", "")); old_gem = str(dragon["gem_id"])
		dragon["owner_household_uid"] = uid; dragon["gem_id"] = gem
	spend(uid, "treasure", {"category": "gems", "gem_id": gem, "quantity": 4})
	var rows: Array = Court.hoard_view(Game, uid)
	var gem_row: Dictionary = rows.back()
	if not dragon.is_empty():
		check(bool(gem_row["gem_match"]) and is_equal_approx(float(gem_row["prestige"]), 4.8), "matching dragon gem gives twenty percent extra prestige")
		dragon["owner_household_uid"] = old_owner; dragon["gem_id"] = old_gem
	check(not Court.preview(Game, uid, "treasure", {"category": "gems", "gem_id": "imaginary"}).get("ok", false), "only catalog gems accepted")
	total = Barge.holdings(Game)
	var sale: Dictionary = Court.sell_hoard(Game, uid, str(gem_row["id"]), 1)
	check(int(sale.get("coin", 0)) == 3000, "hoard sale pays sixty percent")
	check(absf(total - Barge.holdings(Game)) < 0.001, "funded market sale conserves coin")
	market["till"] = 0.0
	check(not Court.sell_hoard(Game, uid, str(gem_row["id"])).get("ok", false), "empty till cannot mint sale coin")
	market["till"] = 1000000.0
	total = Barge.holdings(Game)
	var before_items: int = 0
	for row: Dictionary in Court.hoard_view(Game, uid): before_items += int(row["quantity"])
	var loot: Array = Court.seize_hoard(Game, uid, 0.5)
	var after_items: int = 0
	for row: Dictionary in Court.hoard_view(Game, uid): after_items += int(row["quantity"])
	for row: Dictionary in loot: after_items += int(row["quantity"])
	check(before_items == after_items and not loot.is_empty(), "seizure transfers exact whole treasure pieces")
	check(absf(total - Barge.holdings(Game)) < 0.001, "seizure does not convert property into coin")
	# Receiver takes the returned property (the raid/sack integration contract).
	var recipient: Dictionary = {}
	for t: Dictionary in Game.world["towns"].values():
		if str(t.get("faction", "")) == str(town["faction"]): continue
		var other: Dictionary = Feudal.tax_recipient(Game, str(t["id"]))
		if not other.is_empty():
			recipient = {"town": t, "family": other}; break
	check(not recipient.is_empty(), "foreign ruling household exists")
	if not recipient.is_empty():
		var other: Dictionary = recipient["family"]
		if not other.has("hoard"): other["hoard"] = []
		other["hoard"].append_array(loot)
		var a: String = str(town["faction"]); var b: String = str(recipient["town"]["faction"])
		var pair: Dictionary = Game.world["diplo"]["pairs"][Diplomacy.pair_key(a, b)]
		pair["rel"] = -90.0
		var relation: float = Diplomacy.relation(Game.world, a, b)
		var theirs: float = float(other["purse"])
		spend(uid, "gift", {"to_house": str(other["household_uid"]), "amount": 10000})
		check(is_equal_approx(float(other["purse"]) - theirs, 10000.0), "gift reaches the other ruling purse")
		check(Diplomacy.relation(Game.world, a, b) > relation, "gift improves native diplomacy")
	total = Barge.holdings(Game)
	var purse_before: float = float(f["purse"])
	var raised: int = Court.need_coin(Game, uid, 1000, "buying allies")
	check(raised >= 1000 and is_equal_approx(float(f["purse"]) - purse_before, raised), "need_coin raises actual emergency cash")
	check(absf(total - Barge.holdings(Game)) < 0.001, "emergency sales conserve coin")
	# Weekly policy: reserve protection, wealth scaling, debt and idempotency.
	var keep: int = Court.safe_keep(Game, uid)
	f["purse"] = float(keep + 3000000)
	Game.day += 7.0
	var before: float = float(f["purse"])
	total = Barge.holdings(Game)
	Court.weekly(Game, town, e, f)
	check(float(f["purse"]) < before and float(f["purse"]) >= keep, "rich AI spends only surplus")
	check(absf(total - Barge.holdings(Game)) < 0.001, "AI spending conserves coin")
	before = float(f["purse"])
	Court.weekly(Game, town, e, f)
	check(is_equal_approx(before, float(f["purse"])), "weekly spending runs once per week")
	f["purse"] = float(keep)
	check(absi(Court.expected_yearly_cost(Game, uid) - 550000) <= 1, "one million net/year baseline budgets 550000/year")
	f["purse"] = float(keep + 1000000)
	check(Court.expected_yearly_cost(Game, uid) >= 1450000 - 1, "wealth increases the yearly budget")
	f["purse"] = float(keep - 1000)
	Game.day += 7.0
	total = Barge.holdings(Game)
	Court.weekly(Game, town, e, f)
	check(float(f["purse"]) >= keep and absf(total - Barge.holdings(Game)) < 0.001, "cash-poor AI sells hoard to meet reserves")
	f["debt"] = 100.0; f["purse"] = 5000000.0
	Game.day += 7.0; before = float(f["purse"])
	Court.weekly(Game, town, e, f)
	check(is_equal_approx(before, float(f["purse"])), "indebted house never buys prestige")
	f["debt"] = 0.0
	spend(uid, "treasure", {"category": "silver", "quantity": 2})
	# Save a completed and a pending monument, both with real paid commissions.
	f["court"]["monuments"][0]["complete"] = false
	f["court"]["monuments"][0]["due_day"] = int(Game.day) + 7
	Court._refresh(Game, uid, f)
	var digest: String = JSON.stringify({"hoard": f["hoard"], "monuments": f["court"]["monuments"]})
	var prestige: float = float(f["prestige"])
	Game.save_game(); Game.wait_save()
	check(Game.load_game(), "private test save loads")
	Court.after_load(Game)
	f = Dynasty._household(Game, uid)["family"]
	check(digest == JSON.stringify({"hoard": f["hoard"], "monuments": f["court"]["monuments"]}), "hoard and pending/completed monuments survive actual save/load")
	check(is_equal_approx(prestige, float(f["prestige"])), "load does not stack prestige")
	check(f["hoard"][0]["quantity"] is int and f["court"]["monuments"][0]["due_day"] is int, "load restores integer fields")
	Court.after_load(Game)
	check(is_equal_approx(prestige, float(f["prestige"])), "load normalization is idempotent")
	print("court: %d checks, %d failures" % [checks, failures])
	return failures
